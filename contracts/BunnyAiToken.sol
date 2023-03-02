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

    address public marketing;
    address public stakingPool;

    uint public totalBuyFee = 6;
    uint public totalSellFee = 6;

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

    uint public minTokenSwap = 10 ether;

    uint8[3] public buyFees = [1, 2, 3];
    uint8[3] public sellFees = [3, 2, 1];
    uint256 public constant BASE = 100;

    bool public tradingOpen = false;

    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    constructor(address _mkt, address _stk) ERC20("Bunny AI", "BUNAI") {
        require(_mkt != address(0) && _stk != address(0), "Invalid address");
        marketing = _mkt;
        stakingPool = _stk;
        // 23 million tokens
        _mint(msg.sender, 23_000_000 ether);
        // max Tx amount is 1% of total supply
        maxTxAmount = 23_000_000 ether / 100;
        maxBuyTxAmount = maxTxAmount;
        // max wallet amount is 2% of total supply
        maxWalletAmount = maxTxAmount * 3;

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
    }

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
        if (from == address(0) || to == address(0)) return;
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

        if (
            (sender == address(pair) && !feeExempt[recipient]) ||
            (recipient == address(pair) && !feeExempt[sender])
        ) {
            uint totalFee = takeFee(amount, sender == address(pair));
            super._transfer(sender, address(this), totalFee);
            amount -= totalFee;
        }

        super._transfer(sender, recipient, amount);
    }

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
}
