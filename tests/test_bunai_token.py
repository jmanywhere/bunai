from ape import project, reverts
import pytest


@pytest.fixture
def token_setup(accounts):
    owner = accounts[0]
    token = project.BunnyAiToken.deploy(sender=owner)
    router = project.IUniswapV2Router02.at(token.router())
    factory = project.IUniswapV2Factory.at(router.factory())
    return token, owner, router, factory


def test_initial_state(token_setup):
    token, owner, factory = token_setup
    totalSupply = 23_000_000 * int(1e18)

    assert token.name() == "Bunny AI"
    assert token.symbol() == "BUNAI"
    assert token.decimals() == 18
    assert token.totalSupply() == totalSupply
    assert token.balanceOf(owner) == totalSupply
    assert token.router() == "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
    assert token.pair() == factory.getPair(token, factory.WETH())


def test_trading_blocked(token_setup, accounts):
    token, owner, router = token_setup

    # Transfer tokens to another account
    token.transfer(accounts[1], 1000, sender=owner)

    with reverts("BUNAI: Trading blocked"):
        token.transfer(accounts[2], 1000, sender=accounts[1])
