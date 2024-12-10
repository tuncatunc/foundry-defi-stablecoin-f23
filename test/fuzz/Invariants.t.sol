// SPDX-License-Identifier: MIT
// What are invariant properties of the contract?

// 1. Total value if DSC should always be less than total value of collataral
// 2. Getter view functions should never revert
// 3.

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DscEngine} from "../../src/DscEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDsc deployDsc;
    DscEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig.NetworkConfig networkConfig;
    Handler handler;

    function setUp() external {
        console.log("Setting up the test");
        deployDsc = new DeployDsc();
        console.log("Deploying DSC");
        (dscEngine, dsc, networkConfig) = deployDsc.run();
        console.log("DSC deployed");
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));

        // Don't call redeem collateral, unless there is collateral to redeem
    }

    function invariant_protocolMustHaveMoreValueThenTotalSupplyOfDsc() public view {
        console.log("Checking invariant: protocol must have more value than total supply of DSC");
        address wEthAddress = networkConfig.wEthAddress;
        address wBtcAddress = networkConfig.wBtcAddress;
        IERC20 wEth = IERC20(wEthAddress);
        IERC20 wBtc = IERC20(wBtcAddress);
        uint256 wethDeposited = wEth.balanceOf(address(dscEngine));
        uint256 wbtcDeposited = wBtc.balanceOf(address(dscEngine));

        uint256 ethCollateralValueInUsd = dscEngine.getCollateralValueInUsd(wEthAddress, wethDeposited);
        uint256 btcCollateralValueInUsd = dscEngine.getCollateralValueInUsd(wBtcAddress, wbtcDeposited);
        uint256 totalCollateralValueInUsd = ethCollateralValueInUsd + btcCollateralValueInUsd;

        uint256 totalSupply = dsc.totalSupply();

        console.log("wEth deposited: %d", wethDeposited);
        console.log("wBtc deposited: %d", wbtcDeposited);
        console.log("Total Supply of DSC: %d", totalSupply);
        console.log("Times mint called: %d", handler.timesMintIsCalled());

        require(
            totalCollateralValueInUsd >= totalSupply,
            "Invariant: total value of DSC should be less than total supply of DSC"
        );
    }

    function invariant_gettersShouldNotRevert() public view {
        address[] memory tokens = dscEngine.getCollateralTokens();
        address weth = tokens[0];
        address wbtc = tokens[1];

        dscEngine.getDecentralizedStableCoin();

        dscEngine.getCollateralAmountFromUsd(weth, 1 ether);
        dscEngine.getCollateralAmountFromUsd(wbtc, 1 ether);

        dscEngine.getCollateralValueInUsd(weth, 1 ether);
        dscEngine.getCollateralValueInUsd(wbtc, 1 ether);

        dscEngine.getCollateralAmount(weth, address(0));

        dscEngine.getAccountInfo(address(0));
    }
}
