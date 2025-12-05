// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title CommodityAssetRegistry
/// @notice Registers commodity assets and lets the ReceivablePool update their status.
contract CommodityAssetRegistry {
    enum AssetStatus {
        InTransit,
        Repaid
    }

    struct Asset {
        string commodity;
        uint256 quantity;
        uint256 valuationUSD;
        AssetStatus status;
        address seller;
    }

    uint256 public assetCount;
    address public owner;
    address public receivablePool;

    mapping(uint256 => Asset) private assets;

    event AssetRegistered(
        uint256 indexed assetId,
        address indexed seller,
        string commodity,
        uint256 quantity,
        uint256 valuationUSD
    );
    event AssetStatusUpdated(uint256 indexed assetId, AssetStatus newStatus);
    event ReceivablePoolUpdated(address indexed newReceivablePool);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyReceivablePool() {
        require(msg.sender == receivablePool, "Not receivable pool");
        _;
    }

    constructor(address initialReceivablePool) {
        owner = msg.sender;
        receivablePool = initialReceivablePool;
    }

    function registerAsset(
        string calldata commodity,
        uint256 quantity,
        uint256 valuationUSD
    ) external returns (uint256 assetId) {
        require(bytes(commodity).length > 0, "Commodity required");
        require(quantity > 0, "Quantity must be positive");
        require(valuationUSD > 0, "Valuation must be positive");

        assetId = ++assetCount;
        assets[assetId] = Asset({
            commodity: commodity,
            quantity: quantity,
            valuationUSD: valuationUSD,
            status: AssetStatus.InTransit,
            seller: msg.sender
        });

        emit AssetRegistered(assetId, msg.sender, commodity, quantity, valuationUSD);
    }

    function updateStatus(uint256 assetId, AssetStatus newStatus) external onlyReceivablePool {
        Asset storage asset = _getAssetStorage(assetId);
        asset.status = newStatus;
        emit AssetStatusUpdated(assetId, newStatus);
    }

    function getAsset(uint256 assetId) external view returns (Asset memory) {
        Asset memory asset = assets[assetId];
        require(asset.seller != address(0), "Asset does not exist");
        return asset;
    }

    function setReceivablePool(address newReceivablePool) external onlyOwner {
        require(newReceivablePool != address(0), "Invalid pool address");
        receivablePool = newReceivablePool;
        emit ReceivablePoolUpdated(newReceivablePool);
    }

    function _getAssetStorage(uint256 assetId) private view returns (Asset storage asset) {
        asset = assets[assetId];
        require(asset.seller != address(0), "Asset does not exist");
    }
}
