import React, { useState, useEffect, useCallback, useMemo } from 'react';

// --- DApp Constants ---
const VIEWS = {
    DASHBOARD: 'dashboard', // Holder: Risk Score Dashboard
    SOCIAL_AID: 'social_aid', // Holder: Aid Acknowledgment
    ISSUER_MINT: 'issuer_mint', // Issuer: Minting Panel
    ISSUER_AUDIT: 'issuer_audit' // Issuer: Auditing Panel
};

const TASK_TYPES = {
    IDENTITY_VERIFIED_KYC: 0,
    FINANCIAL_LITERACY_COURSE: 2,
    LOAN_REPAYMENT_SMALL: 4,
    LOAN_REPAYMENT_LARGE: 5,
    AID_DISBURSEMENT_RECEIVED: 6, // NGO Aid Task Type (Holder-triggered)
    COMMUNITY_VOLUNTEERISM: 7,
    SOCIAL_EDUCATION_CERT: 8,
};

const POINT_LEVELS = {
    LEVEL_D_MINOR: 0,
    LEVEL_C_MAJOR: 1,
    LEVEL_B_HARMONY: 2,
    LEVEL_A_PRESTIGE: 3,
};

const TASK_LABELS = {
    [TASK_TYPES.IDENTITY_VERIFIED_KYC]: 'KYC Verified (Identity)',
    [TASK_TYPES.FINANCIAL_LITERACY_COURSE]: 'Financial Literacy Course',
    [TASK_TYPES.LOAN_REPAYMENT_SMALL]: 'Small Loan Repayment (On-Time)',
    [TASK_TYPES.LOAN_REPAYMENT_LARGE]: 'Large Loan Repayment (On-Time)',
    [TASK_TYPES.AID_DISBURSEMENT_RECEIVED]: 'NGO Aid Receipt Acknowledged',
    [TASK_TYPES.COMMUNITY_VOLUNTEERISM]: 'Community Volunteerism',
    [TASK_TYPES.SOCIAL_EDUCATION_CERT]: 'Education Certificate Earned',
};

// Utility function to generate a simple, random risk score (0-1000)
const calculateMockRiskScore = (sbtCount) => {
    let score = 100;
    score += Math.min(sbtCount * 100, 900);
    return Math.min(score, 1000);
};

// --- Initial Mock Data (Simulates SBTs fetched from Celo on initial load) ---
const MOCK_INITIAL_SBTS = [
    { id: 1, taskType: TASK_TYPES.IDENTITY_VERIFIED_KYC, pointLevel: POINT_LEVELS.LEVEL_C_MAJOR, title: 'KYC Verified', issuedAt: Date.now() - 86400000, recipient: "0xbe1900d7202b28c946f0418c351f03a62858b22a" },
    { id: 2, taskType: TASK_TYPES.FINANCIAL_LITERACY_COURSE, pointLevel: POINT_LEVELS.LEVEL_B_HARMONY, title: 'Financial Course Cert', issuedAt: Date.now() - 172800000, recipient: "0xbe1900d7202b28c946f0418c351f03a62858b22a" },
    { id: 3, taskType: TASK_TYPES.AID_DISBURSEMENT_RECEIVED, pointLevel: POINT_LEVELS.LEVEL_C_MAJOR, title: 'NGO Aid 1 Acknowledged', issuedAt: Date.now() - 50000, recipient: "0x4ddc43b3539744c80327f2f1839e93b1693e5dbd" }, // Issued to Issuer's address (Mock for testing)
];

// MOCK ADDRESSES for conditional rendering
// This address will simulate the NGO Minter wallet (the authorized Issuer)
const MOCK_ISSUER_ADDRESS = "0x4ddc43b3539744c80327f2f1839e93b1693e5dbd";
// This address will simulate a standard IDP wallet (the Holder)
const MOCK_HOLDER_ADDRESS = "0xbe1900d7202b28c946f0418c351f03a62858b22a";

let sbtCounter = MOCK_INITIAL_SBTS.length + 1; // Used for unique IDs in the mock

// --- Custom Hook: useCeloSBT (The Decentralized Bridge) ---

function useCeloSBT() {
    const [walletAddress, setWalletAddress] = useState(null);
    const [sbtTokens, setSbtTokens] = useState(MOCK_INITIAL_SBTS); // Pre-load mock data
    const [isConnected, setIsConnected] = useState(false);
    const [isLoading, setIsLoading] = useState(false);
    const [isIssuer, setIsIssuer] = useState(false);

    // 1. Wallet Connection Simulation
    const connectWallet = useCallback((role = 'holder') => {
        setIsLoading(true);
        
        setTimeout(() => {
            let mockAddress;
            if (role === 'issuer') {
                mockAddress = MOCK_ISSUER_ADDRESS;
            } else {
                mockAddress = MOCK_HOLDER_ADDRESS; // Default holder
            }
            
            // Simulating contract check: hasRole(MINTER_ROLE, mockAddress)
            const isMinter = mockAddress.toLowerCase() === MOCK_ISSUER_ADDRESS.toLowerCase();
            
            setWalletAddress(mockAddress);
            setIsIssuer(isMinter);
            setIsConnected(true);
            setIsLoading(false);
        }, 1500);
    }, []);

    // 2. Data Fetching Simulation (Simulates calling SoulboundToken.getSBTsByHolder/getAllSBTS)
    const fetchSBTs = useCallback(() => {
        if (!walletAddress) return;
        setIsLoading(true);

        // In a real app, this would perform the actual contract call.
        setTimeout(() => {
            // Mock data is already loaded in state, so we just toggle loading state.
            setIsLoading(false);
        }, 500);
    }, [walletAddress]);
    
    useEffect(() => {
        if (walletAddress) {
            fetchSBTs();
        }
    }, [walletAddress, fetchSBTs]);


    // 3. Mock SBT Minting Function (Simulates the Smart Contract Transaction)
    // Returns { success: boolean, message: string }
    const mockIssueSBT = useCallback(async (recipientAddress, taskType, pointLevel, title) => {
        if (!walletAddress) {
            return { success: false, message: "Wallet not connected. Please connect your wallet." }; 
        }

        // Simulating the on-chain check: require(hasRole(MINTER_ROLE, msg.sender))
        // AID_DISBURSEMENT_RECEIVED is the only task a holder can trigger via acknowledgment
        if (taskType !== TASK_TYPES.AID_DISBURSEMENT_RECEIVED && !isIssuer) {
             return { success: false, message: "Only authorized Issuers can mint this type of SBT." };
        }

        // Basic address validation for the Issuer's manual mint
        if (taskType !== TASK_TYPES.AID_DISBURSEMENT_RECEIVED && !recipientAddress.match(/^0x[a-fA-F0-9]{40}$/)) {
            return { success: false, message: "Please enter a valid recipient Celo address." };
        }

        setIsLoading(true);

        try {
            // Simulate Celo transaction latency
            await new Promise(resolve => setTimeout(resolve, 3000));
            
            const newSBT = {
                id: sbtCounter++,
                taskType: taskType,
                pointLevel: pointLevel,
                title: title,
                issuedAt: Date.now(),
                recipient: recipientAddress || walletAddress, 
                issuer: walletAddress,
            };

            setSbtTokens(prevTokens => [...prevTokens, newSBT]);

            console.log(`Successfully simulated minting SBT of type ${taskType} to ${recipientAddress || walletAddress}`);
            setIsLoading(false);
            return { success: true, message: `SBT successfully issued to ${recipientAddress || walletAddress}.` };
        } catch (e) {
            console.error("Error mocking SBT issuance: ", e);
            setIsLoading(false);
            return { success: false, message: "Transaction failed due to a mock network error." };
        }
    }, [walletAddress, isIssuer]);

    return {
        isConnected,
        walletAddress,
        sbtTokens,
        isLoading,
        isIssuer, // Critical new state for conditional rendering
        connectWallet,
        mockIssueSBT,
    };
}

// --- Component: Toast Notification ---
const Toast = ({ message, type }) => {
    if (!message) return null;

    const baseStyle = "fixed bottom-5 right-5 p-4 rounded-lg shadow-xl text-white font-semibold z-50 transition-opacity duration-300";
    let colorStyle = '';

    switch (type) {
        case 'success':
            colorStyle = 'bg-green-600';
            break;
        case 'error':
            colorStyle = 'bg-red-600';
            break;
        default:
            colorStyle = 'bg-gray-600';
    }

    return (
        <div className={`${baseStyle} ${colorStyle}`}>
            {message}
        </div>
    );
};


// --- Component: Holder (IDP) Risk Score Dashboard ---
const HolderRiskScoreDashboard = ({ sbtTokens, walletAddress }) => {
    const [score, setScore] = useState(0);

    // Filter SBTs to only show tokens issued to the connected user (the holder)
    const holderTokens = useMemo(() => 
        sbtTokens.filter(t => t.recipient && t.recipient.toLowerCase() === walletAddress.toLowerCase())
    , [sbtTokens, walletAddress]);

    useEffect(() => {
        setScore(calculateMockRiskScore(holderTokens.length));
    }, [holderTokens.length]);

    const totalSBTs = holderTokens.length;

    return (
        <div className="p-6 bg-white shadow-xl rounded-xl w-full max-w-4xl mx-auto">
            <h2 className="text-3xl font-extrabold text-gray-800 mb-6 border-b pb-2">
                <span className="text-indigo-600">IDP</span> Risk Scoring Dashboard
            </h2>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                <div className="bg-indigo-500 text-white p-6 rounded-xl shadow-lg md:col-span-2 flex flex-col justify-center">
                    <p className="text-sm uppercase font-semibold opacity-80">Your Celo Identity Risk Score</p>
                    <p className="text-6xl font-black mt-2">{score}</p>
                    <p className="mt-3 text-sm">
                        Calculated based on {totalSBTs} reputation tokens.
                    </p>
                </div>
                <div className="bg-gray-50 p-6 rounded-xl shadow-inner flex flex-col justify-center">
                    <p className="text-sm uppercase font-semibold text-gray-500">Total SBTs Held</p>
                    <p className="text-4xl font-black text-gray-800 mt-1">{totalSBTs}</p>
                    <p className="mt-2 text-xs text-gray-600">
                        The more tokens, the higher your on-chain reputation.
                    </p>
                </div>
            </div>

            <h3 className="text-xl font-bold text-gray-700 mb-4">Your Soulbound Tokens</h3>
            <div className="space-y-3 max-h-80 overflow-y-auto pr-2">
                {holderTokens.length === 0 ? (
                    <p className="text-gray-500 italic">No SBTs found yet. Your score is based on minimal reputation data.</p>
                ) : (
                    holderTokens.sort((a, b) => b.issuedAt - a.issuedAt).map((token) => (
                        <div key={token.id} className={`p-4 rounded-lg flex justify-between items-center ${token.taskType === TASK_TYPES.AID_DISBURSEMENT_RECEIVED ? 'bg-green-100 border-l-4 border-green-500' : 'bg-gray-100 border-l-4 border-indigo-400'}`}>
                            <div>
                                <p className="font-semibold text-gray-800">{token.title}</p>
                                <p className="text-sm text-gray-600">{TASK_LABELS[token.taskType] || 'Unknown Task'}</p>
                            </div>
                            <span className="text-xs text-gray-500">
                                {new Date(token.issuedAt).toLocaleDateString()}
                            </span>
                        </div>
                    ))
                )}
            </div>
        </div>
    );
};

// --- Component: Holder (IDP) Social Aid Acknowledgment ---
const HolderSocialAidAcknowledgement = ({ walletAddress, mockIssueSBT, sbtTokens, isLoading, showToast }) => {
    const aidSBTType = TASK_TYPES.AID_DISBURSEMENT_RECEIVED;
    const hasAcknowledged = sbtTokens.some(token => token.taskType === aidSBTType && token.recipient && token.recipient.toLowerCase() === walletAddress.toLowerCase());

    const handleAcknowledge = async () => {
        // The recipient is the connected wallet address
        const { success, message } = await mockIssueSBT(
            walletAddress,
            aidSBTType,
            POINT_LEVELS.LEVEL_C_MAJOR,
            `NGO Aid Received - ${new Date().toLocaleDateString()}`
        );

        showToast(message, success ? 'success' : 'error');
    };
    
    let buttonText = "Acknowledge Receipt & Mint SBT";
    let buttonDisabled = isLoading || hasAcknowledged;
    
    if (isLoading) {
        buttonText = "Minting SBT... (Waiting for Celo TX)";
    } else if (hasAcknowledged) {
        buttonText = "Aid Already Acknowledged";
    }

    return (
        <div className="p-8 bg-white shadow-2xl rounded-xl w-full max-w-2xl mx-auto border-t-8 border-green-500">
            <h2 className="text-3xl font-extrabold text-green-700 mb-4 flex items-center">
                <svg className="w-8 h-8 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z"></path></svg>
                Social Aid Acknowledgment
            </h2>
            <p className="text-gray-600 mb-6 border-b pb-4">
                Confirming receipt mints a non-transferable **Proof of Service** receipt on the Celo blockchain.
            </p>

            {walletAddress && (
                <div className="bg-green-50 p-4 rounded-lg mb-6">
                    <p className="text-sm font-semibold text-green-700">Your Celo Wallet Address:</p>
                    <p className="break-words text-xs text-green-900 mt-1">{walletAddress}</p>
                </div>
            )}
            
            {hasAcknowledged ? (
                <div className="text-center p-8 bg-green-100 rounded-lg">
                    <svg className="w-16 h-16 mx-auto text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                    <p className="text-xl font-bold text-green-700 mt-3">Aid Acknowledged!</p>
                </div>
            ) : (
                <>
                    <p className="text-lg font-medium text-gray-800 mb-4">
                        Please confirm receipt of the **100 cUSD** from the NGO.
                    </p>
                    <button
                        onClick={handleAcknowledge}
                        disabled={buttonDisabled}
                        className={`w-full py-4 font-bold text-lg rounded-xl shadow-lg transition duration-200 flex items-center justify-center ${
                            buttonDisabled
                                ? 'bg-gray-400 text-gray-200 cursor-not-allowed'
                                : 'bg-green-600 text-white hover:bg-green-700'
                        }`}
                    >
                        {isLoading && (
                            <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                        )}
                        {buttonText}
                    </button>
                </>
            )}

            <p className="text-xs text-gray-400 mt-6 text-center">
                Minting is a low-fee Celo transaction and requires your digital consent.
            </p>
        </div>
    );
};


// --- Component: Issuer/Verifier Dashboard (Private Access) ---
const IssuerDashboard = ({ walletAddress, sbtTokens, mockIssueSBT, isLoading, showToast }) => {
    const [currentView, setCurrentView] = useState(VIEWS.ISSUER_AUDIT);
    const [recipient, setRecipient] = useState('');
    const [selectedTask, setSelectedTask] = useState(TASK_TYPES.FINANCIAL_LITERACY_COURSE);

    // --- Minting Panel Logic ---
    const handleManualMint = async () => {
        
        const taskTitle = TASK_LABELS[selectedTask] || 'Manual SBT Issue';

        // NOTE: In a real app, we would dynamically determine the point level
        const { success, message } = await mockIssueSBT(
            recipient,
            selectedTask,
            POINT_LEVELS.LEVEL_B_HARMONY, // Example level
            taskTitle
        );
        
        showToast(message, success ? 'success' : 'error');
        
        if (success) {
            setRecipient('');
        }
    };

    // --- Audit Panel Logic ---
    const aidSBTs = sbtTokens.filter(t => t.taskType === TASK_TYPES.AID_DISBURSEMENT_RECEIVED);
    const totalAidsAcknowledged = aidSBTs.length;
    
    // Sort tokens for audit view
    const sortedTokens = useMemo(() => 
        sbtTokens.slice().sort((a, b) => b.issuedAt - a.issuedAt)
    , [sbtTokens]);
    
    // Filter out the 'AID_DISBURSEMENT_RECEIVED' option for manual minting (it's holder-triggered)
    const tokenOptions = useMemo(() => 
        Object.entries(TASK_LABELS)
        .filter(([value]) => parseInt(value) !== TASK_TYPES.AID_DISBURSEMENT_RECEIVED)
        .map(([value, label]) => (
            <option key={value} value={parseInt(value)}>
                {label}
            </option>
        ))
    , []);


    return (
        <div className="p-6 bg-white shadow-2xl rounded-xl w-full max-w-6xl mx-auto border-t-8 border-yellow-500">
            <h2 className="text-3xl font-extrabold text-yellow-700 mb-6 flex items-center">
                <svg className="w-8 h-8 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>
                Issuer & Auditor Dashboard
            </h2>
            <div className="text-sm font-medium text-center text-gray-500 border-b border-gray-200">
                <ul className="flex flex-wrap -mb-px">
                    <li className="mr-2">
                        <button
                            onClick={() => setCurrentView(VIEWS.ISSUER_AUDIT)}
                            className={`inline-block p-4 border-b-2 rounded-t-lg transition-colors ${currentView === VIEWS.ISSUER_AUDIT ? 'text-yellow-600 border-yellow-600' : 'hover:text-gray-600 hover:border-gray-300'}`}
                        >
                            Campaign Audit & Verification
                        </button>
                    </li>
                    <li className="mr-2">
                        <button
                            onClick={() => setCurrentView(VIEWS.ISSUER_MINT)}
                            className={`inline-block p-4 border-b-2 rounded-t-lg transition-colors ${currentView === VIEWS.ISSUER_MINT ? 'text-yellow-600 border-yellow-600' : 'hover:text-gray-600 hover:border-gray-300'}`}
                        >
                            Manual SBT Minting Panel
                        </button>
                    </li>
                </ul>
            </div>


            {/* --- Minting Panel Content --- */}
            {currentView === VIEWS.ISSUER_MINT && (
                <div className="pt-6">
                    <h3 className="text-2xl font-bold text-gray-700 mb-4">Mint New Reputation Token</h3>
                    <div className="bg-yellow-50 p-6 rounded-xl space-y-4 shadow-inner">
                        <p className="text-sm text-yellow-700">
                            Authorized Issuer: **{walletAddress}** (Simulating `hasRole(MINTER_ROLE)`)
                        </p>
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Recipient Address (Holder)</label>
                                <input
                                    type="text"
                                    value={recipient}
                                    onChange={(e) => setRecipient(e.target.value)}
                                    placeholder="0x..."
                                    className="w-full p-2 border border-gray-300 rounded-lg focus:ring-yellow-500 focus:border-yellow-500"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Task Type to Verify</label>
                                <select
                                    value={selectedTask}
                                    onChange={(e) => setSelectedTask(parseInt(e.target.value))}
                                    className="w-full p-2 border border-gray-300 rounded-lg focus:ring-yellow-500 focus:border-yellow-500 bg-white"
                                >
                                    {tokenOptions}
                                </select>
                            </div>
                        </div>
                        <button
                            onClick={handleManualMint}
                            disabled={isLoading}
                            className={`w-full py-3 font-bold text-lg rounded-xl shadow-md transition duration-200 flex items-center justify-center ${
                                isLoading
                                    ? 'bg-gray-400 text-gray-200 cursor-not-allowed'
                                    : 'bg-yellow-600 text-white hover:bg-yellow-700'
                            }`}
                        >
                            {isLoading ? (
                                <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                </svg>
                            ) : (
                                <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                            )}
                            {isLoading ? 'Sending Transaction...' : 'Issue SBT to Recipient'}
                        </button>
                    </div>
                </div>
            )}

            {/* --- Audit/Verification Panel Content --- */}
            {currentView === VIEWS.ISSUER_AUDIT && (
                <div className="pt-6">
                    <h3 className="text-2xl font-bold text-gray-700 mb-4">Global Audit & Service Verification</h3>
                    
                    <div className="grid grid-cols-3 gap-4 mb-6">
                         <div className="p-4 bg-green-100 rounded-xl shadow-md">
                            <p className="text-sm font-semibold text-green-700">Total Aid Acknowledged (SBTs)</p>
                            <p className="text-3xl font-black text-green-800 mt-1">{totalAidsAcknowledged}</p>
                        </div>
                        <div className="p-4 bg-indigo-100 rounded-xl shadow-md">
                            <p className="text-sm font-semibold text-indigo-700">Total Reputation SBTs Issued</p>
                            <p className="text-3xl font-black text-indigo-800 mt-1">{sbtTokens.length}</p>
                        </div>
                         <div className="p-4 bg-gray-100 rounded-xl shadow-md">
                            <p className="text-sm font-semibold text-gray-700">Celo Blockchain Audit</p>
                            <p className="text-sm text-gray-600 mt-1">
                                Auditors query `TokenMinted` events to verify campaign success.
                            </p>
                        </div>
                    </div>

                    <h4 className="text-xl font-bold text-gray-700 mb-3 border-t pt-4">All Recent SBT Mints (Global View)</h4>
                    <div className="space-y-3 max-h-96 overflow-y-auto pr-2">
                         {sortedTokens.map((token) => (
                            <div key={token.id} className={`p-4 rounded-lg flex justify-between items-center text-sm ${token.taskType === TASK_TYPES.AID_DISBURSEMENT_RECEIVED ? 'bg-green-50 border-l-4 border-green-500' : 'bg-gray-50 border-l-4 border-indigo-400'}`}>
                                <div>
                                    <p className="font-semibold text-gray-800">{TASK_LABELS[token.taskType] || 'Unknown Task'}</p>
                                    <p className="text-xs text-gray-600 break-words">To: {token.recipient || 'N/A'}</p>
                                </div>
                                <span className="text-xs text-gray-500 text-right">
                                    {new Date(token.issuedAt).toLocaleDateString()}
                                    <br/>
                                    <span className="font-medium">{token.title}</span>
                                </span>
                            </div>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );
};


// --- Main App Component ---

const App = () => {
    const { 
        isConnected, 
        walletAddress, 
        sbtTokens, 
        isLoading, 
        isIssuer, 
        connectWallet, 
        mockIssueSBT 
    } = useCeloSBT();
    
    const [currentView, setCurrentView] = useState(VIEWS.DASHBOARD); 
    const [toastMessage, setToastMessage] = useState(null);

    const showToast = useCallback((message, type = 'success') => {
        if (!message) return; // Prevent empty toasts
        setToastMessage({ message, type });
        // Auto-hide the toast after 4 seconds
        setTimeout(() => setToastMessage(null), 4000);
    }, []);

    // Reset view when role changes
    useEffect(() => {
        if (isConnected) {
            setCurrentView(isIssuer ? VIEWS.ISSUER_AUDIT : VIEWS.DASHBOARD);
        }
    }, [isConnected, isIssuer]);


    // 1. Initial Loading Screen
    if (isLoading && !isConnected) {
        return (
            <div className="flex items-center justify-center min-h-screen bg-gray-100 p-4">
                <div className="text-center p-8 bg-white rounded-xl shadow-xl">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600 mx-auto mb-4"></div>
                    <p className="text-lg font-semibold text-gray-700">Connecting Wallet to Celo Network...</p>
                </div>
                <Toast message={toastMessage?.message} type={toastMessage?.type} />
            </div>
        );
    }
    
    // 2. Wallet Disconnected Screen
    if (!isConnected) {
        return (
            <div className="flex items-center justify-center min-h-screen bg-gray-100 p-4">
                <div className="text-center p-12 bg-white rounded-xl shadow-2xl border-t-8 border-indigo-500">
                    <h2 className="text-2xl font-bold text-gray-800 mb-4">Connect Your Celo Identity</h2>
                    <p className="text-gray-600 mb-6">
                        Select a role to connect your wallet and view the conditional dashboard.
                    </p>
                    <div className="flex space-x-4 justify-center">
                        <button
                            onClick={() => connectWallet('holder')}
                            className="px-6 py-3 bg-indigo-600 text-white font-semibold rounded-lg shadow-md hover:bg-indigo-700 transition"
                        >
                            Connect as IDP/Holder
                        </button>
                         <button
                            onClick={() => connectWallet('issuer')}
                            className="px-6 py-3 bg-yellow-600 text-white font-semibold rounded-lg shadow-md hover:bg-yellow-700 transition"
                        >
                            Connect as NGO/Issuer
                        </button>
                    </div>
                </div>
                <Toast message={toastMessage?.message} type={toastMessage?.type} />
            </div>
        );
    }

    // 3. Conditional Dashboard Rendering (Wallet Connected)
    
    // UI elements and navigation for the Holder (IDP) role
    const holderNav = (
        <div className="flex space-x-3">
            <button
                onClick={() => setCurrentView(VIEWS.DASHBOARD)}
                className={`px-4 py-2 text-sm font-semibold rounded-lg transition ${
                    currentView === VIEWS.DASHBOARD 
                        ? 'bg-indigo-600 text-white shadow-lg' 
                        : 'text-indigo-600 hover:bg-indigo-50 border border-indigo-200'
                }`}
            >
                Risk Score Dashboard
            </button>
            <button
                onClick={() => setCurrentView(VIEWS.SOCIAL_AID)}
                className={`px-4 py-2 text-sm font-semibold rounded-lg transition ${
                    currentView === VIEWS.SOCIAL_AID
                        ? 'bg-green-600 text-white shadow-lg' 
                        : 'text-green-600 hover:bg-green-50 border border-green-200'
                }`}
            >
                Aid Acknowledgment
            </button>
        </div>
    );
    
    return (
        <div className="min-h-screen bg-gray-50 font-sans p-4 md:p-8">
            <header className="mb-8 p-4 bg-white shadow-md rounded-xl max-w-6xl mx-auto flex flex-col sm:flex-row justify-between items-center">
                <h1 className="text-2xl font-black text-gray-800 mb-3 sm:mb-0">
                    Celo Reputation & Aid Platform
                </h1>
                
                {/* Conditionally display navigation based on role */}
                {isIssuer ? (
                    <span className="px-3 py-1 bg-yellow-100 text-yellow-800 rounded-full font-bold text-sm">ISSUER ROLE ACTIVE (Verifier)</span>
                ) : (
                    holderNav
                )}
            </header>

            <main className="max-w-6xl mx-auto">
                {/* STRICT ROLE-BASED RENDERING */}
                {isIssuer ? (
                    <IssuerDashboard 
                        walletAddress={walletAddress} 
                        sbtTokens={sbtTokens} 
                        mockIssueSBT={mockIssueSBT}
                        isLoading={isLoading}
                        showToast={showToast}
                    />
                ) : (
                    <>
                        {/* Render Holder UI based on navigation state */}
                        {currentView === VIEWS.DASHBOARD && (
                            <HolderRiskScoreDashboard 
                                sbtTokens={sbtTokens} 
                                walletAddress={walletAddress}
                            />
                        )}
                        {currentView === VIEWS.SOCIAL_AID && (
                            <HolderSocialAidAcknowledgement 
                                walletAddress={walletAddress} 
                                mockIssueSBT={mockIssueSBT} 
                                sbtTokens={sbtTokens}
                                isLoading={isLoading}
                                showToast={showToast}
                            />
                        )}
                    </>
                )}
            </main>
            
            <footer className="mt-8 text-center text-xs text-gray-500">
                <p>Status: Connected to Celo Network (Testnet Mock)</p>
                <p>Wallet Address: {walletAddress || 'Disconnected'}</p>
            </footer>

            <Toast message={toastMessage?.message} type={toastMessage?.type} />
        </div>
    );
};

export default App;
