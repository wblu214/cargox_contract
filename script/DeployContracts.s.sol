// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {MockUSDT} from "../src/MockUSDT.sol";
import {CommodityAssetRegistry} from "../src/CommodityAssetRegistry.sol";
import {ReceivablePool, IERC20} from "../src/ReceivablePool.sol";
import {ICommodityAssetRegistry} from "../src/interfaces/ICommodityAssetRegistry.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Deploys the complete CCN MVP stack (MockUSDT, CommodityAssetRegistry, ReceivablePool).
/// @dev The deployer becomes the ReceivablePool owner. The registry ownership is handed to the pool
///      so that risk actions (e.g. `createFinancingDeal`) can update asset states autonomously.
contract DeployContracts is Script {
    struct Deployment {
        MockUSDT usdt;
        CommodityAssetRegistry registry;
        ReceivablePool pool;
    }

    function run() external returns (Deployment memory contracts) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address poolOwner = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        contracts.usdt = new MockUSDT();
        contracts.registry = new CommodityAssetRegistry();
        contracts.pool = new ReceivablePool(
            IERC20(address(contracts.usdt)),
            ICommodityAssetRegistry(address(contracts.registry)),
            poolOwner
        );

        // Allow the pool to manage asset state transitions inside `createFinancingDeal`.
        contracts.registry.transferOwnership(address(contracts.pool));

        vm.stopBroadcast();

        console2.log("MockUSDT deployed at: %s", address(contracts.usdt));
        console2.log("CommodityAssetRegistry deployed at: %s", address(contracts.registry));
        console2.log("ReceivablePool deployed at: %s", address(contracts.pool));
        console2.log("Pool owner: %s", poolOwner);
    }
}
