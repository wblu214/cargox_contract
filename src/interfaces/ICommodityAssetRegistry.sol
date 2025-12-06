// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICommodityAssetRegistry {
    enum AssetStatus {
        Registered,
        InTransit,
        Collateralized,
        Cleared
    }

    function assetStatus(uint256 assetId) external view returns (AssetStatus);

    function assetReferenceValue(
        uint256 assetId
    ) external view returns (uint256);

    function assetIssuer(uint256 assetId) external view returns (address);

    function updateStatus(uint256 assetId, AssetStatus status) external;

    function registerAsset(
        address issuer,
        string calldata name,
        string calldata metadataURI,
        uint256 quantity,
        string calldata unit,
        uint256 referenceValue,
        AssetStatus status
    ) external returns (uint256 assetId);
}
