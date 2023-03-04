from ape import project, reverts
import pytest
import math


@pytest.fixture
def token_setup(accounts):
    owner = accounts[0]
    token = project.BunnyAiToken.deploy(
        accounts[8].address, accounts[9].address, sender=owner
    )
    router = project.IUniswapV2Router02.at(token.router())
    factory = project.IUniswapV2Factory.at(router.factory())
    return token, owner, router, factory


def test_initial_state(token_setup):
    (token, owner, router, factory) = token_setup
    totalSupply = 23_000_000 * int(1e18)

    assert token.name() == "Bunny AI"
    assert token.symbol() == "BUNAI"
    assert token.decimals() == 18
    assert token.totalSupply() == totalSupply
    assert token.balanceOf(owner) == totalSupply
    assert token.router() == "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
    assert token.pair() == factory.getPair(token, router.WETH())


def test_edit_wallets(token_setup, accounts):
    (token, owner, *_) = token_setup

    with reverts("Ownable: caller is not the owner"):
        token.setMarketingWallet(accounts[1].address, sender=accounts[1])

    assert token.marketing() == accounts[8].address
    assert token.stakingPool() == accounts[9].address

    token.setMarketingWallet(accounts[1].address, sender=owner)

    assert token.marketing() == accounts[1].address

    with reverts("Ownable: caller is not the owner"):
        token.setStakingPool(accounts[2].address, sender=accounts[1])
    token.setStakingPool(accounts[2].address, sender=owner)

    assert token.stakingPool() == accounts[2].address


def test_transfer_blocked_without_fees(token_setup, accounts):
    (token, owner, *_) = token_setup

    # Transfer tokens to another account
    token.transfer(accounts[1].address, 1000, sender=owner)

    with reverts("BUNAI: Trading blocked"):
        token.transfer(accounts[2].address, 1000, sender=accounts[1])

    token.openTrade(sender=owner)
    token.setFeeExempt(accounts[1].address, True, sender=owner)

    token.transfer(accounts[2].address, 1000, sender=accounts[1])
    assert token.balanceOf(accounts[2].address) == 1000
    assert token.balanceOf(accounts[1].address) == 0


def test_transfer_with_fees(token_setup, accounts):
    (token, owner, *_) = token_setup

    token.openTrade(sender=owner)

    txAmount = 100 * int(1e18)
    # Transfer tokens to another account
    token.transfer(accounts[1].address, txAmount, sender=owner)

    # Transfer between non exempt accounts
    token.transfer(accounts[2].address, txAmount, sender=accounts[1])
    # Since it's a transfer, no fees are collected
    assert token.balanceOf(accounts[2].address) == txAmount
    assert token.balanceOf(accounts[1].address) == 0
    assert token.balanceOf(owner) == token.totalSupply() - txAmount
    pass


def test_add_liquidity(token_setup, chain, accounts):
    user1 = accounts[1]
    (token, owner, router, factory) = token_setup
    token.openTrade(sender=owner)
    token.approve(router.address, token.totalSupply(), sender=owner)

    assert token.allowance(owner.address, router.address) == token.totalSupply()

    tokensForLiquidity = 1_000_000 * int(1e18)
    ethForLiquidity = int(1e18)
    # 1000 is the MINIMUM_LIQUIDITY that is locked
    expectedTotalLiquidity = int(math.sqrt(tokensForLiquidity * ethForLiquidity))
    expectedLiquidity = expectedTotalLiquidity - 1000

    # NOTICE: OWNER IS EXEMPT FROM MAX TX BUY/SELL
    router.addLiquidityETH(
        token.address,
        tokensForLiquidity,
        tokensForLiquidity,
        ethForLiquidity,
        owner.address,
        chain.pending_timestamp + 3600,
        sender=owner,
        value=ethForLiquidity,
    ).await_confirmations()

    liquidity = project.IUniswapV2Pair.at(token.pair())
    assert liquidity.totalSupply() == expectedTotalLiquidity
    assert liquidity.balanceOf(owner) == expectedLiquidity


@pytest.fixture
def liquidity_setup(token_setup, chain, accounts):
    (token, owner, router, factory) = token_setup
    token.openTrade(sender=owner)
    token.approve(router.address, token.totalSupply(), sender=owner)

    tokensForLiquidity = 10_000_000 * int(1e18)
    ethForLiquidity = 200 * int(1e18)

    # NOTICE: OWNER IS EXEMPT FROM MAX TX BUY/SELL
    liquidity_response = router.addLiquidityETH(
        token.address,
        tokensForLiquidity,
        tokensForLiquidity,
        ethForLiquidity,
        owner.address,
        chain.pending_timestamp + 3600,
        sender=owner,
        value=ethForLiquidity,
    ).await_confirmations()

    token.transfer(accounts[1].address, 1_000 * ethForLiquidity, sender=owner)

    return token, owner, router, factory, liquidity_response.return_value["liquidity"]


def test_buy_fees(liquidity_setup, accounts, chain):
    (token, _, router, *_) = liquidity_setup

    router.swapExactETHForTokens(
        0,
        [router.WETH(), token.address],
        accounts[2].address,
        chain.pending_timestamp + 3600,
        sender=accounts[2],
        value=int(1e18 / 100),
    ).await_confirmations()

    assert token.balanceOf(accounts[2].address) > 0
    marketing = token.marketingFees()
    staking = token.stakingFees()
    liquidity = token.liquidityFees()

    assert token.marketingFees() > 0
    assert token.stakingFees() > 0
    assert token.liquidityFees() > 0

    assert marketing / (marketing + staking + liquidity) == 1 / 6
    assert staking / (marketing + staking + liquidity) == 2 / 6
    assert liquidity / (marketing + staking + liquidity) == 3 / 6

    pass


def test_sell_fees(liquidity_setup, accounts, chain):

    (token, _, router, *_) = liquidity_setup

    token.approve(router.address, token.totalSupply(), sender=accounts[1])
    assert token.allowance(accounts[1].address, router.address) == token.totalSupply()

    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        1_000 * int(1e18),
        0,
        [token.address, router.WETH()],
        accounts[2].address,
        chain.pending_timestamp + 3600,
        sender=accounts[1],
    ).await_confirmations()

    assert token.balanceOf(accounts[1].address) > 0

    marketing = token.marketingFees()
    staking = token.stakingFees()
    liquidity = token.liquidityFees()

    assert token.marketingFees() > 0
    assert token.stakingFees() > 0
    assert token.liquidityFees() > 0

    assert marketing / (marketing + staking + liquidity) == 3 / 6
    assert staking / (marketing + staking + liquidity) == 2 / 6
    assert liquidity / (marketing + staking + liquidity) == 1 / 6

    pass
