// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {MockUSDT} from "../src/MockUSDT.sol";
import {CommodityAssetRegistry} from "../src/CommodityAssetRegistry.sol";
import {ReceivablePool, IERC20} from "../src/ReceivablePool.sol";
import {ICommodityAssetRegistry} from "../src/interfaces/ICommodityAssetRegistry.sol";

contract FullProcessTest is Test {
    MockUSDT internal usdt;
    CommodityAssetRegistry internal registry;
    ReceivablePool internal pool;

    address internal lp = address(0xABCD);
    address internal borrower = address(0xBEEF);
    address internal payer = address(0xCAFE);
    address internal owner = address(this);

    uint256 internal constant ASSET_VALUE = 1_000_000e6;
    uint16 internal constant INTEREST_BPS = 150; // 1.5%
    uint256 internal constant INTEREST_AMOUNT = (ASSET_VALUE * INTEREST_BPS) / 10_000;
    uint256 internal constant LP_CAPITAL = ASSET_VALUE - INTEREST_AMOUNT; // 资金池最多可接受的本金
    uint64 internal constant TENOR_DAYS = 30;

    function setUp() public {
        usdt = new MockUSDT();
        registry = new CommodityAssetRegistry();
        pool = new ReceivablePool(IERC20(address(usdt)), ICommodityAssetRegistry(address(registry)), owner);
        
        // 给LP铸币并授权
        usdt.mint(lp, 2_000_000e6);
        vm.prank(lp);
        usdt.approve(address(pool), type(uint256).max);
        
        // 给还款人铸币并授权
        usdt.mint(payer, 2_000_000e6);
        vm.prank(payer);
        usdt.approve(address(pool), type(uint256).max);
    }

    /// @dev Owner registers the asset, promotes it to InTransit, then hands registry control to the pool.
    function _registerAsset(string memory name, string memory metadata) internal returns (uint256 assetId) {
        vm.prank(owner);
        assetId = registry.registerAsset(
            borrower,
            name,
            metadata,
            1000,
            "ton",
            ASSET_VALUE,
            CommodityAssetRegistry.AssetStatus.Registered
        );

        vm.prank(owner);
        registry.updateStatus(assetId, CommodityAssetRegistry.AssetStatus.InTransit);

        vm.prank(owner);
        registry.transferOwnership(address(pool));
    }

    /// @dev The pool (current owner of the registry) marks the asset as cleared so LPs can exit.
    function _markAssetCleared(uint256 assetId) internal {
        vm.prank(address(pool));
        registry.updateStatus(assetId, CommodityAssetRegistry.AssetStatus.Cleared);
    }

    function testFullBusinessProcess() public {
        // 1. 注册资产并由 owner 将状态从 Registered 推动到 InTransit
        uint256 assetId = _registerAsset("Copper", "ipfs://copper");
        
        console.log("Step 1: Asset registered and moved to InTransit with ID %d", assetId);

        // 2. LP尝试存款，应该失败，因为还没有创建融资交易
        vm.prank(lp);
        vm.expectRevert(bytes("Pool: no financing deal created yet"));
        pool.deposit(assetId, 500_000e6);
        
        console.log("Step 2: LP deposit failed as expected before financing deal creation");

        // 3. 合约所有者创建融资交易
        vm.prank(owner);
        uint256 dealId = pool.createFinancingDeal(
            assetId,
            borrower,
            payer,
            INTEREST_BPS,
            TENOR_DAYS
        );
        
        console.log("Step 3: Financing deal created with ID %d", dealId);
        console.log("Principal: %d", ASSET_VALUE);
        console.log("Interest: %d", (ASSET_VALUE * INTEREST_BPS) / 10_000);
        assertEq(
            uint256(registry.assetStatus(assetId)),
            uint256(CommodityAssetRegistry.AssetStatus.Collateralized)
        );

        // 4. LP存款
        vm.prank(lp);
        pool.deposit(assetId, LP_CAPITAL);
        
        console.log("Step 4: LP deposited %d", LP_CAPITAL);
        assertEq(pool.poolTotalDeposits(assetId), LP_CAPITAL);
        assertEq(pool.lpBalanceOf(assetId, lp), LP_CAPITAL);
        assertEq(pool.availableLiquidity(assetId), LP_CAPITAL);

        // 5. 借款人提取资金
        vm.prank(borrower);
        pool.drawdown(dealId, LP_CAPITAL);
        
        console.log("Step 5: Borrower drew down %d", LP_CAPITAL);
        assertEq(usdt.balanceOf(borrower), LP_CAPITAL);
        assertEq(pool.availableLiquidity(assetId), 0);

        // 6. 还款人还款
        uint256 payoff = pool.payoffAmount(dealId);
        console.log("Step 6: Payoff amount is %d", payoff);
        
        vm.prank(payer);
        pool.repay(dealId);
        
        console.log("Step 6: Payer repaid %d", payoff);
        assertEq(usdt.balanceOf(address(pool)), payoff);
        assertEq(pool.availableLiquidity(assetId), payoff);

        // 7. owner（当前为池子）更新资产状态为 Cleared，以便 LP 提现
        _markAssetCleared(assetId);
        
        console.log("Step 7: Asset status updated to Cleared");

        // 8. LP提取本金和利息
        uint256 lpBalanceBefore = usdt.balanceOf(lp);
        vm.prank(lp);
        pool.withdraw(assetId);
        
        uint256 lpBalanceAfter = usdt.balanceOf(lp);
        uint256 lpEarnings = lpBalanceAfter - lpBalanceBefore;
        
        console.log(
            "Step 8: LP withdrew %d (principal: %d, interest: %d)",
            lpEarnings,
            LP_CAPITAL,
            lpEarnings - LP_CAPITAL
        );
        assertEq(pool.lpBalanceOf(assetId, lp), 0);
        assertEq(lpEarnings, payoff);
    }

    function testMultipleDrawdowns() public {
        // 1. 注册资产并推进到可融资状态
        uint256 assetId = _registerAsset("Iron", "ipfs://iron");

        // 2. 创建融资交易
        vm.prank(owner);
        uint256 dealId = pool.createFinancingDeal(
            assetId,
            borrower,
            payer,
            INTEREST_BPS,
            TENOR_DAYS
        );

        // 3. LP存款
        vm.prank(lp);
        pool.deposit(assetId, LP_CAPITAL);

        // 4. 借款人分批提取资金
        uint256 halfDraw = LP_CAPITAL / 2;
        vm.prank(borrower);
        pool.drawdown(dealId, halfDraw);
        
        assertEq(usdt.balanceOf(borrower), halfDraw);
        assertEq(pool.availableLiquidity(assetId), LP_CAPITAL - halfDraw);

        vm.prank(borrower);
        pool.drawdown(dealId, LP_CAPITAL - halfDraw);
        
        assertEq(usdt.balanceOf(borrower), LP_CAPITAL);
        assertEq(pool.availableLiquidity(assetId), 0);

        // 5. 还款人还款
        uint256 payoff = pool.payoffAmount(dealId);
        vm.prank(payer);
        pool.repay(dealId);
        assertEq(usdt.balanceOf(address(pool)), payoff);
        
        // 6. 更新资产状态为已清算 (由owner操作)
        _markAssetCleared(assetId);
        
        // 7. LP提取本金和利息
        uint256 lpBalanceBefore = usdt.balanceOf(lp);
        vm.prank(lp);
        pool.withdraw(assetId);
        
        uint256 lpEarnings = usdt.balanceOf(lp) - lpBalanceBefore;
        assertEq(lpEarnings, payoff);
    }
}
