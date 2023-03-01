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

### Taxes

Taxes are split to 3 different addresses.

1. Marketing Wallet
2. Staking pool contract
3. Liquidity

#### Buy Taxes

#### Sell Taxes
