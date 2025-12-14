// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @notice Mock WETH contract for testing
 */
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

/**
 * @notice Mock UniswapV2 Pair contract for simulating DEX interactions
 */
contract MockPair {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
}

/**
 * @notice Mock UniswapV2 Factory contract that creates MockPair
 */
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

/**
 * @notice Mock UniswapV2 Router contract that simulates swap and liquidity operations
 */
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

    /**
     * @notice Sets the BNB multiplier for swaps (scaled by 1e12 for precision)
     */
    function setSwapBNBMultiplier(uint256 _multiplier) external {
        swapBNBMultiplier = _multiplier;
    }

    /**
     * @notice Mock swap that converts tokens to BNB and sends to recipient
     */
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

    /**
     * @notice Mock addLiquidityETH that records the liquidity addition
     */
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

    /**
     * @notice Allow router to receive ETH for swaps
     */
    receive() external payable {}
}

/**
 * @notice Contract that rejects ETH transfers (for testing charity transfer failure)
 */
contract RejectingReceiver {
    // Explicitly reject all ETH transfers
    receive() external payable {
        revert("ETH rejected");
    }

    fallback() external payable {
        revert("ETH rejected");
    }
}
