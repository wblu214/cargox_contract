// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ICommodityAssetRegistry
} from "./interfaces/ICommodityAssetRegistry.sol";

/// @title 应收账款融资池合约
/// @notice 最小化的流动性池，为已注册的商品资产提供稳定币流动性融资
/// @dev 设计假设：
///      - 利率 / 利息在创建融资单时锁死；
///      - 借款人可以分批提取本金，但总额不超过 principal；
///      - 不管实际提取多少，最终需要按 principal + interestAmount 进行还款。
contract ReceivablePool is Ownable {
    using SafeERC20 for IERC20;

    /// @notice 融资交易结构体
    struct FinancingDeal {
        uint256 assetId; // 支持此贷款的注册资产ID
        address borrower; // 借款人（商户）
        address payer; // 还款人
        uint256 principal; // 最大可融资本金（总上限）
        uint16 interestRateBps; // 利率（基点，万分之几）
        uint64 startDate; // 融资创建时间戳
        uint64 dueDate; // 预期到期时间戳
        uint256 interestAmount; // 固定利息金额（在创建时就算死）
        uint256 drawnAmount; // 已累计提取的本金
        bool repaid; // 是否已结清
    }

    /// @notice 资金池桶结构体（按 assetId 分桶）
    struct PoolBucket {
        mapping(address => uint256) lpBalances; // LP 地址 => 存款余额
        uint256 totalDeposits; // 总存款金额（本金总和）
        uint256 availableLiquidity; // 可用流动性金额（用于放款 & 还款后的资金）
        uint256 reservedInterest; // 未偿还交易的总利息预留（风控用途）
    }

    /// @notice 存款事件
    event Deposited(
        uint256 indexed assetId,
        address indexed lp,
        uint256 amount
    );

    /// @notice 提款事件
    event Withdrawn(
        uint256 indexed assetId,
        address indexed lp,
        uint256 amount
    );

    /// @notice 创建融资交易事件
    event DealCreated(
        uint256 indexed dealId,
        uint256 indexed assetId,
        address indexed borrower,
        uint256 principal,
        uint16 interestRateBps,
        uint64 tenorDays
    );

    /// @notice 融资交易还款事件
    event DealRepaid(uint256 indexed dealId, uint256 payoffAmount);

    // 商品资产注册表（不可变）
    ICommodityAssetRegistry public immutable registry;
    // 稳定币代币合约（不可变）
    IERC20 public immutable stablecoin;

    // 资产ID => 资金池桶
    mapping(uint256 => PoolBucket) private _pools;

    // 交易ID => 融资交易
    mapping(uint256 => FinancingDeal) public deals;

    // 下一个交易ID
    uint256 public nextDealId = 1;

    /// @notice 构造函数
    /// @param stablecoin_ 稳定币代币合约地址
    /// @param registry_ 商品资产注册表合约地址
    /// @param owner_ 合约所有者地址
    constructor(
        IERC20 stablecoin_,
        ICommodityAssetRegistry registry_,
        address owner_
    ) Ownable(owner_) {
        stablecoin = stablecoin_;
        registry = registry_;
    }

    /// @notice 通过池子代理注册商品资产（池子是 registry 的 owner）
    /// @dev 仅池子 owner 可调用；状态在创建时即设定
    function registerAsset(
        address issuer,
        string calldata name,
        string calldata metadataURI,
        uint256 quantity,
        string calldata unit,
        uint256 referenceValue,
        ICommodityAssetRegistry.AssetStatus status
    ) external onlyOwner returns (uint256 assetId) {
        assetId = registry.registerAsset(
            issuer,
            name,
            metadataURI,
            quantity,
            unit,
            referenceValue,
            status
        );
    }

    /// @notice 通过池子代理更新商品资产状态（池子是 registry 的 owner）
    /// @dev 仅池子 owner 可调用
    function updateAssetStatus(
        uint256 assetId,
        ICommodityAssetRegistry.AssetStatus status
    ) external onlyOwner {
        registry.updateStatus(assetId, status);
    }

    // -------------------------------------------------------------------------
    // 核心业务流程：创建融资、分批提取、还款
    // -------------------------------------------------------------------------

    /// @notice 为特定资产ID创建融资交易（只记录条目 & 预留利息，不动流动性）
    /// @dev owner 作为风险管理员，负责利率
    function createFinancingDeal(
        uint256 assetId,
        address borrower,
        address payer,
        uint16 interestRateBps,
        uint64 tenorDays
    ) external onlyOwner returns (uint256 dealId) {
        require(borrower != address(0), "Pool: borrower missing");
        require(payer != address(0), "Pool: payer missing");

        PoolBucket storage poolData = _pools[assetId];

        // 资产必须处于运输中（InTransit），才可以拿来做应收账款融资
        ICommodityAssetRegistry.AssetStatus status = registry.assetStatus(
            assetId
        );
        require(
            status == ICommodityAssetRegistry.AssetStatus.InTransit,
            "Pool: asset not in transit"
        );

        // 资产参考价值（例如 100）
        uint256 principal = registry.assetReferenceValue(assetId);

        // 在这里就把利息算死（例如 5% 折价）
        uint256 interest = (principal * interestRateBps) / 10_000;

        // 预留利息空间（风控维度）
        poolData.reservedInterest += interest;

        // 记录融资交易
        dealId = nextDealId++;
        deals[dealId] = FinancingDeal({
            assetId: assetId,
            borrower: borrower,
            payer: payer,
            principal: principal,
            interestRateBps: interestRateBps,
            startDate: uint64(block.timestamp),
            dueDate: uint64(block.timestamp + tenorDays * 1 days),
            interestAmount: interest, // 固定利息
            drawnAmount: 0, // 尚未提取
            repaid: false
        });

        // 更新资产状态为已抵押
        registry.updateStatus(
            assetId,
            ICommodityAssetRegistry.AssetStatus.Collateralized
        );

        emit DealCreated(
            dealId,
            assetId,
            borrower,
            principal,
            interestRateBps,
            tenorDays
        );
    }

    /// @notice 借款人可以分批提取本金，总和不超过 principal
    /// @param dealId 交易ID
    /// @param amount 本次提取金额
    function drawdown(uint256 dealId, uint256 amount) external {
        FinancingDeal storage deal = deals[dealId];
        require(deal.borrower != address(0), "Pool: unknown deal");
        require(msg.sender == deal.borrower, "Pool: not borrower");
        require(!deal.repaid, "Pool: deal already repaid");
        require(amount > 0, "Pool: amount zero");

        // 资产必须处于 Collateralized
        ICommodityAssetRegistry.AssetStatus status = registry.assetStatus(
            deal.assetId
        );
        require(
            status == ICommodityAssetRegistry.AssetStatus.Collateralized,
            "Pool: asset not collateralized"
        );

        // 本金上限控制：总提取 ≤ principal
        uint256 remaining = deal.principal - deal.drawnAmount;
        require(remaining > 0, "Pool: fully drawn");
        require(amount <= remaining, "Pool: exceeds remaining principal");

        // 检查资金池可用流动性
        PoolBucket storage poolData = _pools[deal.assetId];
        require(
            poolData.availableLiquidity >= amount,
            "Pool: insufficient liquidity"
        );

        // 更新已提取金额
        deal.drawnAmount += amount;

        // 扣减可用流动性
        poolData.availableLiquidity -= amount;

        // 把钱打给借款人
        stablecoin.safeTransfer(deal.borrower, amount);
    }

    /// @notice 计算还款金额（约定的本金 + 约定的利息）
    function payoffAmount(uint256 dealId) public view returns (uint256) {
        FinancingDeal storage deal = deals[dealId];
        require(deal.borrower != address(0), "Pool: unknown deal");
        // 这里基于产品假设：利息与「融资额度承诺」挂钩，而不是实际提取额
        return deal.principal + deal.interestAmount;
    }

    /// @notice 借款人结清融资（本金+利息）
    /// @dev 还款会增加池子流动性并释放预留利息，资产状态变为 Cleared，LP 可以提款
    function repay(uint256 dealId) external {
        FinancingDeal storage deal = deals[dealId];
        require(!deal.repaid, "Pool: already repaid");
        require(msg.sender == deal.payer, "Pool: not borrower");

        // 可以要求至少提取过一点钱才允许还款
        require(deal.drawnAmount > 0, "Pool: nothing drawn");

        PoolBucket storage poolData = _pools[deal.assetId];

        uint256 payoff = payoffAmount(dealId);
        deal.repaid = true;

        // 借款人转入本金+利息
        stablecoin.safeTransferFrom(msg.sender, address(this), payoff);

        // 本金 + 利息全部进池子，供 LP 提款
        poolData.availableLiquidity += payoff;

        // 释放预留利息
        poolData.reservedInterest -= deal.interestAmount;

        emit DealRepaid(dealId, payoff);
    }

    // -------------------------------------------------------------------------
    // LP 存取款逻辑
    // -------------------------------------------------------------------------

    /// @notice LP 向特定资产池存入资金
    function deposit(uint256 assetId, uint256 amount) external {
        require(amount > 0, "Pool: amount zero");
        _ensureAssetExists(assetId);

        PoolBucket storage poolData = _pools[assetId];

        // 设计选择：只有当该资产上已经有融资需求（预留利息）时才允许存款

        require(
            poolData.reservedInterest > 0,
            "Pool: no financing deal created yet"
        );

        uint256 maxCapacity = registry.assetReferenceValue(assetId);

        // 存款后，不允许本金总额 + 预留利息超过抵押物价值
        require(
            poolData.totalDeposits + amount <=
                maxCapacity - poolData.reservedInterest,
            "Pool: asset pool is full"
        );

        poolData.lpBalances[msg.sender] += amount;
        poolData.totalDeposits += amount;
        poolData.availableLiquidity += amount;

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(assetId, msg.sender, amount);
    }

    /// @notice LP 在资产清算后提取本金+利息（按份额分配）
    function withdraw(uint256 assetId) external {
        PoolBucket storage poolData = _pools[assetId];

        ICommodityAssetRegistry.AssetStatus status = registry.assetStatus(
            assetId
        );
        require(
            status == ICommodityAssetRegistry.AssetStatus.Cleared,
            "Pool: asset not cleared"
        );

        uint256 balance = poolData.lpBalances[msg.sender];
        require(balance > 0, "Pool: nothing to withdraw");

        uint256 totalShares = poolData.totalDeposits;
        require(totalShares > 0, "Pool: no shares");

        // 池子里的"利息部分" = 当前可用流动性 - 总本金
        uint256 poolInterest = 0;
        if (poolData.availableLiquidity > totalShares) {
            poolInterest = poolData.availableLiquidity - totalShares;
        }

        // 按 LP 份额分配利息
        uint256 interestShare = (poolInterest * balance) / totalShares;
        uint256 payout = balance + interestShare;
        require(payout > 0, "Pool: zero payout");

        // 更新状态
        poolData.lpBalances[msg.sender] = 0;
        poolData.totalDeposits -= balance;
        poolData.availableLiquidity -= payout;

        // 转账给 LP
        stablecoin.safeTransfer(msg.sender, payout);

        emit Withdrawn(assetId, msg.sender, payout);
    }

    // -------------------------------------------------------------------------
    // 辅助方法 & 视图函数
    // -------------------------------------------------------------------------

    /// @notice 确保资产存在（如果 assetId 不存在，registry 实现里一般会 revert）
    function _ensureAssetExists(uint256 assetId) internal view {
        registry.assetIssuer(assetId);
    }

    /// @notice 查询 LP 在特定资产池中的存款本金余额
    function lpBalanceOf(
        uint256 assetId,
        address lp
    ) external view returns (uint256) {
        return _pools[assetId].lpBalances[lp];
    }

    /// @notice 查询特定资产池的总存款本金
    function poolTotalDeposits(
        uint256 assetId
    ) external view returns (uint256) {
        return _pools[assetId].totalDeposits;
    }

    /// @notice 查询特定资产池的可用流动性
    function availableLiquidity(
        uint256 assetId
    ) external view returns (uint256) {
        return _pools[assetId].availableLiquidity;
    }

    /// @notice 查询特定资产池的预留利息总额
    function reservedInterest(uint256 assetId) external view returns (uint256) {
        return _pools[assetId].reservedInterest;
    }
}
