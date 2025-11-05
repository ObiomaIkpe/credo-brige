/**
 * Calculate FINANCIAL_RISK Score (0-1000)
 * Used by LoanManager for interest rate calculation
 */
function calculateFinancialRiskScore(userSBTs) {
    // STEP 1: MANDATORY KYC CHECK - NO KYC = ZERO SCORE
    const hasKYC = userSBTs.some(sbt => 
        sbt.taskType === 'IDENTITY_VERIFIED_KYC' || 
        sbt.taskType === 'IDENTITY_MULTI_FACTOR'
    );
    
    if (!hasKYC) {
        return 0;  // NO KYC = INELIGIBLE
    }

    // STEP 2: Calculate raw weighted score
    let rawScore = 0;
    
    // Weight definitions
    const weights = {
        IDENTITY_VERIFIED_KYC: 3.0,
        IDENTITY_MULTI_FACTOR: 4.0,
        LOAN_REPAYMENT_SMALL: 10.0,
        LOAN_REPAYMENT_LARGE: 15.0,
        FINANCIAL_LITERACY_COURSE: 2.0,
        FINANCIAL_SAVINGS_GOAL: 2.5,
        AID_DISBURSEMENT_RECEIVED: 1.0,
        COMMUNITY_VOLUNTEERISM: 2.0,
        SOCIAL_EDUCATION_CERT: 2.0,
        SOCIAL_MENTORSHIP: 2.5
    };
    
    // Calculate weighted sum with recency
    for (const sbt of userSBTs) {
        const weight = weights[sbt.taskType] || 0;
        const pointValue = sbt.pointLevel; // 100, 300, 750, or 1500
        const recency = calculateRecencyMultiplier(sbt.issuedAt);
        
        rawScore += weight * pointValue * recency;
    }
    
    // STEP 3: Check first-time borrower requirements
    const hasLoanRepayment = userSBTs.some(sbt => 
        sbt.taskType === 'LOAN_REPAYMENT_SMALL' || 
        sbt.taskType === 'LOAN_REPAYMENT_LARGE'
    );
    
    if (!hasLoanRepayment) {
        // First-time borrower: needs KYC + social + other
        const hasSocial = userSBTs.some(sbt => 
            sbt.taskType === 'COMMUNITY_VOLUNTEERISM' ||
            sbt.taskType === 'SOCIAL_EDUCATION_CERT' ||
            sbt.taskType === 'SOCIAL_MENTORSHIP'
        );
        
        const nonFinancialCount = userSBTs.filter(sbt => 
            !['LOAN_REPAYMENT_SMALL', 'LOAN_REPAYMENT_LARGE', 
              'FINANCIAL_LITERACY_COURSE', 'FINANCIAL_SAVINGS_GOAL',
              'AID_DISBURSEMENT_RECEIVED'].includes(sbt.taskType)
        ).length;
        
        if (!hasSocial || nonFinancialCount < 2) {
            return 0;  // Doesn't meet first-timer requirements
        }
    }
    
    // STEP 4: Scale to 0-1000
    const finalScore = scaleToThousand(rawScore);
    return Math.max(0, Math.min(1000, finalScore));
}

/**
 * Calculate UBI_ELIGIBILITY Score (0-1000)
 * Used by PointLedger for social service eligibility
 */
function calculateUBIEligibilityScore(userSBTs) {
    // STEP 1: MANDATORY KYC CHECK - NO KYC = ZERO SCORE
    const hasKYC = userSBTs.some(sbt => 
        sbt.taskType === 'IDENTITY_VERIFIED_KYC' || 
        sbt.taskType === 'IDENTITY_MULTI_FACTOR'
    );
    
    if (!hasKYC) {
        return 0;  // NO KYC = INELIGIBLE
    }

    // STEP 2: Calculate raw weighted score
    let rawScore = 0;
    
    // Weight definitions (social-focused)
    const weights = {
        IDENTITY_VERIFIED_KYC: 5.0,
        IDENTITY_MULTI_FACTOR: 6.0,
        COMMUNITY_VOLUNTEERISM: 8.0,
        SOCIAL_EDUCATION_CERT: 7.0,
        SOCIAL_MENTORSHIP: 9.0,
        FINANCIAL_LITERACY_COURSE: 2.0,
        FINANCIAL_SAVINGS_GOAL: 1.5,
        LOAN_REPAYMENT_SMALL: 1.0,
        LOAN_REPAYMENT_LARGE: 1.0,
        AID_DISBURSEMENT_RECEIVED: 3.0
    };
    
    // Calculate weighted sum with recency
    for (const sbt of userSBTs) {
        const weight = weights[sbt.taskType] || 0;
        const pointValue = sbt.pointLevel; // 100, 300, 750, or 1500
        const recency = calculateRecencyMultiplier(sbt.issuedAt);
        
        rawScore += weight * pointValue * recency;
    }
    
    // STEP 3: Scale to 0-1000
    const finalScore = scaleToThousand(rawScore);
    return Math.max(0, Math.min(1000, finalScore));
}

/**
 * Calculate recency multiplier based on achievement age
 */
function calculateRecencyMultiplier(issuedAtTimestamp) {
    const ageInMonths = (Date.now() / 1000 - issuedAtTimestamp) / (30 * 24 * 60 * 60);
    
    if (ageInMonths <= 6) return 1.0;
    if (ageInMonths <= 12) return 0.75;
    if (ageInMonths <= 18) return 0.50;
    if (ageInMonths <= 24) return 0.25;
    return 0.10;
}

/**
 * Scale raw weighted score to 0-1000 range
 */
function scaleToThousand(rawScore) {
    // Reference thresholds (calibrate these based on your data)
    const EXCELLENT_THRESHOLD = 8000;  // Raw score for 800+ final score
    
    if (rawScore >= EXCELLENT_THRESHOLD) {
        // Above excellent: scale 800-1000
        const excess = rawScore - EXCELLENT_THRESHOLD;
        return 800 + Math.min(200, (excess / EXCELLENT_THRESHOLD) * 200);
    } else {
        // Below excellent: linear scale 0-800
        return (rawScore / EXCELLENT_THRESHOLD) * 800;
    }
}