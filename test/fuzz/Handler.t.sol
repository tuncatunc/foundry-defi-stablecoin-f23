// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call function
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DscEngine} from "../../src/DscEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {MockV3Aggregator} from "@chainlink/contracts/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DscEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    uint256 public timesMintIsCalled = 0;
    address[] public usersWithCollateralDeposited;

    uint96 public constant MAX_DEPOSIT = type(uint96).max;

    constructor(DscEngine _dsce, DecentralizedStableCoin _dsc) {
        dscEngine = _dsce;
        dsc = _dsc;
        address[] memory tokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);

        wethUsdPriceFeed = dscEngine.getCollateralPriceFeed(address(weth));
        wbtcUsdPriceFeed = dscEngine.getCollateralPriceFeed(address(wbtc));
    }

    // redeem collateral

    function mintAndDepositCollateral(uint256 _collateralSeed, uint256 _amount) public {
        usersWithCollateralDeposited.push(msg.sender);
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        _amount = bound(_amount, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, _amount);
        collateral.approve(address(dscEngine), _amount);
        dscEngine.depositCollateral(address(collateral), _amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 _collateralSeed, uint256 _amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);

        vm.startPrank(msg.sender);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralAmount(address(collateral), msg.sender);
        if (maxCollateralToRedeem == 0) {
            return;
        }

        _amount = bound(_amount, 1, maxCollateralToRedeem);

        dscEngine.redeemCollateral(address(collateral), _amount);
        vm.stopPrank();
    }

    function mintDsc(uint256 _amount, uint256 _addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        // randomly select a user with collateral deposited
        address userWithDepositCollateral =
            usersWithCollateralDeposited[_addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(userWithDepositCollateral);

        int256 maxDscToMint = (int256(collateralValueInUsd) * 500 / 1000) - int256(totalDscMinted);
        console.log("Max Dsc to mint: %d", maxDscToMint);
        if (maxDscToMint < 1) {
            return;
        }

        _amount = bound(_amount, 1, uint256(maxDscToMint));

        vm.startPrank(userWithDepositCollateral);
        dscEngine.mintDsc(_amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     MockV3Aggregator priceFeed = MockV3Aggregator(wethUsdPriceFeed);
    //     priceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 _collateralSeed) internal view returns (ERC20Mock) {
        address[] memory tokens = dscEngine.getCollateralTokens();
        return (ERC20Mock(tokens[_collateralSeed % 2]));
    }
}
