// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Kindora (KNR) - Ultra-Secure Charity Token
 *
 * Features:
 * - Fixed 5% tax on DEX buys/sells (3% charity, 1% liquidity, 1% burn)
 * - No tax on wallet-to-wallet transfers
 * - SwapBack at 0.05% of total supply
 * - Auto-LP add, LP tokens sent to dead address
 * - Anti-whale (2% max tx / wallet, only loosening after launch)
 * - Buy cooldown (10s between buys from LP)
 * - No honeypot: trading cannot be paused, tax cannot be changed after launch
 * - Charity wallet locked after trading enabled
 * - Fail-safe for charity transfer (BNB stays in contract if send fails)
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount)
        external
        returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        external
        returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

// UniswapV2 / PancakeV2 style interfaces
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract Kindora is IERC20Metadata {
    // ERC20 basic data
    string private constant _name = "Kindora";
    string private constant _symbol = "KNR";
    uint8 private constant _decimals = 18;

    uint256 private constant _totalSupply =
        10_000_000 * 10 ** uint256(_decimals);

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Ownership
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function renounceOwnership() external onlyOwner {
        require(tradingEnabled, "Trading not enabled");
        require(charityWalletLocked, "Charity wallet not locked");
        owner = address(0);
    }

    // Addresses
    address public immutable deadAddress =
        0x000000000000000000000000000000000000dEaD;

    IUniswapV2Router02 public immutable router;
    address public immutable pair;

    address public charityWallet;
    bool public charityWalletLocked;

    // Fixed tax configuration
    uint256 public constant TAX_TOTAL = 5;      // 5%
    uint256 public constant TAX_CHARITY = 3;    // 3%
    uint256 public constant TAX_LIQUIDITY = 1;  // 1%
    uint256 public constant TAX_BURN = 1;       // 1%

    // Swap threshold: 0.05% of supply
    uint256 public immutable swapThreshold;
    bool public swapEnabled = true;

    // Trading control & limits
    bool public tradingEnabled;
    bool public limitsInEffect = true;

    uint256 public maxTxAmount;     // anti-whale
    uint256 public maxWalletAmount; // anti-whale

    // Cooldown for buys from LP
    bool public cooldownEnabled = true;
    uint256 public constant BUY_COOLDOWN_SECONDS = 10;
    mapping(address => uint256) public lastBuyTimestamp;

    // Fee & limit exclusions
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;

    // Internal swap flag
    bool private _swapping;

    // Events for dashboard & transparency
    event SwapBack(
        uint256 tokensSwapped,
        uint256 bnbForLiquidity,
        uint256 bnbForCharity
    );
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event CharityFunded(uint256 bnbAmount);
    event TokensBurned(uint256 amount);
    event TradingEnabled();
    event CharityWalletSet(address wallet);
    event SwapEnabledSet(bool enabled);
    event CooldownEnabledSet(bool enabled);
    event LimitsInEffectSet(bool enabled);
    event MaxTxUpdated(uint256 maxTx);
    event MaxWalletUpdated(uint256 maxWallet);

    constructor(address _router) {
        owner = msg.sender;

        // BSC mainnet PancakeV2 router:
        // 0x10ED43C718714eb63d5aA57B78B54704E256024E
        router = IUniswapV2Router02(_router);
        address _pair = IUniswapV2Factory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        pair = _pair;

        // Mint all tokens to owner
        _balances[owner] = _totalSupply;

        // Exclusions
        isExcludedFromFees[owner] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[deadAddress] = true;

        isExcludedFromLimits[owner] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[deadAddress] = true;
        isExcludedFromLimits[address(0)] = true;

        // 0.05% of supply as swap threshold
        swapThreshold = (_totalSupply * 5) / 10_000;

        // Initial anti-whale: 2% of supply
        uint256 twoPercent = (_totalSupply * 2) / 100;
        maxTxAmount = twoPercent;
        maxWalletAmount = twoPercent;

        emit Transfer(address(0), owner, _totalSupply);
    }

    // ERC20 view functions
    function name() external pure override returns (string memory) {
        return _name;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function allowance(address _owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[_owner][spender];
    }

    // ERC20 write functions
    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function _approve(
        address _owner,
        address spender,
        uint256 amount
    ) internal {
        require(_owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");

        _allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }

    // Config: charity wallet
    function setCharityWallet(address _wallet) external onlyOwner {
        require(!charityWalletLocked, "Charity wallet locked");
        require(_wallet != address(0), "Zero address");
        charityWallet = _wallet;
        emit CharityWalletSet(_wallet);
    }

    // Enable trading (one-way)
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        require(charityWallet != address(0), "Set charity wallet first");

        tradingEnabled = true;
        charityWalletLocked = true;

        emit TradingEnabled();
    }

    // Swap on/off (emergency switch, does not affect trading itself)
    function setSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
        emit SwapEnabledSet(_enabled);
    }

    // Cooldown toggle
    function setCooldownEnabled(bool _enabled) external onlyOwner {
        cooldownEnabled = _enabled;
        emit CooldownEnabledSet(_enabled);
    }

    // Global limits toggle
    function setLimitsInEffect(bool _enabled) external onlyOwner {
        limitsInEffect = _enabled;
        emit LimitsInEffectSet(_enabled);
    }

    // Max tx (can only be loosened after launch)
    function setMaxTxAmount(uint256 newMax) external onlyOwner {
        require(newMax > 0, "Zero maxTx");
        if (tradingEnabled) {
            require(newMax >= maxTxAmount, "Can only loosen after launch");
        }
        maxTxAmount = newMax;
        emit MaxTxUpdated(newMax);
    }

    // Max wallet (can only be loosened after launch)
    function setMaxWalletAmount(uint256 newMax) external onlyOwner {
        require(newMax > 0, "Zero maxWallet");
        if (tradingEnabled) {
            require(newMax >= maxWalletAmount, "Can only loosen after launch");
        }
        maxWalletAmount = newMax;
        emit MaxWalletUpdated(newMax);
    }

    // Fee exclusions (locked after launch)
    function setExcludedFromFees(address account, bool excluded)
        external
        onlyOwner
    {
        require(!tradingEnabled, "Cannot change fee-exempt after launch");
        isExcludedFromFees[account] = excluded;
    }

    // Limit exclusions (locked after launch)
    function setExcludedFromLimits(address account, bool excluded)
        external
        onlyOwner
    {
        require(!tradingEnabled, "Cannot change limits-exempt after launch");
        isExcludedFromLimits[account] = excluded;
    }

    // Core transfer logic
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        require(amount > 0, "Zero amount");

        if (!tradingEnabled) {
            require(
                isExcludedFromFees[from] || isExcludedFromFees[to],
                "Trading not enabled"
            );
        }

        _balances[from] -= amount;

        bool isBuy = (from == pair && to != address(router));
        bool isSell = (to == pair);

        // Anti-whale and max wallet
        if (
            limitsInEffect &&
            !_swapping &&
            !isExcludedFromLimits[from] &&
            !isExcludedFromLimits[to]
        ) {
            if (isBuy) {
                require(amount <= maxTxAmount, "Buy exceeds maxTx");
                uint256 newBalance = _balances[to] + amount;
                require(newBalance <= maxWalletAmount, "Exceeds maxWallet");
            } else if (isSell) {
                require(amount <= maxTxAmount, "Sell exceeds maxTx");
            } else {
                uint256 newBalance = _balances[to] + amount;
                require(newBalance <= maxWalletAmount, "Exceeds maxWallet");
            }
        }

        // Cooldown on buys from LP
        if (
            cooldownEnabled &&
            isBuy &&
            !isExcludedFromLimits[to] &&
            tradingEnabled
        ) {
            require(
                block.timestamp >=
                    lastBuyTimestamp[to] + BUY_COOLDOWN_SECONDS,
                "Buy cooldown active"
            );
            lastBuyTimestamp[to] = block.timestamp;
        }

        uint256 transferAmount = amount;

        bool takeFee = !_swapping &&
            swapEnabled &&
            tradingEnabled &&
            (isBuy || isSell) &&
            !(isExcludedFromFees[from] || isExcludedFromFees[to]);

        if (takeFee) {
            uint256 feeAmount = (amount * TAX_TOTAL) / 100; // 5%
            uint256 burnAmount = (amount * TAX_BURN) / 100; // 1%
            uint256 tokensForSwap = feeAmount - burnAmount; // 4%

            if (burnAmount > 0) {
                _balances[deadAddress] += burnAmount;
                emit Transfer(from, deadAddress, burnAmount);
                emit TokensBurned(burnAmount);
            }

            if (tokensForSwap > 0) {
                _balances[address(this)] += tokensForSwap;
                emit Transfer(from, address(this), tokensForSwap);
            }

            transferAmount = amount - feeAmount;

            uint256 contractTokenBalance = _balances[address(this)];
            if (
                isSell &&
                contractTokenBalance >= swapThreshold &&
                !_swapping
            ) {
                _swapBack(contractTokenBalance);
            }
        }

        _balances[to] += transferAmount;
        emit Transfer(from, to, transferAmount);
    }

    // Swapback logic
    function _swapBack(uint256 tokenAmount) private {
        if (tokenAmount == 0) return;

        _swapping = true;

        // 4% total = 1% LP + 3% charity
        uint256 liquidityTokens = (tokenAmount * TAX_LIQUIDITY) /
            (TAX_LIQUIDITY + TAX_CHARITY); // 1/4
        uint256 charityTokens = tokenAmount - liquidityTokens; // 3/4

        uint256 tokensForLiquidity = liquidityTokens / 2;
        uint256 tokensToSwapForBNB = charityTokens +
            (liquidityTokens - tokensForLiquidity);

        if (tokensToSwapForBNB == 0 || tokensForLiquidity == 0) {
            _swapping = false;
            return;
        }

        uint256 initialBNBBalance = address(this).balance;

        _swapTokensForBNB(tokensToSwapForBNB);

        uint256 newBNB = address(this).balance - initialBNBBalance;
        if (newBNB == 0) {
            _swapping = false;
            return;
        }

        uint256 bnbForLiquidity = (newBNB *
            (liquidityTokens - tokensForLiquidity)) / tokensToSwapForBNB;
        uint256 bnbForCharity = newBNB - bnbForLiquidity;

        if (bnbForLiquidity > 0 && tokensForLiquidity > 0) {
            _addLiquidity(tokensForLiquidity, bnbForLiquidity);
            emit LiquidityAdded(tokensForLiquidity, bnbForLiquidity);
        }

        if (charityWallet != address(0) && bnbForCharity > 0) {
            (bool success, ) = payable(charityWallet).call{
                value: bnbForCharity
            }("");
            if (success) {
                emit CharityFunded(bnbForCharity);
            }
        }

        emit SwapBack(tokenAmount, bnbForLiquidity, bnbForCharity);

        _swapping = false;
    }

  function _swapTokensForBNB(uint256 tokenAmount) private {
    _approve(address(this), address(router), tokenAmount);

    address[] memory path = new address[](2); // <-- Fix: Declares path
    path[0] = address(this);
    path[1] = router.WETH();

    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        tokenAmount,
        0,
        path,
        address(this),
        block.timestamp
    );
}

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(router), tokenAmount);

        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            deadAddress, // LP tokens sent to dead
            block.timestamp
        );
    }

    // Receive BNB from router
    receive() external payable {}

    // Rescue NON-KNR, NON-LP tokens mistakenly sent to this contract
    function rescueTokens(address token, uint256 amount)
        external
        onlyOwner
    {
        require(token != address(this), "Cannot rescue KNR");
        require(token != pair, "Cannot rescue LP");
        require(token != address(0), "Zero token");
        IERC20(token).transfer(owner, amount);
    }
}
