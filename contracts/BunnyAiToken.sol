//  SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswap.sol";

contract BunnyAiToken is ERC20, Ownable {
    mapping(address => bool) public blacklist;
    mapping(address => bool) public feeExempt;
    mapping(address => bool) public maxTxExempt;
    mapping(address => uint) private lastTx;
    mapping(address => bool) private cooldownWhitelist;

    uint8 public constant blockCooldown = 5;

    address public marketing;
    address public stakingPool;

    uint public totalBuyFee;
    uint public totalSellFee;

    uint public maxWalletAmount;
    uint public maxTxAmount;
    uint public maxBuyTxAmount;
    uint public maxSellTxAmount;

    uint public marketingFees;
    uint public stakingFees;
    uint public liquidityFees;

    uint public totalMarketingFees;
    uint public totalStakingFees;
    uint public totalLiquidityFees;

    uint public swapThreshold = 10 ether;

    uint8[3] public buyFees;
    uint8[3] public sellFees;
    uint256 public constant BASE = 100;
    address public constant DEAD_WALLET =
        0x000000000000000000000000000000000000dEaD;

    bool public tradingOpen = false;

    bool private swapping = false;

    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    /// @notice Modifier to check if this is an internal swap
    modifier swapExecuting() {
        swapping = true;
        _;
        swapping = false;
    }

    constructor(address _mkt, address _stk) ERC20("Bunny AI", "BUNAI") {
        require(_mkt != address(0) && _stk != address(0), "Invalid address");
        marketing = _mkt;
        stakingPool = _stk;
        // 23 million tokens
        _mint(msg.sender, 23_000_000 ether);
        // max Tx amount is 1% of total supply
        maxTxAmount = 23_000_000 ether / 100;
        maxBuyTxAmount = maxTxAmount;
        maxSellTxAmount = maxTxAmount;
        // max wallet amount is 2% of total supply
        maxWalletAmount = maxTxAmount * 3;

        buyFees[0] = 5;
        buyFees[1] = 2;
        buyFees[2] = 1;
        sellFees[0] = 5;
        sellFees[1] = 2;
        sellFees[2] = 1;

        totalBuyFee = buyFees[0] + buyFees[1] + buyFees[2];
        totalSellFee = sellFees[0] + sellFees[1] + sellFees[2];

        // Set Uniswap V2 Router for both ETH and ARBITRUM
        if (block.chainid == 1) {
            router = IUniswapV2Router02(
                0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
            );
        } else if (block.chainid == 42161) {
            // need to double check this address on ARBITRUM
            router = IUniswapV2Router02(
                0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106
            );
        } else revert("Chain not supported");

        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        pair = IUniswapV2Pair(factory.createPair(address(this), router.WETH()));

        setFeeExempt(address(this), true);
        setFeeExempt(owner(), true);
        setMaxTxExempt(address(this), true);
        setMaxTxExempt(owner(), true);
        setCooldownWhitelist(address(this), true);
        setCooldownWhitelist(owner(), true);
        setCooldownWhitelist(marketing, true);
        setCooldownWhitelist(address(pair), true);
        setCooldownWhitelist(address(router), true);
    }

    /// @notice Allowed to receive ETH
    receive() external payable {}

    /// @notice Checks before Token Transfer
    /// @param from Address of sender
    /// @param to Address of receiver
    /// @param amount Amount of tokens to transfer
    /// @dev Checks if the sender and receiver are blacklisted or if amounts are within limits
    function _beforeTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from == address(0) || to == address(0) || swapping) return;
        require(
            !blacklist[from] && !blacklist[to],
            "BUNAI: Blacklisted address"
        );
        // Only Owner can transfer tokens before trading is open
        require(tradingOpen || from == owner(), "BUNAI: Trading blocked");

        if (!maxTxExempt[from]) {
            if (from == address(pair)) {
                require(
                    amount <= maxBuyTxAmount,
                    "BUNAI: Max buy amount exceeded"
                );
            } else if (to == address(pair)) {
                require(
                    amount <= maxSellTxAmount,
                    "BUNAI: Max sell amount exceeded"
                );
            }
        }
        if (to != address(pair) && to != address(router)) {
            require(
                balanceOf(to) + amount <= maxWalletAmount,
                "BUNAI: Max wallet amount exceeded"
            );
        }
        if (!cooldownWhitelist[from]) {
            require(lastTx[from] <= block.number, "BUNAI: Bot?");
            lastTx[from] = block.number + blockCooldown;
        }
    }

    /// @notice Burn tokens from sender address
    /// @param amount Amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn tokens from other owners as long as it is approved
    /// @param account Address of owner
    /// @param amount Amount of tokens to burn
    function burnFrom(address account, uint256 amount) external {
        require(
            amount <= allowance(account, msg.sender),
            "BUNAI: Not enough allowance"
        );
        uint256 decreasedAllowance = allowance(account, msg.sender) - amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }

    /// @notice Internal transfer tokens
    /// @param sender Address of receiver
    /// @param recipient Address of receiver
    /// @param amount Amount of tokens to transfer
    /// @dev calls _beforeTokenTransfer, manages taxes and transfers tokens
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        _beforeTransfer(sender, recipient, amount);
        if (!swapping) {
            uint currentTokensHeld = balanceOf(address(this));
            if (
                currentTokensHeld >= swapThreshold &&
                sender != address(pair) &&
                sender != address(router)
            ) {
                _handleSwapAndDistribute(currentTokensHeld);
            }

            if (
                ((sender == address(pair) && !feeExempt[recipient]) ||
                    (recipient == address(pair) && !feeExempt[sender]))
            ) {
                uint totalFee = takeFee(amount, sender == address(pair));
                super._transfer(sender, address(this), totalFee);
                amount -= totalFee;
            }
        }

        super._transfer(sender, recipient, amount);
    }

    /// @notice Set the fee for a specific transaction type
    /// @param amount Amount of transaction
    /// @param isBuy True if transaction is a buy, false if transaction is a sell
    /// @return totalFee Total fee taken in this transaction
    function takeFee(
        uint256 amount,
        bool isBuy
    ) internal returns (uint256 totalFee) {
        uint selectedFee = isBuy ? totalBuyFee : totalSellFee;
        totalFee = (selectedFee * amount) / BASE;

        uint8[3] storage fees = isBuy ? buyFees : sellFees;

        uint marketingFee = (fees[0] * totalFee) / selectedFee;
        uint poolFee = (fees[1] * totalFee) / selectedFee;
        uint liqFee = totalFee - marketingFee - poolFee;

        marketingFees += marketingFee;
        stakingFees += poolFee;
        liquidityFees += liqFee;
    }

    /// @notice Swap tokens for ETH and distribute to marketing, liquidity and staking
    /// @param tokensHeld Amount of tokens held in contract to swap
    /// @dev to make the most out of the liquidity that is added, the contract will swap and add liquidity before swapping the amount to distribute
    function _handleSwapAndDistribute(uint tokensHeld) private swapExecuting {
        uint totalFees = marketingFees + stakingFees + liquidityFees;

        uint mkt = marketingFees;
        uint stk = stakingFees;
        uint liq = liquidityFees;

        if (totalFees != tokensHeld) {
            mkt = (marketingFees * tokensHeld) / totalFees;
            stk = (stakingFees * tokensHeld) / totalFees;
            liq = tokensHeld - mkt - stk;
        }
        if (liq > 0) _swapAndLiquify(liq);

        if (mkt + stk > 0) {
            swapTokensForEth(mkt + stk);
            uint ethBalance = address(this).balance;
            bool succ;
            if (mkt > 0) {
                mkt = (mkt * ethBalance) / (mkt + stk);
                (succ, ) = payable(marketing).call{value: mkt}("");
                require(succ);
                totalMarketingFees += mkt;
            }
            if (stk > 0) {
                stk = ethBalance - mkt;
                (succ, ) = payable(stakingPool).call{value: stk}("");
                require(succ);
                totalStakingFees += stk;
            }
        }
        marketingFees = 0;
        stakingFees = 0;
        liquidityFees = 0;
    }

    /// @notice Swap half of tokens for ETH and create liquidity from an external call
    function swapAndLiquify() public swapExecuting {
        require(
            liquidityFees >= balanceOf(address(this)),
            "BUNAI: Not enough tokens"
        );
        _swapAndLiquify(liquidityFees);
        liquidityFees = 0;
    }

    /// @notice Swap half tokens for ETH and create liquidity internally
    /// @param tokens Amount of tokens to swap
    function _swapAndLiquify(uint tokens) private {
        uint half = tokens / 2;
        uint otherHalf = tokens - half;

        uint initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint newBalance = address(this).balance - initialBalance;

        _approve(address(this), address(router), otherHalf);
        (, , uint liquidity) = router.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0,
            0,
            DEAD_WALLET,
            block.timestamp
        );

        totalLiquidityFees += liquidity;

        emit SwapAndLiquify(half, newBalance, liquidity);
    }

    /// @notice Swap tokens for ETH
    function swapTokensForEth(uint tokens) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokens);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // Only Owner section
    ///@notice Set the fee for buy transactions
    ///@param _marketing Marketing fee
    ///@param _pool Staking Pool fee
    ///@param _liq Liquidity fee
    ///@dev Fees are in percentage and cant be more than 25%
    function setBuyFees(
        uint8 _marketing,
        uint8 _pool,
        uint8 _liq
    ) external onlyOwner {
        totalBuyFee = _marketing + _pool + _liq;
        require(totalBuyFee <= 25, "Fees cannot be more than 25%");
        buyFees = [_marketing, _pool, _liq];
    }

    ///@notice Set the fee for sell transactions
    ///@param _marketing Marketing fee
    ///@param _pool Staking Pool fee
    ///@param _liq Liquidity fee
    ///@dev Fees are in percentage and cant be more than 25%
    function setSellFees(
        uint8 _marketing,
        uint8 _pool,
        uint8 _liq
    ) external onlyOwner {
        totalSellFee = _marketing + _pool + _liq;
        require(totalSellFee <= 25, "Fees cannot be more than 25%");
        sellFees = [_marketing, _pool, _liq];
    }

    ///@notice set address to be exempt from fees
    ///@param _address Address to be exempt
    ///@param exempt true or false
    function setFeeExempt(address _address, bool exempt) public onlyOwner {
        feeExempt[_address] = exempt;
    }

    ///@notice set address to be blacklisted
    ///@param _address Address to be blacklisted
    ///@param _blacklist true or false
    function setBlacklist(
        address _address,
        bool _blacklist
    ) external onlyOwner {
        blacklist[_address] = _blacklist;
    }

    ///@notice allow token trading to start
    function openTrade() external onlyOwner {
        tradingOpen = true;
    }

    ///@notice get tokens sent "mistakenly" to the contract
    ///@param _token Address of the token to be recovered
    function recoverToken(address _token) external onlyOwner {
        require(_token != address(this), "Cannot withdraw BUNAI");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

    /// @notice recover ETH sent to the contract
    function recoverETH() external onlyOwner {
        payable(msg.sender).call{value: address(this).balance}("");
    }

    ///@notice set the marketing wallet address
    ///@param _marketing Address of the new marketing wallet
    ///@dev Marketing wallet address cannot be 0x0 or the current marketing wallet address
    function setMarketingWallet(address _marketing) external onlyOwner {
        require(
            _marketing != address(0) && _marketing != marketing,
            "Invalid address"
        );
        marketing = _marketing;
    }

    ///@notice set the staking pool address
    ///@param _stakingPool Address of the new staking pool
    ///@dev Staking pool address cannot be 0x0 or the current staking pool address
    function setStakingPool(address _stakingPool) external onlyOwner {
        require(
            _stakingPool != address(0) && _stakingPool != stakingPool,
            "Invalid address"
        );
        stakingPool = _stakingPool;
    }

    ///@notice set address to be exempt from max buys and sells
    ///@param _address Address to be exempt
    ///@param exempt true or false
    function setMaxTxExempt(address _address, bool exempt) public onlyOwner {
        maxTxExempt[_address] = exempt;
    }

    function setMaxBuy(uint256 _amount) external onlyOwner {
        require(_amount >= maxTxAmount, "Invalid Max Buy Amount");
        maxBuyTxAmount = _amount;
    }

    function setMaxSell(uint256 _amount) external onlyOwner {
        require(_amount >= maxTxAmount, "Invalid Max Sell Amount");
        maxSellTxAmount = _amount;
    }

    function setMaxTxAmount(uint256 _amount) external onlyOwner {
        require(_amount >= totalSupply() / 100, "Invalid Max Tx Amount");
        maxTxAmount = _amount;
    }

    function setSwapThreshold(uint256 _amount) external onlyOwner {
        require(_amount >= 0, "Invalid Min Token Swap Amount");
        swapThreshold = _amount;
    }

    function setCooldownWhitelist(
        address _address,
        bool _whitelist
    ) public onlyOwner {
        cooldownWhitelist[_address] = _whitelist;
    }
}
