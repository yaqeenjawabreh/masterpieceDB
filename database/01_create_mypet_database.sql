/* ============================================================================
   mypet  -  SQL Server database
   FILE 1 of 2 : 01_create_mypet_database.sql

   Builds the whole database in one run (press F5 in SSMS):
     PART A  Database            CREATE / DROP DATABASE                (Day 1)
     PART B  Tables              data types + constraints + relations  (Day 1 + Day 2)
     PART C  Indexes             clustered / non-clustered             (Day 2)
     PART D  Functions           scalar + table-valued                 (Day 2)
     PART E  Views                                                     (Day 2)
     PART F  Stored procedures                                         (Day 2)
     PART G  Triggers                                                  (Day 2)
     PART H  Sample data         INSERT                                (Day 1)

   Running it again deletes MyPetDB and builds it from zero.
   The practice queries for every topic are in 02_practice_queries.sql.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;     -- needed for the filtered index in PART C
GO


/* ============================================================================
   PART A - DATABASE                                           (Day 1)
   ============================================================================ */
USE master;
GO

-- DROP DATABASE: remove the old copy so the script can be run again
IF DB_ID(N'MyPetDB') IS NOT NULL
BEGIN
    ALTER DATABASE MyPetDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;   -- close open connections first
    DROP DATABASE MyPetDB;
END
GO

-- CREATE DATABASE
CREATE DATABASE MyPetDB;
GO

USE MyPetDB;
GO


/* ============================================================================
   PART B - TABLES                                             (Day 1 + Day 2)

   Data types used
     INT / SMALLINT / TINYINT   whole numbers (ids, stock, hours)
     DECIMAL(p,s)               money and ratings (exact; never FLOAT for money)
     NVARCHAR(n)                text that can hold Arabic (N = Unicode)
     VARCHAR(n)                 English codes, e-mails, phone numbers
     NVARCHAR(MAX)              long text (blog article body)
     CHAR(n)                    fixed length (last 4 card digits, day code)
     BIT                        yes / no  (1 / 0)
     DATE, TIME(0), DATETIME2   dates and times

   Constraints used
     PRIMARY KEY   one row = one id (also creates the CLUSTERED index)
     NOT NULL      the value is required
     UNIQUE        no two rows can share the value
     CHECK         the value must pass a rule
     DEFAULT       value used when none is given
     FOREIGN KEY   the value must exist in another table (this is a RELATION)

   Relations (Day 2)
     one-to-one    Users      - Providers      (UNIQUE foreign key Providers.UserID)
     one-to-many   Governorates - Areas, Users - Pets, Providers - Bookings, ...
     many-to-many  Orders     - Products       (junction table OrderItems)
                   Users      - Products       (junction table Wishlist)
                   Users      - ShelterPets    (junction table AdoptionRequests)
   ============================================================================ */

/* ---------- 1. Governorates : Jordan's 12 governorates ---------- */
CREATE TABLE Governorates (
    GovernorateID   INT IDENTITY(1,1)   NOT NULL,
    Name            NVARCHAR(50)        NOT NULL,
    CONSTRAINT PK_Governorates      PRIMARY KEY (GovernorateID),
    CONSTRAINT UQ_Governorates_Name UNIQUE (Name)
);

/* ---------- 2. Areas : main areas of each governorate (one governorate -> many areas) ---------- */
CREATE TABLE Areas (
    AreaID          INT IDENTITY(1,1)   NOT NULL,
    GovernorateID   INT                 NOT NULL,
    Name            NVARCHAR(60)        NOT NULL,
    CONSTRAINT PK_Areas              PRIMARY KEY (AreaID),
    CONSTRAINT UQ_Areas_Gov_Name     UNIQUE (GovernorateID, Name),
    CONSTRAINT FK_Areas_Governorates FOREIGN KEY (GovernorateID) REFERENCES Governorates(GovernorateID)
);

/* ---------- 3. Users : every login (pet owners, providers, the admin) ---------- */
CREATE TABLE Users (
    UserID              INT IDENTITY(1,1)   NOT NULL,
    FullName            NVARCHAR(100)       NOT NULL,
    Email               VARCHAR(150)        NOT NULL,
    Phone               VARCHAR(20)         NULL,
    PasswordHash        VARCHAR(255)        NOT NULL,   -- never store the real password
    Role                VARCHAR(10)         NOT NULL CONSTRAINT DF_Users_Role       DEFAULT 'Owner',
    Status              VARCHAR(10)         NOT NULL CONSTRAINT DF_Users_Status     DEFAULT 'Active',
    MustChangePassword  BIT                 NOT NULL CONSTRAINT DF_Users_MustChange DEFAULT 0,   -- 1 = "Choose a new password" on first sign-in
    CreatedAt           DATETIME2(0)        NOT NULL CONSTRAINT DF_Users_CreatedAt  DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Users        PRIMARY KEY (UserID),
    CONSTRAINT UQ_Users_Email  UNIQUE (Email),
    CONSTRAINT CK_Users_Role   CHECK (Role   IN ('Owner', 'Provider', 'Admin')),
    CONSTRAINT CK_Users_Status CHECK (Status IN ('Active', 'Invited', 'Suspended'))
);
GO

-- ALTER TABLE: add a column after the table exists (the user's city on admin/users.html)
ALTER TABLE Users ADD GovernorateID INT NULL;
GO
ALTER TABLE Users ADD CONSTRAINT FK_Users_Governorates
    FOREIGN KEY (GovernorateID) REFERENCES Governorates(GovernorateID);
GO

/* ---------- 4. Providers : clinics, day care, trainers, walkers, shelters ----------
   ONE-TO-ONE with Users: every provider has exactly one login, and a login
   belongs to at most one provider (the UNIQUE on UserID makes it 1 : 1).          */
CREATE TABLE Providers (
    ProviderID       INT IDENTITY(1,1)  NOT NULL,
    UserID           INT                NOT NULL,
    ProviderType     VARCHAR(10)        NOT NULL,
    BusinessName     NVARCHAR(100)      NOT NULL,
    AreaID           INT                NOT NULL,
    Phone            VARCHAR(20)        NOT NULL,
    About            NVARCHAR(1000)     NULL,
    Price            DECIMAL(8,2)       NULL,      -- Clinic: fee | DayCare: per hour | Trainer: per session | Walker: per 30 min | Shelter: NULL (adoption is free)
    PhotoUrl         VARCHAR(300)       NULL,
    Specialty        NVARCHAR(50)       NULL,      -- trainers only
    YearsExperience  TINYINT            NULL,      -- trainers only
    SlotMinutes      TINYINT            NOT NULL CONSTRAINT DF_Providers_Slot        DEFAULT 30,  -- clinic appointment length
    MinNoticeHours   TINYINT            NOT NULL CONSTRAINT DF_Providers_Notice      DEFAULT 0,
    AvgRating        DECIMAL(3,2)       NOT NULL CONSTRAINT DF_Providers_AvgRating   DEFAULT 0,   -- DENORMALIZED: kept up to date by a trigger
    ReviewCount      INT                NOT NULL CONSTRAINT DF_Providers_ReviewCount DEFAULT 0,   -- DENORMALIZED: kept up to date by a trigger
    CONSTRAINT PK_Providers        PRIMARY KEY (ProviderID),
    CONSTRAINT UQ_Providers_UserID UNIQUE (UserID),
    CONSTRAINT FK_Providers_Users  FOREIGN KEY (UserID) REFERENCES Users(UserID),
    CONSTRAINT FK_Providers_Areas  FOREIGN KEY (AreaID) REFERENCES Areas(AreaID),
    CONSTRAINT CK_Providers_Type   CHECK (ProviderType IN ('Clinic', 'DayCare', 'Trainer', 'Walker', 'Shelter')),
    CONSTRAINT CK_Providers_Price  CHECK (Price IS NULL OR Price >= 0),
    CONSTRAINT CK_Providers_Rating CHECK (AvgRating BETWEEN 0 AND 5)
);

/* ---------- 5. ProviderHours : weekly opening hours (one row per provider per day) ---------- */
CREATE TABLE ProviderHours (
    ProviderID  INT       NOT NULL,
    DayCode     CHAR(3)   NOT NULL,
    IsOpen      BIT       NOT NULL CONSTRAINT DF_ProviderHours_IsOpen DEFAULT 1,
    OpenTime    TIME(0)   NOT NULL,
    CloseTime   TIME(0)   NOT NULL,
    CONSTRAINT PK_ProviderHours           PRIMARY KEY (ProviderID, DayCode),        -- composite primary key
    CONSTRAINT FK_ProviderHours_Providers FOREIGN KEY (ProviderID) REFERENCES Providers(ProviderID),
    CONSTRAINT CK_ProviderHours_Day       CHECK (DayCode IN ('Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri')),
    CONSTRAINT CK_ProviderHours_Times     CHECK (CloseTime > OpenTime)
);

/* ---------- 6. ProviderDaysOff : holidays, no bookings on these dates ---------- */
CREATE TABLE ProviderDaysOff (
    DayOffID    INT IDENTITY(1,1)  NOT NULL,
    ProviderID  INT                NOT NULL,
    OffDate     DATE               NOT NULL,
    Reason      NVARCHAR(100)      NULL,
    CONSTRAINT PK_ProviderDaysOff           PRIMARY KEY (DayOffID),
    CONSTRAINT UQ_ProviderDaysOff_Date      UNIQUE (ProviderID, OffDate),
    CONSTRAINT FK_ProviderDaysOff_Providers FOREIGN KEY (ProviderID) REFERENCES Providers(ProviderID)
);

/* ---------- 7. Pets : the owners' own pets (user/my-pets.html) ---------- */
CREATE TABLE Pets (
    PetID     INT IDENTITY(1,1)  NOT NULL,
    OwnerID   INT                NOT NULL,
    Name      NVARCHAR(50)       NOT NULL,
    PetType   VARCHAR(10)        NOT NULL,
    AgeYears  DECIMAL(4,1)       NULL,
    PhotoUrl  VARCHAR(300)       NULL,
    CONSTRAINT PK_Pets       PRIMARY KEY (PetID),
    CONSTRAINT FK_Pets_Users FOREIGN KEY (OwnerID) REFERENCES Users(UserID),
    CONSTRAINT CK_Pets_Type  CHECK (PetType IN ('Dog', 'Cat', 'Bird', 'Fish', 'Other')),
    CONSTRAINT CK_Pets_Age   CHECK (AgeYears IS NULL OR AgeYears >= 0)
);

/* ---------- 8. Bookings : clinic, day care, training and walking bookings ----------
   No UserID column: the customer is the pet's owner (Pets.OwnerID).
   No ServiceType column: the service is the provider's type.
   Storing them here too would break 3rd Normal Form.                               */
CREATE TABLE Bookings (
    BookingID        INT IDENTITY(1001,1)  NOT NULL,
    PetID            INT                   NOT NULL,
    ProviderID       INT                   NOT NULL,
    BookingDate      DATE                  NOT NULL,
    StartTime        TIME(0)               NOT NULL,      -- drop-off time for day care
    Hours            TINYINT               NULL,          -- day care only (1 - 10)
    DurationMinutes  SMALLINT              NULL,          -- clinic / training / walking
    EndTime          AS DATEADD(MINUTE, COALESCE(Hours * 60, DurationMinutes, 0), StartTime),   -- computed column (day care: pick-up time)
    SessionType      NVARCHAR(30)          NULL,          -- training: Private / Group session
    Reason           NVARCHAR(50)          NULL,          -- clinic: Vaccination, Dental care, ...
    PickupAddress    NVARCHAR(200)         NULL,          -- walking
    Notes            NVARCHAR(500)         NULL,
    TotalPrice       DECIMAL(8,2)          NOT NULL,      -- final price, paid online
    CardLast4        CHAR(4)               NOT NULL,      -- bookings are always paid by card; only the last 4 digits are kept
    Status           VARCHAR(10)           NOT NULL CONSTRAINT DF_Bookings_Status    DEFAULT 'Confirmed',
    PayoutStatus     VARCHAR(4)            NOT NULL CONSTRAINT DF_Bookings_Payout    DEFAULT 'Due',   -- Due = mypet still owes the provider
    CreatedAt        DATETIME2(0)          NOT NULL CONSTRAINT DF_Bookings_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Bookings           PRIMARY KEY (BookingID),
    CONSTRAINT FK_Bookings_Pets      FOREIGN KEY (PetID)      REFERENCES Pets(PetID),
    CONSTRAINT FK_Bookings_Providers FOREIGN KEY (ProviderID) REFERENCES Providers(ProviderID),
    CONSTRAINT CK_Bookings_Hours     CHECK (Hours IS NULL OR Hours BETWEEN 1 AND 10),
    CONSTRAINT CK_Bookings_Price     CHECK (TotalPrice >= 0),
    CONSTRAINT CK_Bookings_Card      CHECK (CardLast4 LIKE '[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Bookings_Status    CHECK (Status IN ('Confirmed', 'Completed', 'Cancelled')),
    CONSTRAINT CK_Bookings_Payout    CHECK (PayoutStatus IN ('Due', 'Paid'))
);

/* ---------- 9. BookingStatusLog : history of status changes (filled by a trigger) ----------
   Example of a table whose PRIMARY KEY is NON-CLUSTERED, so the CLUSTERED index
   can go on another column (ChangedAt) - see PART C.                                    */
CREATE TABLE BookingStatusLog (
    LogID      INT IDENTITY(1,1)  NOT NULL,
    BookingID  INT                NOT NULL,
    OldStatus  VARCHAR(10)        NULL,          -- NULL = the booking was just created
    NewStatus  VARCHAR(10)        NOT NULL,
    ChangedAt  DATETIME2(0)       NOT NULL CONSTRAINT DF_BookingStatusLog_ChangedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_BookingStatusLog          PRIMARY KEY NONCLUSTERED (LogID),
    CONSTRAINT FK_BookingStatusLog_Bookings FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
);

/* ---------- 10. ShelterPets : pets for adoption (only a shelter lists pets) ---------- */
CREATE TABLE ShelterPets (
    ShelterPetID  INT IDENTITY(1,1)  NOT NULL,
    ShelterID     INT                NOT NULL,      -- a provider whose type is 'Shelter'
    Name          NVARCHAR(50)       NOT NULL,
    PetType       VARCHAR(10)        NOT NULL,
    Breed         NVARCHAR(50)       NULL,
    Gender        VARCHAR(6)         NOT NULL,
    AgeMonths     SMALLINT           NOT NULL,
    About         NVARCHAR(1000)     NULL,
    PhotoUrl      VARCHAR(300)       NULL,
    Status        VARCHAR(10)        NOT NULL CONSTRAINT DF_ShelterPets_Status  DEFAULT 'Available',
    AddedAt       DATETIME2(0)       NOT NULL CONSTRAINT DF_ShelterPets_AddedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ShelterPets           PRIMARY KEY (ShelterPetID),
    CONSTRAINT FK_ShelterPets_Providers FOREIGN KEY (ShelterID) REFERENCES Providers(ProviderID),
    CONSTRAINT CK_ShelterPets_Type      CHECK (PetType IN ('Dog', 'Cat')),
    CONSTRAINT CK_ShelterPets_Gender    CHECK (Gender  IN ('Male', 'Female')),
    CONSTRAINT CK_ShelterPets_Age       CHECK (AgeMonths >= 0),
    CONSTRAINT CK_ShelterPets_Status    CHECK (Status  IN ('Available', 'Pending', 'Adopted'))
);

/* ---------- 11. AdoptionRequests : MANY-TO-MANY between Users and ShelterPets ----------
   A family can ask for many pets, a pet can get requests from many families.
   The shelter approves or declines and sets the visit time itself.                    */
CREATE TABLE AdoptionRequests (
    RequestID     INT IDENTITY(1,1)  NOT NULL,
    UserID        INT                NOT NULL,
    ShelterPetID  INT                NOT NULL,
    Message       NVARCHAR(500)      NULL,
    RequestedAt   DATETIME2(0)       NOT NULL CONSTRAINT DF_AdoptionRequests_RequestedAt DEFAULT SYSDATETIME(),
    VisitAt       DATETIME2(0)       NULL,
    Status        VARCHAR(10)        NOT NULL CONSTRAINT DF_AdoptionRequests_Status DEFAULT 'Pending',
    CONSTRAINT PK_AdoptionRequests             PRIMARY KEY (RequestID),
    CONSTRAINT UQ_AdoptionRequests_User_Pet    UNIQUE (UserID, ShelterPetID),          -- one request per family per pet
    CONSTRAINT FK_AdoptionRequests_Users       FOREIGN KEY (UserID)       REFERENCES Users(UserID),
    CONSTRAINT FK_AdoptionRequests_ShelterPets FOREIGN KEY (ShelterPetID) REFERENCES ShelterPets(ShelterPetID),
    CONSTRAINT CK_AdoptionRequests_Status      CHECK (Status IN ('Pending', 'Approved', 'Declined')),
    CONSTRAINT CK_AdoptionRequests_Visit       CHECK ((Status = 'Approved' AND VisitAt IS NOT NULL) OR (Status <> 'Approved' AND VisitAt IS NULL))
);

/* ---------- 12. Categories : shop categories ---------- */
CREATE TABLE Categories (
    CategoryID  INT IDENTITY(1,1)  NOT NULL,
    Name        NVARCHAR(30)       NOT NULL,
    CONSTRAINT PK_Categories      PRIMARY KEY (CategoryID),
    CONSTRAINT UQ_Categories_Name UNIQUE (Name)
);

/* ---------- 13. Products : shop products ---------- */
CREATE TABLE Products (
    ProductID    INT IDENTITY(1,1)  NOT NULL,
    CategoryID   INT                NOT NULL,
    Name         NVARCHAR(100)      NOT NULL,
    Description  NVARCHAR(1000)     NULL,
    PetType      VARCHAR(10)        NOT NULL,
    Price        DECIMAL(8,2)       NOT NULL,
    Stock        INT                NOT NULL CONSTRAINT DF_Products_Stock     DEFAULT 0,
    Status       VARCHAR(10)        NOT NULL CONSTRAINT DF_Products_Status    DEFAULT 'Active',
    ImageUrl     VARCHAR(300)       NULL,
    CreatedAt    DATETIME2(0)       NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Products            PRIMARY KEY (ProductID),
    CONSTRAINT UQ_Products_Name       UNIQUE (Name),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
    CONSTRAINT CK_Products_PetType    CHECK (PetType IN ('Dogs', 'Cats', 'Birds', 'Fish')),
    CONSTRAINT CK_Products_Price      CHECK (Price > 0),
    CONSTRAINT CK_Products_Stock      CHECK (Stock >= 0),
    CONSTRAINT CK_Products_Status     CHECK (Status IN ('Active', 'Inactive'))
);

/* ---------- 14. Orders : shop orders (card or cash on delivery) ---------- */
CREATE TABLE Orders (
    OrderID        INT IDENTITY(5001,1)  NOT NULL,
    UserID         INT                   NOT NULL,
    OrderDate      DATETIME2(0)          NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT SYSDATETIME(),
    CustomerName   NVARCHAR(100)         NOT NULL,     -- DENORMALIZED on purpose: a copy of the delivery details
    Phone          VARCHAR(20)           NOT NULL,     -- at checkout, so old orders don't change when the
    Address        NVARCHAR(200)         NOT NULL,     -- customer edits their profile later
    GovernorateID  INT                   NOT NULL,
    PostalCode     VARCHAR(10)           NULL,
    PaymentMethod  VARCHAR(4)            NOT NULL,
    CardLast4      CHAR(4)               NULL,
    PromoCode      VARCHAR(20)           NULL,
    Subtotal       DECIMAL(10,2)         NOT NULL CONSTRAINT DF_Orders_Subtotal DEFAULT 0,   -- filled by a trigger from OrderItems
    Discount       DECIMAL(10,2)         NOT NULL CONSTRAINT DF_Orders_Discount DEFAULT 0,   -- PET10 = 10 % off
    Total          AS (Subtotal - Discount),                                                -- computed column
    Status         VARCHAR(10)           NOT NULL CONSTRAINT DF_Orders_Status DEFAULT 'Processing',
    CONSTRAINT PK_Orders              PRIMARY KEY (OrderID),
    CONSTRAINT FK_Orders_Users        FOREIGN KEY (UserID)        REFERENCES Users(UserID),
    CONSTRAINT FK_Orders_Governorates FOREIGN KEY (GovernorateID) REFERENCES Governorates(GovernorateID),
    CONSTRAINT CK_Orders_Payment      CHECK (PaymentMethod IN ('Card', 'Cash')),
    CONSTRAINT CK_Orders_Card         CHECK ((PaymentMethod = 'Card' AND CardLast4 IS NOT NULL) OR (PaymentMethod = 'Cash' AND CardLast4 IS NULL)),
    CONSTRAINT CK_Orders_Status       CHECK (Status IN ('Processing', 'Shipped', 'Delivered', 'Cancelled'))
);

/* ---------- 15. OrderItems : MANY-TO-MANY between Orders and Products ---------- */
CREATE TABLE OrderItems (
    OrderID    INT            NOT NULL,
    ProductID  INT            NOT NULL,
    Quantity   SMALLINT       NOT NULL,
    UnitPrice  DECIMAL(8,2)   NOT NULL,          -- price at the time of the order (the product price may change later)
    LineTotal  AS (Quantity * UnitPrice),        -- computed column
    CONSTRAINT PK_OrderItems          PRIMARY KEY (OrderID, ProductID),     -- composite primary key
    CONSTRAINT FK_OrderItems_Orders   FOREIGN KEY (OrderID)   REFERENCES Orders(OrderID) ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductID) REFERENCES Products(ProductID),
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0)
);

/* ---------- 16. Wishlist : MANY-TO-MANY between Users and Products (the heart icon) ---------- */
CREATE TABLE Wishlist (
    UserID     INT           NOT NULL,
    ProductID  INT           NOT NULL,
    AddedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_Wishlist_AddedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Wishlist          PRIMARY KEY (UserID, ProductID),
    CONSTRAINT FK_Wishlist_Users    FOREIGN KEY (UserID)    REFERENCES Users(UserID),
    CONSTRAINT FK_Wishlist_Products FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

/* ---------- 17. Reviews : customer feedback (user/feedback.html) ---------- */
CREATE TABLE Reviews (
    ReviewID     INT IDENTITY(1,1)  NOT NULL,
    UserID       INT                NOT NULL,
    ProviderID   INT                NULL,         -- NULL when the feedback is about the Shop or the Website
    BookingID    INT                NULL,         -- set when it came from the "Rate" button on a completed booking
    ServiceType  VARCHAR(10)        NOT NULL,
    Rating       TINYINT            NOT NULL,
    Message      NVARCHAR(1000)     NULL,
    Status       VARCHAR(10)        NOT NULL CONSTRAINT DF_Reviews_Status    DEFAULT 'Pending',
    CreatedAt    DATETIME2(0)       NOT NULL CONSTRAINT DF_Reviews_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Reviews           PRIMARY KEY (ReviewID),
    CONSTRAINT FK_Reviews_Users     FOREIGN KEY (UserID)     REFERENCES Users(UserID),
    CONSTRAINT FK_Reviews_Providers FOREIGN KEY (ProviderID) REFERENCES Providers(ProviderID),
    CONSTRAINT FK_Reviews_Bookings  FOREIGN KEY (BookingID)  REFERENCES Bookings(BookingID),
    CONSTRAINT CK_Reviews_Service   CHECK (ServiceType IN ('Clinic', 'DayCare', 'Training', 'Walking', 'Adoption', 'Shop', 'Website')),
    CONSTRAINT CK_Reviews_Rating    CHECK (Rating BETWEEN 1 AND 5),
    CONSTRAINT CK_Reviews_Status    CHECK (Status IN ('Pending', 'Published', 'Hidden')),
    CONSTRAINT CK_Reviews_Provider  CHECK ((ServiceType IN ('Shop', 'Website') AND ProviderID IS NULL)
                                        OR (ServiceType NOT IN ('Shop', 'Website') AND ProviderID IS NOT NULL))
);

/* ---------- 18. Articles : the blog ---------- */
CREATE TABLE Articles (
    ArticleID    INT IDENTITY(1,1)  NOT NULL,
    Title        NVARCHAR(150)      NOT NULL,
    Slug         VARCHAR(150)       NOT NULL,      -- user/article-<slug>.html
    Category     NVARCHAR(30)       NOT NULL,
    AuthorName   NVARCHAR(100)      NOT NULL CONSTRAINT DF_Articles_Author DEFAULT N'mypet Team',
    Summary      NVARCHAR(300)      NULL,
    Content      NVARCHAR(MAX)      NOT NULL,
    CoverUrl     VARCHAR(300)       NULL,
    Status       VARCHAR(10)        NOT NULL CONSTRAINT DF_Articles_Status DEFAULT 'Draft',
    PublishedAt  DATE               NULL,
    CONSTRAINT PK_Articles          PRIMARY KEY (ArticleID),
    CONSTRAINT UQ_Articles_Title    UNIQUE (Title),
    CONSTRAINT UQ_Articles_Slug     UNIQUE (Slug),
    CONSTRAINT CK_Articles_Category CHECK (Category IN (N'Cat care', N'Dog care', N'Health', N'Home & safety', N'Nutrition', N'Training')),
    CONSTRAINT CK_Articles_Status   CHECK (Status IN ('Draft', 'Published'))
);
GO


/* ============================================================================
   PART C - INDEXES                                            (Day 2)

   CLUSTERED index      = the table itself, sorted by the key. Only ONE per table.
                          Every PRIMARY KEY above already made one automatically.
   NON-CLUSTERED index  = a separate sorted list that points back to the rows.
                          Many per table. Put them on columns used in WHERE / JOIN / ORDER BY
                          (foreign keys are the usual first choice).
   INCLUDE (...)        = extra columns stored in the index so the query never has
                          to open the table ("covering index").
   ============================================================================ */

-- CLUSTERED index on a column that is not the primary key (the PK of this table is NONCLUSTERED)
CREATE CLUSTERED INDEX CIX_BookingStatusLog_ChangedAt ON BookingStatusLog (ChangedAt);

-- NON-CLUSTERED indexes on foreign keys and search columns
CREATE NONCLUSTERED INDEX IX_Providers_Type_Area      ON Providers (ProviderType, AreaID) INCLUDE (BusinessName, Price, AvgRating);
CREATE NONCLUSTERED INDEX IX_Pets_OwnerID             ON Pets (OwnerID);
CREATE NONCLUSTERED INDEX IX_Bookings_Provider_Date   ON Bookings (ProviderID, BookingDate) INCLUDE (Status, TotalPrice);
CREATE NONCLUSTERED INDEX IX_Bookings_PetID           ON Bookings (PetID);
CREATE NONCLUSTERED INDEX IX_BookingStatusLog_Booking ON BookingStatusLog (BookingID);
CREATE NONCLUSTERED INDEX IX_ShelterPets_ShelterID    ON ShelterPets (ShelterID, Status);
CREATE NONCLUSTERED INDEX IX_AdoptionRequests_Pet     ON AdoptionRequests (ShelterPetID);
CREATE NONCLUSTERED INDEX IX_Products_Category        ON Products (CategoryID) INCLUDE (Price, Stock);
CREATE NONCLUSTERED INDEX IX_Orders_User_Date         ON Orders (UserID, OrderDate);
CREATE NONCLUSTERED INDEX IX_OrderItems_ProductID     ON OrderItems (ProductID);
CREATE NONCLUSTERED INDEX IX_Reviews_ProviderID       ON Reviews (ProviderID) INCLUDE (Rating, Status);

-- Filtered UNIQUE index: one review per booking, but many reviews may have no booking (NULL)
-- (a normal UNIQUE constraint would allow only ONE NULL)
CREATE UNIQUE NONCLUSTERED INDEX UX_Reviews_BookingID ON Reviews (BookingID) WHERE BookingID IS NOT NULL;
GO


/* ============================================================================
   PART D - FUNCTIONS                                          (Day 2)
   A function RETURNS a value (scalar) or a table (table-valued).
   It can be used inside SELECT, WHERE, JOIN ... but cannot change data.
   ============================================================================ */

-- Scalar: mypet's 10 % commission. The ONLY place the rate is written (like COMMISSION_RATE in base.js).
CREATE FUNCTION dbo.fn_Commission (@Amount DECIMAL(10,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN ROUND(@Amount * 0.10, 2);
END;
GO

-- Scalar: what the provider receives = invoice - commission
CREATE FUNCTION dbo.fn_ProviderPayout (@Amount DECIMAL(10,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN @Amount - dbo.fn_Commission(@Amount);
END;
GO

-- Scalar: stock label shown on admin/products.html
CREATE FUNCTION dbo.fn_StockLabel (@Stock INT)
RETURNS VARCHAR(12)
AS
BEGIN
    RETURN CASE
               WHEN @Stock = 0  THEN 'Out of stock'
               WHEN @Stock <= 5 THEN 'Low stock'
               ELSE                  'In stock'
           END;
END;
GO

-- Scalar: day code of a date ('Sat' ... 'Fri') to match ProviderHours.DayCode.
-- 6 Jan 1900 was a Saturday, so the remainder of the day difference / 7 gives 0 = Sat ... 6 = Fri.
-- (Works whatever the server language or DATEFIRST setting is.)
CREATE FUNCTION dbo.fn_DayCode (@Date DATE)
RETURNS CHAR(3)
AS
BEGIN
    RETURN CHOOSE(DATEDIFF(DAY, '19000106', @Date) % 7 + 1, 'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri');
END;
GO

-- Table-valued: active providers of one type, optionally in one governorate (the list pages + filters)
CREATE FUNCTION dbo.fn_FindProviders (@ProviderType VARCHAR(10), @Governorate NVARCHAR(50))
RETURNS TABLE
AS
RETURN
    SELECT p.ProviderID, p.BusinessName, g.Name AS Governorate, a.Name AS Area,
           p.Price, p.AvgRating, p.ReviewCount
    FROM Providers p
    INNER JOIN Users u        ON u.UserID = p.UserID
    INNER JOIN Areas a        ON a.AreaID = p.AreaID
    INNER JOIN Governorates g ON g.GovernorateID = a.GovernorateID
    WHERE p.ProviderType = @ProviderType
      AND u.Status = 'Active'
      AND (@Governorate IS NULL OR g.Name = @Governorate);
GO


/* ============================================================================
   PART E - VIEWS                                              (Day 2)
   A view is a saved SELECT that you query like a table.
   ============================================================================ */

-- admin/providers.html : one list of all business accounts
CREATE VIEW dbo.vw_ProviderDirectory
AS
SELECT p.ProviderID, p.BusinessName, p.ProviderType,
       g.Name  AS Governorate, a.Name AS Area, p.Phone,
       u.Email AS LoginEmail,  u.Status AS AccountStatus,
       p.Price, p.AvgRating, p.ReviewCount
FROM Providers p
INNER JOIN Users u        ON u.UserID = p.UserID
INNER JOIN Areas a        ON a.AreaID = p.AreaID
INNER JOIN Governorates g ON g.GovernorateID = a.GovernorateID;
GO

-- admin/bookings.html, user/my-bookings.html, provider appointments
CREATE VIEW dbo.vw_BookingDetails
AS
SELECT b.BookingID, b.BookingDate, b.StartTime, b.EndTime,
       u.UserID, u.FullName AS Customer,
       pt.PetID, pt.Name AS Pet, pt.PetType,
       p.ProviderID, p.BusinessName AS Provider, p.ProviderType AS Service,
       b.TotalPrice,
       dbo.fn_Commission(b.TotalPrice)    AS Commission,
       dbo.fn_ProviderPayout(b.TotalPrice) AS ProviderPayout,
       b.Status, b.PayoutStatus, b.CardLast4
FROM Bookings b
INNER JOIN Pets pt     ON pt.PetID = b.PetID
INNER JOIN Users u     ON u.UserID = pt.OwnerID
INNER JOIN Providers p ON p.ProviderID = b.ProviderID;
GO

-- admin/commissions.html and provider <type>-earnings.html
-- A booking becomes an invoice once it is Completed.
CREATE VIEW dbo.vw_ProviderEarnings
AS
SELECT p.ProviderID, p.BusinessName, p.ProviderType, b.PayoutStatus,
       COUNT(*)                                 AS Invoices,
       SUM(b.TotalPrice)                        AS InvoiceTotal,
       SUM(dbo.fn_Commission(b.TotalPrice))     AS Commission,
       SUM(dbo.fn_ProviderPayout(b.TotalPrice)) AS PayoutToProvider
FROM Bookings b
INNER JOIN Providers p ON p.ProviderID = b.ProviderID
WHERE b.Status = 'Completed'
GROUP BY p.ProviderID, p.BusinessName, p.ProviderType, b.PayoutStatus;
GO

-- admin/products.html
CREATE VIEW dbo.vw_ProductStock
AS
SELECT pr.ProductID, pr.Name, c.Name AS Category, pr.PetType, pr.Price, pr.Stock,
       dbo.fn_StockLabel(pr.Stock) AS StockLabel, pr.Status
FROM Products pr
INNER JOIN Categories c ON c.CategoryID = pr.CategoryID;
GO

-- admin/orders.html, user/my-orders.html
CREATE VIEW dbo.vw_OrderSummary
AS
SELECT o.OrderID, o.OrderDate, u.UserID, u.FullName AS Customer, g.Name AS City,
       (SELECT SUM(oi.Quantity) FROM OrderItems oi WHERE oi.OrderID = o.OrderID) AS Items,   -- subquery
       o.PaymentMethod, o.Subtotal, o.Discount, o.Total, o.Status
FROM Orders o
INNER JOIN Users u        ON u.UserID = o.UserID
INNER JOIN Governorates g ON g.GovernorateID = o.GovernorateID;
GO

-- admin/adoption-requests.html, provider/shelter-appointments.html
CREATE VIEW dbo.vw_AdoptionRequests
AS
SELECT r.RequestID, r.RequestedAt, u.FullName AS Applicant, g.Name AS City,
       sp.ShelterPetID, sp.Name AS Pet, sp.PetType,
       s.ProviderID AS ShelterID, s.BusinessName AS Shelter,
       r.VisitAt, r.Status
FROM AdoptionRequests r
INNER JOIN Users u        ON u.UserID = r.UserID
LEFT  JOIN Governorates g ON g.GovernorateID = u.GovernorateID      -- LEFT: a user may not have set a city
INNER JOIN ShelterPets sp ON sp.ShelterPetID = r.ShelterPetID
INNER JOIN Providers s    ON s.ProviderID = sp.ShelterID;
GO


/* ============================================================================
   PART F - STORED PROCEDURES                                  (Day 2)
   A procedure is saved code that can check rules, change data and use
   transactions. Run it with EXEC. Errors are raised with THROW.
   ============================================================================ */

-- user/signup.html
CREATE PROCEDURE dbo.sp_RegisterOwner
    @FullName  NVARCHAR(100),
    @Email     VARCHAR(150),
    @Phone     VARCHAR(20),
    @Password  VARCHAR(100),
    @NewUserID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM Users WHERE Email = @Email)
        THROW 50010, 'This e-mail is already registered.', 1;
    IF LEN(@Password) < 6
        THROW 50011, 'The password must have at least 6 characters.', 1;

    -- Demo only: a real back-end hashes the password itself (bcrypt / Argon2 with a salt)
    INSERT INTO Users (FullName, Email, Phone, PasswordHash, Role)
    VALUES (@FullName, @Email, @Phone, CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', @Password), 2), 'Owner');

    SET @NewUserID = SCOPE_IDENTITY();
END;
GO

-- admin/add-clinic.html, add-daycare, add-trainer, add-walker, add-shelter
-- Creates the login (Users) and the business (Providers) together: ONE-TO-ONE insert in a TRANSACTION.
CREATE PROCEDURE dbo.sp_AddProvider
    @ProviderType   VARCHAR(10),
    @BusinessName   NVARCHAR(100),
    @Governorate    NVARCHAR(50),
    @Area           NVARCHAR(60),
    @Phone          VARCHAR(20),
    @LoginEmail     VARCHAR(150),
    @FirstPassword  VARCHAR(100),
    @NewProviderID  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AreaID INT, @GovernorateID INT, @UserID INT;

    SELECT @AreaID = a.AreaID, @GovernorateID = g.GovernorateID
    FROM Areas a
    INNER JOIN Governorates g ON g.GovernorateID = a.GovernorateID
    WHERE g.Name = @Governorate AND a.Name = @Area;

    IF @AreaID IS NULL
        THROW 50020, 'Unknown governorate or area.', 1;
    IF EXISTS (SELECT 1 FROM Users WHERE Email = @LoginEmail)
        THROW 50021, 'This login e-mail is already used.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

            INSERT INTO Users (FullName, Email, Phone, PasswordHash, Role, Status, MustChangePassword, GovernorateID)
            VALUES (@BusinessName, @LoginEmail, @Phone,
                    CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', @FirstPassword), 2),
                    'Provider', 'Invited', 1, @GovernorateID);          -- "Invited" until the first sign-in
            SET @UserID = SCOPE_IDENTITY();

            INSERT INTO Providers (UserID, ProviderType, BusinessName, AreaID, Phone)
            VALUES (@UserID, @ProviderType, @BusinessName, @AreaID, @Phone);
            SET @NewProviderID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- nothing is saved if one insert fails
        THROW;
    END CATCH
END;
GO

-- user/clinic-booking.html, daycare-booking, training-booking, walking-booking
-- Checks every booking rule, works out the final price, saves the booking.
CREATE PROCEDURE dbo.sp_CreateBooking
    @PetID            INT,
    @ProviderID       INT,
    @BookingDate      DATE,
    @StartTime        TIME(0),
    @Hours            TINYINT       = NULL,   -- day care: 1 - 10
    @DurationMinutes  SMALLINT      = NULL,   -- walking: 30 or 60
    @SessionType      NVARCHAR(30)  = NULL,   -- training
    @Reason           NVARCHAR(50)  = NULL,   -- clinic
    @PickupAddress    NVARCHAR(200) = NULL,   -- walking
    @Notes            NVARCHAR(500) = NULL,
    @CardLast4        CHAR(4),
    @NewBookingID     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Type VARCHAR(10), @Price DECIMAL(8,2), @SlotMinutes TINYINT,
            @NoticeHours TINYINT, @AccountStatus VARCHAR(10);

    SELECT @Type = p.ProviderType, @Price = p.Price, @SlotMinutes = p.SlotMinutes,
           @NoticeHours = p.MinNoticeHours, @AccountStatus = u.Status
    FROM Providers p
    INNER JOIN Users u ON u.UserID = p.UserID
    WHERE p.ProviderID = @ProviderID;

    IF @Type IS NULL              THROW 50030, 'Provider not found.', 1;
    IF @Type = 'Shelter'          THROW 50031, 'Shelters are not booked: send an adoption request instead.', 1;
    IF @AccountStatus <> 'Active' THROW 50032, 'This provider is not taking bookings right now.', 1;
    IF @Price IS NULL             THROW 50033, 'This provider has not set a price yet.', 1;
    IF NOT EXISTS (SELECT 1 FROM Pets WHERE PetID = @PetID)
                                  THROW 50034, 'Pet not found.', 1;

    -- 1) length of the visit
    IF @Type = 'DayCare'
    BEGIN
        IF ISNULL(@Hours, 0) NOT BETWEEN 1 AND 10
            THROW 50035, 'Day care is booked for 1 to 10 hours.', 1;
        SET @DurationMinutes = NULL;
    END
    ELSE
    BEGIN
        SET @Hours = NULL;
        IF @Type = 'Walker' AND ISNULL(@DurationMinutes, 0) NOT IN (30, 60)
            THROW 50036, 'A walk is 30 or 60 minutes.', 1;
        IF @Type = 'Trainer' SET @DurationMinutes = 60;
        IF @Type = 'Clinic'  SET @DurationMinutes = @SlotMinutes;
    END

    DECLARE @EndTime TIME(0)     = DATEADD(MINUTE, COALESCE(@Hours * 60, @DurationMinutes), @StartTime);
    DECLARE @StartAt DATETIME2(0) = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), @StartTime),
                                            CAST(@BookingDate AS DATETIME2(0)));

    -- 2) not in the past, and respects the provider's minimum notice
    IF @StartAt < DATEADD(HOUR, @NoticeHours, SYSDATETIME())
        THROW 50037, 'This time is in the past or too soon for this provider.', 1;

    -- 3) open that day, not a day off, and inside opening hours
    DECLARE @IsOpen BIT, @Open TIME(0), @Close TIME(0);
    SELECT @IsOpen = IsOpen, @Open = OpenTime, @Close = CloseTime
    FROM ProviderHours
    WHERE ProviderID = @ProviderID AND DayCode = dbo.fn_DayCode(@BookingDate);

    IF ISNULL(@IsOpen, 0) = 0
       OR EXISTS (SELECT 1 FROM ProviderDaysOff WHERE ProviderID = @ProviderID AND OffDate = @BookingDate)
        THROW 50038, 'The provider is closed on this date.', 1;

    IF @StartTime < @Open OR @EndTime > @Close OR @EndTime <= @StartTime
        THROW 50039, 'The visit must start and end inside opening hours (day care: pick-up by closing time).', 1;

    -- 4) the time must be free (day care takes many pets at once, so it is not checked)
    IF @Type <> 'DayCare' AND EXISTS (
            SELECT 1 FROM Bookings
            WHERE ProviderID = @ProviderID AND BookingDate = @BookingDate AND Status = 'Confirmed'
              AND @StartTime < EndTime AND StartTime < @EndTime)        -- the two time ranges overlap
        THROW 50040, 'This time is already booked.', 1;

    -- 5) final price (nothing is paid at the visit)
    DECLARE @Total DECIMAL(8,2) = CASE @Type
                                      WHEN 'DayCare' THEN @Hours * @Price                   -- hours x price per hour
                                      WHEN 'Walker'  THEN @Price * (@DurationMinutes / 30)  -- price is per 30 minutes
                                      ELSE @Price                                           -- clinic fee / training session
                                  END;

    INSERT INTO Bookings (PetID, ProviderID, BookingDate, StartTime, Hours, DurationMinutes,
                          SessionType, Reason, PickupAddress, Notes, TotalPrice, CardLast4)
    VALUES (@PetID, @ProviderID, @BookingDate, @StartTime, @Hours, @DurationMinutes,
            @SessionType, @Reason, @PickupAddress, @Notes, @Total, @CardLast4);

    SET @NewBookingID = SCOPE_IDENTITY();   -- SCOPE_IDENTITY, not @@IDENTITY: the trigger also inserts a row
END;
GO

-- provider <type>-appointments.html and user/my-bookings.html
-- Confirmed -> Completed (the visit happened) or Confirmed -> Cancelled (refunded to the card)
CREATE PROCEDURE dbo.sp_UpdateBookingStatus
    @BookingID  INT,
    @NewStatus  VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewStatus NOT IN ('Completed', 'Cancelled')
        THROW 50050, 'The new status must be Completed or Cancelled.', 1;

    UPDATE Bookings
    SET Status = @NewStatus
    WHERE BookingID = @BookingID AND Status = 'Confirmed';

    IF @@ROWCOUNT = 0
        THROW 50051, 'Booking not found, or it is no longer Confirmed.', 1;

    IF @NewStatus = 'Cancelled'
        SELECT BookingID, TotalPrice AS RefundAmount,
               'Refunded to the card ending ' + CardLast4 AS Refund
        FROM Bookings
        WHERE BookingID = @BookingID;
END;
GO

-- admin/commissions.html : "Mark as paid" once mypet has sent the money
CREATE PROCEDURE dbo.sp_MarkProviderPaid
    @ProviderID    INT,
    @InvoicesPaid  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Bookings
    SET PayoutStatus = 'Paid'
    WHERE ProviderID = @ProviderID AND Status = 'Completed' AND PayoutStatus = 'Due';

    SET @InvoicesPaid = @@ROWCOUNT;
END;
GO

-- provider/shelter-appointments.html : the shelter approves (and sets the visit) or declines
CREATE PROCEDURE dbo.sp_ReviewAdoption
    @RequestID  INT,
    @Decision   VARCHAR(10),                -- 'Approved' or 'Declined'
    @VisitAt    DATETIME2(0) = NULL         -- needed when approving
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status VARCHAR(10), @PetID INT, @ShelterID INT;

    SELECT @Status = r.Status, @PetID = r.ShelterPetID, @ShelterID = sp.ShelterID
    FROM AdoptionRequests r
    INNER JOIN ShelterPets sp ON sp.ShelterPetID = r.ShelterPetID
    WHERE r.RequestID = @RequestID;

    IF @Status IS NULL        THROW 50070, 'Request not found.', 1;
    IF @Status <> 'Pending'   THROW 50071, 'This request was already answered.', 1;

    IF @Decision = 'Declined'
    BEGIN
        UPDATE AdoptionRequests SET Status = 'Declined' WHERE RequestID = @RequestID;
        RETURN;
    END

    IF @Decision <> 'Approved' THROW 50072, 'The decision must be Approved or Declined.', 1;
    IF @VisitAt IS NULL OR @VisitAt < SYSDATETIME()
                               THROW 50073, 'Choose a future visit time.', 1;

    -- The visit lasts 30 minutes and must end by closing time, not on a day off
    DECLARE @VisitDate DATE = CAST(@VisitAt AS DATE), @VisitTime TIME(0) = CAST(@VisitAt AS TIME(0));

    IF NOT EXISTS (SELECT 1 FROM ProviderHours
                   WHERE ProviderID = @ShelterID AND DayCode = dbo.fn_DayCode(@VisitDate) AND IsOpen = 1
                     AND @VisitTime >= OpenTime AND DATEADD(MINUTE, 30, @VisitTime) <= CloseTime)
       OR EXISTS (SELECT 1 FROM ProviderDaysOff WHERE ProviderID = @ShelterID AND OffDate = @VisitDate)
        THROW 50074, 'The visit must be inside the shelter''s opening hours and not on a day off.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE AdoptionRequests SET Status = 'Approved', VisitAt = @VisitAt WHERE RequestID = @RequestID;
            UPDATE ShelterPets      SET Status = 'Pending'                     WHERE ShelterPetID = @PetID;   -- on hold until the visit
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- user/my-bookings.html
CREATE PROCEDURE dbo.sp_GetMyBookings
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT BookingID, BookingDate, StartTime, EndTime, Pet, Provider, Service, TotalPrice, Status,
           'Paid by card' AS Payment
    FROM dbo.vw_BookingDetails
    WHERE UserID = @UserID
    ORDER BY BookingDate DESC, StartTime DESC;
END;
GO


/* ============================================================================
   PART G - TRIGGERS                                           (Day 2)
   A trigger runs by itself when rows are inserted / updated / deleted.
   Inside it, "inserted" holds the new rows and "deleted" holds the old rows.
   ============================================================================ */

-- 1) Keep a history of every booking status (new booking, completed, cancelled)
CREATE TRIGGER trg_Bookings_LogStatus
ON Bookings
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BookingStatusLog (BookingID, OldStatus, NewStatus)
    SELECT i.BookingID, d.Status, i.Status
    FROM inserted i
    LEFT JOIN deleted d ON d.BookingID = i.BookingID
    WHERE d.BookingID IS NULL          -- a new booking (INSERT has no "deleted" row)
       OR d.Status <> i.Status;        -- the status changed
END;
GO

-- 2) When items are added to an order: check stock, take it out of stock, work out the order totals
CREATE TRIGGER trg_OrderItems_AfterInsert
ON OrderItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM (SELECT ProductID, SUM(Quantity) AS Qty FROM inserted GROUP BY ProductID) i
               INNER JOIN Products p ON p.ProductID = i.ProductID
               WHERE p.Stock < i.Qty OR p.Status <> 'Active')
        THROW 50060, 'A product in this order is out of stock or not for sale.', 1;   -- cancels the whole insert

    UPDATE p
    SET p.Stock = p.Stock - i.Qty
    FROM Products p
    INNER JOIN (SELECT ProductID, SUM(Quantity) AS Qty FROM inserted GROUP BY ProductID) i
            ON i.ProductID = p.ProductID;

    UPDATE o
    SET o.Subtotal = t.Subtotal,
        o.Discount = CASE WHEN o.PromoCode = 'PET10' THEN ROUND(t.Subtotal * 0.10, 2) ELSE 0 END
    FROM Orders o
    INNER JOIN (SELECT OrderID, SUM(Quantity * UnitPrice) AS Subtotal
                FROM OrderItems
                WHERE OrderID IN (SELECT OrderID FROM inserted)
                GROUP BY OrderID) t ON t.OrderID = o.OrderID;
END;
GO

-- 3) When an order is cancelled, put its items back in stock
CREATE TRIGGER trg_Orders_Cancelled
ON Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Status) RETURN;

    UPDATE p
    SET p.Stock = p.Stock + x.Qty
    FROM Products p
    INNER JOIN (SELECT oi.ProductID, SUM(oi.Quantity) AS Qty
                FROM inserted i
                INNER JOIN deleted d     ON d.OrderID = i.OrderID
                INNER JOIN OrderItems oi ON oi.OrderID = i.OrderID
                WHERE i.Status = 'Cancelled' AND d.Status <> 'Cancelled'
                GROUP BY oi.ProductID) x ON x.ProductID = p.ProductID;
END;
GO

-- 4) Keep Providers.AvgRating and ReviewCount up to date (hidden reviews don't count)
CREATE TRIGGER trg_Reviews_UpdateRating
ON Reviews
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.AvgRating   = ISNULL(r.AvgRating, 0),
        p.ReviewCount = ISNULL(r.ReviewCount, 0)
    FROM Providers p
    LEFT JOIN (SELECT ProviderID,
                      CAST(AVG(CAST(Rating AS DECIMAL(4,2))) AS DECIMAL(3,2)) AS AvgRating,
                      COUNT(*) AS ReviewCount
               FROM Reviews
               WHERE Status <> 'Hidden' AND ProviderID IS NOT NULL
               GROUP BY ProviderID) r ON r.ProviderID = p.ProviderID
    WHERE p.ProviderID IN (SELECT ProviderID FROM inserted
                           UNION
                           SELECT ProviderID FROM deleted);
END;
GO

-- 5) Providers are never deleted: DELETE suspends the account instead (INSTEAD OF trigger)
CREATE TRIGGER trg_Providers_NoDelete
ON Providers
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE u
    SET u.Status = 'Suspended'
    FROM Users u
    INNER JOIN deleted d ON d.UserID = u.UserID;

    PRINT 'Providers are not deleted: the account was suspended instead.';
END;
GO


/* ============================================================================
   PART H - SAMPLE DATA (INSERT)                               (Day 1)
   The same names as the front-end demo pages.
   The triggers above are already active, so stock, order totals and ratings
   fill in by themselves.
   ============================================================================ */

-- Governorates: ids 1 Ajloun, 2 Amman, 3 Aqaba, 4 Balqa, 5 Irbid, 6 Jerash,
--               7 Karak, 8 Ma'an, 9 Madaba, 10 Mafraq, 11 Tafilah, 12 Zarqa
INSERT INTO Governorates (Name) VALUES
(N'Ajloun'), (N'Amman'), (N'Aqaba'), (N'Balqa'), (N'Irbid'), (N'Jerash'),
(N'Karak'), (N'Ma''an'), (N'Madaba'), (N'Mafraq'), (N'Tafilah'), (N'Zarqa');

-- Areas (the AREAS list in assets/js/base.js). INSERT ... SELECT finds each governorate's id by name.
INSERT INTO Areas (GovernorateID, Name)
SELECT g.GovernorateID, v.AreaName
FROM (VALUES
    (N'Ajloun', N'Ajloun City'), (N'Ajloun', N'Ain Janna'), (N'Ajloun', N'Anjara'), (N'Ajloun', N'Kufranjah'),
    (N'Ajloun', N'Orjan'), (N'Ajloun', N'Sakhra'),
    (N'Amman', N'Abdali'), (N'Amman', N'Abdoun'), (N'Amman', N'Abu Nseir'), (N'Amman', N'Al-Jubeiha'),
    (N'Amman', N'Al-Rabiah'), (N'Amman', N'Dabouq'), (N'Amman', N'Jabal Al-Hussein'), (N'Amman', N'Jabal Al-Weibdeh'),
    (N'Amman', N'Jabal Amman'), (N'Amman', N'Khalda'), (N'Amman', N'Marj Al-Hamam'), (N'Amman', N'Marka'),
    (N'Amman', N'Naour'), (N'Amman', N'Sahab'), (N'Amman', N'Shafa Badran'), (N'Amman', N'Shmeisani'),
    (N'Amman', N'Sweifieh'), (N'Amman', N'Sweileh'), (N'Amman', N'Tla'' Al-Ali'), (N'Amman', N'Umm Al-Summaq'),
    (N'Amman', N'Umm Uthaina'), (N'Amman', N'Wadi Al-Seer'),
    (N'Aqaba', N'Aqaba City'), (N'Aqaba', N'Al-Quwayra'), (N'Aqaba', N'Tala Bay'), (N'Aqaba', N'Wadi Rum'),
    (N'Balqa', N'Salt'), (N'Balqa', N'Ain Al-Basha'), (N'Balqa', N'Deir Alla'), (N'Balqa', N'Fuheis'),
    (N'Balqa', N'Mahis'), (N'Balqa', N'South Shouneh'),
    (N'Irbid', N'Irbid City'), (N'Irbid', N'Al-Husn'), (N'Irbid', N'Al-Mazar Al-Shamali'), (N'Irbid', N'Al-Taybeh'),
    (N'Irbid', N'Aydoun'), (N'Irbid', N'Bushra'), (N'Irbid', N'Deir Abu Said'), (N'Irbid', N'Huwwarah'),
    (N'Irbid', N'North Shouneh'), (N'Irbid', N'Ramtha'),
    (N'Jerash', N'Jerash City'), (N'Jerash', N'Al-Mastaba'), (N'Jerash', N'Burma'), (N'Jerash', N'Sakib'),
    (N'Jerash', N'Souf'),
    (N'Karak', N'Karak City'), (N'Karak', N'Al-Mazar Al-Janoubi'), (N'Karak', N'Al-Qasr'), (N'Karak', N'Al-Qatraneh'),
    (N'Karak', N'Ghor Al-Safi'), (N'Karak', N'Mu''tah'),
    (N'Ma''an', N'Ma''an City'), (N'Ma''an', N'Al-Husseiniya'), (N'Ma''an', N'Al-Jafr'), (N'Ma''an', N'Al-Shoubak'),
    (N'Ma''an', N'Wadi Musa (Petra)'),
    (N'Madaba', N'Madaba City'), (N'Madaba', N'Dhiban'), (N'Madaba', N'Ma''in'),
    (N'Mafraq', N'Mafraq City'), (N'Mafraq', N'Al-Khalidiya'), (N'Mafraq', N'Rihab'), (N'Mafraq', N'Ruwaished'),
    (N'Mafraq', N'Sabha'), (N'Mafraq', N'Umm Al-Jimal'),
    (N'Tafilah', N'Tafilah City'), (N'Tafilah', N'Al-Hasa'), (N'Tafilah', N'Busayra'),
    (N'Zarqa', N'Zarqa City'), (N'Zarqa', N'Al-Azraq'), (N'Zarqa', N'Al-Dhulail'), (N'Zarqa', N'Al-Hashimiyya'),
    (N'Zarqa', N'Birein'), (N'Zarqa', N'Russeifa')
) AS v(Governorate, AreaName)
INNER JOIN Governorates g ON g.Name = v.Governorate;

-- Users. Demo password for every account: Pass@123 (the stored value is its SHA-256 hash)
DECLARE @pw VARCHAR(255) = CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', 'Pass@123'), 2);

INSERT INTO Users (FullName, Email, Phone, PasswordHash, Role, Status, MustChangePassword, GovernorateID, CreatedAt) VALUES
-- 1  admin
(N'mypet Admin',                              'admin@mypet.com',          '0790000000', @pw, 'Admin',    'Active',    0, 2,  '2026-01-01'),
-- 2 - 6  pet owners
(N'Sara Jawabreh',                            'sara@example.com',         '0791000001', @pw, 'Owner',    'Active',    0, 2,  '2026-03-14'),
(N'Hala Masri',                               'hala@example.com',         '0791000002', @pw, 'Owner',    'Active',    0, 5,  '2026-05-02'),
(N'Lina Odeh',                                'lina@example.com',         '0791000003', @pw, 'Owner',    'Active',    0, 12, '2026-06-21'),
(N'Ziad Haddad',                              'ziad@example.com',         '0791000004', @pw, 'Owner',    'Active',    0, 2,  '2026-07-09'),
(N'Mona Yousef',                              'mona@example.com',         '0791000005', @pw, 'Owner',    'Suspended', 0, 3,  '2026-09-30'),
-- 7 - 18  provider logins (same order as the Providers rows below)
(N'Gold Veterinary Clinic for Pet Medicine',  'clinic@mypet.com',         '0792000001', @pw, 'Provider', 'Active',    0, 5,  '2026-02-01'),
(N'Hope Veterinary Clinic',                   'hope.clinic@example.com',  '0792000002', @pw, 'Provider', 'Active',    0, 2,  '2026-02-10'),
(N'Amman Animal Hospital',                    'amman.hospital@example.com','0792000003', @pw, 'Provider', 'Suspended', 0, 2,  '2026-02-15'),
(N'Cozy Paws Day Care',                       'daycare@mypet.com',        '0792000004', @pw, 'Provider', 'Active',    0, 2,  '2026-03-01'),
(N'Happy Tails Boarding',                     'happytails@example.com',   '0792000005', @pw, 'Provider', 'Active',    0, 12, '2026-03-05'),
(N'Paw Palace Boarding',                      'pawpalace@example.com',    '0792000006', @pw, 'Provider', 'Suspended', 0, 5,  '2026-03-08'),
(N'Khalid Mansour',                           'trainer@mypet.com',        '0792000007', @pw, 'Provider', 'Active',    0, 2,  '2026-04-01'),
(N'Dana Barakat',                             'dana.trainer@example.com', '0792000008', @pw, 'Provider', 'Invited',   1, 2,  '2026-10-28'),
(N'Omar Khaled',                              'walker@mypet.com',         '0792000009', @pw, 'Provider', 'Active',    0, 2,  '2026-04-12'),
(N'Rana Fares',                               'rana.walker@example.com',  '0792000010', @pw, 'Provider', 'Active',    0, 2,  '2026-04-20'),
(N'Mercy Shelter',                            'shelter@mypet.com',        '0792000011', @pw, 'Provider', 'Active',    0, 2,  '2026-01-20'),
(N'Hope Association',                         'hope.shelter@example.com', '0792000012', @pw, 'Provider', 'Invited',   1, 2,  '2026-10-30');

-- Providers 1 - 12 (UserID 7 - 18). The area id is looked up by name with a subquery.
INSERT INTO Providers (UserID, ProviderType, BusinessName, AreaID, Phone, About, Price, Specialty, YearsExperience, SlotMinutes, MinNoticeHours) VALUES
(7,  'Clinic',  N'Gold Veterinary Clinic for Pet Medicine', (SELECT AreaID FROM Areas WHERE Name = N'Aydoun'),      '0792000001', N'Full-service vet clinic: checkups, vaccines, dental care and surgery.', 15.00, NULL, NULL, 30, 2),
(8,  'Clinic',  N'Hope Veterinary Clinic',                  (SELECT AreaID FROM Areas WHERE Name = N'Abdoun'),      '0792000002', N'Friendly neighbourhood clinic for cats and dogs.',                     12.00, NULL, NULL, 30, 2),
(9,  'Clinic',  N'Amman Animal Hospital',                   (SELECT AreaID FROM Areas WHERE Name = N'Shmeisani'),   '0792000003', N'24-hour animal hospital.',                                             20.00, NULL, NULL, 30, 2),
(10, 'DayCare', N'Cozy Paws Day Care',                      (SELECT AreaID FROM Areas WHERE Name = N'Khalda'),      '0792000004', N'Daytime care with play areas and a garden.',                            2.00, NULL, NULL, 30, 2),
(11, 'DayCare', N'Happy Tails Boarding',                    (SELECT AreaID FROM Areas WHERE Name = N'Zarqa City'),  '0792000005', N'Small groups, lots of attention.',                                      2.50, NULL, NULL, 30, 2),
(12, 'DayCare', N'Paw Palace Boarding',                     (SELECT AreaID FROM Areas WHERE Name = N'Irbid City'),  '0792000006', N'Air-conditioned rooms and daily photo updates.',                        3.00, NULL, NULL, 30, 2),
(13, 'Trainer', N'Khalid Mansour',                          (SELECT AreaID FROM Areas WHERE Name = N'Khalda'),      '0792000007', N'Positive-reinforcement trainer for puppies and adult dogs.',          15.00, N'Obedience training', 6, 60, 12),
(14, 'Trainer', N'Dana Barakat',                            (SELECT AreaID FROM Areas WHERE Name = N'Dabouq'),      '0792000008', NULL,                                                                     NULL, NULL, NULL, 60, 0),
(15, 'Walker',  N'Omar Khaled',                             (SELECT AreaID FROM Areas WHERE Name = N'Sweifieh'),    '0792000009', N'Daily walks around Sweifieh and Abdoun.',                               5.00, NULL, NULL, 30, 2),
(16, 'Walker',  N'Rana Fares',                              (SELECT AreaID FROM Areas WHERE Name = N'Jabal Amman'), '0792000010', N'Calm walks for small and senior dogs.',                                 4.00, NULL, NULL, 30, 2),
(17, 'Shelter', N'Mercy Shelter',                           (SELECT AreaID FROM Areas WHERE Name = N'Abu Nseir'),   '0792000011', N'Rescue shelter for cats and dogs. Adoption is free.',                   NULL, NULL, NULL, 30, 0),
(18, 'Shelter', N'Hope Association',                        (SELECT AreaID FROM Areas WHERE Name = N'Marka'),       '0792000012', NULL,                                                                     NULL, NULL, NULL, 30, 0);

-- Opening hours for every provider and every day (CROSS JOIN = every provider x every day)
-- Friday is closed except for shelters, which are open daily 9:00 - 17:00.
INSERT INTO ProviderHours (ProviderID, DayCode, IsOpen, OpenTime, CloseTime)
SELECT p.ProviderID,
       d.DayCode,
       CASE WHEN d.DayCode = 'Fri' AND p.ProviderType <> 'Shelter' THEN 0 ELSE 1 END,
       CASE p.ProviderType WHEN 'DayCare' THEN '08:00' WHEN 'Walker' THEN '07:00' ELSE '09:00' END,
       CASE p.ProviderType WHEN 'Clinic'  THEN '21:00' WHEN 'DayCare' THEN '18:00'
                           WHEN 'Shelter' THEN '17:00' ELSE '20:00' END
FROM Providers p
CROSS JOIN (VALUES ('Sat'), ('Sun'), ('Mon'), ('Tue'), ('Wed'), ('Thu'), ('Fri')) AS d(DayCode);

INSERT INTO ProviderDaysOff (ProviderID, OffDate, Reason) VALUES
(1,  '2026-11-20', N'Staff training'),
(4,  '2026-12-25', N'Public holiday'),
(11, '2026-11-21', N'Vaccination campaign');

-- Pets 1 - 7 (OwnerID = UserID of the owner)
INSERT INTO Pets (OwnerID, Name, PetType, AgeYears) VALUES
(2, N'Max',   'Dog',  3),     -- 1  Sara
(2, N'Luna',  'Cat',  2),     -- 2  Sara
(3, N'Bella', 'Dog',  5),     -- 3  Hala
(4, N'Kiwi',  'Bird', 1),     -- 4  Lina
(5, N'Rocky', 'Dog',  4),     -- 5  Ziad
(5, N'Nemo',  'Fish', 1),     -- 6  Ziad
(6, N'Milo',  'Cat',  0.5);   -- 7  Mona

-- Bookings 1001 - 1012 (past ones are Completed / Cancelled, future ones Confirmed)
INSERT INTO Bookings (PetID, ProviderID, BookingDate, StartTime, Hours, DurationMinutes, SessionType, Reason, PickupAddress, TotalPrice, CardLast4, Status, PayoutStatus) VALUES
(1, 1,  '2026-10-24', '10:00', NULL, 30, NULL,                        N'Vaccination',     NULL,                         15.00, '4242', 'Completed', 'Paid'),  -- 1001
(2, 4,  '2026-10-26', '09:00', 4,    NULL, NULL,                      NULL,               NULL,                          8.00, '4242', 'Completed', 'Paid'),  -- 1002  4 h x 2.00
(1, 7,  '2026-10-28', '17:00', NULL, 60, N'Private session - 60 min', NULL,               NULL,                         15.00, '4242', 'Completed', 'Paid'),  -- 1003
(3, 9,  '2026-11-01', '08:00', NULL, 60, NULL,                        NULL,               N'Sweifieh, Building 12',     10.00, '5511', 'Completed', 'Due'),   -- 1004  60 min = 2 x 5.00
(5, 2,  '2026-11-02', '11:00', NULL, 30, NULL,                        N'Dental care',     NULL,                         12.00, '1881', 'Completed', 'Due'),   -- 1005
(4, 1,  '2026-11-03', '12:00', NULL, 30, NULL,                        N'Routine checkup', NULL,                         15.00, '7340', 'Cancelled', 'Due'),   -- 1006  refunded
(7, 5,  '2026-11-03', '10:00', 6,    NULL, NULL,                      NULL,               NULL,                         15.00, '9012', 'Completed', 'Due'),   -- 1007  6 h x 2.50
(1, 1,  '2026-11-09', '10:30', NULL, 30, NULL,                        N'Routine checkup', NULL,                         15.00, '4242', 'Confirmed', 'Due'),   -- 1008
(2, 4,  '2026-11-10', '08:00', 8,    NULL, NULL,                      NULL,               NULL,                         16.00, '4242', 'Confirmed', 'Due'),   -- 1009  pick-up 16:00
(5, 10, '2026-11-08', '07:30', NULL, 30, NULL,                        NULL,               N'Abdoun, Street 5',           4.00, '1881', 'Confirmed', 'Due'),   -- 1010
(3, 7,  '2026-11-11', '18:00', NULL, 60, N'Group session - 60 min',   NULL,               NULL,                         15.00, '5511', 'Confirmed', 'Due'),   -- 1011
(5, 9,  '2026-10-27', '08:00', NULL, 30, NULL,                        NULL,               N'Abdoun, Street 5',           5.00, '1881', 'Completed', 'Paid');  -- 1012

-- Shelter pets (the adoption page): Mercy Shelter = provider 11, Hope Association = provider 12
INSERT INTO ShelterPets (ShelterID, Name, PetType, Breed, Gender, AgeMonths, About, Status) VALUES
(11, N'Lulu',  'Cat', N'Domestic Shorthair', 'Female', 12, N'A calm cat who loves window seats and gentle cuddles.', 'Available'),  -- 1
(11, N'Simba', 'Cat', N'Tabby mix',          'Male',   36, N'A friendly cat who enjoys company and a good sunny spot.', 'Available'), -- 2
(11, N'Sky',   'Dog', N'Jack Russell mix',   'Male',    6, N'A playful puppy full of energy.', 'Available'),                         -- 3
(12, N'Coco',  'Cat', N'Ginger Tabby',       'Female',  8, N'A curious kitten who loves toys.', 'Available'),                        -- 4
(12, N'Rex',   'Dog', N'Poodle mix',         'Male',   24, N'A gentle dog who loves long walks and belly rubs.', 'Available'),       -- 5
(11, N'Nala',  'Cat', N'Siamese mix',        'Female', 18, N'Already found her family.', 'Adopted');                                 -- 6

INSERT INTO AdoptionRequests (UserID, ShelterPetID, Message, RequestedAt, VisitAt, Status) VALUES
(2, 1, N'We have a quiet home and a balcony.',   '2026-11-02 10:15', NULL,               'Pending'),
(4, 5, N'We have a garden and walk every day.',  '2026-11-03 18:40', NULL,               'Pending'),
(6, 4, NULL,                                     '2026-11-04 09:05', NULL,               'Pending'),
(3, 3, N'Our kids would love a puppy.',          '2026-10-29 12:00', '2026-11-08 11:00', 'Approved'),
(5, 2, NULL,                                     '2026-10-20 16:30', NULL,               'Declined'),
(5, 6, N'Looking for a calm cat.',               '2026-10-05 14:00', '2026-10-10 10:00', 'Approved');

UPDATE ShelterPets SET Status = 'Pending' WHERE ShelterPetID = 3;   -- Sky has an approved visit

-- Shop
INSERT INTO Categories (Name) VALUES (N'Food'), (N'Toys'), (N'Accessories'), (N'Grooming');   -- 1 - 4

INSERT INTO Products (CategoryID, Name, Description, PetType, Price, Stock, Status) VALUES
(1, N'Royal Canin Cat Food',  N'Complete dry food for adult cats.',         'Cats',  12.00, 43, 'Active'),
(2, N'Interactive Cat Ball',  N'Rolling ball with a bell inside.',          'Cats',   6.00,  0, 'Active'),
(4, N'Dog Care Shampoo',      N'Gentle shampoo for sensitive skin.',        'Dogs',   9.00, 25, 'Active'),
(3, N'Dog Walking Collar',    N'Adjustable padded collar.',                 'Dogs',   8.00, 30, 'Active'),
(3, N'Small Bird Cage',       N'Cage with two perches and feeders.',        'Birds', 18.00,  5, 'Active'),
(1, N'Vitamin Supplement',    N'Daily vitamins for healthy joints.',        'Dogs',  14.00, 20, 'Active'),
(1, N'Premium Dog Food 5kg',  N'Grain-free food with real chicken.',        'Dogs',  22.00, 36, 'Active'),
(3, N'Cat Scratching Post',   N'Sisal post with a soft top.',               'Cats',  15.00, 14, 'Active'),
(1, N'Bird Seed Mix',         N'Mixed seeds for small birds.',              'Birds',  5.00, 54, 'Active'),
(3, N'Aquarium Starter Kit',  N'20 L tank with filter and light.',          'Fish',  35.00,  7, 'Active'),
(1, N'Fish Flakes 200g',      N'Daily food for tropical fish.',             'Fish',   4.00, 63, 'Active'),
(2, N'Chew Bone Toy',         N'Tough rubber bone for strong chewers.',     'Dogs',   5.00, 47, 'Inactive');

-- Orders 5001 - 5006 (Subtotal and Discount are filled by the trigger when the items go in)
INSERT INTO Orders (UserID, OrderDate, CustomerName, Phone, Address, GovernorateID, PostalCode, PaymentMethod, CardLast4, PromoCode, Status) VALUES
(2, '2026-10-12 14:20', N'Sara Jawabreh', '0791000001', N'Khalda, Street 8, Building 3',    2,  '11953', 'Card', '4242', 'PET10', 'Delivered'),  -- 5001
(3, '2026-10-18 09:45', N'Hala Masri',    '0791000002', N'Aydoun, Main Street',             5,  '21110', 'Cash', NULL,   NULL,    'Delivered'),  -- 5002
(5, '2026-10-25 19:10', N'Ziad Haddad',   '0791000004', N'Abdoun, Street 5',                2,  '11183', 'Card', '1881', NULL,    'Delivered'),  -- 5003
(4, '2026-11-01 11:30', N'Lina Odeh',     '0791000003', N'Zarqa City, Al-Malek Street',     12, '13110', 'Cash', NULL,   NULL,    'Shipped'),    -- 5004
(6, '2026-11-03 16:05', N'Mona Yousef',   '0791000005', N'Aqaba City, Corniche Street',     3,  '77110', 'Card', '9012', 'PET10', 'Processing'), -- 5005
(2, '2026-11-04 08:50', N'Sara Jawabreh', '0791000001', N'Khalda, Street 8, Building 3',    2,  '11953', 'Card', '4242', NULL,    'Processing'); -- 5006

-- Order items: the unit price is copied from Products at the time of the order
-- (the Chew Bone Toy is turned on for these old orders and switched off afterwards)
UPDATE Products SET Status = 'Active' WHERE Name = N'Chew Bone Toy';

INSERT INTO OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT v.OrderID, p.ProductID, v.Quantity, p.Price
FROM (VALUES
    (5001, N'Royal Canin Cat Food', 2), (5001, N'Cat Scratching Post', 1),
    (5002, N'Premium Dog Food 5kg', 1), (5002, N'Chew Bone Toy', 2),
    (5003, N'Aquarium Starter Kit', 1), (5003, N'Fish Flakes 200g', 3),
    (5004, N'Bird Seed Mix', 4),        (5004, N'Small Bird Cage', 1),
    (5005, N'Royal Canin Cat Food', 1), (5005, N'Cat Scratching Post', 1),
    (5006, N'Dog Care Shampoo', 2),     (5006, N'Dog Walking Collar', 1)
) AS v(OrderID, ProductName, Quantity)
INNER JOIN Products p ON p.Name = v.ProductName;

UPDATE Products SET Status = 'Inactive' WHERE Name = N'Chew Bone Toy';

-- Sara cancels order 5006 -> the trigger puts the shampoo and collar back in stock
UPDATE Orders SET Status = 'Cancelled' WHERE OrderID = 5006;

INSERT INTO Wishlist (UserID, ProductID) VALUES (2, 2), (2, 7), (4, 5), (6, 8);

-- Reviews (the trigger works out each provider's AvgRating and ReviewCount)
INSERT INTO Reviews (UserID, ProviderID, BookingID, ServiceType, Rating, Message, Status, CreatedAt) VALUES
(2, 1,    1001, 'Clinic',   5, N'Very kind with Max during his vaccination.',   'Published', '2026-10-24 18:00'),
(2, 4,    1002, 'DayCare',  4, N'Luna came home happy and relaxed.',            'Published', '2026-10-26 20:00'),
(2, 7,    1003, 'Training', 5, N'Max finally walks on a loose lead!',           'Published', '2026-10-29 09:00'),
(3, 9,    1004, 'Walking',  4, N'On time and sent photos during the walk.',     'Pending',   '2026-11-01 12:00'),
(5, 2,    1005, 'Clinic',   3, N'Good care, but we waited 20 minutes.',         'Published', '2026-11-02 15:00'),
(6, 5,    1007, 'DayCare',  1, N'(removed by the admin: offensive language)',   'Hidden',    '2026-11-03 19:00'),
(5, 9,    1012, 'Walking',  5, N'Rocky loves Omar.',                            'Published', '2026-10-27 13:00'),
(5, 11,   NULL, 'Adoption', 5, N'Nala settled in perfectly. Thank you!',        'Published', '2026-10-15 10:00'),
(4, NULL, NULL, 'Shop',     5, N'Fast delivery to Zarqa.',                      'Published', '2026-11-03 10:00'),
(2, NULL, NULL, 'Website',  4, N'Easy to book, would love a mobile app.',       'Pending',   '2026-11-04 21:00');

-- Blog
INSERT INTO Articles (Title, Slug, Category, AuthorName, Summary, Content, Status, PublishedAt) VALUES
(N'5 Tips to Settle Your New Cat at Home', '5-tips-to-settle-your-new-cat-at-home', N'Cat care',      N'mypet Team',      N'Help a new cat feel safe in its first week.',      N'Give your cat one quiet room first ...',             'Published', '2026-09-02'),
(N'Basic Obedience Training',              'basic-obedience-training',              N'Training',      N'Khalid Mansour',  N'Sit, stay and come: where to start.',             N'Keep sessions short and positive ...',               'Published', '2026-09-10'),
(N'Benefits of Daily Walks',               'benefits-of-daily-walks',               N'Dog care',      N'mypet Team',      N'Why a daily walk matters for body and mind.',     N'Walking keeps joints healthy ...',                   'Published', '2026-09-18'),
(N'Best Nutrition for Puppies',            'best-nutrition-for-puppies',            N'Nutrition',     N'mypet Team',      N'What a growing puppy needs on its plate.',        N'Puppies need more protein than adult dogs ...',      'Published', '2026-09-25'),
(N'Dental Care Basics',                    'dental-care-basics',                    N'Health',        N'Gold Veterinary Clinic', N'Simple habits that prevent dental disease.', N'Brush two or three times a week ...',               'Published', '2026-10-03'),
(N'Dog Vaccination Schedule',              'dog-vaccination-schedule',              N'Health',        N'Gold Veterinary Clinic', N'Which vaccines and when.',                   N'The first vaccines start at 6 to 8 weeks ...',       'Published', '2026-10-12'),
(N'Preparing a Pet-Safe Home',             'preparing-a-pet-safe-home',             N'Home & safety', N'mypet Team',      N'Hidden dangers to remove before a pet arrives.',  N'Keep cables, plants and cleaning products away ...', 'Draft',     NULL);
GO

PRINT 'MyPetDB is ready. Open 02_practice_queries.sql to try every topic.';
GO
