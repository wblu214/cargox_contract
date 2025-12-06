## PicWe Commodity Credit Network (CCN) MVP

Receivable financing demo for commodity lots. Assets are registered in an on-chain registry, financed through a receivable pool, and repaid so LPs can exit with principal + interest. **Permissions are open for hackathon/demo use**: anyone can register assets, move statuses, and create deals; business checks (correct status, matching borrower/payer, nonzero addresses) still apply.

### Contracts
- `CommodityAssetRegistry`: Stores asset metadata and status (`Registered → InTransit → Collateralized → Cleared`).
- `ReceivablePool`: Manages financing deals, LP deposits/withdrawals, borrower drawdowns, payer repayments, and status updates.
- `MockUSDT`: 6-decimal ERC20 used as the stablecoin.

### Status enum (frontends must match)
- `0 Registered`
- `1 InTransit`
- `2 Collateralized`
- `3 Cleared`

### Core flow (demo script)
1) `registerAsset(...)` → returns `assetId`.  
2) `updateAssetStatus(assetId, InTransit)` (value `1`).  
3) `createFinancingDeal(assetId, borrower, payer, interestBps, tenorDays)` → returns `dealId`.  
4) LP `deposit(assetId, amount)` (after approving USDT).  
5) Borrower `drawdown(dealId, amount)` (must be `borrower`).  
6) Payer `repay(dealId)` (must be `payer`; pays `payoffAmount(dealId)`).  
7) `updateAssetStatus(assetId, Cleared)` (value `3`).  
8) LP `withdraw(assetId)`.

### BSC Testnet deployment (chain 97)
- `MockUSDT`: `0xE707FEE53BfDd6C69Fc8D05caF148a6C28Edf49b`
- `CommodityAssetRegistry`: `0x8dB7E0ed381a43de2b7c46585529e9bA0063eAA1`
- `ReceivablePool`: `0x9F213109d2E9ADEA09e247AFC56bB2A03214C4E7`

### Local development
Prereqs: [Foundry](https://book.getfoundry.sh/getting-started/installation)
```bash
forge test
```

### Deployment
Broadcast the full stack (MockUSDT, registry, pool):
```bash
export PRIVATE_KEY=0x...
export RPC_URL=https://your.rpc
forge script script/DeployContracts.s.sol --rpc-url $RPC_URL --broadcast -vvvv
```
Script output prints deployed addresses.

### Project structure
- `src/`: contracts
- `test/`: end-to-end Foundry tests
- `script/`: deployment script
- `out/`: build artifacts
