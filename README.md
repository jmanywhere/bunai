# Bunny AI Token

The contracts are built in solidity and are meant for the ETH and ARB blockchains.

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

## Dev Environment

Tests using Apeworx
Underlying dev chain: Hardhat
To run tests, please run `ape test --network ethereum:mainnet-fork:hardhat`
for interactivity, add the ` -I` flag
