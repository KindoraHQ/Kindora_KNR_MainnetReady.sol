# Kindora Token Test Suite

## Overview

This comprehensive test suite validates all functionality of the Kindora (KNR) token contract using Hardhat with Mocha and Chai. The tests cover ERC20 functionality, trading mechanics, tax distribution, anti-whale protection, and all edge cases.

## Test Environment

- **Framework**: Hardhat v2.22.15
- **Test Runner**: Mocha
- **Assertion Library**: Chai
- **Network**: Hardhat Network (local EVM)
- **Solidity Version**: 0.8.24

## Mock Contracts

The test suite includes comprehensive mock contracts to simulate external dependencies:

### MockRouter
- Simulates UniswapV2/PancakeSwap router functionality
- Supports `swapExactTokensForETHSupportingFeeOnTransferTokens`
- Supports `addLiquidityETH`
- Configurable BNB multiplier for simulating swap rates
- Tracks swap and liquidity operations for verification

### MockFactory
- Creates pair contracts
- Maintains pair mappings

### MockPair
- Represents a DEX liquidity pair
- Used to simulate buy/sell transactions

### MockWETH
- Wrapped ETH implementation for testing

### RejectingReceiver
- Special contract that rejects ETH transfers
- Used to test charity transfer failure scenarios

## Test Structure

The test suite is organized into the following categories:

### 1. ERC20 Basic Functionality (11 tests)
- Token name, symbol, decimals
- Total supply and initial balances
- Approve and allowance
- Transfer and transferFrom
- Zero amount and zero address validations

### 2. Ownership and Access Control (4 tests)
- Owner verification
- Ownership renouncement
- OnlyOwner function restrictions

### 3. Trading Enable/Disable (5 tests)
- Trading enablement process
- Charity wallet requirement
- Trading enabled only once
- Transfer restrictions before trading enabled
- Excluded address behavior

### 4. Wallet-to-Wallet Transfers (2 tests)
- No tax on wallet-to-wallet transfers
- Multiple transfer scenarios

### 5. Buy Transactions (4 tests)
- 5% tax application (1% burn + 4% to contract)
- Tax distribution verification
- TokensBurned event emission

### 6. Sell Transactions (2 tests)
- 5% tax application
- SwapBack trigger mechanism

### 7. SwapBack Mechanism (3 tests)
- Token to BNB swap
- Liquidity addition
- BNB transfer to charity wallet
- Charity transfer failure handling (fail-safe)

### 8. Anti-Whale Protection (8 tests)
- maxTxAmount enforcement on buys
- maxTxAmount enforcement on sells
- maxWalletAmount enforcement on buys
- maxWalletAmount enforcement on transfers
- Excluded address bypass
- Max limit loosening after launch (one-way)
- Prevention of tightening after launch

### 9. Buy Cooldown (4 tests)
- 10-second cooldown enforcement
- Cooldown reset after period
- Excluded address exemption
- Cooldown disable functionality

### 10. Charity Wallet Management (3 tests)
- Charity wallet setting
- Charity wallet locking after trading
- Zero address validation

### 11. Fee and Limit Exclusions (3 tests)
- Fee exclusion immutability after launch
- Limit exclusion immutability after launch
- Exclusion changes before trading

### 12. Swap and Limits Toggles (3 tests)
- Swap enabled toggle
- Cooldown enabled toggle
- Limits in effect toggle

### 13. Rescue Tokens (3 tests)
- Prevention of KNR token rescue
- Prevention of LP token rescue
- Zero address validation

### 14. Edge Cases and Constants (5 tests)
- Swap threshold verification (0.05% of supply)
- Tax constant verification (5% total: 3% charity, 1% liquidity, 1% burn)
- Initial limit verification (2% max tx/wallet)
- Cooldown constant verification (10 seconds)
- Receive function for BNB

### 15. Event Emissions (5 tests)
- TradingEnabled event
- Transfer event
- Approval event
- MaxTxUpdated event
- MaxWalletUpdated event

### 16. Integration Tests (2 tests)
- Complete buy-sell flow with taxes
- Multiple users trading scenario

## Running the Tests

### Install Dependencies
```bash
npm install
```

### Run All Tests
```bash
npm test
```

### Run Specific Test File
```bash
npx hardhat test test/hardhat/Kindora.test.js
```

### Run Tests with Gas Reporting
```bash
REPORT_GAS=true npm test
```

### Generate Coverage Report
```bash
npm run test:coverage
```

## Test Coverage

The test suite aims for 100% coverage of:
- ✅ All public and external functions
- ✅ All modifiers and access controls
- ✅ All state transitions
- ✅ All event emissions
- ✅ All error conditions and reverts
- ✅ Edge cases and boundary conditions
- ✅ Integration scenarios

## Key Test Scenarios

### Tax Distribution Test
Validates that on every buy/sell through the DEX:
- 1% is burned to the dead address
- 4% is sent to the contract (split between charity and liquidity)
- 95% is transferred to the recipient

### SwapBack Mechanism Test
Verifies that when the contract accumulates tokens >= 0.05% of supply:
- Tokens are swapped to BNB via the router
- BNB is split between liquidity and charity (1:3 ratio)
- Liquidity is added with LP tokens burned
- Charity receives BNB (or BNB stays in contract if transfer fails)

### Anti-Whale Protection Test
Ensures that:
- Buys cannot exceed maxTxAmount
- Sells cannot exceed maxTxAmount
- Wallet balances cannot exceed maxWalletAmount
- Limits can only be loosened after trading is enabled
- Excluded addresses bypass all limits

### Buy Cooldown Test
Confirms that:
- Users must wait 10 seconds between buys from the LP
- Cooldown does not apply to excluded addresses
- Cooldown can be disabled by owner

### Immutability Test
Verifies post-launch immutability:
- Charity wallet cannot be changed after trading enabled
- Fee exclusions cannot be modified after trading enabled
- Limit exclusions cannot be modified after trading enabled
- Owner cannot tighten maxTx or maxWallet after launch

## Test Utilities

### Time Manipulation
```javascript
await time.increase(BUY_COOLDOWN_SECONDS + 1);
```

### Account Impersonation
```javascript
const pairSigner = await ethers.getImpersonatedSigner(pair);
await token.connect(pairSigner).transfer(user1.address, buyAmount);
```

### Event Verification
```javascript
await expect(token.enableTrading())
  .to.emit(token, "TradingEnabled");
```

## Troubleshooting

### Network Restrictions
If you encounter network errors when downloading the Solidity compiler:
- The Hardhat network may have restrictions on external downloads
- Consider pre-downloading the compiler or using a local installation

### Gas Estimation Failures
If tests fail with gas estimation errors:
- Ensure the router has sufficient ETH for swaps
- Check that accounts have sufficient balances

## Notes

- All tests use BigInt notation for token amounts (e.g., `ethers.parseEther("1000")`)
- Tests use the Hardhat Network's time manipulation for cooldown testing
- Mock contracts accurately simulate UniswapV2 behavior
- Tests are independent and can be run in any order

## Contributing

When adding new tests:
1. Follow the existing test structure and naming conventions
2. Group related tests in describe blocks
3. Use meaningful test names that describe the expected behavior
4. Include both positive and negative test cases
5. Update this README with new test categories

## Total Test Count

**Total Tests: 61**

- ERC20 Basic Functionality: 11
- Ownership and Access Control: 4
- Trading Enable/Disable: 5
- Wallet-to-Wallet Transfers: 2
- Buy Transactions: 4
- Sell Transactions: 2
- SwapBack Mechanism: 3
- Anti-Whale Protection: 8
- Buy Cooldown: 4
- Charity Wallet Management: 3
- Fee and Limit Exclusions: 3
- Swap and Limits Toggles: 3
- Rescue Tokens: 3
- Edge Cases and Constants: 5
- Event Emissions: 5
- Integration Tests: 2
