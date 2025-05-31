# xDLOL Core Contracts

xDLOL is a universal staking layer that enables users to stake, earn, and interact with major LST (Liquid Staking Token), LRT (Liquid Restaking Token), and vault protocols from any supported chain, without bridging or waiting for slow cross-chain messages. This repository contains the core smart contracts powering xDLOL’s cross-chain staking, yield synchronization, and protocol accounting.

## Overview

Traditional staking and yield protocols are siloed on their origin chain. Users must bridge assets and deal with complex workflows just to access opportunities on another network. xDLOL solves this.

xDLOL mirrors LST, LRT, and major vault protocols on all supported chains.
Users can stake and earn as if the protocol natively exists on their current chain. Rewards and liquidity are synchronized automatically and securely—no manual bridging, no fragmented UX.


## Key Features
* Omni-Chain Staking: Stake into major protocols (Lido, Ether.fi, Renzo, Morpho, etc.) from any supported chain in one click.
* Reward Synchronization: Yield and rewards are automatically synced cross-chain.
* No Bridges, No Delays: Underlying protocol logic abstracts away all bridging and messaging from the user.
* Unified Liquidity: Protocol and asset liquidity is virtually aggregated and available from any chain.
* Composable Layer: All staking/vaults are available to both users and smart contracts on all chains.


## Key Design Principles
* Security: All critical sync operations are permissionless, minimizing trust assumptions.
* Extensibility: New protocols and cross-chain routers can be integrated with minimal changes.
* Gas Efficiency: Core accounting and root updates are optimized for batch updates and minimized state writes.
* Transparency: All root synchronizations and user state changes are on-chain and auditable.


## Security & Audits

All core contracts are written to minimize cross-chain trust.
Security reviews are ongoing. For bug reports or responsible disclosures, please reach out via team@levx.io 

## License

BUSL
