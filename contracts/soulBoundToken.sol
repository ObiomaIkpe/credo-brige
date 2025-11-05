// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IPointLedger
 * @notice Interface for the PointLedger contract to enable type-safe external calls.
 */
interface IPointLedger {
    function addPoints(address _holder, uint256 _pointsToAdd) external;
}

/**
 * @title SoulboundToken
 * @notice Non-transferable reputation badges (SBTs) that track user achievements.
 * 
 * @dev ROLE IN SYSTEM:
 * - Foundation layer: All reputation originates here
 * - Tracks both financial AND social achievements
 * - Automatically updates PointLedger when SBTs are minted
 * - Provides data source for client-side AI scoring
 * 
 * KEY FEATURES:
 * - 10 distinct TaskTypes for granular reputation tracking
 * - 4-tier point system (100, 300, 750, 1500 points)
 * - Multi-issuer support for decentralized reputation building
 * - Non-transferable (Soulbound) enforcement
 * - Emergency pause capability
 */
contract SoulboundToken is 
    ERC721Enumerable, 
    ERC721URIStorage, 
    Ownable, 
    Pausable,
    ReentrancyGuard 
{
    // CHANGED: Replaced Counters.Counter with simple uint256
    uint256 private _nextTokenId;

    // --- EVENTS ---
    event IssuerRoleGranted(address indexed account, address indexed by, uint256 timestamp);
    event IssuerRoleRevoked(address indexed account, address indexed by, uint256 timestamp);
    
    event SBTIssued(
        uint256 indexed tokenId, 
        address indexed holder, 
        TaskType taskType, 
        PointLevel pointLevel,
        uint256 points,
        uint256 issuedAt,
        address indexed issuer
    );
    
    event SBTBurned(uint256 indexed tokenId, address indexed holder, uint256 timestamp);
    event PointLedgerUpdated(address indexed oldAddress, address indexed newAddress, uint256 timestamp);

    // --- ENUMS: HIGH-RESOLUTION ACHIEVEMENT CATEGORIES ---

    /**
     * @notice Comprehensive TaskType enum covering financial, identity, and social domains.
     * Each type serves as a distinct feature for AI risk assessment.
     */
    enum TaskType {
        // IDENTITY DOMAIN (Trust Foundation)
        IDENTITY_VERIFIED_KYC,        // Government ID verification
        IDENTITY_MULTI_FACTOR,        // Biometrics + address verification
        
        // FINANCIAL DOMAIN (Credit History)
        FINANCIAL_LITERACY_COURSE,    // Completed financial education
        FINANCIAL_SAVINGS_GOAL,       // Achieved savings milestone
        LOAN_REPAYMENT_SMALL,         // Repaid small loan (<$500)
        LOAN_REPAYMENT_LARGE,         // Repaid large loan (≥$500)
        AID_DISBURSEMENT_RECEIVED,    // Received social aid/grant
        
        // SOCIAL DOMAIN (Community Participation)
        COMMUNITY_VOLUNTEERISM,       // Documented volunteer hours
        SOCIAL_EDUCATION_CERT,        // Non-financial education (job training, etc.)
        SOCIAL_MENTORSHIP             // Verified mentorship activity
    }

    /**
     * @notice Fixed point brackets for weighted achievements.
     * Tier 1 weighting system for rapid on-chain point calculation.
     */
    enum PointLevel {
        LEVEL_D_MINOR,      // 100 points  - Basic achievements
        LEVEL_C_MAJOR,      // 300 points  - Significant achievements
        LEVEL_B_HARMONY,    // 750 points  - Major accomplishments
        LEVEL_A_PRESTIGE    // 1500 points - Exceptional achievements
    }

    // --- DATA STRUCTURES ---

    /**
     * @notice Immutable metadata for each Soulbound Token.
     * This data is read by the client-side AI for risk scoring.
     */
    struct SBTData {
        string title;           // Human-readable description
        TaskType taskType;      // Achievement category (AI feature)
        PointLevel pointLevel;  // Reward tier
        address issuer;         // Who verified this achievement
        uint256 issuedAt;       // Timestamp (important for AI temporal analysis)
    }

    // --- STATE VARIABLES ---

    IPointLedger private _pointLedger;
    mapping(address => bool) private _issuers;
    mapping(uint256 => SBTData) private _tokenData;

    // --- MODIFIERS ---

    modifier onlyIssuer() {
        require(_issuers[msg.sender], "SBT: Caller is not an authorized issuer");
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @notice Initializes the SBT contract with PointLedger linkage.
     * @param _pointLedgerAddress Address of the PointLedger contract for automatic updates.
     */
    constructor(address _pointLedgerAddress) 
        ERC721("CeloReputationSBT", "CRSBT") 
        Ownable(msg.sender) 
    {
        require(_pointLedgerAddress != address(0), "SBT: Zero address for PointLedger");
        _pointLedger = IPointLedger(_pointLedgerAddress);
        
        // Grant deployer Issuer role
        _issuers[msg.sender] = true;
        emit IssuerRoleGranted(msg.sender, msg.sender, block.timestamp);
        
        // CHANGED: Initialize counter to 1 (first token will be ID 1)
        _nextTokenId = 1;
    }

    // --- CORE FUNCTIONS ---

    /**
     * @notice Translates PointLevel enum to numerical value.
     * @dev Used for both on-chain point aggregation and AI feature weighting.
     * @param _level The point level enum.
     * @return The fixed point value (100, 300, 750, or 1500).
     */
    function getPointValueFromLevel(PointLevel _level) public pure returns (uint256) {
        if (_level == PointLevel.LEVEL_D_MINOR) return 100;
        if (_level == PointLevel.LEVEL_C_MAJOR) return 300;
        if (_level == PointLevel.LEVEL_B_HARMONY) return 750;
        if (_level == PointLevel.LEVEL_A_PRESTIGE) return 1500;
        revert("SBT: Invalid PointLevel");
    }

    /**
     * @notice Mints a new Soulbound Token and updates the PointLedger.
     * @dev CRITICAL FUNCTION: This is where ALL reputation enters the system.
     * 
     * Process Flow:
     * 1. Authorized issuer calls this function
     * 2. SBT is minted with metadata
     * 3. Points automatically pushed to PointLedger
     * 4. Event emitted for off-chain indexing
     * 
     * @param _holder The user receiving the reputation badge.
     * @param _taskType The achievement category (AI feature).
     * @param _pointLevel The reward tier.
     * @param _title Human-readable achievement description.
     * @param _tokenURI IPFS or HTTP link to detailed metadata.
     */
    function issueSBT(
        address _holder,
        TaskType _taskType,
        PointLevel _pointLevel,
        string memory _title,
        string memory _tokenURI
    ) external onlyIssuer whenNotPaused nonReentrant {
        require(_holder != address(0), "SBT: Mint to the zero address");
        
        // CHANGED: Generate new token ID using post-increment
        uint256 tokenId = _nextTokenId++;
        
        // Mint the token
        _safeMint(_holder, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        // Store SBT Metadata
        _tokenData[tokenId] = SBTData({
            title: _title,
            taskType: _taskType,
            pointLevel: _pointLevel,
            issuer: msg.sender,
            issuedAt: block.timestamp
        });

        // AUTOMATIC POINT AGGREGATION (Secured one-way push)
        uint256 points = getPointValueFromLevel(_pointLevel);
        _pointLedger.addPoints(_holder, points);

        emit SBTIssued(tokenId, _holder, _taskType, _pointLevel, points, block.timestamp, msg.sender);
    }

    /**
     * @notice Burns an SBT. Callable by token owner or contract owner.
     * @dev Points remain in PointLedger (reputation is permanent, tokens are not).
     * @param tokenId The ID of the token to burn.
     */
    function burnSBT(uint256 tokenId) external whenNotPaused {
        require(
            ownerOf(tokenId) == msg.sender || owner() == msg.sender,
            "SBT: Not authorized to burn"
        );
        
        address holder = ownerOf(tokenId);
        _burn(tokenId);
        
        emit SBTBurned(tokenId, holder, block.timestamp);
    }

    // --- DATA ACCESS FUNCTIONS (FOR CLIENT-SIDE AI) ---

    /**
     * @notice Retrieves complete metadata for a specific SBT.
     * @dev Used by client-side AI to analyze individual achievements.
     * @param _tokenId The token ID.
     * @return The full SBTData struct.
     */
    function getSBTData(uint256 _tokenId) external view returns (SBTData memory) {
        require(_ownerOf(_tokenId) != address(0), "SBT: Token does not exist");
        return _tokenData[_tokenId];
    }

    /**
     * @notice Retrieves all SBT IDs owned by a user.
     * @dev PRIMARY DATA SOURCE for client-side AI scoring.
     * The user's browser will:
     * 1. Call this to get all token IDs
     * 2. Call getSBTData() for each ID
     * 3. Run local AI model on the dataset
     * 4. Publish score to AIRiskOracle
     * 
     * @param _holder The user's address.
     * @return Array of all token IDs owned by the user.
     */
    function getSBTsByHolder(address _holder) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(_holder);
        uint256[] memory tokens = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(_holder, i);
        }
        
        return tokens;
    }

    /**
     * @notice Returns the total number of SBTs minted across the entire system.
     * @dev Useful for analytics and system health monitoring.
     * @return Total supply count.
     */
    function getTotalSBTsMinted() external view returns (uint256) {
        // CHANGED: Return _nextTokenId - 1 to get the count of minted tokens
        return _nextTokenId - 1;
    }

    // --- ACCESS CONTROL FUNCTIONS ---

    /**
     * @notice Grants minting privileges to a new issuer.
     * @dev Enables decentralized reputation building (NGOs, schools, employers can all be issuers).
     * @param _newIssuer Address to authorize.
     */
    function addIssuer(address _newIssuer) external onlyOwner {
        require(_newIssuer != address(0), "SBT: Zero address");
        require(!_issuers[_newIssuer], "SBT: Address already an Issuer");
        
        _issuers[_newIssuer] = true;
        emit IssuerRoleGranted(_newIssuer, msg.sender, block.timestamp);
    }

    /**
     * @notice Revokes minting privileges from an issuer.
     * @param _issuerToRemove Address to de-authorize.
     */
    function removeIssuer(address _issuerToRemove) external onlyOwner {
        require(_issuers[_issuerToRemove], "SBT: Address is not an Issuer");
        
        _issuers[_issuerToRemove] = false;
        emit IssuerRoleRevoked(_issuerToRemove, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Checks if an address is an authorized Issuer.
     * @param account Address to check.
     * @return Boolean indicating issuer status.
     */
    function isIssuer(address account) external view returns (bool) {
        return _issuers[account];
    }

    // --- CONFIGURATION FUNCTIONS ---

    /**
     * @notice Updates the PointLedger contract address.
     * @dev Allows for contract upgrades without redeploying SBT contract.
     * @param _newAddress New PointLedger address.
     */
    function setPointLedgerAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "SBT: Zero address");
        address oldAddress = address(_pointLedger);
        _pointLedger = IPointLedger(_newAddress);
        emit PointLedgerUpdated(oldAddress, _newAddress, block.timestamp);
    }

    /**
     * @notice Returns current PointLedger address.
     * @return The PointLedger contract address.
     */
    function getPointLedgerAddress() external view returns (address) {
        return address(_pointLedger);
    }

    // --- EMERGENCY FUNCTIONS ---

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --- REQUIRED OVERRIDES FOR MULTIPLE INHERITANCE ---

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        address from = _ownerOf(tokenId);
        
        // SOULBOUND ENFORCEMENT: Prevent transfers (allow only mint and burn)
        if (from != address(0) && to != address(0)) {
            revert("SBT: Non-transferable token");
        }
        
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Enumerable, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "";
    }
}