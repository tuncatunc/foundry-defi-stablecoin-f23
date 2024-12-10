// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title DscEngine
 * @author Tunca following Patrick stable coin course
 * @notice Collateral: wBTC, wETH
 * @notice Minting: Algorithmic
 * @notice Relative Stability: Pegged to USD
 * @notice The DSC system should always be overcollateralized, meaning that the value of the collateral should always be greater than the value of the DSC minted.
 * @dev This contract is meant to be managed by DSCEngine
 * @notice
 */
contract DscEngine is ReentrancyGuard, Script {
    ///////////////////////
    // Errors
    ///////////////////////

    error DscEngine__AmountIsLessThanZero(uint256 amount);
    error DscEngine__InvalidInputLength();
    error DscEngine__CollateralNotAllowed(address collateralAddress);
    error DscEngine__TransferCollateralFailed(address collateralAddress, uint256 amount);
    error DscEngine__HealthFactorIsBelowOne(uint256 healthFactor);
    error DscEngine__HealthFactorNotImproved(uint256 healthFactor);
    error DscEngine__MintDscFailed();
    error DscEngine__HealthFactorOk(uint256 healthFactor);
    error DscEngine__RedeemAmountIsMoreThanAvailable(uint256 amount, uint256 available);

    ///////////////////////
    // State Variables
    ///////////////////////
    uint256 private constant ADDTIONAL_FEED_PRECISION = 1e10; // price returned from Chainlink is 1e8, we need to multiply it by 1e10 to get 1e18
    uint256 private constant PRECISION = 1e18; // 18 decimals
    uint256 private constant COLLATERAL_RATIO = 50; // 150%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%
    uint256 private constant MIN_HEALTH_FACTOR = 1; // 1

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateral; // user's token collateral
    mapping(address user => uint256 dscMinted) private s_dscMinted; // user's DSC minted
    address[] private s_collateralTokens;
    DecentralizedStableCoin private i_dsc;

    ///////////////////////
    // Events
    ///////////////////////
    event DscEngine__CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amount);
    event DscEngine__CollateralRedeemed(
        address indexed redeemedFrom, address redeemedTo, address indexed tokenCollateral, uint256 amount
    );

    ///////////////////////
    // Modifiers
    ///////////////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DscEngine__AmountIsLessThanZero(_amount);
        }
        _;
    }

    modifier isAllowedCollateral(address _collateralAddress) {
        bool isAllowed = false;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            if (s_collateralTokens[i] == _collateralAddress) {
                isAllowed = true;
                break;
            }
        }
        if (!isAllowed) {
            revert DscEngine__CollateralNotAllowed(_collateralAddress);
        }
        _;
    }

    ///////////////////////
    // Functions
    ///////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DscEngine__InvalidInputLength();
        }

        s_collateralTokens = tokenAddresses;

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////
    // External Functions
    ///////////////////////

    /**
     * @notice Deposit collateral to mint DSC
     * @notice follows CEI (Check-Effects-Interactions) pattern
     * @param tokenCollateralAddress wBTC, wETH address
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        // Transfer collateral to this contract
        s_userCollateral[msg.sender][tokenCollateralAddress] += amount;
        emit DscEngine__CollateralDeposited(msg.sender, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DscEngine__TransferCollateralFailed(tokenCollateralAddress, amount);
        }
    }

    /**
     * @notice Mint DSC by depositing collateral
     * @param _amountDscToMint The amount of DSC to mint
     * @notice must have more collaretal than the DSC amount to mint
     */
    function mintDsc(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        // Check collaretal amount is greater than the DSC amount
        // pricefeeds, values, ratios
        // mint DSC
        s_dscMinted[msg.sender] += _amountDscToMint;
        // Revert if health factor is broken
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DscEngine__MintDscFailed();
        }
    }

    /**
     * @notice Deposit collateral and mint DSC
     * @param _collateralAddress Collataral address
     * @param _collateralAmount Collateral amount
     * @param _dscAmount DSC amount to mint
     */
    function depositCollateralAndMintDsc(address _collateralAddress, uint256 _collateralAmount, uint256 _dscAmount)
        external
    {
        // deposit collateral
        depositCollateral(_collateralAddress, _collateralAmount);
        // mint DSC
        mintDsc(_dscAmount);
    }

    /**
     * @notice After redeeming collateral, the health factor should be greater than 1
     * @param _collataralAddress Collateral address
     * @param _amountCollateral Collateral amount
     */
    function redeemCollateral(address _collataralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        nonReentrant
    {
        // redeem collateral
        _redeemCollateral(msg.sender, msg.sender, _collataralAddress, _amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 _dscAmount) public moreThanZero(_dscAmount) {
        // burn DSC
        _burnDsc(_dscAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralAndBurnDsc(address _collateralAddress, uint256 _collateralAmount, uint256 _dscAmount)
        external
    {
        // burn DSC
        burnDsc(_dscAmount);

        // redeem collateral
        redeemCollateral(_collateralAddress, _collateralAmount);
    }

    /**
     * @dev The backing collataral at least 150% of the DSC minted
     * @dev 100$ ETH backing 50$ DSC OK Health factor is 2
     * @dev 75$ ETH backing 50$ DSC OK Health factor is 1.5
     * @dev ETH price goes down to 70$
     * @dev 70$ ETH backing 50$ DSC NOK, health factor is 1.4 (70/50)
     * @dev If liquidator pays 50$ DSC, it can redeem all underlaying collateral 70$ worth of ETH and burn the 50$ DSC
     *
     * @param _user User who has proken the health factor
     * @param _collateralAddress Collateral address
     * @param _debtToCover The amount of DSC to burn and improve the user's health factor
     *
     * @notice You can partially liquidate the user's collateral
     * @notice This function follows CEI (Check-Effects-Interactions) pattern
     */
    function liquidate(address _user, address _collateralAddress, uint256 _debtToCover)
        external
        moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _getHealthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DscEngine__HealthFactorOk(startingUserHealthFactor);
        }

        // We want to burn their DSC "debt"
        // and take their collateral
        // Bad User: $140 ETH backing $100 DSC, Heath factor is 1.4 below 2
        // Liquidator pays $100 "debt" in collateral, gets $140 worth of "collateral"
        // Thus, the collateral amount increases in the system
        // and bad actor's are liquidated
        uint256 collateralAmountFromDebtToCover = getCollateralAmountFromUsd(_collateralAddress, _debtToCover);
        // Give 10% worth of collataral as bonus to the liquidator
        uint256 bonusCollateral = (collateralAmountFromDebtToCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateral = collateralAmountFromDebtToCover + bonusCollateral;

        _redeemCollateral(_user, msg.sender, _collateralAddress, totalCollateral);
        // Burn the bad actor's DSC
        _burnDsc(_debtToCover, _user, msg.sender);

        // Check if the bad actor's health factor is above 1 after burning the DSC
        uint256 endingUserHealthFactor = _getHealthFactor(_user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DscEngine__HealthFactorNotImproved(endingUserHealthFactor);
        }

        // Adding collateral should always improve the health factor of the liquidator
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        // return health factor
    }

    ///////////////////////
    // Private & Internal Functions
    ///////////////////////
    function _getAccountInfo(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // return total DSC minted and total collateral value
        totalDscMinted = s_dscMinted[_user];
        collateralValueInUsd = getUserCollateralValueInUsd(_user);
        return (totalDscMinted, collateralValueInUsd);
    }

    /**
     * Returns how close the user is to being liquidated
     * If the health factor is less than 1, the user is in danger of being liquidated
     * @param _user User address
     */
    function _getHealthFactor(address _user) private view returns (uint256) {
        // return health factor
        // Total Dsc Minted
        // Total Collateral Value

        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInfo(_user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 liquidationAdjustedCollateralValue = (totalCollateralValue * COLLATERAL_RATIO) / LIQUIDATION_PRECISION;

        uint256 healthFactor = (liquidationAdjustedCollateralValue * PRECISION) / totalDscMinted;
        return healthFactor;
    }

    /**
     * @notice Revert if health factor is broken
     * @dev Health factor should be greater than 1
     * @dev Health factor = (collateralValue / DSCValue)
     * @dev Collateral value is get from Chainlink price feeds
     */
    function _revertIfHealthFactorIsBroken(address user) private view {
        // revert if health factor is broken
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DscEngine__HealthFactorIsBelowOne(healthFactor);
        }
    }

    function _redeemCollateral(address _from, address _to, address _collateralAddress, uint256 _amountCollateral)
        private
    {
        // Revert if the user doesn't have enough collateral
        if (s_userCollateral[_from][_collateralAddress] < _amountCollateral) {
            revert DscEngine__RedeemAmountIsMoreThanAvailable(
                _amountCollateral, s_userCollateral[_from][_collateralAddress]
            );
        }

        s_userCollateral[_from][_collateralAddress] -= _amountCollateral;
        emit DscEngine__CollateralRedeemed(_from, _to, _collateralAddress, _amountCollateral);

        // Transfer collateral to user
        bool success = IERC20(_collateralAddress).transfer(_to, _amountCollateral);

        if (!success) {
            revert DscEngine__TransferCollateralFailed(_collateralAddress, _amountCollateral);
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Low-level internal function, don't call this directly unless the function calling it checking for heatl factors broken
     */
    function _burnDsc(uint256 _dscAmount, address _onBehalfOf, address _dscFrom) internal {
        // burn DSC minteds
        s_dscMinted[_onBehalfOf] -= _dscAmount;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _dscAmount);
        if (!success) {
            revert DscEngine__TransferCollateralFailed(address(i_dsc), _dscAmount);
        }

        i_dsc.burn(_dscAmount);
    }

    ///////////////////////
    // Public and View Functions
    ///////////////////////

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDecentralizedStableCoin() public view returns (address) {
        return address(i_dsc);
    }

    function getUserCollateralValueInUsd(address _user) public view returns (uint256) {
        // console2.log("getUserCollateralValueInUsd(user: %s)", _user);

        // return user's collateral value in USD
        // Loop through all the collaterals of the user and get the value in USD
        uint256 totalValue;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            console2.log("collateral: %s", s_collateralTokens[i]);
            address collateralAddress = s_collateralTokens[i];
            uint256 amount = s_userCollateral[_user][collateralAddress];
            console2.log("s_userCollateral[_user][collateralAddress] %s", amount);

            uint256 value = getCollateralValueInUsd(collateralAddress, amount);
            totalValue += value;
            // Get the price feed of the collateral
            // Get the amount of collateral
            // Get the price of the collateral
            // Add the value to the total value
        }

        return totalValue;
    }

    function getCollateralAmountFromUsd(address _collateralAddress, uint256 _usdAmount) public view returns (uint256) {
        address feed = s_priceFeeds[_collateralAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price == 0) {
            return 0;
        }

        // The returned price is in 8 decimals
        // 1 ETH = 1000 USD
        // price will be 1000 * 1e8
        // _amount is 18 decimals
        // divide by 1e18 to get the value in USD with 18 decimals

        uint256 collateralAmount = (_usdAmount * PRECISION) / (uint256(price) * ADDTIONAL_FEED_PRECISION);
        return collateralAmount;
    }

    function getCollateralValueInUsd(address _collateralAddress, uint256 _amount) public view returns (uint256) {
        address feed = s_priceFeeds[_collateralAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        console2.log("priceFeed %s", price);

        // The returned price is in 8 decimals
        // 1 ETH = 1000 USD
        // price will be 1000 * 1e8
        // _amount is 18 decimals
        // divide by 1e18 to get the value in USD with 18 decimals

        uint256 usdValue = (uint256(price) * ADDTIONAL_FEED_PRECISION * _amount) / PRECISION;
        return usdValue;
    }

    function getCollateralAmount(address _collateralAddress, address _user) public view returns (uint256) {
        return s_userCollateral[_user][_collateralAddress];
    }

    function getAccountInfo(address _user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInfo(_user);
    }

    function getCollateralPriceFeed(address _collateralAddress) public view returns (address) {
        return s_priceFeeds[_collateralAddress];
    }
}
