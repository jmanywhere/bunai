//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BunnyAiToken.sol";

interface IBunaiNft is IERC721 {
    function totalSupply() external returns (uint);
}

contract FoundersLoot is Ownable {
    struct NFTClaim {
        uint256 accTracker; // Track the rewards accumulated at any point to reduce already claimed amounts
        uint256 totalClaimed; // Track the rewards claimed by user in ETH
    }
    mapping(uint8 => NFTClaim) public claimed;

    uint256 public constant MAGNIFY_FACTOR = 1e12; // This helps with math precision
    // NFT address
    IBunaiNft public immutable founderNFT;
    // BUNAI address
    BunnyAiToken public immutable bunai;
    // Accumulated rewards per NFT * Magnify factor
    uint256 public accumulatedRewardsPerNFT;
    // BUNAI amount to burn to claim
    uint256 public burnBunai;
    // Reentrancy guard
    bool public reentrancyGuard;
    // Total NFTs in existence
    uint256 public totalNFTs;

    event Claim(address indexed user, uint256 amount);

    ///@notice Reentrancy guard modifier
    modifier nonReentrant() {
        require(!reentrancyGuard, "ReentrancyGuard: reentrant call");
        reentrancyGuard = true;
        _;
        reentrancyGuard = false;
    }

    /// @notice Constructor, here we set the initial burn BUNAI amount as well as totalNFTs
    /// @param _founderNFT the address of the Founder's NFT contract
    /// @param _bunai the address of the BUNAI token contract
    constructor(address _founderNFT, address payable _bunai) {
        require(
            _founderNFT != address(0) && _bunai != address(0),
            "Invalid addresses"
        );
        founderNFT = IBunaiNft(_founderNFT);
        bunai = BunnyAiToken(_bunai);
        totalNFTs = founderNFT.totalSupply();
        burnBunai = 100 ether;
        require(totalNFTs > 0, "Invalid address");
    }

    ///@notice automatically increases reward based on ETH amount received.
    ///@dev if there are not staked NFT's we send the ETH to the marketing wallet
    receive() external payable {
        accumulatedRewardsPerNFT += (msg.value * MAGNIFY_FACTOR) / totalNFTs;
    }

    ///@notice Send ETH to user
    ///@param _amount amount of ETH to send
    ///@dev if nothing to send, will revert as well if there is not enough ETH in the contract;
    function sendETH(uint _amount) private {
        require(_amount > 0, "Nothing to claim");
        require(_amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Error on ETH Transfer");
    }

    ///@notice External claim function
    ///@param _tokenId id of the NFT to claim
    ///@dev To claim pending rewards a BUNAI burn needs to occur by accessing the BUNAI `burnFrom` function
    function claim(uint8 _tokenId) external nonReentrant {
        uint reward = _claim(_tokenId);
        if (reward != 0) _burnToClaim(1);
        sendETH(reward);
    }

    ///@notice External claim function for multiple NFTs
    ///@param _tokenIds ids of the NFTs to claim, all ids must belong to msg sender
    ///@dev To claim pending rewards a BUNAI burn needs to occur by accessing the BUNAI `burnFrom` function, amount to burn depends on amount of NFT's claimed
    function claimMultiple(uint8[] calldata _tokenIds) external nonReentrant {
        uint totalReward = 0;
        for (uint8 i = 0; i < _tokenIds.length; i++) {
            totalReward += _claim(_tokenIds[i]);
        }
        if (totalReward > 0) _burnToClaim(_tokenIds.length);
        sendETH(totalReward);
    }

    ///@notice Claim any pending rewards
    ///@dev To claim pending rewards a BUNAI burn needs to occur by accessing the BUNAI `burnFrom` function
    function _claim(uint8 _tokenId) private returns (uint _totalReward) {
        require(_tokenId <= totalNFTs && _tokenId != 0, "Invalid token");
        require(founderNFT.ownerOf(_tokenId) == msg.sender, "NFT: Not owner");
        NFTClaim storage nft = claimed[_tokenId];
        _totalReward =
            (accumulatedRewardsPerNFT - nft.accTracker) /
            MAGNIFY_FACTOR;
        nft.accTracker = accumulatedRewardsPerNFT;
        nft.totalClaimed += _totalReward;
        emit Claim(msg.sender, _totalReward);
    }

    ///@notice Calculate pending rewards for user
    ///@param _tokenId id of the NFT
    ///@return pending rewards in ETH
    function pendingRewards(uint8 _tokenId) public view returns (uint256) {
        if (_tokenId > totalNFTs || _tokenId == 0) return 0;
        NFTClaim storage nft = claimed[_tokenId];
        return (accumulatedRewardsPerNFT - nft.accTracker) / MAGNIFY_FACTOR;
    }

    ///@notice Calculate pending rewards for multiple NFTs
    ///@param _tokenIds ids of the NFTs
    ///@return totalPending total pending rewards in ETH
    ///@dev this function is used to calculate the amount of BUNAI to burn when claiming multiple NFTs
    ///@dev though a repeat is counted multiple times, it can only be claimed once.
    function pendingRewardFromMultiple(
        uint8[] calldata _tokenIds
    ) external view returns (uint256 totalPending) {
        totalPending = 0;
        for (uint8 i = 0; i < _tokenIds.length; i++) {
            totalPending += pendingRewards(_tokenIds[i]);
        }
    }

    ///@notice Burn BUNAI
    ///@param tokens amount of tokens to claim
    ///@dev burn the BUNAI amount set in the burnBunai variable
    function _burnToClaim(uint tokens) internal {
        if (burnBunai > 0) bunai.burnFrom(msg.sender, burnBunai * tokens);
    }

    ///@notice Owner can change the BUNAI amount to burn
    function setBurnAmount(uint _burnBunai) external onlyOwner {
        burnBunai = _burnBunai;
    }
}
