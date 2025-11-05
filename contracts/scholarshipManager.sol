// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IPointLedger
 * @notice Interface for checking user eligibility via PointLedger.
 */
interface IPointLedger {
    function checkServiceEligibility(address _holder) 
        external 
        view 
        returns (bool isEligible, uint256 currentPoints, uint256 currentAIScore);
    
    function getTotalPoints(address _holder) external view returns (uint256);
}

/**
 * @title ISoulboundToken
 * @notice Interface for rewarding application/completion with SBTs.
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
 * @title ScholarshipManager
 * @notice Manages scholarship/discount applications based on social participation.
 */
contract ScholarshipManager is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // --- ENUMS ---

    enum ProgramType {
        EDUCATION_SCHOLARSHIP,
        HEALTHCARE_DISCOUNT,
        HOUSING_ASSISTANCE,
        FOOD_SECURITY,
        PROFESSIONAL_TRAINING,
        CHILDCARE_SUPPORT,
        GENERAL_GRANT
    }

    enum ApplicationStatus {
        PENDING,
        APPROVED,
        REJECTED,
        DISBURSED,
        COMPLETED,
        CANCELLED
    }

    enum BenefitType {
        MONETARY,
        DISCOUNT_CODE,
        VOUCHER,
        FREE_ACCESS
    }

    // --- DATA STRUCTURES ---

    struct Program {
        string name;
        string description;
        ProgramType programType;
        BenefitType benefitType;
        
        address provider;
        bool isActive;
        
        uint256 minReputationPoints;
        uint256 minSocialScore;
        
        uint256 benefitAmount;
        uint256 discountPercentage;
        uint256 maxRecipients;
        uint256 currentRecipients;
        
        uint256 applicationDeadline;
        uint256 createdAt;
    }

    struct Application {
        uint256 programId;
        address applicant;
        ApplicationStatus status;
        
        uint256 appliedAt;
        uint256 reviewedAt;
        uint256 disbursedAt;
        
        string applicationNotes;
        string reviewNotes;
        string discountCode;
        
        bool sbtRewarded;
    }

    // --- STATE VARIABLES ---

    IPointLedger private pointLedger;
    ISoulboundToken private sbtContract;
    IERC20 private stableCoin;

    uint256 public nextProgramId;
    mapping(uint256 => Program) public programs;
    
    uint256 public nextApplicationId;
    mapping(uint256 => Application) public applications;
    mapping(address => uint256[]) public userApplications;
    mapping(uint256 => uint256[]) public programApplications;
    
    mapping(address => bool) public authorizedProviders;
    
    uint256 public totalProgramsCreated;
    uint256 public totalApplicationsSubmitted;
    uint256 public totalBenefitsDisbursed;
    uint256 public totalAmountDisbursed;

    // --- EVENTS ---

    event ProgramCreated(
        uint256 indexed programId,
        string name,
        ProgramType programType,
        address indexed provider,
        uint256 timestamp
    );

    event ProgramUpdated(
        uint256 indexed programId,
        bool isActive,
        uint256 timestamp
    );

    event ApplicationSubmitted(
        uint256 indexed applicationId,
        uint256 indexed programId,
        address indexed applicant,
        uint256 reputationPoints,
        uint256 socialScore,
        uint256 timestamp
    );

    event ApplicationReviewed(
        uint256 indexed applicationId,
        ApplicationStatus status,
        address indexed reviewer,
        uint256 timestamp
    );

    event BenefitDisbursed(
        uint256 indexed applicationId,
        address indexed recipient,
        BenefitType benefitType,
        uint256 amount,
        string discountCode,
        uint256 timestamp
    );

    event ApplicationCompleted(
        uint256 indexed applicationId,
        address indexed recipient,
        bool sbtRewarded,
        uint256 timestamp
    );

    event ProviderAuthorized(address indexed provider, uint256 timestamp);
    event ProviderRevoked(address indexed provider, uint256 timestamp);

    // --- MODIFIERS ---

    modifier onlyProvider() {
        require(authorizedProviders[msg.sender] || msg.sender == owner(), 
            "ScholarshipManager: Not authorized provider");
        _;
    }

    // --- CONSTRUCTOR ---

    constructor(
        address _pointLedgerAddress,
        address _sbtAddress,
        address _stableCoinAddress
    ) Ownable(msg.sender) {
        require(_pointLedgerAddress != address(0), "Invalid PointLedger address");
        require(_sbtAddress != address(0), "Invalid SBT address");
        require(_stableCoinAddress != address(0), "Invalid StableCoin address");
        
        pointLedger = IPointLedger(_pointLedgerAddress);
        sbtContract = ISoulboundToken(_sbtAddress);
        stableCoin = IERC20(_stableCoinAddress);
        
        nextProgramId = 1;
        nextApplicationId = 1;
    }

    // --- PROGRAM MANAGEMENT ---

    function createProgram(
        string memory _name,
        string memory _description,
        ProgramType _programType,
        BenefitType _benefitType,
        uint256 _minReputationPoints,
        uint256 _minSocialScore,
        uint256 _benefitAmount,
        uint256 _discountPercentage,
        uint256 _maxRecipients,
        uint256 _applicationDeadline
    ) external onlyProvider whenNotPaused returns (uint256 programId) {
        require(_applicationDeadline > block.timestamp, "Deadline must be in future");
        require(_maxRecipients > 0, "Must allow at least 1 recipient");
        
        programId = nextProgramId++;
        
        programs[programId] = Program({
            name: _name,
            description: _description,
            programType: _programType,
            benefitType: _benefitType,
            provider: msg.sender,
            isActive: true,
            minReputationPoints: _minReputationPoints,
            minSocialScore: _minSocialScore,
            benefitAmount: _benefitAmount,
            discountPercentage: _discountPercentage,
            maxRecipients: _maxRecipients,
            currentRecipients: 0,
            applicationDeadline: _applicationDeadline,
            createdAt: block.timestamp
        });
        
        totalProgramsCreated++;
        
        emit ProgramCreated(programId, _name, _programType, msg.sender, block.timestamp);
        
        return programId;
    }

    function updateProgramStatus(uint256 _programId, bool _isActive) external {
        Program storage program = programs[_programId];
        require(program.provider == msg.sender || msg.sender == owner(), 
            "Not program owner");
        
        program.isActive = _isActive;
        
        emit ProgramUpdated(_programId, _isActive, block.timestamp);
    }

    // --- USER APPLICATION FUNCTIONS ---

    function applyForProgram(
        uint256 _programId,
        string memory _applicationNotes
    ) external whenNotPaused nonReentrant returns (uint256 applicationId) {
        Program storage program = programs[_programId];
        
        require(program.createdAt > 0, "Program does not exist");
        require(program.isActive, "Program is not active");
        require(block.timestamp <= program.applicationDeadline, "Application deadline passed");
        require(program.currentRecipients < program.maxRecipients, "Program is full");
        
        (bool isEligible, uint256 currentPoints, uint256 currentSocialScore) = 
            pointLedger.checkServiceEligibility(msg.sender);
        
        require(isEligible, "Does not meet program eligibility criteria");
        require(currentPoints >= program.minReputationPoints, "Insufficient reputation points");
        require(currentSocialScore >= program.minSocialScore, "Insufficient social score");
        
        applicationId = nextApplicationId++;
        
        applications[applicationId] = Application({
            programId: _programId,
            applicant: msg.sender,
            status: ApplicationStatus.PENDING,
            appliedAt: block.timestamp,
            reviewedAt: 0,
            disbursedAt: 0,
            applicationNotes: _applicationNotes,
            reviewNotes: "",
            discountCode: "",
            sbtRewarded: false
        });
        
        userApplications[msg.sender].push(applicationId);
        programApplications[_programId].push(applicationId);
        
        totalApplicationsSubmitted++;
        
        emit ApplicationSubmitted(
            applicationId,
            _programId,
            msg.sender,
            currentPoints,
            currentSocialScore,
            block.timestamp
        );
        
        return applicationId;
    }

    // --- PROVIDER REVIEW FUNCTIONS ---

    function reviewApplication(
        uint256 _applicationId,
        ApplicationStatus _decision,
        string memory _reviewNotes
    ) external onlyProvider nonReentrant {
        require(_decision == ApplicationStatus.APPROVED || _decision == ApplicationStatus.REJECTED,
            "Invalid decision");
        
        Application storage app = applications[_applicationId];
        Program storage program = programs[app.programId];
        
        require(program.provider == msg.sender || msg.sender == owner(), "Not program owner");
        require(app.status == ApplicationStatus.PENDING, "Application already reviewed");
        
        app.status = _decision;
        app.reviewedAt = block.timestamp;
        app.reviewNotes = _reviewNotes;
        
        emit ApplicationReviewed(_applicationId, _decision, msg.sender, block.timestamp);
    }

    function disburseBenefit(
        uint256 _applicationId,
        string memory _discountCode
    ) external onlyProvider nonReentrant {
        Application storage app = applications[_applicationId];
        Program storage program = programs[app.programId];
        
        require(program.provider == msg.sender || msg.sender == owner(), "Not program owner");
        require(app.status == ApplicationStatus.APPROVED, "Application not approved");
        require(app.disbursedAt == 0, "Benefit already disbursed");
        
        app.status = ApplicationStatus.DISBURSED;
        app.disbursedAt = block.timestamp;
        
        program.currentRecipients++;
        
        if (program.benefitType == BenefitType.MONETARY) {
            require(program.benefitAmount > 0, "Invalid benefit amount");
            require(
                stableCoin.balanceOf(address(this)) >= program.benefitAmount,
                "Insufficient contract balance"
            );
            
            stableCoin.safeTransfer(app.applicant, program.benefitAmount);
            totalAmountDisbursed += program.benefitAmount;
            
        } else if (program.benefitType == BenefitType.DISCOUNT_CODE) {
            require(bytes(_discountCode).length > 0, "Discount code required");
            app.discountCode = _discountCode;
            
        } else if (program.benefitType == BenefitType.VOUCHER) {
            require(bytes(_discountCode).length > 0, "Voucher code required");
            app.discountCode = _discountCode;
        }
        
        totalBenefitsDisbursed++;
        
        _rewardAidReceipt(app.applicant, program.benefitAmount);
        
        emit BenefitDisbursed(
            _applicationId,
            app.applicant,
            program.benefitType,
            program.benefitAmount,
            _discountCode,
            block.timestamp
        );
    }

    function markAsCompleted(uint256 _applicationId) external onlyProvider {
        Application storage app = applications[_applicationId];
        Program storage program = programs[app.programId];
        
        require(program.provider == msg.sender || msg.sender == owner(), "Not program owner");
        require(app.status == ApplicationStatus.DISBURSED, "Benefit not yet disbursed");
        require(!app.sbtRewarded, "Already rewarded");
        
        app.status = ApplicationStatus.COMPLETED;
        
        bool sbtSuccess = _rewardCompletion(app.applicant, program.programType);
        app.sbtRewarded = sbtSuccess;
        
        emit ApplicationCompleted(_applicationId, app.applicant, sbtSuccess, block.timestamp);
    }

    // --- INTERNAL REWARD FUNCTIONS ---

    function _rewardAidReceipt(address _user, uint256) private returns (bool) {
        try sbtContract.issueSBT(
            _user,
            ISoulboundToken.TaskType.AID_DISBURSEMENT_RECEIVED,
            ISoulboundToken.PointLevel.LEVEL_D_MINOR,
            "Social Benefit Received",
            "ipfs://aid-receipt-metadata"
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function _rewardCompletion(address _user, ProgramType _programType) private returns (bool) {
        ISoulboundToken.TaskType taskType;
        ISoulboundToken.PointLevel pointLevel;
        string memory title;
        
        if (_programType == ProgramType.EDUCATION_SCHOLARSHIP) {
            taskType = ISoulboundToken.TaskType.SOCIAL_EDUCATION_CERT;
            pointLevel = ISoulboundToken.PointLevel.LEVEL_B_HARMONY;
            title = "Scholarship Program Completed";
        } else if (_programType == ProgramType.PROFESSIONAL_TRAINING) {
            taskType = ISoulboundToken.TaskType.SOCIAL_EDUCATION_CERT;
            pointLevel = ISoulboundToken.PointLevel.LEVEL_C_MAJOR;
            title = "Professional Training Completed";
        } else {
            taskType = ISoulboundToken.TaskType.COMMUNITY_VOLUNTEERISM;
            pointLevel = ISoulboundToken.PointLevel.LEVEL_C_MAJOR;
            title = "Social Program Completed";
        }
        
        try sbtContract.issueSBT(
            _user,
            taskType,
            pointLevel,
            title,
            "ipfs://program-completion-metadata"
        ) {
            return true;
        } catch {
            return false;
        }
    }

    // --- VIEW FUNCTIONS ---

    function getActivePrograms() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        for (uint256 i = 1; i < nextProgramId; i++) {
            if (programs[i].isActive && block.timestamp <= programs[i].applicationDeadline) {
                activeCount++;
            }
        }
        
        uint256[] memory activeProgramIds = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < nextProgramId; i++) {
            if (programs[i].isActive && block.timestamp <= programs[i].applicationDeadline) {
                activeProgramIds[index] = i;
                index++;
            }
        }
        
        return activeProgramIds;
    }

    function getUserApplications(address _user) external view returns (uint256[] memory) {
        return userApplications[_user];
    }

    function getProgramApplications(uint256 _programId) external view returns (uint256[] memory) {
        return programApplications[_programId];
    }

    function checkProgramEligibility(address _user, uint256 _programId) 
        external 
        view 
        returns (bool isEligible, uint256 points, uint256 socialScore, string memory reason) 
    {
        Program storage program = programs[_programId];
        
        if (program.createdAt == 0) {
            return (false, 0, 0, "Program does not exist");
        }
        
        if (!program.isActive) {
            return (false, 0, 0, "Program is not active");
        }
        
        if (block.timestamp > program.applicationDeadline) {
            return (false, 0, 0, "Application deadline passed");
        }
        
        if (program.currentRecipients >= program.maxRecipients) {
            return (false, 0, 0, "Program is full");
        }
        
        (bool eligible, uint256 currentPoints, uint256 currentSocialScore) = 
            pointLedger.checkServiceEligibility(_user);
        
        if (!eligible) {
            return (false, currentPoints, currentSocialScore, "Does not meet minimum criteria");
        }
        
        if (currentPoints < program.minReputationPoints) {
            return (false, currentPoints, currentSocialScore, "Insufficient reputation points");
        }
        
        if (currentSocialScore < program.minSocialScore) {
            return (false, currentPoints, currentSocialScore, "Insufficient social score");
        }
        
        return (true, currentPoints, currentSocialScore, "Eligible");
    }

    function getSystemStats() external view returns (
        uint256 programsCreated,
        uint256 applicationsSubmitted,
        uint256 benefitsDisbursed,
        uint256 totalDisbursed,
        uint256 contractBalance
    ) {
        return (
            totalProgramsCreated,
            totalApplicationsSubmitted,
            totalBenefitsDisbursed,
            totalAmountDisbursed,
            stableCoin.balanceOf(address(this))
        );
    }

    // --- ADMINISTRATIVE FUNCTIONS ---

    function authorizeProvider(address _provider) external onlyOwner {
        require(_provider != address(0), "Invalid address");
        require(!authorizedProviders[_provider], "Already authorized");
        
        authorizedProviders[_provider] = true;
        emit ProviderAuthorized(_provider, block.timestamp);
    }

    function revokeProvider(address _provider) external onlyOwner {
        require(authorizedProviders[_provider], "Not authorized");
        
        authorizedProviders[_provider] = false;
        emit ProviderRevoked(_provider, block.timestamp);
    }

    function depositFunds(uint256 _amount) external onlyOwner {
        stableCoin.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdrawFunds(address _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "Invalid address");
        stableCoin.safeTransfer(_to, _amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getContractAddresses() external view returns (
        address pointLedgerAddr,
        address sbtAddr,
        address stableCoinAddr
    ) {
        return (
            address(pointLedger),
            address(sbtContract),
            address(stableCoin)
        );
    }
}