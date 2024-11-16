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
    error DscEngine__MintDscFailed();

    ///////////////////////
    // State Variables
    ///////////////////////
    uint256 private constant ADDTIONAL_FEED_PRECISION = 1e10; // price returned from Chainlink is 1e8, we need to multiply it by 1e10 to get 1e18
    uint256 private constant PRECISION = 1e18; // 18 decimals
    uint256 private constant COLLATERAL_RATIO = 50; // 150%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1; // 1

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateral; // user's token collateral
    mapping(address user => uint256 dscMinted) private s_dscMinted; // user's DSC minted
    address[] private s_collateralTokens;
    DecentralizedStableCoin private i_dsc;

    ///////////////////////
    // Events
    ///////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amount);

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
        // Check if collateral is allowed
        if (s_priceFeeds[_collateralAddress] == address(0)) {
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
        external
        moreThanZero(amount)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        // Transfer collateral to this contract
        s_userCollateral[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DscEngine__TransferCollateralFailed(tokenCollateralAddress, amount);
        }
    }

    function redeemCollateralForDsc(uint256 _dscAmount) external {
        // redeem DSC
        // burn DSC
    }

    function redeemCollateral(uint256 _collateralAmount) external {
        // redeem collateral
    }

    /**
     * @notice Mint DSC by depositing collateral
     * @param _amountDscToMint The amount of DSC to mint
     * @notice must have more collaretal than the DSC amount to mint
     */
    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) nonReentrant {
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

    // Make people burn their DSC, for their collareal not liquidated and keep collaretal DSC ratio safe
    function burnDsc(uint256 _dscAmount) external {
        // burn DSC
    }

    // 100$ ETH mints 50$ DSC
    // if ETH price goes down below $75, someone can pay $50 DSC and redeem all underlaying collateral $74 worth of ETH
    function liquidate() external {
        // liquidate collateral
    }

    function getHealthFactor() external view returns (uint256) {
        // return health factor
    }

    ///////////////////////
    // Private & Internal Functions
    ///////////////////////
    function _getTotalDscMintedAndTotalCollateralValue(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // return total DSC minted and total collateral value
        totalDscMinted = s_dscMinted[_user];
        return (totalDscMinted, getUserCollateralValueInUsd(_user));
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
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getTotalDscMintedAndTotalCollateralValue(_user);
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

    ///////////////////////
    // Public and View Functions
    ///////////////////////
    function getUserCollateralValueInUsd(address _user) public view returns (uint256) {
        console2.log("getUserCollateralValueInUsd(user: %s)", _user);

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
}
