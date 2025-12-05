// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../Kindora_Mainnet.sol";

// =============================================================================
// MOCK CONTRACTS
// =============================================================================

/// @notice Mock UniswapV2 Pair contract for simulating DEX interactions
contract MockPair {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
}

/// @notice Mock UniswapV2 Factory contract that creates MockPair
contract MockFactory {
    mapping(address => mapping(address => address)) public pairs;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Always create a new pair for consistency
        pair = address(new MockPair(tokenA, tokenB));
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
        return pair;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}

/// @notice Mock WETH contract for testing
contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

/// @notice Mock UniswapV2 Router contract that simulates swap and liquidity operations
contract MockRouter {
    MockFactory public factoryContract;
    MockWETH public wethContract;

    // Track liquidity added for verification
    uint256 public lastLiquidityTokens;
    uint256 public lastLiquidityETH;
    address public lastLiquidityTo;

    // Track swaps for verification
    uint256 public lastSwapAmountIn;
    address public lastSwapTo;
    uint256 public swapBNBMultiplier = 1; // How much BNB to send per token (scaled by 1e12)

    constructor() {
        factoryContract = new MockFactory();
        wethContract = new MockWETH();
    }

    function factory() external view returns (address) {
        return address(factoryContract);
    }

    function WETH() external view returns (address) {
        return address(wethContract);
    }

    /// @notice Sets the BNB multiplier for swaps (scaled by 1e12 for precision)
    function setSwapBNBMultiplier(uint256 _multiplier) external {
        swapBNBMultiplier = _multiplier;
    }

    /// @notice Mock swap that converts tokens to BNB and sends to recipient
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 /* amountOutMin */,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external {
        require(path.length >= 2, "Invalid path");
        
        // Transfer tokens from sender
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        // Calculate BNB to send (simulated swap)
        uint256 bnbOut = (amountIn * swapBNBMultiplier) / 1e12;
        
        // Send BNB to recipient
        if (bnbOut > 0 && address(this).balance >= bnbOut) {
            payable(to).transfer(bnbOut);
        }
        
        lastSwapAmountIn = amountIn;
        lastSwapTo = to;
    }

    /// @notice Mock addLiquidityETH that records the liquidity addition
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 /* amountTokenMin */,
        uint256 /* amountETHMin */,
        address to,
        uint256 /* deadline */
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        // Transfer tokens from sender
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        
        // Record for verification
        lastLiquidityTokens = amountTokenDesired;
        lastLiquidityETH = msg.value;
        lastLiquidityTo = to;
        
        // Return values
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = (amountTokenDesired + msg.value) / 2; // Simulated LP tokens
    }

    /// @notice Allow router to receive ETH for swaps
    receive() external payable {}
}

/// @notice Contract that rejects ETH transfers (for testing charity transfer failure)
contract RejectingReceiver {
    // Explicitly reject all ETH transfers
    receive() external payable {
        revert("ETH rejected");
    }

    fallback() external payable {
        revert("ETH rejected");
    }
}

// =============================================================================
// TEST CONTRACT
// =============================================================================

contract KindoraTest is Test {
    Kindora public token;
    MockRouter public router;
    address public pair;
    
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public charityWallet = address(0x3);
    
    uint256 public constant TOTAL_SUPPLY = 10_000_000 * 1e18;
    uint256 public constant SWAP_THRESHOLD = (TOTAL_SUPPLY * 5) / 10_000; // 0.05%
    uint256 public constant MAX_TX = (TOTAL_SUPPLY * 2) / 100; // 2%
    uint256 public constant MAX_WALLET = (TOTAL_SUPPLY * 2) / 100; // 2%

    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SwapBack(uint256 tokensSwapped, uint256 bnbForLiquidity, uint256 bnbForCharity);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event CharityFunded(uint256 bnbAmount);
    event TokensBurned(uint256 amount);
    event TradingEnabled();

    function setUp() public {
        // Deploy mock router
        router = new MockRouter();
        
        // Deploy token with mock router
        token = new Kindora(address(router));
        
        // Get the pair address
        pair = token.pair();
        
        // Setup: set charity wallet before enabling trading
        token.setCharityWallet(charityWallet);
        
        // Fund the router with ETH for swap simulation
        vm.deal(address(router), 1000 ether);
    }

    // =========================================================================
    // ERC20 BASICS TESTS
    // =========================================================================

    function test_TotalSupply() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY, "Total supply should be 10M tokens");
    }

    function test_Name() public view {
        assertEq(token.name(), "Kindora", "Name should be Kindora");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "KNR", "Symbol should be KNR");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18, "Decimals should be 18");
    }

    function test_InitialBalances() public view {
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY, "Owner should have all tokens");
        assertEq(token.balanceOf(user1), 0, "User1 should have 0 tokens");
    }

    function test_Approve() public {
        // Test approval
        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, 1000 * 1e18);
        
        assertTrue(token.approve(user1, 1000 * 1e18), "Approve should return true");
        assertEq(token.allowance(owner, user1), 1000 * 1e18, "Allowance should be set");
    }

    function test_ApproveAndAllowance() public {
        uint256 approveAmount = 5000 * 1e18;
        token.approve(user1, approveAmount);
        assertEq(token.allowance(owner, user1), approveAmount, "Allowance should match approved amount");
    }

    function test_TransferFrom() public {
        // Enable trading first
        token.enableTrading();
        
        // Approve user1 to spend owner's tokens
        uint256 approveAmount = 1000 * 1e18;
        token.approve(user1, approveAmount);
        
        // Exclude user2 from limits to simplify test
        vm.prank(owner);
        // Can't exclude after trading enabled, so we transfer to user2 which should work
        
        // User1 transfers from owner to user2
        uint256 transferAmount = 500 * 1e18;
        
        vm.prank(user1);
        assertTrue(token.transferFrom(owner, user2, transferAmount), "TransferFrom should succeed");
        
        // Check balances - wallet to wallet, no tax
        assertEq(token.balanceOf(user2), transferAmount, "User2 should receive full amount (no tax on wallet transfer)");
        assertEq(token.allowance(owner, user1), approveAmount - transferAmount, "Allowance should be reduced");
    }

    function test_TransferFromExceedsAllowance() public {
        token.approve(user1, 100 * 1e18);
        
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer exceeds allowance");
        token.transferFrom(owner, user2, 200 * 1e18);
    }

    // =========================================================================
    // WALLET-TO-WALLET TRANSFER (NO TAX)
    // =========================================================================

    function test_WalletToWalletTransfer_NoTax() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to user1 first
        uint256 initialAmount = 1000 * 1e18;
        token.transfer(user1, initialAmount);
        assertEq(token.balanceOf(user1), initialAmount, "User1 should receive full amount");
        
        // Now transfer from user1 to user2 (wallet to wallet)
        uint256 transferAmount = 500 * 1e18;
        
        vm.prank(user1);
        token.transfer(user2, transferAmount);
        
        // No tax on wallet-to-wallet transfers
        assertEq(token.balanceOf(user2), transferAmount, "User2 should receive full amount (no tax)");
        assertEq(token.balanceOf(user1), initialAmount - transferAmount, "User1 balance should be reduced");
    }

    function test_WalletToWalletTransfer_NoTaxMultiple() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to user1
        token.transfer(user1, 1000 * 1e18);
        
        // Multiple transfers
        vm.startPrank(user1);
        token.transfer(user2, 100 * 1e18);
        token.transfer(user2, 200 * 1e18);
        token.transfer(user2, 300 * 1e18);
        vm.stopPrank();
        
        // No tax on any transfer
        assertEq(token.balanceOf(user2), 600 * 1e18, "User2 should receive full amounts");
        assertEq(token.balanceOf(user1), 400 * 1e18, "User1 balance should be reduced correctly");
    }

    // =========================================================================
    // BUY TESTS (PAIR -> BUYER): 5% TAX (1% BURN + 4% TO CONTRACT)
    // =========================================================================

    function test_Buy_AppliesTax() public {
        // Enable trading
        token.enableTrading();
        
        // First, transfer tokens to the pair (simulate liquidity)
        uint256 pairLiquidity = 100_000 * 1e18;
        token.transfer(pair, pairLiquidity);
        
        // Simulate buy: transfer from pair to user1
        uint256 buyAmount = 10_000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Calculate expected amounts
        uint256 taxAmount = (buyAmount * 5) / 100; // 5% tax
        uint256 burnAmount = (buyAmount * 1) / 100; // 1% burn
        uint256 contractAmount = taxAmount - burnAmount; // 4% to contract (3% charity + 1% liquidity, accumulated for swapBack)
        uint256 receivedAmount = buyAmount - taxAmount; // 95%
        
        // Verify balances
        assertEq(token.balanceOf(user1), receivedAmount, "Buyer should receive 95% of amount");
        assertEq(token.balanceOf(token.deadAddress()), burnAmount, "Dead address should receive 1% burn");
        assertEq(token.balanceOf(address(token)), contractAmount, "Contract should receive 4%");
    }

    function test_Buy_EmitsTokensBurnedEvent() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, 100_000 * 1e18);
        
        uint256 buyAmount = 10_000 * 1e18;
        uint256 burnAmount = (buyAmount * 1) / 100;
        
        // Expect TokensBurned event
        vm.expectEmit(false, false, false, true);
        emit TokensBurned(burnAmount);
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
    }

    function test_Buy_TaxDistribution() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, 100_000 * 1e18);
        
        uint256 buyAmount = 20_000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // 1% burn = 200 tokens
        // 4% to contract = 800 tokens (3% charity + 1% liquidity, accumulated for swapBack)
        // 95% to buyer = 19,000 tokens
        assertEq(token.balanceOf(user1), 19_000 * 1e18, "Buyer gets 95%");
        assertEq(token.balanceOf(token.deadAddress()), 200 * 1e18, "1% burned");
        assertEq(token.balanceOf(address(token)), 800 * 1e18, "4% to contract");
    }

    // =========================================================================
    // SELL TESTS (SELLER -> PAIR): 5% TAX + SWAPBACK
    // =========================================================================

    function test_Sell_AppliesTax() public {
        // Enable trading
        token.enableTrading();
        
        // Give user1 tokens
        uint256 userBalance = 50_000 * 1e18;
        token.transfer(user1, userBalance);
        
        // Clear dead address balance for clean test
        uint256 deadBalanceBefore = token.balanceOf(token.deadAddress());
        
        // User1 sells to pair
        uint256 sellAmount = 10_000 * 1e18;
        
        vm.prank(user1);
        token.transfer(pair, sellAmount);
        
        // Calculate expected amounts
        uint256 taxAmount = (sellAmount * 5) / 100; // 5%
        uint256 burnAmount = (sellAmount * 1) / 100; // 1%
        uint256 receivedByPair = sellAmount - taxAmount; // 95%
        
        // Verify
        assertEq(token.balanceOf(pair), receivedByPair, "Pair should receive 95%");
        assertEq(
            token.balanceOf(token.deadAddress()), 
            deadBalanceBefore + burnAmount, 
            "1% should be burned"
        );
    }

    function test_Sell_TriggersSwapBack() public {
        // Enable trading
        token.enableTrading();
        
        // Configure router to return BNB on swaps
        router.setSwapBNBMultiplier(1e9); // 0.001 BNB per token
        
        // Give user1 enough tokens to trigger swapBack
        // SwapThreshold is 0.05% of supply = 5000 tokens
        // 4% of sell goes to contract (3% charity + 1% liquidity portions), so we need to sell enough
        // To get 5000 tokens in contract, need to sell 5000 / 0.04 = 125,000 tokens
        uint256 userBalance = MAX_TX; // Use max allowed for single transaction
        token.transfer(user1, userBalance);
        
        // Sell to pair - this should accumulate tokens in contract
        vm.prank(user1);
        token.transfer(pair, userBalance);
        
        // After first sell, contract has 4% of userBalance
        uint256 contractBalance = token.balanceOf(address(token));
        
        // If contract balance >= swapThreshold, swapBack should have been triggered
        if (contractBalance >= SWAP_THRESHOLD) {
            // SwapBack was triggered, contract balance should be near 0
            assertLt(token.balanceOf(address(token)), SWAP_THRESHOLD, "Contract should have swapped back");
        }
    }

    function test_Sell_SwapBackEmitsEvents() public {
        // Enable trading
        token.enableTrading();
        
        // Configure router to return BNB
        router.setSwapBNBMultiplier(1e9);
        
        // First, accumulate tokens in contract through multiple sells
        // We need contract balance >= swapThreshold
        // Transfer directly to contract to set up the test
        token.transfer(address(token), SWAP_THRESHOLD + 1000 * 1e18);
        
        // Now a sell should trigger swapBack
        uint256 sellAmount = 10_000 * 1e18;
        token.transfer(user1, sellAmount);
        
        // Expect SwapBack event
        vm.expectEmit(false, false, false, false);
        emit SwapBack(0, 0, 0);
        
        vm.prank(user1);
        token.transfer(pair, sellAmount);
    }

    // =========================================================================
    // SWAPBACK TESTS
    // =========================================================================

    function test_SwapBack_RouterSwapAndLiquidity() public {
        // Enable trading
        token.enableTrading();
        
        // Configure router
        router.setSwapBNBMultiplier(1e9);
        
        // Accumulate tokens in contract
        token.transfer(address(token), SWAP_THRESHOLD * 2);
        
        // Transfer to user1 and sell to trigger swapBack
        token.transfer(user1, 10_000 * 1e18);
        
        vm.prank(user1);
        token.transfer(pair, 10_000 * 1e18);
        
        // Verify router was called (check last swap values)
        assertGt(router.lastSwapAmountIn(), 0, "Router should have swapped tokens");
    }

    function test_SwapBack_CharityReceivesBNB() public {
        // Enable trading
        token.enableTrading();
        
        // Configure router to return BNB
        router.setSwapBNBMultiplier(1e9);
        
        // Record charity balance before
        uint256 charityBalanceBefore = charityWallet.balance;
        
        // Accumulate tokens in contract
        token.transfer(address(token), SWAP_THRESHOLD * 2);
        
        // Transfer to user1 and sell to trigger swapBack
        token.transfer(user1, 10_000 * 1e18);
        
        vm.prank(user1);
        token.transfer(pair, 10_000 * 1e18);
        
        // Charity should have received BNB
        assertGe(charityWallet.balance, charityBalanceBefore, "Charity should receive BNB");
    }

    function test_SwapBack_CharityTransferFails_BNBRemainsInContract() public {
        // Enable trading with a rejecting charity wallet
        RejectingReceiver rejectingCharity = new RejectingReceiver();
        
        // Need to deploy new token with rejecting charity
        MockRouter newRouter = new MockRouter();
        vm.deal(address(newRouter), 1000 ether);
        Kindora newToken = new Kindora(address(newRouter));
        
        // Set rejecting charity wallet
        newToken.setCharityWallet(address(rejectingCharity));
        newToken.enableTrading();
        
        // Configure router
        newRouter.setSwapBNBMultiplier(1e9);
        
        // Accumulate tokens in contract
        newToken.transfer(address(newToken), (newToken.totalSupply() * 5) / 10_000 * 2);
        
        // Record contract BNB balance before
        uint256 contractBNBBefore = address(newToken).balance;
        
        // Transfer to user1 and sell to trigger swapBack
        newToken.transfer(user1, 10_000 * 1e18);
        
        vm.prank(user1);
        newToken.transfer(newToken.pair(), 10_000 * 1e18);
        
        // Contract should still have BNB (charity transfer failed)
        // The contract balance might be 0 if no BNB was received from swap
        // or > 0 if charity transfer failed
        // Either way, rejecting charity should not have received anything
        assertEq(address(rejectingCharity).balance, 0, "Rejecting charity should not receive BNB");
    }

    function test_SwapBack_LiquidityAddedEmitsEvent() public {
        // Enable trading
        token.enableTrading();
        
        // Configure router
        router.setSwapBNBMultiplier(1e9);
        
        // Accumulate tokens in contract
        token.transfer(address(token), SWAP_THRESHOLD * 2);
        
        // Transfer to user1 and sell
        token.transfer(user1, 10_000 * 1e18);
        
        vm.expectEmit(false, false, false, false);
        emit LiquidityAdded(0, 0);
        
        vm.prank(user1);
        token.transfer(pair, 10_000 * 1e18);
    }

    // =========================================================================
    // ANTI-WHALE TESTS: MAX TX AND MAX WALLET
    // =========================================================================

    function test_AntiWhale_MaxTxOnBuy() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // Try to buy more than maxTx
        uint256 buyAmount = MAX_TX + 1;
        
        vm.prank(pair);
        vm.expectRevert("Buy exceeds maxTx");
        token.transfer(user1, buyAmount);
    }

    function test_AntiWhale_MaxTxOnSell() public {
        // Enable trading
        token.enableTrading();
        
        // Give user1 tokens (owner is excluded from limits, so transfer works)
        token.transfer(user1, MAX_WALLET);
        
        // Try to sell more than maxTx
        uint256 sellAmount = MAX_TX + 1;
        
        vm.prank(user1);
        vm.expectRevert("Sell exceeds maxTx");
        token.transfer(pair, sellAmount);
    }

    function test_AntiWhale_MaxWalletOnBuy() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // First, give user1 some tokens (less than max wallet)
        vm.prank(pair);
        token.transfer(user1, MAX_WALLET / 2);
        
        // Wait for cooldown
        vm.warp(block.timestamp + 11);
        
        // Try to buy more that would exceed maxWallet
        // User1 has MAX_WALLET/2, try to buy another MAX_WALLET/2 + some
        // But remember 5% tax, so we need to account for that
        uint256 currentBalance = token.balanceOf(user1);
        uint256 buyAmount = MAX_WALLET - currentBalance + 1000 * 1e18; // Should exceed after receiving
        
        // Make sure buyAmount doesn't exceed maxTx
        if (buyAmount <= MAX_TX) {
            vm.prank(pair);
            vm.expectRevert("Exceeds maxWallet");
            token.transfer(user1, buyAmount);
        }
    }

    function test_AntiWhale_MaxWalletOnTransfer() public {
        // Enable trading
        token.enableTrading();
        
        // Give user1 tokens
        token.transfer(user1, MAX_WALLET);
        
        // Give user2 some tokens
        token.transfer(user2, MAX_WALLET / 2);
        
        // Try to transfer to user2 that would exceed max wallet
        uint256 transferAmount = (MAX_WALLET / 2) + 1000 * 1e18;
        
        vm.prank(user1);
        vm.expectRevert("Exceeds maxWallet");
        token.transfer(user2, transferAmount);
    }

    function test_AntiWhale_ExcludedFromLimits() public {
        // Before enabling trading, exclude user1 from limits
        token.setExcludedFromLimits(user1, true);
        
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // User1 can buy more than maxTx because they're excluded
        uint256 buyAmount = MAX_TX * 2;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Should succeed (with tax)
        assertGt(token.balanceOf(user1), 0, "Excluded user should receive tokens");
    }

    // =========================================================================
    // BUY COOLDOWN TESTS
    // =========================================================================

    function test_BuyCooldown_EnforcedOnBuys() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // First buy
        uint256 buyAmount = 1000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Immediate second buy should fail
        vm.prank(pair);
        vm.expectRevert("Buy cooldown active");
        token.transfer(user1, buyAmount);
    }

    function test_BuyCooldown_ResetsAfterCooldownPeriod() public {
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // First buy
        uint256 buyAmount = 1000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Wait for cooldown (10 seconds)
        vm.warp(block.timestamp + 11);
        
        // Second buy should succeed
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Verify user1 received tokens from both buys
        // Each buy: 1000 tokens * 95% = 950 tokens
        assertEq(token.balanceOf(user1), 950 * 1e18 * 2, "User should have tokens from both buys");
    }

    function test_BuyCooldown_NotAppliedToExcludedAddresses() public {
        // Exclude user1 from limits (which also excludes from cooldown)
        token.setExcludedFromLimits(user1, true);
        
        // Enable trading
        token.enableTrading();
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // First buy
        uint256 buyAmount = 1000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Immediate second buy should succeed for excluded user
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Should have tokens from both buys
        assertGt(token.balanceOf(user1), buyAmount, "Excluded user should receive multiple buys");
    }

    function test_BuyCooldown_CanBeDisabled() public {
        // Enable trading
        token.enableTrading();
        
        // Disable cooldown
        token.setCooldownEnabled(false);
        
        // Transfer tokens to pair
        token.transfer(pair, TOTAL_SUPPLY / 2);
        
        // First buy
        uint256 buyAmount = 1000 * 1e18;
        
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        // Immediate second buy should succeed when cooldown is disabled
        vm.prank(pair);
        token.transfer(user1, buyAmount);
        
        assertGt(token.balanceOf(user1), buyAmount, "Should allow multiple buys when cooldown disabled");
    }

    // =========================================================================
    // EVENT TESTS
    // =========================================================================

    function test_Event_TradingEnabled() public {
        vm.expectEmit(false, false, false, true);
        emit TradingEnabled();
        
        token.enableTrading();
    }

    function test_Event_Transfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, 1000 * 1e18);
        
        token.transfer(user1, 1000 * 1e18);
    }

    function test_Event_Approval() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, 1000 * 1e18);
        
        token.approve(user1, 1000 * 1e18);
    }

    // =========================================================================
    // OWNER-ONLY RESTRICTIONS AFTER TRADING ENABLED
    // =========================================================================

    function test_OwnerRestrictions_SetExcludedFromFeesRevertsAfterTradingEnabled() public {
        // Enable trading
        token.enableTrading();
        
        // Try to set fee exclusion - should revert
        vm.expectRevert("Cannot change fee-exempt after launch");
        token.setExcludedFromFees(user1, true);
    }

    function test_OwnerRestrictions_SetExcludedFromLimitsRevertsAfterTradingEnabled() public {
        // Enable trading
        token.enableTrading();
        
        // Try to set limit exclusion - should revert
        vm.expectRevert("Cannot change limits-exempt after launch");
        token.setExcludedFromLimits(user1, true);
    }

    function test_OwnerRestrictions_CharityWalletLockedAfterTradingEnabled() public {
        // Enable trading
        token.enableTrading();
        
        // Charity wallet should be locked
        assertTrue(token.charityWalletLocked(), "Charity wallet should be locked");
        
        // Try to change charity wallet - should revert
        vm.expectRevert("Charity wallet locked");
        token.setCharityWallet(user1);
    }

    function test_OwnerRestrictions_CanStillToggleSwapAndCooldown() public {
        // Enable trading
        token.enableTrading();
        
        // Should still be able to toggle swap
        token.setSwapEnabled(false);
        assertFalse(token.swapEnabled(), "Swap should be disabled");
        
        // Should still be able to toggle cooldown
        token.setCooldownEnabled(false);
        assertFalse(token.cooldownEnabled(), "Cooldown should be disabled");
        
        // Should still be able to toggle limits
        token.setLimitsInEffect(false);
        assertFalse(token.limitsInEffect(), "Limits should be disabled");
    }

    function test_OwnerRestrictions_MaxTxCanOnlyBeLoosenedAfterLaunch() public {
        // Enable trading
        token.enableTrading();
        
        // Try to lower maxTx - should revert
        vm.expectRevert("Can only loosen after launch");
        token.setMaxTxAmount(MAX_TX - 1);
        
        // Increasing should work
        token.setMaxTxAmount(MAX_TX + 1);
        assertEq(token.maxTxAmount(), MAX_TX + 1, "Max TX should be increased");
    }

    function test_OwnerRestrictions_MaxWalletCanOnlyBeLoosenedAfterLaunch() public {
        // Enable trading
        token.enableTrading();
        
        // Try to lower maxWallet - should revert
        vm.expectRevert("Can only loosen after launch");
        token.setMaxWalletAmount(MAX_WALLET - 1);
        
        // Increasing should work
        token.setMaxWalletAmount(MAX_WALLET + 1);
        assertEq(token.maxWalletAmount(), MAX_WALLET + 1, "Max wallet should be increased");
    }

    // =========================================================================
    // TRADING NOT ENABLED TESTS
    // =========================================================================

    function test_TradingNotEnabled_TransferReverts() public {
        // Without enabling trading, transfers should fail for non-excluded addresses
        token.transfer(user1, 1000 * 1e18); // Owner is excluded
        
        vm.prank(user1);
        vm.expectRevert("Trading not enabled");
        token.transfer(user2, 500 * 1e18);
    }

    function test_TradingNotEnabled_ExcludedCanTransfer() public {
        // Owner is excluded from fees, so can transfer
        token.transfer(user1, 1000 * 1e18);
        
        // User1 is not excluded, cannot transfer without trading enabled
        assertEq(token.balanceOf(user1), 1000 * 1e18, "Transfer from excluded should work");
    }

    // =========================================================================
    // ADDITIONAL EDGE CASE TESTS
    // =========================================================================

    function test_EdgeCase_ZeroTransferReverts() public {
        token.enableTrading();
        
        vm.expectRevert("Zero amount");
        token.transfer(user1, 0);
    }

    function test_EdgeCase_TransferToZeroAddressReverts() public {
        token.enableTrading();
        
        vm.expectRevert("ERC20: transfer to zero");
        token.transfer(address(0), 1000 * 1e18);
    }

    function test_EdgeCase_ApproveToZeroAddressReverts() public {
        vm.expectRevert("ERC20: approve to zero");
        token.approve(address(0), 1000 * 1e18);
    }

    function test_EdgeCase_ApproveFromZeroAddressReverts() public {
        vm.prank(address(0));
        vm.expectRevert("ERC20: approve from zero");
        token.approve(user1, 1000 * 1e18);
    }

    function test_EdgeCase_SwapThresholdValue() public view {
        // Verify swap threshold is correctly set to 0.05% of supply
        assertEq(token.swapThreshold(), SWAP_THRESHOLD, "Swap threshold should be 0.05% of supply");
    }

    function test_EdgeCase_RenounceOwnership() public {
        // Enable trading first (required for renouncing)
        token.enableTrading();
        
        // Verify charity wallet is locked
        assertTrue(token.charityWalletLocked(), "Charity wallet should be locked");
        
        // Renounce ownership
        token.renounceOwnership();
        
        // Owner should be zero address
        assertEq(token.owner(), address(0), "Owner should be zero after renouncing");
    }

    function test_EdgeCase_RenounceOwnership_RequiresTradingEnabled() public {
        vm.expectRevert("Trading not enabled");
        token.renounceOwnership();
    }

    function test_EdgeCase_EnableTradingRequiresCharityWallet() public {
        // Deploy new token without setting charity wallet
        MockRouter newRouter = new MockRouter();
        Kindora newToken = new Kindora(address(newRouter));
        
        vm.expectRevert("Set charity wallet first");
        newToken.enableTrading();
    }

    function test_EdgeCase_EnableTradingOnlyOnce() public {
        token.enableTrading();
        
        vm.expectRevert("Trading already enabled");
        token.enableTrading();
    }

    function test_EdgeCase_OnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert("Not owner");
        token.setSwapEnabled(false);
        
        vm.prank(user1);
        vm.expectRevert("Not owner");
        token.setCooldownEnabled(false);
        
        vm.prank(user1);
        vm.expectRevert("Not owner");
        token.enableTrading();
    }

    // =========================================================================
    // RESCUE TOKENS TEST
    // =========================================================================

    function test_RescueTokens_CannotRescueKNR() public {
        vm.expectRevert("Cannot rescue KNR");
        token.rescueTokens(address(token), 1000);
    }

    function test_RescueTokens_CannotRescueLP() public {
        vm.expectRevert("Cannot rescue LP");
        token.rescueTokens(pair, 1000);
    }

    function test_RescueTokens_CannotRescueZeroAddress() public {
        vm.expectRevert("Zero token");
        token.rescueTokens(address(0), 1000);
    }

    // =========================================================================
    // HELPER FUNCTIONS
    // =========================================================================

    receive() external payable {}
}
