from ape import project, reverts
import pytest


@pytest.fixture
def env_setup(accounts):
    owner = accounts[0]
    mkt = accounts[1]
    stk = accounts[2]
    bunai = project.BunnyAiToken.deploy(mkt, stk, sender=owner)

    mock_multi_holder = accounts["0x126E8c16b8aD86fd3DC0E8f49583E4486E14DB9D"]
    mock_single_holder = accounts["0x29F0cF310994afC60be5a75Cc65943F213d92731"]

    nft = project.IBunaiNft.at("0xbB520cE73Fd6e3F5777f583705db081BA3Dd65Ac")
    loot = project.FoundersLoot.deploy(nft.address, bunai.address, sender=owner)
    return loot, owner, nft, bunai, mock_multi_holder, mock_single_holder


def test_owner_functions(env_setup, accounts):
    loot, owner, *_ = env_setup
    assert loot.owner() == owner.address
    assert loot.burnBunai() == int(1e18) * 100
    with reverts("Ownable: caller is not the owner"):
        loot.setBurnAmount(int(1e18) * 200, sender=accounts[1])
    loot.setBurnAmount(int(1e18) * 200, sender=owner)
    assert loot.burnBunai() == int(1e18) * 200
    pass


def test_claim_non_holder(env_setup, accounts):
    non_owner = accounts[3]
    loot, *_ = env_setup
    with reverts("Invalid token"):
        loot.claim(0, sender=non_owner)
    with reverts("NFT: Not owner"):
        loot.claim(1, sender=non_owner)
    pass


def test_claim_with_nothing(env_setup):
    loot, _, nft, _, mock_multi_holder, mock_single_holder = env_setup

    assert nft.balanceOf(mock_multi_holder.address) == 7
    assert nft.balanceOf(mock_single_holder.address) == 1

    assert loot.pendingRewards(46) == 0
    assert loot.pendingRewardFromMultiple([45, 46, 66, 67, 68, 69, 70]) == 0

    with reverts("Nothing to claim"):
        loot.claim(11, sender=mock_single_holder)
    with reverts("Nothing to claim"):
        loot.claimMultiple([45, 46], sender=mock_multi_holder)
    pass


def test_sent_eth_is_distributed(env_setup, accounts):
    loot, owner, *_, mock_multi_holder, mock_single_holder = env_setup

    assert loot.accumulatedRewardsPerNFT() == 0

    # Send 1 eth to loot contract from accounts 0
    owner.transfer(loot.address, "1 ether")

    assert loot.accumulatedRewardsPerNFT() == int(1e18) * int(1e12) // 100
    pass


def test_claim_single(env_setup, accounts):
    loot, owner, _, bunai, mock_multi_holder, mock_single_holder = env_setup

    owner.transfer(loot.address, "1 ether")
    init_balance = mock_single_holder.balance

    assert loot.accumulatedRewardsPerNFT() == int(1e18) * int(1e12) // 100
    assert loot.pendingRewards(11) == int(1e18) // 100
    assert loot.pendingRewardFromMultiple([11]) == int(1e18) // 100
    assert loot.pendingRewardFromMultiple([45, 46]) == int(1e18) * 2 // 100
    # Need approval
    with reverts("BUNAI: Not enough allowance"):
        loot.claim(11, sender=mock_single_holder)

    bunai.approve(loot.address, int(1e18) * 100, sender=mock_single_holder)
    #  Need balance
    with reverts("ERC20: burn amount exceeds balance"):
        loot.claim(11, sender=mock_single_holder)
    # Should succeed
    bunai.transfer(mock_single_holder.address, int(1e18) * 100, sender=owner)
    loot.claim(11, sender=mock_single_holder)

    assert loot.pendingRewards(11) == 0
    assert loot.pendingRewardFromMultiple([11]) == 0
    assert loot.pendingRewardFromMultiple([45, 46]) == int(1e18) * 2 // 100

    assert mock_single_holder.balance == init_balance + (int(1e18) // 100)
    # Make sure we can't double claim
    with reverts("Nothing to claim"):
        loot.claim(11, sender=mock_single_holder)
    pass


def test_claim_multiple(env_setup, accounts):
    loot, owner, _, bunai, mock_multi_holder, mock_single_holder = env_setup

    owner.transfer(loot.address, "10 ether")

    assert loot.accumulatedRewardsPerNFT() == int(1e18) * int(1e12) * 10 // 100

    assert loot.pendingRewards(45) == int(1e18) * 10 // 100
    assert loot.pendingRewardFromMultiple([45, 46]) == int(1e18) * 10 * 2 // 100

    bunai.approve(loot.address, int(1e18) * 100, sender=mock_multi_holder)
    bunai.transfer(mock_multi_holder.address, int(1e18) * 100, sender=owner)

    with reverts("NFT: Not owner"):
        loot.claimMultiple([45, 46], sender=mock_single_holder)
    with reverts("BUNAI: Not enough allowance"):
        loot.claimMultiple([45, 46], sender=mock_multi_holder)
    bunai.approve(loot.address, int(1e18) * 200, sender=mock_multi_holder)

    with reverts("ERC20: burn amount exceeds balance"):
        loot.claimMultiple([45, 46], sender=mock_multi_holder)
    bunai.transfer(mock_multi_holder.address, int(1e18) * 100, sender=owner)

    multi_init_balance = mock_multi_holder.balance

    loot.claimMultiple([45, 46], sender=mock_multi_holder)
    assert bunai.balanceOf(mock_multi_holder.address) == 0
    assert loot.pendingRewards(45) == 0
    assert loot.pendingRewardFromMultiple([45, 46]) == 0
    assert mock_multi_holder.balance == multi_init_balance + (int(1e18) * 10 * 2 // 100)
    pass


def test_claim_multiple_repeat_ids(env_setup, accounts):
    loot, owner, _, bunai, mock_multi_holder, mock_single_holder = env_setup

    owner.transfer(loot.address, "10 ether")
    assert loot.accumulatedRewardsPerNFT() == int(1e18) * int(1e12) * 10 // 100

    assert loot.pendingRewards(45) == int(1e18) * 10 // 100
    assert loot.pendingRewardFromMultiple([45, 45]) == int(1e18) * 10 * 2 // 100

    bunai.approve(loot.address, int(1e18) * 100, sender=mock_multi_holder)
    bunai.transfer(mock_multi_holder.address, int(1e18) * 100, sender=owner)

    # Trying to play smart, but if you duplicate, you need to burn double tokens and only get the same
    # amount of rewards
    with reverts("BUNAI: Not enough allowance"):
        loot.claimMultiple([45, 45], sender=mock_multi_holder)
    bunai.approve(loot.address, int(1e18) * 200, sender=mock_multi_holder)
    with reverts("ERC20: burn amount exceeds balance"):
        loot.claimMultiple([45, 45], sender=mock_multi_holder)
    bunai.transfer(mock_multi_holder.address, int(1e18) * 100, sender=owner)

    multi_init_balance = mock_multi_holder.balance

    loot.claimMultiple([45, 45], sender=mock_multi_holder)

    assert bunai.balanceOf(mock_multi_holder.address) == 0
    assert loot.pendingRewards(45) == 0
    assert loot.claimed(45)["accTracker"] == int(1e18) * int(1e12) * 10 // 100
    assert loot.claimed(45)["totalClaimed"] == int(1e18) * 10 // 100
    assert loot.pendingRewardFromMultiple([45, 45]) == 0
    assert mock_multi_holder.balance == multi_init_balance + (int(1e18) * 10 // 100)

    pass
