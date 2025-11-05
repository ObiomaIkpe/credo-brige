// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// --- INTERFACES FOR DEPENDENT CONTRACTS ---

/**
 * @notice Standard ERC-20 Interface for interacting with Celo Stablecoins (cUSD/cEUR).
 */
interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

/**
 * @notice Interface for querying verified AI scores from the AIRiskOracle.
 */
interface IAIRiskOracle {
    enum ScoreType { FINANCIAL_RISK, UBI_ELIGIBILITY }
    function getLatestScore(address _holder, ScoreType _scoreType) external returns (uint256);
}

/**
 * @notice Interface for checking reputation points from PointLedger.
 */
interface IPointLedger {
    function getTotalPoints(address _holder) external view returns (uint256);
}

/**
 * @notice Interface for rewarding successful repayment by minting SBTs.
 */
interface ISoulboundToken {
    enum TaskType { 
        IDENTITY_VERIFIED_KYC,
        IDENTITY_MULTI_FACTOR,
        FINANCIAL_LITERACY_COURSE,
        FINANCIAL_SAVINGS_GOAL,
        LOAN_REPAYMENT_SMALL,
        LOAN_REPAYMENT_LARGE,
        AID_DISBURSEMENT_RECEIVED,
        COMMUNITY_VOLUNTEERISM,
        SOCIAL_EDUCATION_CERT,
        SOCIAL_MENTORSHIP
    }
    enum PointLevel { LEVEL_D_MINOR, LEVEL_C_MAJOR, LEVEL_B_HARMONY, LEVEL_A_PRESTIGE }
    
    function issueSBT(
        address _holder,
        TaskType _taskType,
        PointLevel _pointLevel,
        string memory _title,
        string memory _tokenURI
    ) external;
}

/**
 * @title LoanManager
 * @notice Manages the lending pool, calculates interest rates based on AI scores, and rewards repayment.
 * 
 * @dev ROLE IN SYSTEM:
 * - Integration layer: Consumes data from all three other contracts
 * - Financial utility: Provides loans based on reputation and AI scores
 * - Reputation loop closer: Rewards good behavior with high-value SBTs
 * - Multi-criteria gating: Checks both reputation points AND AI score
 * 
 * KEY FEATURES (ALL FIXES IMPLEMENTED):
 * ✅ Correct interest calculation using stored duration
 * ✅ Reentrancy protection on all state-changing functions
 * ✅ Address validation in constructor
 * ✅ Balance checks before disbursement
 * ✅ Try-catch for SBT minting (graceful failure handling)
 * ✅ Integration with PointLedger for minimum reputation check
 * ✅ Loan cancellation mechanism
 * ✅ Withdrawal function for profit management
 * ✅ Comprehensive event emission
 * ✅ Emergency pause capability
 * ✅ Late payment tracking (optional penalty structure)
 * 
 * LOAN TIERS:
 * - Small Loan: < 500 cUSD → Rewards LOAN_REPAYMENT_SMALL (300 points)
 * - Large Loan: ≥ 500 cUSD → Rewards LOAN_REPAYMENT_LARGE (1500 points)
 */
contract LoanManager is Ownable, ReentrancyGuard, Pausable {
    
    // --- DATA STRUCTURES ---

    /**
     * @notice Complete loan record with all necessary data for interest calculation.
     */
    struct Loan {
        address borrower;
        uint256 principalAmount;
        uint256 interestRateBps;       // Annual rate in basis points (100 bps = 1%)
        uint256 disbursedAt;           // [FIXED] Timestamp when loan was disbursed
        uint256 durationDays;          // [FIXED] Loan term in days
        uint256 repaymentDeadline;     // Calculated from disbursedAt + duration
        bool isRepaid;
        bool isApproved;               // Distinguishes between applied and approved
    }

    // --- STATE VARIABLES ---

    // Dependent contract addresses
    IAIRiskOracle private oracleContract;
    ISoulboundToken private sbtContract;
    IPointLedger private pointLedgerContract;
    IERC20 private stableCoinContract;

    // Authorized loan administrator
    address public loanAdmin;

    // Loan tracking
    mapping(address => Loan) private activeLoans;

    // Loan eligibility criteria
    uint256 public minReputationPoints;     // Minimum points needed to apply
    uint256 public minAIRiskScore;          // Minimum AI score needed to apply
    uint256 public maxLoanAmount;           // Maximum loan size
    uint256 public minLoanAmount;           // Minimum loan size
    uint256 public loanSizeThreshold;       // Threshold for small vs large loan (for SBT rewards)

    // System statistics
    uint256 public totalLoansIssued;
    uint256 public totalLoansRepaid;
    uint256 public totalPrincipalDisbursed;
    uint256 public totalPrincipalRepaid;
    uint256 public totalInterestCollected;

    // --- EVENTS ---

    event LoanApplied(
        address indexed borrower, 
        uint256 principal, 
        uint256 rateBps, 
        uint256 aiScore,
        uint256 reputationPoints,
        uint256 timestamp
    );
    
    event LoanApproved(
        address indexed borrower,
        uint256 principal,
        uint256 durationDays,
        uint256 deadline,
        uint256 timestamp
    );
    
    event LoanDisbursed(
        address indexed borrower, 
        uint256 principal, 
        uint256 totalRepaymentDue,
        uint256 interestAmount,
        uint256 timestamp
    );
    
    event LoanRepaid(
        address indexed borrower, 
        uint256 amountPaid,
        uint256 interestPaid,
        bool sbtMinted,
        bool isLate,
        uint256 timestamp
    );
    
    event LoanCancelled(
        address indexed borrower,
        uint256 principal,
        uint256 timestamp
    );
    
    event ProfitsWithdrawn(
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );
    
    event EligibilityCriteriaUpdated(
        uint256 minPoints,
        uint256 minAIScore,
        uint256 timestamp
    );
    
    event LoanLimitsUpdated(
        uint256 minAmount,
        uint256 maxAmount,
        uint256 threshold,
        uint256 timestamp
    );

    event AdminChanged(address indexed oldAdmin, address indexed newAdmin, uint256 timestamp);

    // --- MODIFIERS ---

    modifier onlyAdmin() {
        require(msg.sender == loanAdmin, "LoanManager: Caller is not the authorized admin");
        _;
    }
    
    // --- CONSTRUCTOR ---

    /**
     * @notice Initializes LoanManager with all dependencies and configuration.
     * @param _oracleAddress AIRiskOracle contract address.
     * @param _sbtAddress SoulboundToken contract address.
     * @param _pointLedgerAddress PointLedger contract address.
     * @param _stableCoinAddress Celo stablecoin (cUSD/cEUR) contract address.
     * @param _initialAdmin Address authorized to approve loans.
     * @param _minReputationPoints Minimum reputation points required to apply.
     * @param _minAIRiskScore Minimum AI risk score required to apply (0-1000).
     */
    constructor(
        address _oracleAddress,
        address _sbtAddress,
        address _pointLedgerAddress,
        address _stableCoinAddress,
        address _initialAdmin,
        uint256 _minReputationPoints,
        uint256 _minAIRiskScore
    ) Ownable(msg.sender) {
        // [FIXED] Comprehensive address validation
        require(_oracleAddress != address(0), "LoanManager: Oracle address cannot be zero");
        require(_sbtAddress != address(0), "LoanManager: SBT address cannot be zero");
        require(_pointLedgerAddress != address(0), "LoanManager: PointLedger address cannot be zero");
        require(_stableCoinAddress != address(0), "LoanManager: StableCoin address cannot be zero");
        require(_initialAdmin != address(0), "LoanManager: Admin address cannot be zero");
        require(_minAIRiskScore <= 1000, "LoanManager: AI score must be <= 1000");
        
        oracleContract = IAIRiskOracle(_oracleAddress);
        sbtContract = ISoulboundToken(_sbtAddress);
        pointLedgerContract = IPointLedger(_pointLedgerAddress);
        stableCoinContract = IERC20(_stableCoinAddress);
        loanAdmin = _initialAdmin;
        
        minReputationPoints = _minReputationPoints;
        minAIRiskScore = _minAIRiskScore;
        
        // Default loan limits (can be adjusted by owner)
        minLoanAmount = 100e18;        // 100 cUSD minimum
        maxLoanAmount = 5000e18;       // 5,000 cUSD maximum
        loanSizeThreshold = 500e18;    // 500 cUSD threshold (small vs large)
    }

    // --- INTEREST RATE LOGIC ---

    /**
     * @notice Calculates annual interest rate based on AI risk score.
     * @dev Higher score = lower risk = lower interest rate.
     * 
     * RATE TIERS:
     * - 800-1000: 5.00% (Excellent)
     * - 700-799:  7.50% (Good)
     * - 600-699:  10.00% (Fair)
     * - 0-599:    15.00% (High Risk)
     * 
     * @param _riskScore The FINANCIAL_RISK score from AIRiskOracle (0-1000).
     * @return Annual interest rate in basis points (bps).
     */
    function getInterestRate(uint256 _riskScore) internal pure returns (uint256) {
        if (_riskScore >= 800) return 500;   // 5.00%
        if (_riskScore >= 700) return 750;   // 7.50%
        if (_riskScore >= 600) return 1000;  // 10.00%
        return 1500; // 15.00%
    }

    /**
     * @notice Calculates total repayment amount (Principal + Interest).
     * @dev [FIXED] Now uses simple interest formula with correct inputs.
     * 
     * Formula: Interest = Principal × (Rate / 10000) × (Days / 365)
     * 
     * @param _principal Original loan amount.
     * @param _rateBps Annual interest rate in basis points.
     * @param _durationDays Loan term in days.
     * @return totalRepayment Total amount due (principal + interest).
     */
    function calculateTotalRepayment(
        uint256 _principal,
        uint256 _rateBps,
        uint256 _durationDays
    ) public pure returns (uint256) {
        // Interest = Principal * (Rate / 10000) * (Days / 365)
        uint256 interest = (_principal * _rateBps * _durationDays) / (10000 * 365);
        return _principal + interest;
    }

    // --- LOAN APPLICATION FLOW ---

    /**
     * @notice User initiates a loan application.
     * @dev [FIXED] Now checks BOTH reputation points AND AI score.
     * 
     * MULTI-CRITERIA GATING:
     * 1. User must have minimum reputation points (on-chain verified achievements)
     * 2. User must have fresh AI risk score above threshold
     * 3. User cannot have an active loan already
     * 4. Loan amount must be within limits
     * 
     * @param _principalAmount Desired loan amount in stablecoin.
     */
    function applyForLoan(uint256 _principalAmount) external whenNotPaused nonReentrant {
        require(activeLoans[msg.sender].principalAmount == 0, "LoanManager: User already has an active loan");
        require(_principalAmount >= minLoanAmount && _principalAmount <= maxLoanAmount, 
            "LoanManager: Loan amount outside allowed range");

        // [FIXED] Check reputation points (integration with PointLedger)
        uint256 userPoints = pointLedgerContract.getTotalPoints(msg.sender);
        require(userPoints >= minReputationPoints, 
            "LoanManager: Insufficient reputation points");

        // Read AI Risk Score (reverts if stale or non-existent)
        uint256 riskScore = oracleContract.getLatestScore(msg.sender, IAIRiskOracle.ScoreType.FINANCIAL_RISK);
        require(riskScore >= minAIRiskScore, 
            "LoanManager: AI risk score too low");

        // Calculate interest rate based on score
        uint256 rateBps = getInterestRate(riskScore);

        // Create loan application (not yet approved/disbursed)
        activeLoans[msg.sender] = Loan({
            borrower: msg.sender,
            principalAmount: _principalAmount,
            interestRateBps: rateBps,
            disbursedAt: 0,              // Set during approval
            durationDays: 0,             // Set during approval
            repaymentDeadline: 0,        // Set during approval
            isRepaid: false,
            isApproved: false            // Pending admin approval
        });

        emit LoanApplied(msg.sender, _principalAmount, rateBps, riskScore, userPoints, block.timestamp);
    }

    /**
     * @notice Admin approves and disburses loan funds.
     * @dev [FIXED] Now includes:
     * - Balance check before disbursement
     * - Proper timestamp and duration storage
     * - State update before external call
     * 
     * @param _borrower Address of the applicant.
     * @param _durationDays Loan term in days (e.g., 30, 90, 180).
     */
    function approveAndDisburseLoan(
        address _borrower,
        uint256 _durationDays
    ) external onlyAdmin whenNotPaused nonReentrant {
        Loan storage loan = activeLoans[_borrower];
        require(loan.principalAmount > 0, "LoanManager: No loan application found");
        require(!loan.isApproved, "LoanManager: Loan already approved");
        require(_durationDays > 0 && _durationDays <= 365, "LoanManager: Invalid duration");

        // [FIXED] Check contract has sufficient balance
        uint256 contractBalance = stableCoinContract.balanceOf(address(this));
        require(contractBalance >= loan.principalAmount, 
            "LoanManager: Insufficient contract balance for disbursement");

        // [FIXED] Store duration and timestamps BEFORE external call
        loan.disbursedAt = block.timestamp;
        loan.durationDays = _durationDays;
        loan.repaymentDeadline = block.timestamp + (_durationDays * 1 days);
        loan.isApproved = true;

        // Update statistics
        totalLoansIssued++;
        totalPrincipalDisbursed += loan.principalAmount;

        emit LoanApproved(_borrower, loan.principalAmount, _durationDays, loan.repaymentDeadline, block.timestamp);

        // Disburse funds (external call AFTER state updates)
        require(
            stableCoinContract.transfer(_borrower, loan.principalAmount),
            "LoanManager: Stablecoin disbursement failed"
        );

        uint256 totalRepayment = calculateTotalRepayment(loan.principalAmount, loan.interestRateBps, _durationDays);
        uint256 interestAmount = totalRepayment - loan.principalAmount;
        
        emit LoanDisbursed(_borrower, loan.principalAmount, totalRepayment, interestAmount, block.timestamp);
    }

    /**
     * @notice User repays their loan in full.
     * @dev [FIXED] Multiple critical fixes:
     * - Correct interest calculation using stored duration
     * - Try-catch for SBT minting (graceful failure)
     * - State updates before external calls
     * - Late payment detection
     * - Tiered SBT rewards based on loan size
     * 
     * REPAYMENT FLOW:
     * 1. User must approve LoanManager to spend stablecoin (off-chain)
     * 2. User calls this function
     * 3. Contract calculates correct total due
     * 4. Transfers funds from user to contract
     * 5. Marks loan as repaid
     * 6. Attempts to mint reward SBT
     * 7. Updates statistics
     */
    function repayLoan() external whenNotPaused nonReentrant {
        Loan storage loan = activeLoans[msg.sender];
        require(loan.principalAmount > 0, "LoanManager: No active loan found");
        require(loan.isApproved, "LoanManager: Loan not yet approved");
        require(!loan.isRepaid, "LoanManager: Loan already repaid");

        // [FIXED] Calculate total due using STORED duration
        uint256 totalDue = calculateTotalRepayment(
            loan.principalAmount,
            loan.interestRateBps,
            loan.durationDays  // Uses stored value from approval
        );
        uint256 interestAmount = totalDue - loan.principalAmount;

        // Check if repayment is late
        bool isLate = block.timestamp > loan.repaymentDeadline;

        // Mark as repaid BEFORE external calls (reentrancy protection)
        loan.isRepaid = true;

        // Update statistics
        totalLoansRepaid++;
        totalPrincipalRepaid += loan.principalAmount;
        totalInterestCollected += interestAmount;

        // Transfer repayment from user to contract
        require(
            stableCoinContract.transferFrom(msg.sender, address(this), totalDue),
            "LoanManager: Repayment transfer failed (check allowance and balance)"
        );

        // [FIXED] Attempt to mint reward SBT with try-catch for graceful failure
        bool sbtMinted = _rewardRepayment(msg.sender, loan.principalAmount);

        emit LoanRepaid(msg.sender, totalDue, interestAmount, sbtMinted, isLate, block.timestamp);
        
        // Clean up loan data
        delete activeLoans[msg.sender];
    }

    /**
     * @notice Internal function to reward loan repayment with SBT.
     * @dev [FIXED] Uses try-catch to prevent repayment failure if SBT minting fails.
     * Tiered rewards: Small loans get 300 points, large loans get 1500 points.
     * 
     * @param _borrower User who repaid.
     * @param _loanAmount Size of the repaid loan.
     * @return success True if SBT was successfully minted.
     */
    function _rewardRepayment(address _borrower, uint256 _loanAmount) private returns (bool success) {
        // Determine reward tier based on loan size
        ISoulboundToken.TaskType taskType;
        ISoulboundToken.PointLevel pointLevel;
        string memory title;
        
        if (_loanAmount >= loanSizeThreshold) {
            // Large loan (≥500 cUSD)
            taskType = ISoulboundToken.TaskType.LOAN_REPAYMENT_LARGE;
            pointLevel = ISoulboundToken.PointLevel.LEVEL_A_PRESTIGE;  // 1500 points
            title = "Large Loan Repayment Success";
        } else {
            // Small loan (<500 cUSD)
            taskType = ISoulboundToken.TaskType.LOAN_REPAYMENT_SMALL;
            pointLevel = ISoulboundToken.PointLevel.LEVEL_C_MAJOR;  // 300 points
            title = "Small Loan Repayment Success";
        }

        // Try to mint SBT, but don't revert repayment if it fails
        try sbtContract.issueSBT(
            _borrower,
            taskType,
            pointLevel,
            title,
            "ipfs://loan-repayment-metadata"
        ) {
            return true;  // SBT minted successfully
        } catch {
            return false;  // SBT minting failed, but loan still repaid
        }
    }

    // --- LOAN MANAGEMENT FUNCTIONS ---

    /**
     * @notice User cancels their unapproved loan application.
     * @dev [FIXED] Allows users to cancel if admin hasn't approved yet.
     */
    function cancelLoanApplication() external nonReentrant {
        Loan storage loan = activeLoans[msg.sender];
        require(loan.principalAmount > 0, "LoanManager: No active loan application");
        require(!loan.isApproved, "LoanManager: Cannot cancel approved loan");

        uint256 principal = loan.principalAmount;
        delete activeLoans[msg.sender];

        emit LoanCancelled(msg.sender, principal, block.timestamp);
    }

    /**
     * @notice Admin rejects a loan application.
     * @param _borrower Address of applicant to reject.
     */
    function rejectLoanApplication(address _borrower) external onlyAdmin nonReentrant {
        Loan storage loan = activeLoans[_borrower];
        require(loan.principalAmount > 0, "LoanManager: No loan application found");
        require(!loan.isApproved, "LoanManager: Cannot reject approved loan");

        uint256 principal = loan.principalAmount;
        delete activeLoans[_borrower];

        emit LoanCancelled(_borrower, principal, block.timestamp);
    }

    // --- VIEW FUNCTIONS ---

    /**
     * @notice Returns complete loan details for a borrower.
     */
    function getLoanStatus(address _borrower) external view returns (Loan memory) {
        return activeLoans[_borrower];
    }

    /**
     * @notice Calculates expected repayment amount for an active loan.
     * @param _borrower Address to query.
     * @return totalDue Total amount to be repaid (0 if no active loan).
     * @return principal Original loan amount.
     * @return interest Interest amount.
     */
    function getRepaymentAmount(address _borrower) external view returns (
        uint256 totalDue,
        uint256 principal,
        uint256 interest
    ) {
        Loan storage loan = activeLoans[_borrower];
        if (loan.principalAmount == 0 || !loan.isApproved) {
            return (0, 0, 0);
        }

        totalDue = calculateTotalRepayment(loan.principalAmount, loan.interestRateBps, loan.durationDays);
        principal = loan.principalAmount;
        interest = totalDue - principal;

        return (totalDue, principal, interest);
    }

    /**
     * @notice Returns system-wide statistics.
     */
    function getSystemStats() external view returns (
        uint256 loansIssued,
        uint256 loansRepaid,
        uint256 principalDisbursed,
        uint256 principalRepaid,
        uint256 interestCollected,
        uint256 contractBalance
    ) {
        return (
            totalLoansIssued,
            totalLoansRepaid,
            totalPrincipalDisbursed,
            totalPrincipalRepaid,
            totalInterestCollected,
            stableCoinContract.balanceOf(address(this))
        );
    }

    /**
     * @notice Simulates loan terms for a given amount (before applying).
     * @param _user User address (to check their AI score).
     * @param _amount Desired loan amount.
     * @param _duration Desired duration in days.
     * @return eligible Whether user meets criteria.
     * @return rateBps Interest rate they would receive.
     * @return totalRepayment Total amount they would need to repay.
     */
    function simulateLoan(address _user, uint256 _amount, uint256 _duration) external view returns (
        bool eligible,
        uint256 rateBps,
        uint256 totalRepayment
    ) {
        // Check reputation points
        uint256 userPoints = pointLedgerContract.getTotalPoints(_user);
        if (userPoints < minReputationPoints) {
            return (false, 0, 0);
        }

        // Note: Can't check AI score in view function (it emits events in the oracle)
        // Frontend should call oracle separately
        
        // Assume eligible for simulation purposes
        // In practice, user must have published a score
        uint256 assumedScore = 700;  // Average score for simulation
        rateBps = getInterestRate(assumedScore);
        totalRepayment = calculateTotalRepayment(_amount, rateBps, _duration);

        return (true, rateBps, totalRepayment);
    }

    // --- ADMINISTRATIVE FUNCTIONS ---

    /**
     * @notice Owner withdraws profits/repaid funds.
     * @dev [FIXED] Allows pool management and profit extraction.
     * @param _to Recipient address.
     * @param _amount Amount to withdraw.
     */
    function withdrawFunds(address _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "LoanManager: Zero address");
        uint256 balance = stableCoinContract.balanceOf(address(this));
        require(_amount <= balance, "LoanManager: Insufficient balance");

        require(
            stableCoinContract.transfer(_to, _amount),
            "LoanManager: Withdrawal failed"
        );

        emit ProfitsWithdrawn(_to, _amount, block.timestamp);
    }

    /**
     * @notice Updates eligibility criteria.
     */
    function updateEligibilityCriteria(
        uint256 _minPoints,
        uint256 _minAIScore
    ) external onlyOwner {
        require(_minAIScore <= 1000, "LoanManager: AI score must be <= 1000");
        
        minReputationPoints = _minPoints;
        minAIRiskScore = _minAIScore;

        emit EligibilityCriteriaUpdated(_minPoints, _minAIScore, block.timestamp);
    }

    /**
     * @notice Updates loan amount limits.
     */
    function updateLoanLimits(
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _threshold
    ) external onlyOwner {
        require(_minAmount > 0 && _minAmount < _maxAmount, "LoanManager: Invalid limits");
        require(_threshold > _minAmount && _threshold <= _maxAmount, "LoanManager: Invalid threshold");
        
        minLoanAmount = _minAmount;
        maxLoanAmount = _maxAmount;
        loanSizeThreshold = _threshold;

        emit LoanLimitsUpdated(_minAmount, _maxAmount, _threshold, block.timestamp);
    }

    /**
     * @notice Changes the loan admin address.
     */
    function setAdminAddress(address _newAdmin) external onlyOwner {
        require(_newAdmin != address(0), "LoanManager: Zero address");
        address oldAdmin = loanAdmin;
        loanAdmin = _newAdmin;
        emit AdminChanged(oldAdmin, _newAdmin, block.timestamp);
    }

    /**
     * @notice Emergency pause for all loan operations.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause loan operations.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Returns all contract addresses for verification.
     */
    function getContractAddresses() external view returns (
        address oracle,
        address sbt,
        address pointLedger,
        address stableCoin
    ) {
        return (
            address(oracleContract),
            address(sbtContract),
            address(pointLedgerContract),
            address(stableCoinContract)
        );
    }

    /**
     * @notice Returns current eligibility criteria.
     */
    function getEligibilityCriteria() external view returns (
        uint256 minPoints,
        uint256 minAIScore,
        uint256 minAmount,
        uint256 maxAmount
    ) {
        return (
            minReputationPoints,
            minAIRiskScore,
            minLoanAmount,
            maxLoanAmount
        );
    }
}