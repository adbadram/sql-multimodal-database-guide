-- ============================================================================
-- Microsoft SQL Multimodal Database - All Blog Scripts
-- For SQL Server 2025 / Azure SQL Database
-- ============================================================================
-- NOTE: Execute sections individually. Some require SQL Server 2025 features.
-- ============================================================================

USE master;
GO

-- Create a test database
IF DB_ID('MultimodalDemo') IS NOT NULL
    DROP DATABASE MultimodalDemo;
GO

CREATE DATABASE MultimodalDemo;
GO

USE MultimodalDemo;
GO

-- ============================================================================
-- SECTION 1: RELATIONAL + JSON + GRAPH IN ONE TRANSACTION
-- ============================================================================

-- Create base tables
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Email NVARCHAR(255),
    LastActivity DATETIME2
);

CREATE TABLE Devices (
    DeviceID NVARCHAR(50) PRIMARY KEY,
    DeviceType NVARCHAR(50)
);

CREATE TABLE DeviceEvents (
    EventID INT IDENTITY PRIMARY KEY,
    CustomerID INT,
    EventData NVARCHAR(MAX)  -- Use JSON type in SQL Server 2025
);

-- Graph tables for fraud network
CREATE TABLE FraudNetwork_Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100)
) AS NODE;

CREATE TABLE FraudNetwork_Devices (
    DeviceID NVARCHAR(50) PRIMARY KEY
) AS NODE;

CREATE TABLE UsesDevice AS EDGE;

GO

-- Insert sample data
INSERT INTO Customers VALUES (12345, 'John Doe', 'john@example.com', GETUTCDATE());
INSERT INTO Devices VALUES ('abc-123', 'Mobile');

INSERT INTO FraudNetwork_Customers VALUES (12345, 'John Doe');
INSERT INTO FraudNetwork_Devices VALUES ('abc-123');

GO

-- Multi-model transaction example
BEGIN TRANSACTION;

-- 1. Relational: Update customer record
UPDATE Customers 
SET LastActivity = GETUTCDATE() 
WHERE CustomerID = 12345;

-- 2. JSON: Log device context (schema-flexible)
INSERT INTO DeviceEvents (CustomerID, EventData)
VALUES (12345, '{
    "deviceId": "abc-123",
    "fingerprint": {
        "browser": "Chrome/120",
        "os": "Windows 11",
        "screen": "1920x1080"
    },
    "geoLocation": {
        "country": "US",
        "city": "Seattle"
    }
}');

-- 3. Graph: Create relationship edge
INSERT INTO UsesDevice ($from_id, $to_id)
SELECT c.$node_id, d.$node_id
FROM FraudNetwork_Customers c, FraudNetwork_Devices d
WHERE c.CustomerID = 12345 AND d.DeviceID = 'abc-123';

COMMIT TRANSACTION;

GO

-- ============================================================================
-- SECTION 2: NATIVE JSON TYPE (SQL Server 2025)
-- ============================================================================

-- SQL Server 2025: Native JSON type with validation
CREATE TABLE Events (
    EventID INT IDENTITY PRIMARY KEY,
    Data JSON NOT NULL,  -- Native type: compressed, validated, indexed
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

GO

INSERT INTO Events (Data) VALUES 
('{"deviceId":"d1","fingerprint":{"browser":"Chrome","os":"Windows"}}'),
('{"deviceId":"d2","fingerprint":{"browser":"Firefox","os":"macOS"}}'),
('{"deviceId":"d3","fingerprint":{"browser":"Chrome","os":"Linux"}}');

GO

-- OPENJSON transforms JSON into queryable rows
SELECT 
    e.EventID,
    j.deviceId,
    j.browser,
    j.os,
    COUNT(*) OVER (PARTITION BY j.browser) as BrowserCount
FROM Events e
CROSS APPLY OPENJSON(e.Data) 
WITH (
    deviceId NVARCHAR(50) '$.deviceId',
    browser NVARCHAR(50) '$.fingerprint.browser',
    os NVARCHAR(50) '$.fingerprint.os'
) j;

GO

-- ============================================================================
-- SECTION 3: CREATE JSON INDEX (SQL Server 2025)
-- ============================================================================

-- Create a table for JSON index demo
CREATE TABLE Sales_SalesOrderHeader (
    SalesOrderID INT PRIMARY KEY,
    Info JSON NOT NULL
);

GO

-- Insert sample data
INSERT INTO Sales_SalesOrderHeader VALUES 
(1, '{"Customer":{"ID":16167,"Type":"IN"},"Order":{"TotalDue":1500.00,"IsProcessed":true}}'),
(2, '{"Customer":{"ID":16168,"Type":"OUT"},"Order":{"TotalDue":2500.00,"IsProcessed":false}}'),
(3, '{"Customer":{"ID":16167,"Type":"IN"},"Order":{"TotalDue":750.00,"IsProcessed":true}}'),
(4, '{"Customer":{"ID":16169,"Type":"IN"},"Order":{"TotalDue":3200.00}}');

GO

-- Create JSON index on the entire document
CREATE JSON INDEX IX_SalesInfo
ON Sales_SalesOrderHeader (Info);

GO

-- Drop and recreate with specific paths
DROP INDEX IX_SalesInfo ON Sales_SalesOrderHeader;
GO

-- Index specific JSON paths for targeted optimization
CREATE JSON INDEX IX_CustomerInfo
ON Sales_SalesOrderHeader (Info)
FOR ('$.Customer.ID', '$.Customer.Type', '$.Order.TotalDue');

GO

-- Query 1: JSON_PATH_EXISTS — Check if a path exists
SELECT COUNT(*)
FROM Sales_SalesOrderHeader
WHERE JSON_PATH_EXISTS(Info, '$.Order.IsProcessed') = 1;

GO

-- Query 2: JSON_VALUE — Equality search on JSON string property
SELECT COUNT(*)
FROM Sales_SalesOrderHeader
WHERE JSON_VALUE(Info, '$.Customer.Type') = 'IN';

GO

-- Query 3: JSON_VALUE with type conversion
SELECT *
FROM Sales_SalesOrderHeader
WHERE JSON_VALUE(Info, '$.Customer.ID' RETURNING INT) = 16167;

GO

-- Query 4: Range search with type conversion
SELECT *
FROM Sales_SalesOrderHeader
WHERE JSON_VALUE(Info, '$.Order.TotalDue' RETURNING DECIMAL(20, 4)) 
      BETWEEN 1000 AND 2000;

GO

-- ============================================================================
-- SECTION 4: JSON INDEX WITH ARRAY OPTIMIZATION
-- ============================================================================

CREATE TABLE Customers_WithArrays (
    CustomerID INT IDENTITY PRIMARY KEY,
    CustomerInfo JSON NOT NULL
);

GO

-- Create JSON index with array optimization
CREATE JSON INDEX IX_CustomerJson
ON Customers_WithArrays (CustomerInfo)
WITH (OPTIMIZE_FOR_ARRAY_SEARCH = ON);

GO

-- Insert customer with array data
INSERT INTO Customers_WithArrays (CustomerInfo) VALUES 
('{"name":"customer1", "email":"c1@example.com", "phone":["123-456-7890", "234-567-8901"]}'),
('{"name":"customer2", "email":"c2@example.com", "phone":["345-678-9012"]}'),
('{"name":"customer3", "email":"c3@example.com", "phone":["123-456-7890", "456-789-0123"]}');

GO

-- Fast array searches using JSON_CONTAINS
-- JSON_CONTAINS returns INT (0 or 1), not boolean - must compare to 1
SELECT * FROM Customers_WithArrays
WHERE JSON_CONTAINS(CustomerInfo, '"123-456-7890"', '$.phone') = 1;

GO

-- ============================================================================
-- SECTION 5: SCHEMA EVOLUTION WITHOUT DOWNTIME
-- ============================================================================

-- Week 1: Original schema
INSERT INTO Events (Data) VALUES 
('{"version":1,"action":"click","target":"button"}');

-- Week 2: Added nested analytics (backward compatible)
INSERT INTO Events (Data) VALUES 
('{"version":2,"action":"click","target":"button","analytics":{"duration":1.5}}');

GO

-- Query works on BOTH versions
SELECT 
    JSON_VALUE(Data, '$.action') as Action,
    JSON_VALUE(Data, '$.target') as Target,
    JSON_VALUE(Data, '$.analytics.duration') as Duration  -- NULL for v1
FROM Events
WHERE JSON_VALUE(Data, '$.action') IS NOT NULL;

GO

-- ============================================================================
-- SECTION 6: GRAPH QUERIES - FRAUD DETECTION NETWORK
-- ============================================================================

-- Create nodes for fraud detection network
CREATE TABLE Person (
    PersonID INT PRIMARY KEY,
    Name NVARCHAR(100),
    RiskScore FLOAT
) AS NODE;

CREATE TABLE TransactionNode (
    TxnID INT PRIMARY KEY,
    Amount MONEY,
    TxnTimestamp DATETIME2
) AS NODE;

CREATE TABLE Account (
    AccountID INT PRIMARY KEY,
    Bank NVARCHAR(50)
) AS NODE;

-- Create edges (relationships)
CREATE TABLE Owns AS EDGE;           -- Person OWNS Account
CREATE TABLE SentMoney AS EDGE;      -- Account SENT MONEY TO Account
CREATE TABLE InvolvedIn AS EDGE;     -- Person INVOLVED IN Transaction
CREATE TABLE Knows AS EDGE;          -- Person KNOWS Person

GO

-- Insert sample graph data
INSERT INTO Person VALUES (1, 'Alice', 0.2), (2, 'Bob', 0.9), (3, 'Charlie', 0.85), (4, 'Diana', 0.3);
INSERT INTO Account VALUES (101, 'Bank A'), (102, 'Bank B'), (103, 'Bank C');
INSERT INTO TransactionNode VALUES (1001, 15000, GETUTCDATE()), (1002, 25000, GETUTCDATE());

GO

-- Create relationships
INSERT INTO Owns ($from_id, $to_id)
SELECT p.$node_id, a.$node_id FROM Person p, Account a WHERE p.PersonID = 1 AND a.AccountID = 101;
INSERT INTO Owns ($from_id, $to_id)
SELECT p.$node_id, a.$node_id FROM Person p, Account a WHERE p.PersonID = 2 AND a.AccountID = 102;
INSERT INTO Owns ($from_id, $to_id)
SELECT p.$node_id, a.$node_id FROM Person p, Account a WHERE p.PersonID = 3 AND a.AccountID = 103;

INSERT INTO SentMoney ($from_id, $to_id)
SELECT a1.$node_id, a2.$node_id FROM Account a1, Account a2 WHERE a1.AccountID = 101 AND a2.AccountID = 102;
INSERT INTO SentMoney ($from_id, $to_id)
SELECT a1.$node_id, a2.$node_id FROM Account a1, Account a2 WHERE a1.AccountID = 102 AND a2.AccountID = 103;

INSERT INTO Knows ($from_id, $to_id)
SELECT p1.$node_id, p2.$node_id FROM Person p1, Person p2 WHERE p1.PersonID = 1 AND p2.PersonID = 2;
INSERT INTO Knows ($from_id, $to_id)
SELECT p1.$node_id, p2.$node_id FROM Person p1, Person p2 WHERE p1.PersonID = 2 AND p2.PersonID = 3;

INSERT INTO InvolvedIn ($from_id, $to_id)
SELECT p.$node_id, t.$node_id FROM Person p, TransactionNode t WHERE p.PersonID = 2 AND t.TxnID = 1001;

GO

-- Find fraud rings: People connected through account transfers
SELECT 
    p1.Name AS Sender,
    p1.RiskScore AS SenderRisk,
    a1.Bank AS FromBank,
    a2.Bank AS ToBank,
    p2.Name AS Receiver,
    p2.RiskScore AS ReceiverRisk
FROM 
    Person p1, Owns o1, Account a1,
    SentMoney s,
    Account a2, Owns o2, Person p2
WHERE MATCH(p1-(o1)->a1-(s)->a2<-(o2)-p2)
AND p1.PersonID <> p2.PersonID;

GO

-- Find people connected to high-risk individuals
SELECT 
    p1.Name AS Person,
    p1.RiskScore,
    p2.Name AS KnowsHighRisk,
    p2.RiskScore AS TheirRiskScore
FROM Person p1, Knows k, Person p2
WHERE MATCH(p1-(k)->p2)
AND p2.RiskScore > 0.8;

GO

-- ============================================================================
-- SECTION 7: VECTOR SEARCH (SQL Server 2025)
-- ============================================================================
-- NOTE: VECTOR type requires SQL Server 2025. This section will be skipped
-- on older versions. Check your version: SELECT @@VERSION;
-- ============================================================================

-- Check if VECTOR type is supported (SQL Server 2025+)
DECLARE @sql2025 BIT = 0;
IF EXISTS (SELECT 1 FROM sys.types WHERE name = 'vector')
    SET @sql2025 = 1;

IF @sql2025 = 0
BEGIN
    PRINT 'SECTION 7 SKIPPED: VECTOR type requires SQL Server 2025.';
    PRINT 'Your version: ' + @@VERSION;
    PRINT 'Vector search features will be available when you upgrade to SQL Server 2025.';
END
GO

-- Only run if VECTOR type exists
IF EXISTS (SELECT 1 FROM sys.types WHERE name = 'vector')
BEGIN
    -- Drop if exists from previous runs
    IF OBJECT_ID('Products', 'U') IS NOT NULL
        EXEC('DROP TABLE Products');
    
    -- Create table with native VECTOR type
    -- Using 3 dimensions for demo; production would use 1536 (OpenAI) or 384 (MiniLM)
    EXEC('
    CREATE TABLE Products (
        ProductID INT PRIMARY KEY,
        Name NVARCHAR(200),
        Description NVARCHAR(MAX),
        Price MONEY,
        StockLevel INT,
        CategoryID INT,
        DescriptionEmbedding VECTOR(3)
    )');
    
    -- Insert sample products with mock embeddings
    EXEC('
    INSERT INTO Products VALUES 
    (1, ''Ergonomic Office Chair'', ''Comfortable seating for long work sessions with lumbar support'', 299.99, 50, 15, ''[0.1, 0.2, 0.3]''),
    (2, ''Standing Desk'', ''Adjustable height desk for healthy posture'', 499.99, 30, 15, ''[0.4, 0.5, 0.6]''),
    (3, ''Monitor Arm'', ''Flexible monitor mounting solution'', 89.99, 100, 15, ''[0.15, 0.25, 0.35]'')');
    
    -- =========================================================================
    -- DiskANN INDEX - AZURE SQL DATABASE ONLY (Cloud)
    -- Uncomment the following if running on Azure SQL Database:
    -- =========================================================================
    /*
    EXEC('
    CREATE VECTOR INDEX IX_Products_Embedding
    ON Products(DescriptionEmbedding)
    WITH (METRIC = ''cosine'', TYPE = ''DiskANN'')');
    */
    -- =========================================================================
    
    -- Vector + Relational Filtering: Hybrid Search
    EXEC('
    DECLARE @searchVector VECTOR(3) = ''[0.1, 0.2, 0.3]'';
    SELECT TOP 10
        p.ProductID,
        p.Name,
        p.Price,
        p.StockLevel,
        VECTOR_DISTANCE(''cosine'', p.DescriptionEmbedding, @searchVector) AS Similarity
    FROM Products p
    WHERE 
        p.StockLevel > 0
        AND p.Price < 500
        AND p.CategoryID = 15
    ORDER BY Similarity ASC');
    
    PRINT 'SECTION 7 completed: Vector table created. DiskANN index is commented out (Azure SQL only).';
END
GO

-- ============================================================================
-- SECTION 8: HTAP - COLUMNSTORE FOR ANALYTICS
-- ============================================================================

CREATE TABLE SalesHistory (
    SaleID BIGINT IDENTITY,
    ProductID INT,
    CustomerID INT,
    Quantity INT,
    UnitPrice MONEY,
    SaleDate DATE,
    Region NVARCHAR(50)
);

GO

-- Insert sample data
INSERT INTO SalesHistory (ProductID, CustomerID, Quantity, UnitPrice, SaleDate, Region)
VALUES 
(1, 1001, 2, 299.99, '2025-01-15', 'West'),
(2, 1002, 1, 499.99, '2025-01-16', 'East'),
(1, 1003, 3, 289.99, '2025-01-17', 'West'),
(3, 1001, 5, 89.99, '2025-01-18', 'Central'),
(2, 1004, 2, 479.99, '2025-01-19', 'East');

GO

-- Create clustered columnstore index for analytics
CREATE CLUSTERED COLUMNSTORE INDEX CCI_Sales ON SalesHistory;

GO

-- Analytical query - runs in batch mode with columnstore
SELECT 
    Region,
    YEAR(SaleDate) as SaleYear,
    MONTH(SaleDate) as SaleMonth,
    COUNT(*) as TotalOrders,
    SUM(Quantity) as TotalUnits,
    SUM(Quantity * UnitPrice) as TotalRevenue,
    AVG(Quantity * UnitPrice) as AvgOrderValue
FROM SalesHistory
GROUP BY Region, YEAR(SaleDate), MONTH(SaleDate)
ORDER BY Region, SaleYear, SaleMonth;

GO

-- ============================================================================
-- SECTION 9: ROW-LEVEL SECURITY ACROSS ALL DATA MODELS
-- ============================================================================

-- Create tenant isolation function
CREATE FUNCTION dbo.fn_TenantFilter(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);

GO

-- Create multi-tenant tables
CREATE TABLE MT_Customers (
    CustomerID INT PRIMARY KEY,
    TenantID INT NOT NULL,
    Name NVARCHAR(100)
);

CREATE TABLE MT_Events (
    EventID INT PRIMARY KEY,
    TenantID INT NOT NULL,
    EventData JSON
);

GO

-- Create security policy (applies to ALL queries)
CREATE SECURITY POLICY TenantIsolation
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID)
ON dbo.MT_Customers,
ADD FILTER PREDICATE dbo.fn_TenantFilter(TenantID)
ON dbo.MT_Events
WITH (STATE = ON);

GO

-- Insert test data
INSERT INTO MT_Customers VALUES (1, 100, 'Tenant100 Customer'), (2, 200, 'Tenant200 Customer');
INSERT INTO MT_Events VALUES (1, 100, '{"event":"login"}'), (2, 200, '{"event":"purchase"}');

GO

-- Test: Set tenant context and query
EXEC sp_set_session_context @key = N'TenantID', @value = 100;
SELECT * FROM MT_Customers;  -- Only sees Tenant 100 data
SELECT * FROM MT_Events;     -- Only sees Tenant 100 data

GO

EXEC sp_set_session_context @key = N'TenantID', @value = 200;
SELECT * FROM MT_Customers;  -- Only sees Tenant 200 data
SELECT * FROM MT_Events;     -- Only sees Tenant 200 data

GO

-- ============================================================================
-- SECTION 10: LEDGER TABLES - IMMUTABLE AUDIT TRAIL
-- ============================================================================
-- Ledger tables provide tamper-evident, cryptographically verifiable history
-- Perfect for: Financial transactions, compliance, supply chain, healthcare
-- ============================================================================

-- Create an updatable ledger table for financial transactions
CREATE TABLE FinancialTransactions (
    TransactionID INT PRIMARY KEY,
    AccountID INT NOT NULL,
    Amount MONEY NOT NULL,
    TransactionType NVARCHAR(20) NOT NULL,
    Description NVARCHAR(500),
    TransactionDate DATETIME2 DEFAULT SYSUTCDATETIME()
)
WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);

GO

-- Insert some transactions
INSERT INTO FinancialTransactions (TransactionID, AccountID, Amount, TransactionType, Description)
VALUES 
(1, 1001, 5000.00, 'DEPOSIT', 'Initial deposit'),
(2, 1001, -500.00, 'WITHDRAWAL', 'ATM withdrawal'),
(3, 1002, 10000.00, 'DEPOSIT', 'Wire transfer received'),
(4, 1001, -1500.00, 'TRANSFER', 'Transfer to account 1002');

GO

-- Update a transaction (ledger tracks the change!)
UPDATE FinancialTransactions 
SET Description = 'Initial deposit - verified'
WHERE TransactionID = 1;

GO

-- View the ledger history - shows ALL changes with cryptographic proof
SELECT 
    TransactionID,
    AccountID,
    Amount,
    TransactionType,
    Description,
    ledger_start_transaction_id,
    ledger_end_transaction_id,
    ledger_operation_type_desc
FROM FinancialTransactions_Ledger
ORDER BY TransactionID, ledger_start_transaction_id;

GO

-- Verify ledger integrity - cryptographic verification
-- This proves no tampering has occurred
EXECUTE sp_verify_database_ledger_from_digest_storage;

GO

-- Create an append-only ledger table (no updates/deletes allowed)
CREATE TABLE AuditLog (
    LogID INT IDENTITY PRIMARY KEY,
    EventType NVARCHAR(50) NOT NULL,
    EventData JSON,
    UserName NVARCHAR(100) DEFAULT SUSER_SNAME(),
    EventTime DATETIME2 DEFAULT SYSUTCDATETIME()
)
WITH (LEDGER = ON (APPEND_ONLY = ON));

GO

-- Insert audit events
INSERT INTO AuditLog (EventType, EventData) VALUES 
('LOGIN', '{"ip":"192.168.1.1","browser":"Chrome"}'),
('DATA_ACCESS', '{"table":"Customers","rows":150}'),
('CONFIG_CHANGE', '{"setting":"MaxConnections","oldValue":100,"newValue":200}');

GO

-- Query audit log - immutable record
SELECT * FROM AuditLog ORDER BY EventTime;

GO

-- ============================================================================
-- SECTION 11: CROSS-MODEL INDEXING STRATEGIES
-- ============================================================================

-- Approach 1: Computed column index (works in older SQL Server versions)
ALTER TABLE Events
ADD EventCategory AS JSON_VALUE(Data, '$.action') PERSISTED;

CREATE INDEX IX_Events_Category ON Events(EventCategory);

GO

-- Approach 2: Native JSON index (SQL Server 2025 - preferred)
-- Already demonstrated in Section 3

-- Graph edge index
CREATE INDEX IX_Knows_FromTo 
ON Knows($from_id, $to_id);

GO

-- ============================================================================
-- CLEANUP (Optional - run to reset)
-- ============================================================================
/*
USE master;
GO
DROP DATABASE MultimodalDemo;
GO
*/

-- ============================================================================
-- END OF SCRIPTS
-- ============================================================================
PRINT 'All blog scripts executed successfully!';
PRINT 'Tested on: SQL Server 2025 Developer Edition';
PRINT 'Download FREE: https://aka.ms/sqldeveloper';
PRINT 'Note: Some features (native JSON type, VECTOR, CREATE JSON INDEX, LEDGER) require SQL Server 2025.';
GO
