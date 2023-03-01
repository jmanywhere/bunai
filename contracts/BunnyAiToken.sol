//  SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "./interfaces/IUniswap.sol";

contract BunnyAiToken is ERC20, Ownable {
    mapping(address => bool) public blacklist;
    mapping(address => bool) public feeExempt;

    uint8[3] public buyFees = [0, 0, 0];
    uint8[3] public sellFees = [0, 0, 0];
    uint8 public constant BASE = 100;

    uint public totalBuyFee;
    uint public totalSellFee;

    uint public maxWalletAmount;
    uint public maxTxAmount;
    uint public maxBuyTxAmount;
    uint public maxSellTxAmount;

    uint public minTokenSwap = 10 ether;

    bool public tradingOpen = false;

    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    constructor() ERC20("Bunny AI", "BUNAI") {
        // 23 million tokens
        _mint(msg.sender, 23_000_000 ether);
        // max Tx amount is 1% of total supply
        maxTxAmount = 23_000_000 ether / 100;
        // max wallet amount is 2% of total supply
        maxWalletAmount = maxTxAmount * 2;

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
}
