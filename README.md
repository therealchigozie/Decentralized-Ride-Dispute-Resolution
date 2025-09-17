# 🚖 Decentralized Ride Dispute Resolution

Welcome to a fairer way to handle disputes in ride-sharing! This Web3 project builds a decentralized system on the Stacks blockchain using Clarity smart contracts. It solves real-world problems in centralized ride-sharing apps (like Uber or Lyft), where disputes over fares, damages, lost items, or misconduct are often resolved slowly, opaquely, or biasedly by the company. Instead, community-elected arbitrators resolve disputes transparently, with staking mechanisms to ensure honesty and incentives for participation.

## ✨ Features

🔒 User registration for drivers and passengers with identity verification hooks  
🚗 Ride tracking with escrow for fares to prevent disputes upfront  
⚖️ Easy dispute filing with evidence submission (e.g., hashes of photos or logs)  
🗳️ Community arbitrators staked in tokens for unbiased resolution  
💰 Rewards for accurate arbitrators and penalties for bad faith  
📊 Transparent voting and resolution logs on-chain  
🔄 Governance for community-driven updates to rules  
🚫 Anti-collusion measures via random arbitrator selection  

## 🛠 How It Works

This project involves 8 smart contracts written in Clarity, interacting to create a trustless dispute resolution ecosystem. Here's a high-level overview:

### Core Smart Contracts
1. **UserRegistry.clar**: Handles registration of drivers and passengers. Stores user profiles (e.g., principal addresses, ratings) and allows basic KYC hooks via off-chain oracles if needed. Prevents sybil attacks with a small registration fee.

2. **RideManager.clar**: Manages ride lifecycle. Users initiate rides, escrow fares (in STX or project tokens), and confirm completion. If a dispute arises post-ride, it locks funds and triggers the dispute process.

3. **DisputeInitiator.clar**: Allows either party to file a dispute within a time window (e.g., 24 hours post-ride). Requires a deposit (refundable if they win) and submission of evidence hashes. Creates a unique dispute ID.

4. **ArbitratorRegistry.clar**: Registers community members as arbitrators. Requires staking a minimum amount of governance tokens. Tracks arbitrator reputation based on past resolutions.

5. **ArbitratorSelector.clar**: Randomly selects 5-7 arbitrators per dispute using on-chain randomness (e.g., via Stacks' block hash). Ensures diversity and prevents collusion by factoring in stake and past activity.

6. **ResolutionVoting.clar**: Facilitates arbitrator voting on disputes. Each arbitrator reviews evidence (off-chain via IPFS hashes stored on-chain) and votes for driver, passenger, or tie. Uses majority rule; slash stakes for minority voters to incentivize consensus.

7. **TokenEscrow.clar**: Manages all financial aspects, including holding ride fares, dispute deposits, and distributing rewards/penalties. Integrates with STX for native payments or a custom token for governance.

8. **GovernanceDAO.clar**: Allows token holders to propose and vote on system updates, like changing stake requirements or resolution fees. Uses quadratic voting to prevent whale dominance.

**For Riders and Drivers**
- Register via UserRegistry and stake tokens if becoming an arbitrator.
- Start a ride in RideManager: Passenger escrows fare; driver accepts.
- If happy, both confirm completion—funds release.
- If not, file in DisputeInitiator with evidence (e.g., "Driver took wrong route—hash of GPS log").

**For Arbitrators**
- Stake in ArbitratorRegistry to join the pool.
- Get selected via ArbitratorSelector for a dispute.
- Review on-chain evidence, vote in ResolutionVoting.
- If your vote matches majority, earn rewards from fees; else, lose a portion of stake.

**Resolution Process**
- Dispute filed → Arbitrators selected → 48-hour voting window → Majority decides → Escrow releases funds accordingly → Update reputations.

This setup ensures fast, fair resolutions without a central authority, reducing costs and building trust in ride-sharing. Deploy on Stacks for Bitcoin-secured finality!