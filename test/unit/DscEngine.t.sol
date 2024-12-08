// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";

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
    uint256 public AMOUNT_COLLATERAL = 100 ether;

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

    // Modifiers
    modifier depositedCollateral(address _user, uint256 _amount) {
        // Prank and the USER
        vm.startPrank(_user);

        // USER approves engine to spend weth
        ERC20Mock wEth = ERC20Mock(config.wEthAddress);
        wEth.approve(address(dscEngine), _amount);

        // Desposit weth as collateral
        dscEngine.depositCollateral(config.wEthAddress, _amount);

        vm.stopPrank();
        _;
    }

    ///////////////////////
    // Contructor Tests
    ///////////////////////

    function testDeployDscEngine() public view {
        assert(dscEngine != DscEngine(address(0)));
        console2.log("DscEngine address: ", address(dscEngine));
        console2.log("Dsc address: ", address(dsc));
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = config.wEthAddress;

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = config.wEthPriceFeedAddress;
        priceFeeds[1] = config.wBtcPriceFeedAddress;

        vm.expectRevert(DscEngine.DscEngine__InvalidInputLength.selector);
        new DscEngine(tokenAddresses, priceFeeds, address(dsc));
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

    function testGetTokenAmountFeeds() public view {
        // 1000 USD => 1000/2000 = 0.5 wEth
        uint256 collateralAmountEth = dscEngine.getCollateralAmountFromUsd(config.wEthAddress, 1_000 ether);

        // 1000 USD => 1000/40_000 = 0.025 wBtc
        uint256 collateralAmountBtc = dscEngine.getCollateralAmountFromUsd(config.wBtcAddress, 1_000 ether);
        assertEq(collateralAmountEth, 0.5 ether);
        assertEq(collateralAmountBtc, 0.025 ether);
    }

    ///////////////////////
    // Desposit Collateral Tests
    ///////////////////////

    function testRevertsIfCollateralIsZero() public {
        uint256 wethAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(DscEngine.DscEngine__AmountIsLessThanZero.selector, wethAmount));
        dscEngine.depositCollateral(config.wEthAddress, wethAmount);
    }

    function testRevertsIfCollateralIsNotApproved() public {
        vm.startPrank(USER);
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(DscEngine.DscEngine__CollateralNotAllowed.selector, address(ranToken)));
        dscEngine.depositCollateral(address(ranToken), 100 ether);
        vm.stopPrank();
    }

    function testCanDepositCollataralAndGetAccountInfo() public depositedCollateral(USER, AMOUNT_COLLATERAL) {
        uint256 colleratalValueInUsd = dscEngine.getUserCollateralValueInUsd(address(USER));
        uint256 expectedWethUsdAmount = AMOUNT_COLLATERAL * 2_000;

        assertEq(colleratalValueInUsd, expectedWethUsdAmount);
    }

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

        // Desposit weth as collateral
        dscEngine.depositCollateral(config.wEthAddress, wethAmount);

        // Deposit wbtc as collateral
        dscEngine.depositCollateral(config.wBtcAddress, wbtcAmount);

        vm.stopPrank();

        uint256 colleratalValueInUsd = dscEngine.getUserCollateralValueInUsd(address(USER));

        assertEq(colleratalValueInUsd, expectedWethUsdAmount + expectedWbtcUsdAmount);
    }

    function testDepositCollateralEmitsCollateralDepositedEvent() public {
        // Arrange
        uint256 wethAmount = 5 ether;
        ERC20Mock wEth = ERC20Mock(config.wEthAddress);

        // Act

        // Prank and the USER
        vm.startPrank(USER);

        // USER approves engine to spend weth
        wEth.approve(address(dscEngine), wethAmount);

        vm.expectEmit(true, true, false, false);
        emit DscEngine.DscEngine__CollateralDeposited(USER, config.wEthAddress, wethAmount);
        // Desposit weth as collateral
        dscEngine.depositCollateral(config.wEthAddress, wethAmount);

        vm.stopPrank();

        // Assert
    }
}
