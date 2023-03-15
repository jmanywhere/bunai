//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BunnyAiToken.sol";

contract FoundersLoot is Ownable {
    struct User {
        uint256 accTracker; // Track the rewards accumulated at any point to reduce already claimed amounts
        uint256 totalClaimed; // Track the rewards claimed by user in ETH
        uint8 stakedNFTs;
    }
    mapping(uint => address) public idStakedBy; // used to recover NFTs on withdraw
    mapping(address => User) public users;
    uint256 public constant MAGNIFY_FACTOR = 1e12;
    // NFT address
    IERC721 public founderNFT;
    // BUNAI address
    BunnyAiToken public bunai;
    address public marketingWallet;
    uint256 accumulatedRewardsPerNFT;
    uint256 public burnBunai;
    uint8 public totalStakedNFTs;

    event Deposit(address indexed user, uint256 indexed nftId);
    event Withdraw(address indexed user, uint256 indexed nftId);
    event Claim(address indexed user, uint256 amount);
    event Forfeit(address indexed user, uint256 amount);

    constructor(address _founderNFT, address payable _bunai) {
        require(
            _founderNFT != address(0) && _bunai != address(0),
            "Invalid addresses"
        );
        founderNFT = IERC721(_founderNFT);
        bunai = BunnyAiToken(_bunai);
    }

    ///@notice automatically increases reward based on ETH amount received.
    ///@dev if there are not staked NFT's we send the ETH to the marketing wallet
    receive() external payable {
        if (totalStakedNFTs > 0)
            accumulatedRewardsPerNFT +=
                (msg.value * MAGNIFY_FACTOR) /
                totalStakedNFTs;
        else {
            (bool succ, ) = marketingWallet.call{value: msg.value}("");
            require(succ, "ETH marketing transfer failed");
        }
    }

    ///@notice Deposit NFT to start receiving rewards
    ///@param _nftId NFT ID to deposit
    ///@dev NFT is transferred to this contract
    function deposit(uint256 _nftId) external {
        require(founderNFT.ownerOf(_nftId) == msg.sender, "Not NFT owner");
        User storage user = users[msg.sender];
        // ----------------- CLAIM ANY REWARDS FIRST -----------------
        _claim(msg.sender, user);
        // Transfer NFT to this contract
        founderNFT.transferFrom(msg.sender, address(this), _nftId);
        idStakedBy[_nftId] = msg.sender;
        user.stakedNFTs++;
        user.accTracker = accumulatedRewardsPerNFT * user.stakedNFTs;
        totalStakedNFTs++;
        emit Deposit(msg.sender, _nftId);
    }

    ///@notice Withdraw NFT and claim any pending rewards
    ///@param _nftId NFT ID to withdraw
    function withdrawNFT(uint _nftId) external {
        require(idStakedBy[_nftId] == msg.sender, "Not NFT owner");
        User storage user = users[msg.sender];
        // ----------------- CLAIM ANY REWARDS FIRST -----------------
        _claim(msg.sender, user);
        // Transfer NFT to user
        founderNFT.transferFrom(address(this), msg.sender, _nftId);
        idStakedBy[_nftId] = address(0);
        user.stakedNFTs--;
        user.accTracker = accumulatedRewardsPerNFT * user.stakedNFTs;
        totalStakedNFTs--;
        emit Withdraw(msg.sender, _nftId);
    }

    ///@notice Withdraw NFT and forfeit any pending rewards
    ///@param _nftId NFT ID to withdraw
    ///@dev NFT is transferred to the user and any pending rewards are sent to marketing wallet
    function withdrawNFTAndForfeit(uint _nftId) external {
        require(
            idStakedBy[_nftId] == msg.sender &&
                founderNFT.ownerOf(_nftId) == address(this),
            "Not NFT owner"
        );
        User storage user = users[msg.sender];
        //  FORFEIT ANY PENDING REWARDS
        uint256 pending = pendingRewards(msg.sender);
        if (pending > 0) {
            (bool succ, ) = payable(marketingWallet).call{value: pending}("");
            require(succ, "ETH marketing transfer failed");
        }
        // Transfer NFT to user
        founderNFT.transferFrom(address(this), msg.sender, _nftId);
        idStakedBy[_nftId] = address(0);
        user.stakedNFTs--;
        user.accTracker = accumulatedRewardsPerNFT * user.stakedNFTs;
        totalStakedNFTs--;
        emit Withdraw(msg.sender, _nftId);
    }

    ///@notice External claim function
    function claim() external {
        User storage user = users[msg.sender];
        _claim(msg.sender, user);
    }

    ///@notice Claim any pending rewards
    ///@dev To claim pending rewards a BUNAI burn needs to occur by accessing the BUNAI `burnFrom` function
    function _claim(address account, User storage user) private {
        _burnToClaim();
        uint256 pending = pendingRewards(account);
        if (pending > 0) {
            user.totalClaimed += pending;
            (bool succ, ) = payable(account).call{value: pending}("");
        }
        user.accTracker = accumulatedRewardsPerNFT * user.stakedNFTs;
        emit Claim(account, pending);
    }

    ///@notice Calculate pending rewards for user
    ///@param _user User address
    ///@return pending rewards in ETH
    function pendingRewards(address _user) public view returns (uint256) {
        User memory user = users[_user];
        uint256 pending = 0;
        if (user.stakedNFTs > 0) {
            pending =
                ((accumulatedRewardsPerNFT * user.stakedNFTs) /
                    MAGNIFY_FACTOR) -
                user.accTracker;
        }
        return pending;
    }

    ///@notice Burn BUNAI
    ///@dev burn the BUNAI amount set in the burnBunai variable
    function _burnToClaim() internal {
        bunai.burnFrom(msg.sender, burnBunai);
    }

    ///@notice Owner can change the BUNAI amount to burn
    function setBurnAmount(uint _burnBunai) external onlyOwner {
        burnBunai = _burnBunai;
    }
}
