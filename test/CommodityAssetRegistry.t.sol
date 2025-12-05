// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CommodityAssetRegistry} from "../src/CommodityAssetRegistry.sol";

contract CommodityAssetRegistryTest is Test {
    CommodityAssetRegistry private registry;
    address private receivablePool = address(0xBEEF);

    function setUp() public {
        registry = new CommodityAssetRegistry(receivablePool);
    }

    function testRegisterAssetStoresData() public {
        uint256 assetId = registry.registerAsset("Copper", 1000, 10_000_000);
        CommodityAssetRegistry.Asset memory asset = registry.getAsset(assetId);

        assertEq(assetId, 1);
        assertEq(asset.commodity, "Copper");
        assertEq(asset.quantity, 1000);
        assertEq(asset.valuationUSD, 10_000_000);
        assertEq(uint256(asset.status), uint256(CommodityAssetRegistry.AssetStatus.InTransit));
        assertEq(asset.seller, address(this));
    }

    function testUpdateStatusRestrictedToReceivablePool() public {
        uint256 assetId = registry.registerAsset("Aluminum", 500, 5_000_000);

        vm.expectRevert("Not receivable pool");
        registry.updateStatus(assetId, CommodityAssetRegistry.AssetStatus.Repaid);

        vm.prank(receivablePool);
        registry.updateStatus(assetId, CommodityAssetRegistry.AssetStatus.Repaid);
        CommodityAssetRegistry.Asset memory asset = registry.getAsset(assetId);
        assertEq(uint256(asset.status), uint256(CommodityAssetRegistry.AssetStatus.Repaid));
    }
}
