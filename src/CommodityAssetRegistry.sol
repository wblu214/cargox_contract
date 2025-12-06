// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CommodityAssetRegistry
/// @notice Minimal registry that tokenizes physical commodity lots so they can be
///         referenced by the credit pools described in the CCN demo deck.
contract CommodityAssetRegistry is Ownable {
    enum AssetStatus {
        Registered, // asset exists on-chain but has not started transit
        InTransit, // goods are in motion and qualify for financing
        Collateralized, // financing issued and the asset is pledged
        Cleared // borrower repaid and the asset is released
    }

    struct Asset {
        string name; // e.g. Copper Cathode
        string metadataURI; // off-chain data pointer supplied by the issuer
        uint256 quantity; // amount of commodity units that back the record
        string unit; // ton, kg, etc.
        uint256 referenceValue; // notional USD value (6 decimals to match USDT)
        address issuer; // party that registered the asset
        AssetStatus status;
    }

    event AssetRegistered(
        uint256 indexed assetId,
        address indexed issuer,
        string name,
        uint256 quantity,
        uint256 referenceValue,
        AssetStatus status
    );

    event StatusUpdated(uint256 indexed assetId, AssetStatus status);
    mapping(uint256 => Asset) private _assets;
    uint256 public nextAssetId = 1;

    constructor() Ownable(msg.sender) {}

    function registerAsset(
        address issuer,
        string calldata name,
        string calldata metadataURI,
        uint256 quantity,
        string calldata unit,
        uint256 referenceValue,
        AssetStatus status
    ) external onlyOwner returns (uint256 assetId) {
        require(issuer != address(0), "Registry: issuer required");
        require(quantity > 0, "Registry: quantity zero");
        assetId = nextAssetId++;
        _assets[assetId] = Asset({
            name: name,
            metadataURI: metadataURI,
            quantity: quantity,
            unit: unit,
            referenceValue: referenceValue,
            issuer: issuer,
            status: status
        });
        emit AssetRegistered(assetId, issuer, name, quantity, referenceValue, status);
    }

    function updateStatus(uint256 assetId, AssetStatus status) external onlyOwner {
        Asset storage asset = _assets[assetId];
        require(asset.issuer != address(0), "Registry: unknown asset");
        asset.status = status;
        emit StatusUpdated(assetId, status);
    }

    function assetStatus(uint256 assetId) external view returns (AssetStatus) {
        Asset storage asset = _assets[assetId];
        require(asset.issuer != address(0), "Registry: unknown asset");
        return asset.status;
    }

    function assetIssuer(uint256 assetId) external view returns (address) {
        Asset storage asset = _assets[assetId];
        require(asset.issuer != address(0), "Registry: unknown asset");
        return asset.issuer;
    }

    function assetReferenceValue(uint256 assetId) external view returns (uint256) {
        Asset storage asset = _assets[assetId];
        require(asset.issuer != address(0), "Registry: unknown asset");
        return asset.referenceValue;
    }

    function getAsset(uint256 assetId) external view returns (Asset memory) {
        Asset storage asset = _assets[assetId];
        require(asset.issuer != address(0), "Registry: unknown asset");
        return asset;
    }
}