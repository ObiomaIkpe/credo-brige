// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IAIRiskOracle
 * @notice Interface for the AIRiskOracle contract to enable PointLedger to query UBI_ELIGIBILITY scores.
 */
interface IAIRiskOracle {
    enum ScoreType { FINANCIAL_RISK, UBI_ELIGIBILITY }
    function getLatestScore(address _holder, ScoreType _scoreType) external view returns (uint256, bool, uint256);
}

/**
 * @title PointLedger
 * @notice Dedicated aggregation layer for reputation points and social eligibility checks.
 * 
 * @dev ROLE IN SYSTEM:
 * - Maintains the official, running total of reputation points for every user
 * - Executes social eligibility checks using both points AND AI scores
 * - Provides analytics events for tracking user progress over time
 * - Acts as the "scoreboard" while SoulboundToken is the "trophy case"
 * 
 * KEY FEATURES:
 * - Secured one-way relationship with SBT (only SBT can update points)
 * - Dual-criteria eligibility: reputation points + AI social score
 * - Comprehensive analytics events for off-chain tracking
 * - Governance-adjustable eligibility thresholds
 * - Supports multiple eligibility programs (scholarships, grants, aid)
 * 
 * WHY SEPARATE FROM SBT CONTRACT?
 * - Gas efficiency: Avoid looping through hundreds of SBTs per user
 * - Instant lookup: totalPoints[user] is O(1) constant time
 * - Clear separation: SBT = detailed data, PointLedger = aggregate score
 */
contract PointLedger is Ownable {
    
    // --- STATE VARIABLES ---

    // The ONLY address allowed to update points (immutable trust relationship)
    address private sbtContractAddress;

    // The AI Risk Oracle for querying social eligibility scores
    IAIRiskOracle private oracleContract;

    // Running total of all points earned by each user
    mapping(address => uint256) private totalPoints;

    // Governance-defined eligibility criteria
    uint256 public minPointsRequired;
    uint256 public minAIScoreRequired;

    // --- EVENTS (COMPREHENSIVE ANALYTICS LAYER) ---

    /**
     * @notice Emitted when points are added to a holder's account.
     * @dev CRITICAL for analytics: Enables tracking of reputation growth over time.
     * Off-chain systems can use this to:
     * - Build user reputation timelines
     * - Track point accumulation velocity
     * - Identify most active users
     * - Generate leaderboards
     */
    event PointsAdded(
        address indexed holder,
        uint256 pointsAdded,
        uint256 newTotal,
        uint256 timestamp
    );

    /**
     * @notice Emitted when an eligibility check is performed.
     * @dev Enables tracking of:
     * - Eligibility approval/rejection rates
     * - User progression toward eligibility
     * - System access patterns
     * - Impact of policy changes
     */
    event EligibilityChecked(
        address indexed holder,
        bool isEligible,
        uint256 currentPoints,
        uint256 currentAIScore,
        uint256 timestamp,
        string checkType  // e.g., "scholarship", "grant", "aid"
    );

    /**
     * @notice Emitted when governance updates eligibility criteria.
     * @dev Tracks policy evolution over time.
     */
    event EligibilityCriteriaUpdated(
        uint256 oldMinPoints,
        uint256 newMinPoints,
        uint256 oldMinAIScore,
        uint256 newMinAIScore,
        uint256 timestamp
    );

    /**
     * @notice Emitted when the AI Risk Oracle address is updated.
     */
    event OracleAddressUpdated(
        address indexed oldOracle,
        address indexed newOracle,
        uint256 timestamp
    );

    // --- MODIFIER ---

    /**
     * @notice Ensures only the SoulboundToken contract can add points.
     * @dev This is the CRITICAL SECURITY BOUNDARY that prevents point manipulation.
     */
    modifier onlySBTContract() {
        require(msg.sender == sbtContractAddress, "Ledger: Only SBT contract can update points");
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @notice Initializes the PointLedger with secured SBT linkage and initial criteria.
     * @param _initialMinPoints Minimum points needed for social eligibility.
     * @param _initialMinAIScore Minimum AI score needed for social eligibility (0-1000 scale).
     */
    constructor(
        uint256 _initialMinPoints,
        uint256 _initialMinAIScore
    ) Ownable(msg.sender) {
        require(_initialMinAIScore <= 1000, "Ledger: AI score must be <= 1000");    
        minPointsRequired = _initialMinPoints;
        minAIScoreRequired = _initialMinAIScore;
    }

    // --- CORE FUNCTIONS ---

    /**
     * @notice Receives point updates from the SoulboundToken contract.
     * @dev SECURED ONE-WAY PUSH: Only callable by the trusted SBT contract.
     * 
     * Process Flow:
     * 1. User earns achievement → Issuer mints SBT
     * 2. SBT contract calls this function automatically
     * 3. Points are aggregated to user's total
     * 4. Event emitted for analytics
     * 
     * @param _holder The user receiving points.
     * @param _pointsToAdd The point value from the newly minted SBT.
     */
    function addPoints(address _holder, uint256 _pointsToAdd) external onlySBTContract {
        uint256 oldTotal = totalPoints[_holder];
        totalPoints[_holder] += _pointsToAdd;
        uint256 newTotal = totalPoints[_holder];

        emit PointsAdded(_holder, _pointsToAdd, newTotal, block.timestamp);
    }

    function setSBTContractAddress(address _sbtAddress) external onlyOwner {
        require(_sbtAddress != address(0), "Invalid address");
        require(sbtContractAddress == address(0), "Already set"); // One-time only
        sbtContractAddress = _sbtAddress;
    }

    /**
     * @notice Checks a user's eligibility for social services using DUAL CRITERIA.
     * @dev This is a VIEW function for querying eligibility without gas costs.
     * 
     * DUAL-CRITERIA ELIGIBILITY MODEL:
     * 1. Reputation Points: Earned through verified on-chain achievements
     * 2. AI Social Score: Measures community participation and social standing
     * 
     * Both criteria must be met for eligibility.
     * 
     * USE CASES:
     * - Scholarship programs
     * - Education grants
     * - UBI/aid distribution
     * - Community resource access
     * 
     * @param _holder The user to check.
     * @return isEligible True if user meets both point AND AI score thresholds.
     * @return currentPoints User's total reputation points.
     * @return currentAIScore User's verified AI social score (0-1000).
     */
    function checkServiceEligibility(address _holder) 
        external 
        view 
        returns (bool isEligible, uint256 currentPoints, uint256 currentAIScore) 
    {
        // 1. Get aggregated reputation points (O(1) lookup)
        currentPoints = totalPoints[_holder];

        // 2. Get verified, non-stale AI social score from Oracle
        require(address(oracleContract) != address(0), "Ledger: Oracle not configured");
        
        bool isValid;
        (currentAIScore, isValid, ) = oracleContract.getLatestScore(_holder, IAIRiskOracle.ScoreType.UBI_ELIGIBILITY);
        require(isValid, "Ledger: Stale or missing AI score");

        // 3. Apply dual-criteria eligibility logic
        isEligible = (currentPoints >= minPointsRequired) && (currentAIScore >= minAIScoreRequired);

        return (isEligible, currentPoints, currentAIScore);
    }

    /**
     * @notice Non-view wrapper for eligibility checks that emits analytics events.
     * @dev Use this when you want to track eligibility checks in off-chain analytics.
     * Gas cost is higher due to event emission, so use checkServiceEligibility() for free queries.
     * 
     * @param _holder The user to check.
     * @param _checkType Description of the eligibility check (e.g., "scholarship", "grant").
     * @return isEligible True if eligible.
     * @return currentPoints User's reputation points.
     * @return currentAIScore User's AI social score.
     */
    function checkAndLogEligibility(address _holder, string memory _checkType)
        external
        returns (bool isEligible, uint256 currentPoints, uint256 currentAIScore)
    {
        // Perform same logic as view function
        currentPoints = totalPoints[_holder];
        
        require(address(oracleContract) != address(0), "Ledger: Oracle not configured");
        
        bool isValid;
        (currentAIScore, isValid, ) = oracleContract.getLatestScore(_holder, IAIRiskOracle.ScoreType.UBI_ELIGIBILITY);
        require(isValid, "Ledger: Stale or missing AI score");
        
        isEligible = (currentPoints >= minPointsRequired) && (currentAIScore >= minAIScoreRequired);

        // Emit event for analytics tracking
        emit EligibilityChecked(_holder, isEligible, currentPoints, currentAIScore, block.timestamp, _checkType);

        return (isEligible, currentPoints, currentAIScore);
    }

    /**
     * @notice Returns a user's total accumulated points.
     * @dev Simple O(1) lookup. This is why we separate PointLedger from SBT contract.
     * @param _holder User address.
     * @return Total reputation points earned.
     */
    function getTotalPoints(address _holder) external view returns (uint256) {
        return totalPoints[_holder];
    }

    /**
     * @notice Batch query for multiple users' point totals.
     * @dev Useful for leaderboards and analytics dashboards.
     * @param _holders Array of user addresses.
     * @return Array of point totals corresponding to each address.
     */
    function getBatchPoints(address[] calldata _holders) external view returns (uint256[] memory) {
        uint256[] memory points = new uint256[](_holders.length);
        for (uint256 i = 0; i < _holders.length; i++) {
            points[i] = totalPoints[_holders[i]];
        }
        return points;
    }

    // --- ADMINISTRATIVE FUNCTIONS ---

    /**
     * @notice Sets the AIRiskOracle contract address.
     * @dev Must be called after Oracle deployment to enable eligibility checks.
     * @param _newOracleAddress Address of the deployed AIRiskOracle contract.
     */
    function setAIRiskOracleAddress(address _newOracleAddress) external onlyOwner {
        require(_newOracleAddress != address(0), "Ledger: Zero address");
        
        address oldOracle = address(oracleContract);
        oracleContract = IAIRiskOracle(_newOracleAddress);

        emit OracleAddressUpdated(oldOracle, _newOracleAddress, block.timestamp);
    }

    /**
     * @notice Updates the minimum requirements for social eligibility.
     * @dev Allows governance to adjust criteria based on:
     * - Program budget constraints
     * - Community feedback
     * - Policy changes
     * - Economic conditions
     * 
     * @param _newMinPoints New minimum reputation points required.
     * @param _newMinAIScore New minimum AI social score required (0-1000).
     */
    function updateEligibilityCriteria(
        uint256 _newMinPoints,
        uint256 _newMinAIScore
    ) external onlyOwner {
        require(_newMinAIScore <= 1000, "Ledger: AI score must be <= 1000");
        
        uint256 oldMinPoints = minPointsRequired;
        uint256 oldMinAIScore = minAIScoreRequired;

        minPointsRequired = _newMinPoints;
        minAIScoreRequired = _newMinAIScore;

        emit EligibilityCriteriaUpdated(
            oldMinPoints,
            _newMinPoints,
            oldMinAIScore,
            _newMinAIScore,
            block.timestamp
        );
    }

    /**
     * @notice Returns current eligibility criteria.
     * @return minPoints Minimum points required.
     * @return minAIScore Minimum AI score required.
     */
    function getEligibilityCriteria() external view returns (uint256 minPoints, uint256 minAIScore) {
        return (minPointsRequired, minAIScoreRequired);
    }

    /**
     * @notice Returns the trusted SBT contract address.
     * @dev This address is immutable after deployment.
     * @return Address of the SoulboundToken contract.
     */
    function getSBTContractAddress() external view returns (address) {
        return sbtContractAddress;
    }

    /**
     * @notice Returns the current Oracle contract address.
     * @return Address of the AIRiskOracle contract.
     */
    function getOracleAddress() external view returns (address) {
        return address(oracleContract);
    }
}