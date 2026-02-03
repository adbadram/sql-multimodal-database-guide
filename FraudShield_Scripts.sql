-- ============================================================================
-- FRAUDSHIELD AI - Complete SQL Scripts
-- ============================================================================
-- Companion scripts for "The Multimodal Database Revolution" tutorial
-- 
-- This script builds a complete fraud detection system using SQL Server 2025
-- multimodal capabilities: Relational, JSON, Graph, Vector, Ledger, Columnstore
--
-- Requirements: SQL Server 2025 or Azure SQL Database
-- ============================================================================

USE master;
GO

-- Create database for FraudShield
IF DB_ID('FraudShieldDB') IS NOT NULL
    DROP DATABASE FraudShieldDB;
GO

CREATE DATABASE FraudShieldDB;
GO

USE FraudShieldDB;
GO

PRINT '============================================================================';
PRINT 'STEP 1: THE FOUNDATION - Users, Accounts, and Transactions (Graph-enabled)';
PRINT '============================================================================';
GO

-- Core relational tables WITH graph capabilities built in
CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    Email NVARCHAR(255) UNIQUE,
    Name NVARCHAR(100),
    RiskScore FLOAT DEFAULT 0.0,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
) AS NODE;  -- Graph-enabled from the start
GO

CREATE TABLE Accounts (
    AccountID INT PRIMARY KEY,
    UserID INT,
    AccountType NVARCHAR(20),
    Balance MONEY DEFAULT 0,
    Bank NVARCHAR(50)
) AS NODE;
GO

CREATE TABLE Transactions (
    TxnID BIGINT IDENTITY PRIMARY KEY,
    FromAccountID INT,
    ToAccountID INT,
    Amount MONEY NOT NULL,
    TxnTimestamp DATETIME2 DEFAULT SYSUTCDATETIME(),
    Status NVARCHAR(20) DEFAULT 'PENDING'
);
GO

-- Graph edges for relationship traversal
CREATE TABLE Owns AS EDGE;           -- User OWNS Account
CREATE TABLE TransferredTo AS EDGE;  -- Account TRANSFERRED TO Account
CREATE TABLE Knows AS EDGE;          -- User KNOWS User (social connections)
GO

PRINT '✓ Step 1 Complete: Core tables and graph edges created';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'STEP 2: DEVICE INTELLIGENCE - JSON for Schema Flexibility';
PRINT '============================================================================';
GO

-- Device fingerprints with flexible schema
CREATE TABLE DeviceFingerprints (
    FingerprintID BIGINT IDENTITY PRIMARY KEY,
    UserID INT,
    DeviceData JSON NOT NULL,  -- Native JSON: compressed, validated, indexed
    CapturedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Create JSON index for fast fingerprint queries
CREATE JSON INDEX IX_DeviceData
ON DeviceFingerprints (DeviceData)
FOR ('$.deviceId', '$.browser', '$.os', '$.riskSignals.vpnDetected');
GO

PRINT '✓ Step 2 Complete: DeviceFingerprints table with JSON index created';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'STEP 3: FRAUD PATTERNS - Vector Search for Similarity';
PRINT '============================================================================';
GO

-- Store fraud pattern embeddings (from your ML model)
CREATE TABLE FraudPatterns (
    PatternID INT IDENTITY PRIMARY KEY,
    Description NVARCHAR(500),
    Severity NVARCHAR(20),
    PatternEmbedding VECTOR(384)  -- MiniLM embedding dimension
);
GO

PRINT '✓ Step 3 Complete: FraudPatterns table with VECTOR column created';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'STEP 4: REGULATORY COMPLIANCE - Ledger for Tamper-Proof Audit';
PRINT '============================================================================';
GO

-- All fraud decisions are immutable and verifiable
-- NOTE: Ledger tables in SQL Server 2025 do NOT support JSON, VECTOR, XML, 
--       sql_variant, filestream, or user-defined types.
--       Use NVARCHAR(MAX) for flexible data and parse as JSON in queries.
CREATE TABLE FraudDecisions (
    DecisionID BIGINT IDENTITY PRIMARY KEY,
    TxnID BIGINT NOT NULL,
    UserID INT NOT NULL,
    Decision NVARCHAR(20) NOT NULL,  -- APPROVED, BLOCKED, REVIEW
    RiskScore FLOAT,
    Reasons NVARCHAR(MAX),  -- Store as text, query with JSON functions
    DecidedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    DecidedBy NVARCHAR(100) DEFAULT 'SYSTEM'
)
WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);
GO

PRINT '✓ Step 4 Complete: FraudDecisions ledger table created';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'STEP 5: ANALYTICS - Columnstore Index for Dashboard Queries';
PRINT '============================================================================';
GO

-- Add columnstore index for analytical queries
-- (This is on the SAME Transactions table used for OLTP!)
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Transactions_Analytics
ON Transactions (TxnID, FromAccountID, ToAccountID, Amount, TxnTimestamp, Status);
GO

PRINT '✓ Step 5 Complete: Columnstore index created on Transactions';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'SAMPLE DATA: Populating FraudShield with test data';
PRINT '============================================================================';
GO

-- Insert sample users
INSERT INTO Users (UserID, Email, Name, RiskScore) VALUES
(1, 'alice@example.com', 'Alice Johnson', 0.1),
(2, 'bob@example.com', 'Bob Smith', 0.85),
(3, 'carol@example.com', 'Carol Williams', 0.3),
(4, 'dave@example.com', 'Dave Brown', 0.92),
(5, 'eve@example.com', 'Eve Davis', 0.15);
GO

-- Insert sample accounts
INSERT INTO Accounts (AccountID, UserID, AccountType, Balance, Bank) VALUES
(101, 1, 'Checking', 5000.00, 'Chase'),
(102, 1, 'Savings', 15000.00, 'Chase'),
(103, 2, 'Checking', 2500.00, 'BofA'),
(104, 3, 'Checking', 8000.00, 'Wells Fargo'),
(105, 4, 'Checking', 500.00, 'Offshore Bank'),
(106, 5, 'Checking', 12000.00, 'Chase');
GO

-- Create graph relationships: Users own Accounts
INSERT INTO Owns ($from_id, $to_id)
SELECT u.$node_id, a.$node_id 
FROM Users u
JOIN Accounts a ON u.UserID = a.UserID;
GO

-- Create social connections (Knows relationships)
INSERT INTO Knows ($from_id, $to_id)
SELECT u1.$node_id, u2.$node_id 
FROM Users u1, Users u2 
WHERE u1.UserID = 1 AND u2.UserID = 2;

INSERT INTO Knows ($from_id, $to_id)
SELECT u1.$node_id, u2.$node_id 
FROM Users u1, Users u2 
WHERE u1.UserID = 2 AND u2.UserID = 4;

INSERT INTO Knows ($from_id, $to_id)
SELECT u1.$node_id, u2.$node_id 
FROM Users u1, Users u2 
WHERE u1.UserID = 3 AND u2.UserID = 5;
GO

-- Insert sample transactions
INSERT INTO Transactions (FromAccountID, ToAccountID, Amount, Status) VALUES
(101, 103, 500.00, 'COMPLETED'),
(103, 105, 2000.00, 'COMPLETED'),
(104, 106, 300.00, 'COMPLETED'),
(101, 104, 150.00, 'PENDING');
GO

-- Create transfer relationships
INSERT INTO TransferredTo ($from_id, $to_id)
SELECT a1.$node_id, a2.$node_id 
FROM Accounts a1, Accounts a2 
WHERE a1.AccountID = 101 AND a2.AccountID = 103;

INSERT INTO TransferredTo ($from_id, $to_id)
SELECT a1.$node_id, a2.$node_id 
FROM Accounts a1, Accounts a2 
WHERE a1.AccountID = 103 AND a2.AccountID = 105;
GO

-- Insert device fingerprints (JSON data)
INSERT INTO DeviceFingerprints (UserID, DeviceData) VALUES 
(1, '{
    "deviceId": "mobile-abc-123",
    "type": "mobile",
    "os": "iOS 18.1",
    "browser": "Safari",
    "screen": "1170x2532",
    "accelerometer": {"x": 0.02, "y": -0.98, "z": 0.01},
    "riskSignals": {
        "jailbroken": false,
        "vpnDetected": true,
        "locationSpoofed": false
    }
}'),
(1, '{
    "deviceId": "desktop-xyz-789",
    "type": "desktop",
    "os": "Windows 11",
    "browser": "Chrome/120",
    "screen": "2560x1440",
    "plugins": ["PDF Viewer", "Chrome PDF"],
    "riskSignals": {
        "vpnDetected": false,
        "remoteDesktop": true,
        "vmDetected": false
    }
}'),
(2, '{
    "deviceId": "suspicious-device-001",
    "type": "desktop",
    "os": "Linux",
    "browser": "Tor Browser",
    "riskSignals": {
        "vpnDetected": true,
        "vmDetected": true,
        "torDetected": true
    }
}');
GO

PRINT '✓ Sample data inserted';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'QUERIES: Demonstrating Multimodal Capabilities';
PRINT '============================================================================';
GO

-- Query 1: JSON - Find all sessions from VPN users
PRINT '';
PRINT '--- Query 1: Find VPN users (JSON query with index) ---';
SELECT 
    u.Name,
    u.Email,
    JSON_VALUE(d.DeviceData, '$.deviceId') AS DeviceID,
    JSON_VALUE(d.DeviceData, '$.type') AS DeviceType,
    d.CapturedAt
FROM DeviceFingerprints d
JOIN Users u ON d.UserID = u.UserID
WHERE JSON_VALUE(d.DeviceData, '$.riskSignals.vpnDetected') = 'true';
GO

-- Query 2: Graph - Find users within 2 hops of high-risk users
PRINT '';
PRINT '--- Query 2: Find users connected to high-risk users (Graph) ---';
SELECT DISTINCT
    suspect.Name AS PotentialFraudster,
    suspect.Email,
    suspect.RiskScore,
    highrisk.Name AS ConnectedTo,
    highrisk.RiskScore AS TheirRiskScore
FROM Users suspect, Knows k1, Users intermediate, Knows k2, Users highrisk
WHERE MATCH(suspect-(k1)->intermediate-(k2)->highrisk)
AND highrisk.RiskScore > 0.8
AND suspect.UserID <> highrisk.UserID;
GO

-- Query 3: Graph - Trace money flow
PRINT '';
PRINT '--- Query 3: Trace money flow through network (Graph) ---';
SELECT 
    sender.Name AS Sender,
    a1.Bank AS FromBank,
    a2.Bank AS ToBank,
    receiver.Name AS Receiver
FROM 
    Users sender, Owns o1, Accounts a1,
    TransferredTo t,
    Accounts a2, Owns o2, Users receiver
WHERE MATCH(sender-(o1)->a1-(t)->a2<-(o2)-receiver);
GO

-- Query 4: Analytics - Fraud metrics (uses Columnstore)
PRINT '';
PRINT '--- Query 4: Transaction analytics (Columnstore) ---';
SELECT 
    a.Bank AS Region,
    COUNT(*) AS TotalTransactions,
    SUM(t.Amount) AS TotalVolume,
    AVG(t.Amount) AS AvgTransaction
FROM Transactions t
JOIN Accounts a ON t.FromAccountID = a.AccountID
GROUP BY a.Bank
ORDER BY TotalVolume DESC;
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'STORED PROCEDURE: The Complete Fraud Check';
PRINT '============================================================================';
GO

CREATE OR ALTER PROCEDURE sp_CheckFraud
    @TxnID BIGINT,
    @UserID INT,
    @Amount MONEY,
    @DeviceFingerprint JSON,
    @TxnEmbedding VECTOR(384)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RiskScore FLOAT = 0;
    DECLARE @Reasons NVARCHAR(MAX) = '{}';
    DECLARE @Decision NVARCHAR(20);
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 1: RELATIONAL - Basic velocity checks
    -- ═══════════════════════════════════════════════════════════════
    DECLARE @RecentTxnCount INT;
    SELECT @RecentTxnCount = COUNT(*)
    FROM Transactions
    WHERE FromAccountID IN (SELECT AccountID FROM Accounts WHERE UserID = @UserID)
    AND TxnTimestamp > DATEADD(HOUR, -1, SYSUTCDATETIME());
    
    IF @RecentTxnCount > 10
        SET @RiskScore = @RiskScore + 0.2;
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 2: JSON - Device risk signals
    -- ═══════════════════════════════════════════════════════════════
    IF JSON_VALUE(@DeviceFingerprint, '$.riskSignals.vpnDetected') = 'true'
        SET @RiskScore = @RiskScore + 0.15;
    
    IF JSON_VALUE(@DeviceFingerprint, '$.riskSignals.vmDetected') = 'true'
        SET @RiskScore = @RiskScore + 0.1;
    
    -- Check if this is a new device for this user
    IF NOT EXISTS (
        SELECT 1 FROM DeviceFingerprints 
        WHERE UserID = @UserID 
        AND JSON_VALUE(DeviceData, '$.deviceId') = JSON_VALUE(@DeviceFingerprint, '$.deviceId')
    )
        SET @RiskScore = @RiskScore + 0.1;
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 3: GRAPH - Network analysis
    -- ═══════════════════════════════════════════════════════════════
    DECLARE @FraudConnections INT;
    SELECT @FraudConnections = COUNT(*)
    FROM Users u, Knows k, Users suspect
    WHERE MATCH(u-(k)->suspect)
    AND u.UserID = @UserID
    AND suspect.RiskScore > 0.7;
    
    SET @RiskScore = @RiskScore + (@FraudConnections * 0.15);
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 4: VECTOR - Pattern similarity
    -- ═══════════════════════════════════════════════════════════════
    DECLARE @BestMatchSeverity NVARCHAR(20);
    DECLARE @BestMatchDistance FLOAT;
    
    SELECT TOP 1 
        @BestMatchSeverity = Severity,
        @BestMatchDistance = VECTOR_DISTANCE('cosine', PatternEmbedding, @TxnEmbedding)
    FROM FraudPatterns
    ORDER BY VECTOR_DISTANCE('cosine', PatternEmbedding, @TxnEmbedding) ASC;
    
    IF @BestMatchDistance < 0.2 AND @BestMatchSeverity = 'CRITICAL'
        SET @RiskScore = @RiskScore + 0.4;
    ELSE IF @BestMatchDistance < 0.3 AND @BestMatchSeverity = 'HIGH'
        SET @RiskScore = @RiskScore + 0.25;
    
    -- ═══════════════════════════════════════════════════════════════
    -- DECISION
    -- ═══════════════════════════════════════════════════════════════
    SET @Decision = CASE 
        WHEN @RiskScore >= 0.7 THEN 'BLOCKED'
        WHEN @RiskScore >= 0.4 THEN 'REVIEW'
        ELSE 'APPROVED'
    END;
    
    -- Build reasons JSON
    SET @Reasons = (
        SELECT 
            @RecentTxnCount AS velocityCount,
            JSON_VALUE(@DeviceFingerprint, '$.riskSignals.vpnDetected') AS vpnDetected,
            @FraudConnections AS fraudNetworkConnections,
            @BestMatchDistance AS patternMatchDistance,
            @BestMatchSeverity AS patternMatchSeverity
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 5: LEDGER - Immutable audit record
    -- Note: Reasons stored as NVARCHAR(MAX) for ledger compatibility,
    --       but contains valid JSON that can be queried with JSON functions
    -- ═══════════════════════════════════════════════════════════════
    INSERT INTO FraudDecisions (TxnID, UserID, Decision, RiskScore, Reasons)
    VALUES (@TxnID, @UserID, @Decision, @RiskScore, @Reasons);
    
    -- Store device fingerprint for future reference
    INSERT INTO DeviceFingerprints (UserID, DeviceData)
    VALUES (@UserID, @DeviceFingerprint);
    
    -- Return decision
    SELECT @Decision AS Decision, @RiskScore AS RiskScore, @Reasons AS Reasons;
END;
GO

PRINT '✓ Stored procedure sp_CheckFraud created';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'SECURITY: Row-Level Security for Multi-Tenant Isolation';
PRINT '============================================================================';
GO

-- Note: This requires adding TenantID columns to tables for production use
-- Example shown for reference:

/*
-- Create tenant isolation that applies to ALL data models
CREATE FUNCTION dbo.fn_TenantFilter(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);

-- One policy protects everything
CREATE SECURITY POLICY TenantIsolation
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.Users,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.Accounts,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.Transactions,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.DeviceFingerprints,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.FraudDecisions,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID) ON dbo.FraudPatterns
WITH (STATE = ON);
*/

PRINT '✓ Security policy template included (commented - requires TenantID columns)';
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT 'LEDGER: Verify Audit Trail Integrity';
PRINT '============================================================================';
GO

-- Insert a sample fraud decision to demonstrate ledger
INSERT INTO FraudDecisions (TxnID, UserID, Decision, RiskScore, Reasons) VALUES
(10001, 1, 'BLOCKED', 0.92, '{
    "graphAnalysis": "2 hops from known fraud ring",
    "vectorMatch": "Similar to pattern #3 (85% confidence)",
    "deviceRisk": "VPN detected, new device"
}');
GO

-- View decision history with ledger metadata
PRINT '';
PRINT '--- Ledger: View fraud decision with tamper-proof metadata ---';
SELECT 
    DecisionID,
    TxnID,
    Decision,
    RiskScore,
    JSON_VALUE(Reasons, '$.graphAnalysis') AS GraphReason,
    JSON_VALUE(Reasons, '$.vectorMatch') AS VectorReason,
    ledger_operation_type_desc AS Operation,
    ledger_transaction_id AS LedgerTxn
FROM FraudDecisions_Ledger
WHERE TxnID = 10001
ORDER BY ledger_transaction_id;
GO

-- ============================================================================
PRINT '';
PRINT '============================================================================';
PRINT '✅ FRAUDSHIELD AI SETUP COMPLETE';
PRINT '============================================================================';
PRINT '';
PRINT 'Database: FraudShieldDB';
PRINT 'Tables created:';
PRINT '  • Users (NODE) - Graph-enabled user accounts';
PRINT '  • Accounts (NODE) - Graph-enabled bank accounts';
PRINT '  • Transactions - Financial transactions with Columnstore';
PRINT '  • DeviceFingerprints - JSON device data with JSON index';
PRINT '  • FraudPatterns - Vector embeddings for similarity search';
PRINT '  • FraudDecisions - Ledger table (Reasons as NVARCHAR for ledger compat)';
PRINT '  • Owns, TransferredTo, Knows (EDGE) - Graph relationships';
PRINT '';
PRINT 'NOTE: Ledger tables in SQL Server 2025 do not support JSON/VECTOR columns.';
PRINT '      FraudDecisions.Reasons uses NVARCHAR(MAX) but stores valid JSON.';
PRINT '';
PRINT 'Stored Procedures:';
PRINT '  • sp_CheckFraud - Complete multimodal fraud check';
PRINT '';
PRINT 'Indexes:';
PRINT '  • IX_DeviceData - JSON index on device fingerprints';
PRINT '  • NCCI_Transactions_Analytics - Columnstore for analytics';
PRINT '';
PRINT 'Try running: EXEC sp_CheckFraud with sample parameters';
PRINT '============================================================================';
GO
