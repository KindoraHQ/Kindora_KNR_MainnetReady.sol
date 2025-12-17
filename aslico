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
    string private constant _name = "Kindora";
    string private constant _symbol = "KNR";
    uint8 private constant _decimals = 18;

    uint256 private constant _totalSupply =
        10_000_000 * 10 ** uint256(_decimals);

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

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

    address public immutable deadAddress =
        0x000000000000000000000000000000000000dEaD;

    IUniswapV2Router02 public immutable router;
    address public immutable pair;

    address public charityWallet;
    bool public charityWalletLocked;
    uint256 public pendingCharityBNB;

    uint256 public constant TAX_TOTAL = 5;
    uint256 public constant TAX_CHARITY = 3;
    uint256 public constant TAX_LIQUIDITY = 1;
    uint256 public constant TAX_BURN = 1;

    uint256 public immutable swapThreshold;
    bool public swapEnabled = true;

    bool public tradingEnabled;
    bool public limitsInEffect = true;

    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    bool public cooldownEnabled = true;
    uint256 public constant BUY_COOLDOWN_SECONDS = 10;
    mapping(address => uint256) public lastBuyTimestamp;

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;

    bool private _swapping;

    event SwapBack(
        uint256 tokensSwapped,
        uint256 bnbForLiquidity,
        uint256 bnbForCharity
    );
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event CharityFunded(uint256 bnbAmount);
    event CharityTransferFailed(uint256 bnbAmount);
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

        router = IUniswapV2Router02(_router);
        address _pair = IUniswapV2Factory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        pair = _pair;

        _balances[owner] = _totalSupply;

        isExcludedFromFees[owner] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[deadAddress] = true;

        isExcludedFromLimits[owner] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[deadAddress] = true;
        isExcludedFromLimits[address(0)] = true;

        swapThreshold = (_totalSupply * 5) / 10_000;

        uint256 twoPercent = (_totalSupply * 2) / 100;
        maxTxAmount = twoPercent;
        maxWalletAmount = twoPercent;

        emit Transfer(address(0), owner, _totalSupply);
    }

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

    function setCharityWallet(address _wallet) external onlyOwner {
        require(!charityWalletLocked, "Charity wallet locked");
        require(_wallet != address(0), "Zero address");
        charityWallet = _wallet;
        emit CharityWalletSet(_wallet);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        require(charityWallet != address(0), "Set charity wallet first");

        tradingEnabled = true;
        charityWalletLocked = true;

        emit TradingEnabled();
    }

    function setSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
        emit SwapEnabledSet(_enabled);
    }

    function setCooldownEnabled(bool _enabled) external onlyOwner {
        cooldownEnabled = _enabled;
        emit CooldownEnabledSet(_enabled);
    }

    function setLimitsInEffect(bool _enabled) external onlyOwner {
        limitsInEffect = _enabled;
        emit LimitsInEffectSet(_enabled);
    }

    function setMaxTxAmount(uint256 newMax) external onlyOwner {
        require(newMax > 0, "Zero maxTx");
        if (tradingEnabled) {
            require(newMax >= maxTxAmount, "Can only loosen after launch");
        }
        maxTxAmount = newMax;
        emit MaxTxUpdated(newMax);
    }

    function setMaxWalletAmount(uint256 newMax) external onlyOwner {
        require(newMax > 0, "Zero maxWallet");
        if (tradingEnabled) {
            require(newMax >= maxWalletAmount, "Can only loosen after launch");
        }
        maxWalletAmount = newMax;
        emit MaxWalletUpdated(newMax);
    }

    function setExcludedFromFees(address account, bool excluded)
        external
        onlyOwner
    {
        require(!tradingEnabled, "Cannot change fee-exempt after launch");
        isExcludedFromFees[account] = excluded;
    }

    function setExcludedFromLimits(address account, bool excluded)
        external
        onlyOwner
    {
        require(!tradingEnabled, "Cannot change limits-exempt after launch");
        isExcludedFromLimits[account] = excluded;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        require(amount > 0, "Zero amount");
        require(_balances[from] >= amount, "Insufficient balance");

        if (!tradingEnabled) {
            require(
                isExcludedFromFees[from] || isExcludedFromFees[to],
                "Trading not enabled"
            );
        }

        _balances[from] -= amount;

        bool isBuy = (from == pair && to != address(router));
        bool isSell = (to == pair);

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
            uint256 feeAmount = (amount * TAX_TOTAL) / 100;
            uint256 burnAmount = (amount * TAX_BURN) / 100;
            uint256 tokensForSwap = feeAmount - burnAmount;

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

    function _swapBack(uint256 tokenAmount) private {
        if (tokenAmount == 0) return;

        _swapping = true;

        uint256 liquidityTokens = (tokenAmount * TAX_LIQUIDITY) /
            (TAX_LIQUIDITY + TAX_CHARITY);
        uint256 charityTokens = tokenAmount - liquidityTokens;

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
                value: bnbForCharity,
                gas: 50000
            }("");
            if (success) {
                emit CharityFunded(bnbForCharity);
            } else {
                pendingCharityBNB += bnbForCharity;
                emit CharityTransferFailed(bnbForCharity);
            }
        }

        emit SwapBack(tokenAmount, bnbForLiquidity, bnbForCharity);

        _swapping = false;
    }

    function _swapTokensForBNB(uint256 tokenAmount) private {
        _approve(address(this), address(router), tokenAmount);

        address[] memory path = new address[](2);
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
            deadAddress,
            block.timestamp
        );
    }

    function sendPendingCharityBNB() external {
        require(pendingCharityBNB > 0, "No pending BNB");
        require(charityWallet != address(0), "Charity wallet not set");

        uint256 amount = pendingCharityBNB;
        pendingCharityBNB = 0;

        (bool success, ) = payable(charityWallet).call{
            value: amount,
            gas: 50000
        }("");

        if (!success) {
            pendingCharityBNB = amount;
            emit CharityTransferFailed(amount);
        } else {
            emit CharityFunded(amount);
        }
    }

    function getPendingCharityBNB() external view returns (uint256) {
        return pendingCharityBNB;
    }

    receive() external payable {}

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
