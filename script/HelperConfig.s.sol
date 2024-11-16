// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    uint256 private constant ANVIL_CHAIN_ID = 31337;
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;
    uint8 private constant DECIMALS = 8;
    int256 private constant WETH_PRICE = int256(2_000 * 10 ** uint256(DECIMALS));
    int256 private constant WBTC_PRICE = int256(40_000 * 10 ** uint256(DECIMALS));
    uint256 public constant DEFAULT_ANVIL_DEPLOYER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wEthAddress;
        address wBtcAddress;
        address wEthPriceFeedAddress;
        address wBtcPriceFeedAddress;
        uint256 deployerKey;
    }

    mapping(uint256 chainId => NetworkConfig chainConfig) private networkConfigs;

    function getConfig() public returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;
        if (chainId == SEPOLIA_CHAIN_ID) {
            // Anvil chain ID
            return getSepoliaConfig();
        } else if (chainId == ANVIL_CHAIN_ID) {
            // Sepolia chain ID
            return createOrGetAnvilConfig();
        } else {
            revert("Unsupported chain ID");
        }
    }

    function getSepoliaConfig() private returns (NetworkConfig memory networkConfig) {
        address dscAddress = networkConfigs[SEPOLIA_CHAIN_ID].wEthAddress;
        if (dscAddress == address(0)) {
            DecentralizedStableCoin dsc = new DecentralizedStableCoin(msg.sender);
            dscAddress = address(dsc);
        }

        networkConfig = NetworkConfig({
            wEthAddress: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            wBtcAddress: 0x52eeA312378ef46140EBE67dE8a143BA2304FD7C,
            wEthPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBtcPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        networkConfigs[SEPOLIA_CHAIN_ID] = networkConfig;
    }

    function createOrGetAnvilConfig() private returns (NetworkConfig memory) {
        address wEthAddress = networkConfigs[ANVIL_CHAIN_ID].wEthAddress;
        if (wEthAddress == address(0)) {
            vm.startBroadcast();

            ERC20Mock wEth = new ERC20Mock();
            wEth.mint(msg.sender, 1000 ether);

            ERC20Mock wBtc = new ERC20Mock();
            wBtc.mint(msg.sender, 1000 ether);

            MockV3Aggregator wEthPriceFeedAddress = new MockV3Aggregator(DECIMALS, WETH_PRICE);
            MockV3Aggregator wBtcPriceFeedAddress = new MockV3Aggregator(DECIMALS, WBTC_PRICE);

            vm.stopBroadcast();

            NetworkConfig memory networkConfig = NetworkConfig({
                wEthAddress: address(wEth),
                wBtcAddress: address(wBtc),
                wEthPriceFeedAddress: address(wEthPriceFeedAddress),
                wBtcPriceFeedAddress: address(wBtcPriceFeedAddress),
                deployerKey: DEFAULT_ANVIL_DEPLOYER_KEY
            });

            networkConfigs[ANVIL_CHAIN_ID] = networkConfig;
        }

        return networkConfigs[ANVIL_CHAIN_ID];
    }
}
