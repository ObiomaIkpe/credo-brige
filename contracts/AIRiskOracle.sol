// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AIRiskOracle
 * @notice User-published AI score verification system for privacy-preserving risk assessment.
 * 
 * @dev ROLE IN SYSTEM:
 * - Stores verifiable, timestamped AI-generated scores
 * - Enables PRIVACY-PRESERVING scoring (AI runs in user's browser)
 * - Enforces score freshness (prevents stale data usage)
 * - Provides trust layer for LoanManager and PointLedger
 * 
 * ARCHITECTURE PHILOSOPHY (LOCAL AI MODEL):
 * Traditional: User → Sends Data → Centralized Server → AI Calculates → Returns Score
 * CredoBridge: User's Browser → Fetches Public SBTs → Local AI Runs → User Publishes Score
 * 
 * WHY THIS DESIGN?
 * - Privacy: User's data never leaves their device
 * - Transparency: AI model is open-source (can be audited)
 * - Decentralization: No central server bottleneck
 * - User Control: Users decide when to update their score
 * 
 * TRUST MODEL:
 * - Users self-publish scores (honor system with incentive alignment)
 * - Timestamp-based freshness prevents score reuse
 * - Consumers (LoanManager) can reject stale scores
 * - Future: Can add cryptographic proofs (ZK-SNARKs) for verification
 * 
 * KEY FEATURES:
 * - Two score types: FINANCIAL_RISK and UBI_ELIGIBILITY
 * - Score staleness enforcement (configurable max age)
 * - Rate limiting to prevent spam
 * - Comprehensive event emission for analytics
 * - Optional: Score history tracking for temporal analysis
 */
contract AIRiskOracle is Ownable {

    // --- ENUMS ---

    /**
     * @notice Two distinct AI scoring categories for different use cases.
     */
    enum ScoreType { 
        FINANCIAL_RISK,      // For loan interest rate calculation (0-1000, higher = better)
        UBI_ELIGIBILITY      // For social service eligibility (0-1000, higher = better)
    }

    // --- DATA STRUCTURES ---

    /**
     * @notice Verified score entry with full metadata.
     */
    struct VerifiedScore {
        uint256 scoreValue;           // The AI-generated score (0-1000 scale)
        uint256 publishedTimestamp;   // When user published this score
        ScoreType scoreType;          // Which type of score this is
        address publishedBy;          // Always the user (self-published)
    }

    /**
     * @notice Optional: Historical score entry for temporal analysis.
     * @dev Enables tracking of score evolution over time.
     */
    struct ScoreHistory {
        uint256 scoreValue;
        uint256 timestamp;
    }

    // --- STATE VARIABLES ---

    // Latest verified score for each user and score type
    mapping(address => mapping(ScoreType => VerifiedScore)) private latestVerifiedScores;

    // Optional: Historical scores for temporal analysis
    mapping(address => mapping(ScoreType => ScoreHistory[])) private scoreHistory;
    bool public historyTrackingEnabled;

    // Score validity configuration
    uint256 public maxScoreAge;           // Maximum time before score is considered stale
    uint256 public constant MIN_SCORE = 0;
    uint256 public constant MAX_SCORE = 1000;

    // Rate limiting to prevent spam (users can't publish too frequently)
    mapping(address => mapping(ScoreType => uint256)) private lastPublishTime;
    uint256 public minPublishInterval;    // Minimum time between publications

    // Emergency controls
    bool public publishingPaused;

    // --- EVENTS ---

    /**
     * @notice Emitted when a user publishes their AI-generated score.
     * @dev CRITICAL for analytics and trust verification.
     */
    event ScorePublished(
        address indexed holder,
        ScoreType indexed scoreType,
        uint256 scoreValue,
        uint256 publishedTimestamp,
        uint256 previousScore  // For tracking score changes
    );

    /**
     * @notice Emitted when a score is queried by another contract.
     * @dev Tracks which contracts are consuming scores (useful for auditing).
     */
    event ScoreQueried(
        address indexed holder,
        ScoreType indexed scoreType,
        uint256 scoreValue,
        address indexed queriedBy,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a stale score query is rejected.
     * @dev Helps users understand why their transaction failed.
     */
    event StaleScoreRejected(
        address indexed holder,
        ScoreType scoreType,
        uint256 scoreAge,
        uint256 maxAllowedAge,
        uint256 timestamp
    );

    event MaxScoreAgeUpdated(uint256 oldAge, uint256 newAge, uint256 timestamp);
    event MinPublishIntervalUpdated(uint256 oldInterval, uint256 newInterval, uint256 timestamp);
    event PublishingPausedToggled(bool isPaused, uint256 timestamp);
    event HistoryTrackingToggled(bool isEnabled, uint256 timestamp);

    // --- MODIFIERS ---

    modifier whenPublishingNotPaused() {
        require(!publishingPaused, "Oracle: Publishing is paused");
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @notice Initializes the Oracle with default settings.
     * @param _initialMaxScoreAge Maximum age before score is stale (e.g., 30 days = 2,592,000 seconds).
     * @param _initialMinPublishInterval Minimum time between score updates (e.g., 1 hour = 3600 seconds).
     */
    constructor(
        uint256 _initialMaxScoreAge,
        uint256 _initialMinPublishInterval
    ) Ownable(msg.sender) {
        require(_initialMaxScoreAge > 0, "Oracle: Max age must be positive");
        require(_initialMinPublishInterval > 0, "Oracle: Min interval must be positive");
        
        maxScoreAge = _initialMaxScoreAge;
        minPublishInterval = _initialMinPublishInterval;
        historyTrackingEnabled = false;  // Disabled by default to save gas
    }

    // --- CORE FUNCTIONS (USER-PUBLISHED MODEL) ---

    /**
     * @notice Users call this to publish their locally-computed AI score.
     * @dev PRIVACY-PRESERVING FLOW:
     * 1. User's browser fetches their SBTs from SoulboundToken contract
     * 2. Open-source AI model runs locally (JavaScript/WASM)
     * 3. Score calculated on client-side (data never sent to server)
     * 4. User signs transaction to publish score on-chain
     * 5. Smart contract validates and stores the score
     * 
     * TRUST MODEL:
     * - Users are incentivized to publish honest scores
     * - Dishonest high scores → Loan default → Bad reputation → Lower future scores
     * - Dishonest low UBI scores → Denied aid → Self-defeating
     * - Timestamp freshness prevents score reuse
     * 
     * FUTURE ENHANCEMENTS:
     * - Require cryptographic proof (ZK-SNARK) that score was calculated correctly
     * - Multi-party computation (MPC) for additional verification
     * - Stake-based honesty incentives
     * 
     * @param _scoreType The category of score (FINANCIAL_RISK or UBI_ELIGIBILITY).
     * @param _scoreValue The AI-generated score (0-1000 scale).
     */
    function publishScore(
        ScoreType _scoreType,
        uint256 _scoreValue
    ) external whenPublishingNotPaused {
        // 1. Validate score range
        require(
            _scoreValue >= MIN_SCORE && _scoreValue <= MAX_SCORE, 
            "Oracle: Score out of valid range (0-1000)"
        );

        // 2. Rate limiting check (prevent spam)
        uint256 timeSinceLastPublish = block.timestamp - lastPublishTime[msg.sender][_scoreType];
        require(
            timeSinceLastPublish >= minPublishInterval, 
            "Oracle: Must wait longer between score updates"
        );

        // 3. Get previous score for event emission
        uint256 previousScore = latestVerifiedScores[msg.sender][_scoreType].scoreValue;

        // 4. Create and store the new verified score
        latestVerifiedScores[msg.sender][_scoreType] = VerifiedScore({
            scoreValue: _scoreValue,
            publishedTimestamp: block.timestamp,
            scoreType: _scoreType,
            publishedBy: msg.sender  // Always self-published
        });

        // 5. Update rate limiting timestamp
        lastPublishTime[msg.sender][_scoreType] = block.timestamp;

        // 6. Optional: Store in history for temporal analysis
        if (historyTrackingEnabled) {
            scoreHistory[msg.sender][_scoreType].push(ScoreHistory({
                scoreValue: _scoreValue,
                timestamp: block.timestamp
            }));
        }

        // 7. Emit event for off-chain tracking
        emit ScorePublished(
            msg.sender, 
            _scoreType, 
            _scoreValue, 
            block.timestamp,
            previousScore
        );
    }

    /**
     * @notice Retrieves a verified, NON-STALE score (called by LoanManager, PointLedger, etc.).
     * @dev CRITICAL FUNCTION: This enforces score freshness.
     * 
     * STALENESS CHECK:
     * - If score is older than maxScoreAge, transaction REVERTS
     * - Forces user to regenerate and publish a fresh score
     * - Prevents users from reusing old favorable scores
     * 
     * @param _holder The user whose score is being queried.
     * @param _scoreType The category of score to retrieve.
     * @return The verified score value (reverts if stale or non-existent).
     */
    function getLatestScore(address _holder, ScoreType _scoreType) external returns (uint256) {
        VerifiedScore storage score = latestVerifiedScores[_holder][_scoreType];

        // 1. Ensure score exists
        require(score.publishedTimestamp > 0, "Oracle: No score published for this user");

        // 2. Check staleness (CRITICAL SECURITY CHECK)
        uint256 scoreAge = block.timestamp - score.publishedTimestamp;
        if (scoreAge > maxScoreAge) {
            emit StaleScoreRejected(_holder, _scoreType, scoreAge, maxScoreAge, block.timestamp);
            revert("Oracle: Score is stale, user must publish a fresh score");
        }

        // 3. Emit query event for analytics
        emit ScoreQueried(_holder, _scoreType, score.scoreValue, msg.sender, block.timestamp);

        return score.scoreValue;
    }

    /**
     * @notice View-only version of getLatestScore (doesn't emit events, free to call).
     * @dev Use for frontend displays. Use getLatestScore() for contract calls.
     * @param _holder User address.
     * @param _scoreType Score category.
     * @return scoreValue The score (or 0 if stale/non-existent).
     * @return isValid True if score exists and is fresh.
     * @return age How old the score is in seconds.
     */
    function getLatestScoreView(address _holder, ScoreType _scoreType) 
        external 
        view 
        returns (uint256 scoreValue, bool isValid, uint256 age) 
    {
        VerifiedScore storage score = latestVerifiedScores[_holder][_scoreType];
        
        if (score.publishedTimestamp == 0) {
            return (0, false, 0);
        }
        
        age = block.timestamp - score.publishedTimestamp;
        isValid = age <= maxScoreAge;
        scoreValue = score.scoreValue;
        
        return (scoreValue, isValid, age);
    }

    /**
     * @notice Returns full score metadata including timestamp and publisher.
     * @dev Useful for frontend dashboards showing score history.
     * @param _holder User address.
     * @param _scoreType Score category.
     * @return The complete VerifiedScore struct.
     */
    function getScoreMetadata(address _holder, ScoreType _scoreType) 
        external 
        view 
        returns (VerifiedScore memory) 
    {
        return latestVerifiedScores[_holder][_scoreType];
    }

    /**
     * @notice Returns historical scores for temporal analysis.
     * @dev Only works if historyTrackingEnabled is true.
     * @param _holder User address.
     * @param _scoreType Score category.
     * @return Array of historical score entries.
     */
    function getScoreHistory(address _holder, ScoreType _scoreType) 
        external 
        view 
        returns (ScoreHistory[] memory) 
    {
        require(historyTrackingEnabled, "Oracle: History tracking is disabled");
        return scoreHistory[_holder][_scoreType];
    }

    /**
     * @notice Batch query for multiple users' scores.
     * @dev Useful for analytics dashboards and leaderboards.
     * @param _holders Array of user addresses.
     * @param _scoreType Score category to query.
     * @return scores Array of score values.
     * @return validities Array of validity flags.
     */
    function getBatchScores(address[] calldata _holders, ScoreType _scoreType) 
        external 
        view 
        returns (uint256[] memory scores, bool[] memory validities) 
    {
        scores = new uint256[](_holders.length);
        validities = new bool[](_holders.length);
        
        for (uint256 i = 0; i < _holders.length; i++) {
            VerifiedScore storage score = latestVerifiedScores[_holders[i]][_scoreType];
            
            if (score.publishedTimestamp > 0) {
                uint256 age = block.timestamp - score.publishedTimestamp;
                scores[i] = score.scoreValue;
                validities[i] = age <= maxScoreAge;
            } else {
                scores[i] = 0;
                validities[i] = false;
            }
        }
        
        return (scores, validities);
    }

    // --- ADMINISTRATIVE FUNCTIONS ---

    /**
     * @notice Updates the maximum age a score remains valid.
     * @dev Governance function to adjust staleness threshold.
     * @param _newMaxAgeInSeconds New maximum age (e.g., 2592000 for 30 days).
     */
    function setMaxScoreAge(uint256 _newMaxAgeInSeconds) external onlyOwner {
        require(_newMaxAgeInSeconds > 0, "Oracle: Max age must be positive");
        
        uint256 oldAge = maxScoreAge;
        maxScoreAge = _newMaxAgeInSeconds;
        
        emit MaxScoreAgeUpdated(oldAge, _newMaxAgeInSeconds, block.timestamp);
    }

    /**
     * @notice Updates the minimum time between score publications.
     * @dev Prevents spam while allowing reasonable update frequency.
     * @param _newMinInterval New minimum interval in seconds.
     */
    function setMinPublishInterval(uint256 _newMinInterval) external onlyOwner {
        require(_newMinInterval > 0, "Oracle: Min interval must be positive");
        
        uint256 oldInterval = minPublishInterval;
        minPublishInterval = _newMinInterval;
        
        emit MinPublishIntervalUpdated(oldInterval, _newMinInterval, block.timestamp);
    }

    /**
     * @notice Emergency pause/unpause for score publishing.
     * @dev Use during security incidents or system upgrades.
     */
    function togglePublishingPause() external onlyOwner {
        publishingPaused = !publishingPaused;
        emit PublishingPausedToggled(publishingPaused, block.timestamp);
    }

    /**
     * @notice Enable/disable historical score tracking.
     * @dev History tracking costs extra gas, so it's optional.
     */
    function toggleHistoryTracking() external onlyOwner {
        historyTrackingEnabled = !historyTrackingEnabled;
        emit HistoryTrackingToggled(historyTrackingEnabled, block.timestamp);
    }

    // --- VIEW FUNCTIONS ---

    /**
     * @notice Returns current configuration parameters.
     */
    function getConfiguration() external view returns (
        uint256 _maxScoreAge,
        uint256 _minPublishInterval,
        bool _publishingPaused,
        bool _historyTrackingEnabled
    ) {
        return (
            maxScoreAge,
            minPublishInterval,
            publishingPaused,
            historyTrackingEnabled
        );
    }

    /**
     * @notice Checks if a user can publish a score right now.
     * @param _holder User address.
     * @param _scoreType Score category.
     * @return canPublish True if rate limit allows publishing.
     * @return timeUntilNextPublish Seconds until next publish is allowed (0 if can publish now).
     */
    function canPublishScore(address _holder, ScoreType _scoreType) 
        external 
        view 
        returns (bool canPublish, uint256 timeUntilNextPublish) 
    {
        if (publishingPaused) {
            return (false, type(uint256).max);
        }
        
        uint256 timeSinceLastPublish = block.timestamp - lastPublishTime[_holder][_scoreType];
        
        if (timeSinceLastPublish >= minPublishInterval) {
            return (true, 0);
        } else {
            return (false, minPublishInterval - timeSinceLastPublish);
        }
    }
}