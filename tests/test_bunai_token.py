from ape import project, reverts
import pytest


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


def test_trading_blocked(token_setup, accounts):
    (token, owner, *_) = token_setup

    # Transfer tokens to another account
    token.transfer(accounts[1].address, 1000, sender=owner)

    with reverts("BUNAI: Trading blocked"):
        token.transfer(accounts[2].address, 1000, sender=accounts[1])
