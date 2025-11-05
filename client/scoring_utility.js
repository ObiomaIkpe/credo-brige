// This file simulates the feature engineering and inference steps (Steps 2 & 3 in the pipeline).
// In a real application, 'tf' would be loaded via <script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs"></script>

/**
 * @notice Simulates the structure of the SBT data fetched from SoulboundToken.sol.
 * In production, this data comes from web3 calls.
 */
const mockSBTData = [
    { taskType: 'IDENTITY_VERIFIED_KYC', pointLevel: 'LEVEL_B_HARMONY', title: 'KYC Verified' },
    { taskType: 'FINANCIAL_LITERACY_COURSE', pointLevel: 'LEVEL_C_MAJOR', title: 'Course 1' },
    { taskType: 'LOAN_REPAYMENT_SMALL', pointLevel: 'LEVEL_C_MAJOR', title: 'Repayment 1' },
    { taskType: 'LOAN_REPAYMENT_LARGE', pointLevel: 'LEVEL_A_PRESTIGE', title: 'Repayment 2' },
    { taskType: 'LOAN_REPAYMENT_LARGE', pointLevel: 'LEVEL_A_PRESTIGE', title: 'Repayment 3' },
    { taskType: 'SOCIAL_MENTORSHIP', pointLevel: 'LEVEL_B_HARMONY', title: 'Mentored User A' },
    // Add more mock data for different task types
];

/**
 * @notice Enumeration of the TaskTypes used for feature engineering.
 * Must match the Solidity enum in SoulboundToken.sol.
 */
const TaskType = {
    IDENTITY_VERIFIED_KYC: 'IDENTITY_VERIFIED_KYC',
    FINANCIAL_LITERACY_COURSE: 'FINANCIAL_LITERACY_COURSE',
    LOAN_REPAYMENT_SMALL: 'LOAN_REPAYMENT_SMALL',
    LOAN_REPAYMENT_LARGE: 'LOAN_REPAYMENT_LARGE',
    SOCIAL_MENTORSHIP: 'SOCIAL_MENTORSHIP'
};

/**
 * @notice Step 2: Feature Engineering - Converts raw SBT data into a clean feature vector.
 * @param sbtList Array of SBT objects owned by the user.
 * @returns A structured object containing the numerical features for the AI model.
 */
function createFeatureVector(sbtList) {
    const counts = sbtList.reduce((acc, sbt) => {
        acc[sbt.taskType] = (acc[sbt.taskType] || 0) + 1;
        return acc;
    }, {});

    // This creates the feature vector (the 5 inputs for the model)
    const features = {
        KYC_COUNT: counts[TaskType.IDENTITY_VERIFIED_KYC] || 0,
        FIN_LIT_SCORE: counts[TaskType.FINANCIAL_LITERACY_COURSE] || 0,
        SMALL_REPAY_COUNT: counts[TaskType.LOAN_REPAYMENT_SMALL] || 0,
        LARGE_REPAY_COUNT: counts[TaskType.LOAN_REPAYMENT_LARGE] || 0,
        SOCIAL_MENTOR_HOURS: counts[TaskType.SOCIAL_MENTORSHIP] || 0,
    };

    // Log the input features for debugging
    console.log("Input Features for AI:", features);
    return features;
}


/**
 * @notice Step 3: Runs the TF.js model inference to predict the risk score.
 * In a real application, the model is loaded from the /models/ directory.
 * @param features The numerical feature vector created in the previous step.
 * @returns The final scaled risk score (e.g., 300-850 range).
 */
async function runModelInference(features) {
    // --- START TF.JS SIMULATION ---
    // NOTE: We are SIMULATING the result of a Logistic Regression model here,
    // as we cannot include the TF.js library or model files in this single response.

    const { KYC_COUNT, SMALL_REPAY_COUNT, LARGE_REPAY_COUNT, SOCIAL_MENTOR_HOURS } = features;

    // SIMULATED LOGISTIC REGRESSION WEIGHTS:
    // Large repayment is the highest weighted feature (0.4)
    // KYC is low weight (0.1)
    // Social is negligible for financial risk (0.05)
    
    let rawProbability = 0;
    
    // Base intercept for a minimum score
    rawProbability += 0.3; 
    
    // Apply weights to features
    rawProbability += KYC_COUNT * 0.1;
    rawProbability += SMALL_REPAY_COUNT * 0.2;
    rawProbability += LARGE_REPAYMENT_COUNT * 0.4;
    rawProbability += SOCIAL_MENTOR_HOURS * 0.05;

    // Cap probability at 0.99 for stability
    rawProbability = Math.min(rawProbability, 0.99);

    // SCALE PROBABILITY TO FICO-like Score (Example: 300 to 850)
    // Score = 300 + (Probability * 550)
    const riskScore = Math.floor(300 + (rawProbability * 550));
    // --- END TF.JS SIMULATION ---

    // The score needed for the Solidity contract (uint256)
    return riskScore; 
}


/**
 * @notice Main function that orchestrates the entire process: fetch, feature engineer, run model, and publish.
 * @param userAddress The connected Celo address.
 * @param sbtData The full list of SBTs (fetched via web3).
 * @param contractInstance The instance of the AIRiskOracle contract.
 */
export async function calculateAndPublishScore(userAddress, sbtData, oracleContractInstance, web3Kit) {
    if (!sbtData || sbtData.length === 0) {
        throw new Error("Cannot calculate score: No SBTs found.");
    }

    // 1. Create Features (Step 2)
    const features = createFeatureVector(sbtData);

    // 2. Run Inference (Step 3)
    const financialRiskScore = await runModelInference(features);
    // UBI score would use different weights, but we will use the same for simplicity here
    const ubiEligibilityScore = Math.floor(financialRiskScore * 0.8 / 500 * 100); // Scaled for 0-100 range

    console.log(`Calculated Financial Risk Score: ${financialRiskScore}`);
    console.log(`Calculated UBI Eligibility Score: ${ubiEligibilityScore}`);

    // 3. Publish to AIRiskOracle (Step 4 - On-Chain Proof)
    const tx1 = await oracleContractInstance.methods.publishScore(0, financialRiskScore).send({ from: userAddress });
    const tx2 = await oracleContractInstance.methods.publishScore(1, ubiEligibilityScore).send({ from: userAddress });

    console.log("Scores successfully published to AIRiskOracle.");
    return { financialRiskScore, ubiEligibilityScore, txHash1: tx1.transactionHash, txHash2: tx2.transactionHash };
}

// Example usage of feature engineering (optional for testing in console)
// const features = createFeatureVector(mockSBTData);
// const score = await runModelInference(features);
