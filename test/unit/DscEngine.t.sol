// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DscEngine} from "../../src/DscEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DscEngineTest is Test {
    DeployDsc deployDsc;
    DscEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig.NetworkConfig config;
    address public USER = makeAddr("user");

    function setUp() public {
        deployDsc = new DeployDsc();
        (DscEngine _dscEngine, DecentralizedStableCoin _dsc, HelperConfig.NetworkConfig memory _config) =
            deployDsc.run();
        dscEngine = _dscEngine;
        dsc = _dsc;
        config = _config;

        // Mint wEth and wBtc to user
        ERC20Mock(config.wEthAddress).mint(USER, 100 ether);
        ERC20Mock(config.wBtcAddress).mint(USER, 100 ether);
    }

    function testDeployDscEngine() public view {
        assert(dscEngine != DscEngine(address(0)));
        console2.log("DscEngine address: ", address(dscEngine));
        console2.log("Dsc address: ", address(dsc));
    }

    ///////////////////////
    // Price Feed Tests
    ///////////////////////
    function testPriceFeed() public view {
        uint256 wethAmount = 5 ether;
        uint256 expectedWethUsdAmount = wethAmount * 2_000;

        uint256 wbtcAmount = 5 ether;
        uint256 expectedWbtcUsdAmount = wbtcAmount * 40_000;

        uint256 actualWethUsdAmount = dscEngine.getCollateralValueInUsd(config.wEthAddress, wethAmount);
        uint256 actualWbtcUsdAmount = dscEngine.getCollateralValueInUsd(config.wBtcAddress, wbtcAmount);

        assertEq(actualWethUsdAmount, expectedWethUsdAmount);
        assertEq(actualWbtcUsdAmount, expectedWbtcUsdAmount);
    }

    ///////////////////////
    // Desposit Collateral Tests
    ///////////////////////

    function testDepositCollateral() public {
        uint256 wethAmount = 5 ether;
        uint256 expectedWethUsdAmount = wethAmount * 2_000;

        uint256 wbtcAmount = 5 ether;
        uint256 expectedWbtcUsdAmount = wbtcAmount * 40_000;
        ERC20Mock wEth = ERC20Mock(config.wEthAddress);
        ERC20Mock wBtc = ERC20Mock(config.wBtcAddress);

        // Prank and the USER
        vm.startPrank(USER);

        // USER approves engine to spend weth
        wEth.approve(address(dscEngine), wethAmount);
        wBtc.approve(address(dscEngine), wbtcAmount);

        uint256 allowance = wEth.allowance(USER, address(dscEngine));

        console2.log("dscEngine %s ", address(dscEngine));
        console2.log("USER %s ", USER);
        console2.log("dscEngine Allowance on behalf of USER", allowance);
        console2.log("weth address %s ", config.wEthAddress);

        // Desposit weth as collateral
        dscEngine.depositCollateral(config.wEthAddress, wethAmount);

        // Deposit wbtc as collateral
        dscEngine.depositCollateral(config.wBtcAddress, wbtcAmount);

        vm.stopPrank();

        uint256 colleratalValueInUsd = dscEngine.getUserCollateralValueInUsd(address(USER));

        assertEq(colleratalValueInUsd, expectedWethUsdAmount + expectedWbtcUsdAmount);
    }
}
