// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DscEngine} from "../src/DscEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDsc is Script {
    function deploy() public returns (DscEngine, DecentralizedStableCoin, HelperConfig.NetworkConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        // Deploy DscEngine
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = networkConfig.wEthAddress;
        tokenAddresses[1] = networkConfig.wBtcAddress;

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = networkConfig.wEthPriceFeedAddress;
        priceFeeds[1] = networkConfig.wBtcPriceFeedAddress;

        vm.startBroadcast(networkConfig.deployerKey);
        address owner = vm.addr(networkConfig.deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(owner);
        DscEngine dscEngine = new DscEngine(tokenAddresses, priceFeeds, address(dsc));

        dsc.transferOwnership(address(dscEngine)); // Transfer ownership to DscEngine
        vm.stopBroadcast();

        return (dscEngine, dsc, helperConfig.getConfig());

        // Deploy DecentralizedStableCoin
    }

    function run() external returns (DscEngine, DecentralizedStableCoin, HelperConfig.NetworkConfig memory) {
        (DscEngine dscEngine, DecentralizedStableCoin decentralizedStableCoin, HelperConfig.NetworkConfig memory config)
        = deploy();
        return (dscEngine, decentralizedStableCoin, config);
    }
}
