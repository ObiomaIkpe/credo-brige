Celo dApp Frontend Architecture Plan: "The Reputation Catalyst"

This plan outlines the architecture for the client-side application, ensuring seamless integration with the deployed Celo smart contracts (SoulboundToken.sol, AIRiskOracle.sol, and LoanManager.sol).

1. Recommended Tech Stack

Category

Technology

Rationale

Framework

React / Next.js

Provides robust structure and component model necessary for complex dApps.

Styling

Tailwind CSS

Ensures rapid, responsive development and a great mobile-first experience, critical for Celo.

Celo Toolkit

@celo/react-celo

The native hook-based library for Celo wallet connection (Valora, MetaMask, Ledger). Essential for authentication and signing transactions.

Web3 Interface

ethers.js or web3.js

Standard library for contract interaction, reading data, and preparing transaction payloads.

AI Simulation

Client-Side JS

A pure JavaScript function that simulates the AI's calculation using the data retrieved from the SBT contract.

2. Celo-Native Tooling: @celo/react-celo

We will use the @celo/react-celo library for all wallet and network management. Key features we will rely on:

useCelo() Hook: Provides the current address, kit (the core Celo SDK instance), and the connect function.

Wallet Integration: Automatically handles connecting to Valora (Celo's flagship mobile wallet) and WalletConnect, supporting the mobile-first strategy.

Core Connection Flow:

Setup: Wrap the main App component with <CeloProvider>.

Connect Button: On user click, call connect({ options: ['valora', 'metamask'] }).

Authentication: Once connected, the user's Celo address is available via the hook.

3. Core DApp Components

The application will be structured around three main views:

A. SBT Data Dashboard (/dashboard)

Purpose: Shows the user their current reputation assets.

Interaction:

Calls SoulboundToken.getSBTsByHolder(userAddress) to retrieve all owned token IDs.

Calls SoulboundToken.getSBTData(tokenId) for each token to display the TaskType, PointLevel, and title.

Calls PointLedger.getTotalPoints(userAddress) to display the running total score.

B. AI Score Generator (/score)

Purpose: Executes the client-side AI and publishes the verified score to the blockchain.

Interaction:

Data Fetch: Re-fetches the latest SBT data.

AI Calculation (Off-chain): A local JavaScript function processes the SBT data (e.g., assigning weights based on TaskType) to compute the final FINANCIAL_RISK and UBI_ELIGIBILITY scores.

Submission: The user signs and submits two transactions:

AIRiskOracle.publishScore(FINANCIAL_RISK, scoreValue)

AIRiskOracle.publishScore(UBI_ELIGIBILITY, scoreValue)

Status Display: Calls AIRiskOracle.getScoreMetadata(userAddress, type) to show the score and the publishedTimestamp, verifying it's not stale.

C. Loan Application (/loan)

Purpose: The utility gate, allowing the user to apply for a loan based on their verified score.

Interaction:

Risk Check: Calls AIRiskOracle.getLatestScore(userAddress, FINANCIAL_RISK). If this reverts (score is stale), the user is prompted to go to the /score tab first.

Application: Calls LoanManager.applyForLoan(principalAmount). This creates the application record on-chain.

Repayment Tracking: Displays the status using LoanManager.getLoanStatus(userAddress) (Repayment Due Date, Total Due).

Repayment: Guides the user to Approve the LoanManager to spend their cUSD via IERC20.approve(), and then calls LoanManager.repayLoan() to close the loop and trigger the reward SBT minting.

4. Step-by-Step User Journey & Contract Calls

Step

User Action

DApp Frontend Task

Contract Call (Function)

1. Connect

Clicks "Connect Wallet"

Initializes useCelo() hook.

N/A (Client-side connection)

2. Audit

Views Dashboard

Fetches data for the AI input.

SoulboundToken.getSBTsByHolder()

3. Generate

Clicks "Generate Risk Score"

Simulates AI, gets score (e.g., 780).

N/A (Local JS Computation)

4. Publish

Clicks "Publish to Celo"

Signs transaction to log scores.

AIRiskOracle.publishScore()

5. Apply

Enters desired principal.

Checks recency and submits application.

AIRiskOracle.getLatestScore() (View) then LoanManager.applyForLoan() (Write)

6. Repay

Sends stablecoin to clear debt.

Prompts user to set allowance, then calls repayment.

IERC20.approve() (Write) then LoanManager.repayLoan() (Write)

This plan sets the foundation for a robust, mobile-friendly Celo dApp that implements the full data flow of our four-contract architecture.