// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {CommodityAssetRegistry} from "../src/CommodityAssetRegistry.sol";

/// @notice Foundry deploy script for CommodityAssetRegistry.
/// @dev Provide RECEIVABLE_POOL env var when running.
contract DeployCommodityAssetRegistry is Script {
    function run() external returns (CommodityAssetRegistry registry) {
        address receivablePool = vm.envAddress("RECEIVABLE_POOL");

        vm.startBroadcast();
        registry = new CommodityAssetRegistry(receivablePool);
        vm.stopBroadcast();
    }
}
