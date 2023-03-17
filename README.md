# Bunny AI Token

The contracts are built in solidity and are meant for the ETH and ARB blockchains.

## Dev Environment

Tests using Apeworx
Underlying dev chain: Hardhat
To run tests, please run `ape test --network ethereum:mainnet-fork:hardhat`
for interactivity, add the ` -I` flag

## Requirements

- 23M total Supply
- Max Tx limit
  - buys
  - sells
  - transfers
- Open Trade fn
- Buy Taxes
  - set
- Sell Taxes
  - set
- Swap Token Amount Threshold
  - editable
- Rescue ERC tokens
- Transfer ownership (all ownership fns will be handled by Ownable)
- Update Tax Addresses
  - Marketing
  - Staking
- Exclude Wallets from Fees
  - add / remove fee exclusion status
- Blacklist
  - blacklist addresses so the funds in their wallets cannot move.
- MEV Sandwich Block
  - block transfers when transactions happen in less than 5 blocks. There is a function to exclude other wallets.

### Taxes

Taxes are split to 3 different addresses.

1. Marketing Wallet
2. Staking pool contract
3. Liquidity

#### Buy Taxes

#### Sell Taxes

# Founder's Loot (NFT Staking contract)

## Requirements

- NFT Bunny AI Founder (`0xbB520cE73Fd6e3F5777f583705db081BA3Dd65Ac`) can claim funds by tokenId
- Rewards will be in ETH
- All Founder NFTs are worth an equal portion
- In order to claim any rewards, a BURN fee of BUNAI token is claimed per NFT. Starting at 100 BUNAI per token
- Only owner of tokenId can claim at any given time.

### Note to USERS

Please make sure that BUNAI is approved to spend by the FoundersLoot contract.
Trying to claim the same rewards twice will result in double the BUNAI required to burn
and single amount of rewards claimed.
