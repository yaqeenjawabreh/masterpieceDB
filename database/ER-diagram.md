# mypet – ER diagram (MyPetDB)

Paste the code block below into https://mermaid.live to edit it or export PNG/SVG.
It also renders directly on GitHub, and in VS Code with the "Markdown Preview Mermaid Support" extension.
`ER-diagram.html` shows the same diagram in the browser, and `ER-diagram.png` is a ready image.

**How to read the lines (crow's foot):** `||` exactly one · `|o` zero or one · `|{` one or more · `o{` zero or more.
**Keys:** PK = primary key · FK = foreign key · UK = unique.

```mermaid
erDiagram
    Governorates ||--o{ Areas            : "has"
    Governorates |o--o{ Users            : "home of"
    Governorates ||--o{ Orders           : "delivered to"
    Areas        ||--o{ Providers        : "located in"
    Users        ||--o| Providers        : "logs in as (1:1)"
    Users        ||--o{ Pets             : "owns"
    Users        ||--o{ Orders           : "places"
    Users        ||--o{ Reviews          : "writes"
    Users        ||--o{ AdoptionRequests : "sends"
    Users        ||--o{ Wishlist         : "saves"
    Providers    ||--o{ ProviderHours    : "opens"
    Providers    ||--o{ ProviderDaysOff  : "closes on"
    Providers    ||--o{ Bookings         : "receives"
    Providers    ||--o{ ShelterPets      : "shelters"
    Providers    |o--o{ Reviews          : "is rated in"
    Pets         ||--o{ Bookings         : "is booked in"
    Bookings     ||--o{ BookingStatusLog : "history"
    Bookings     |o--o| Reviews          : "rated by"
    ShelterPets  ||--o{ AdoptionRequests : "requested in"
    Categories   ||--o{ Products         : "groups"
    Orders       ||--|{ OrderItems       : "contains"
    Products     ||--o{ OrderItems       : "sold in"
    Products     ||--o{ Wishlist         : "saved in"

    Governorates {
        int GovernorateID PK
        nvarchar Name UK
    }
    Areas {
        int AreaID PK
        int GovernorateID FK
        nvarchar Name
    }
    Users {
        int UserID PK
        nvarchar FullName
        varchar Email UK
        varchar Phone
        varchar PasswordHash
        varchar Role "Owner | Provider | Admin"
        varchar Status "Active | Invited | Suspended"
        bit MustChangePassword
        int GovernorateID FK
        datetime2 CreatedAt
    }
    Providers {
        int ProviderID PK
        int UserID FK,UK "UNIQUE = one-to-one"
        varchar ProviderType "Clinic | DayCare | Trainer | Walker | Shelter"
        nvarchar BusinessName
        int AreaID FK
        varchar Phone
        nvarchar About
        decimal Price
        nvarchar Specialty
        tinyint YearsExperience
        tinyint SlotMinutes
        tinyint MinNoticeHours
        decimal AvgRating "denormalized"
        int ReviewCount "denormalized"
    }
    ProviderHours {
        int ProviderID PK,FK
        char DayCode PK "Sat ... Fri"
        bit IsOpen
        time OpenTime
        time CloseTime
    }
    ProviderDaysOff {
        int DayOffID PK
        int ProviderID FK
        date OffDate
        nvarchar Reason
    }
    Pets {
        int PetID PK
        int OwnerID FK
        nvarchar Name
        varchar PetType
        decimal AgeYears
    }
    Bookings {
        int BookingID PK
        int PetID FK
        int ProviderID FK
        date BookingDate
        time StartTime
        tinyint Hours "day care"
        smallint DurationMinutes
        time EndTime "computed"
        nvarchar SessionType
        nvarchar Reason
        nvarchar PickupAddress
        decimal TotalPrice
        char CardLast4
        varchar Status "Confirmed | Completed | Cancelled"
        varchar PayoutStatus "Due | Paid"
    }
    BookingStatusLog {
        int LogID PK
        int BookingID FK
        varchar OldStatus
        varchar NewStatus
        datetime2 ChangedAt
    }
    ShelterPets {
        int ShelterPetID PK
        int ShelterID FK
        nvarchar Name
        varchar PetType
        nvarchar Breed
        varchar Gender
        smallint AgeMonths
        varchar Status "Available | Pending | Adopted"
    }
    AdoptionRequests {
        int RequestID PK
        int UserID FK
        int ShelterPetID FK
        nvarchar Message
        datetime2 RequestedAt
        datetime2 VisitAt
        varchar Status "Pending | Approved | Declined"
    }
    Categories {
        int CategoryID PK
        nvarchar Name UK
    }
    Products {
        int ProductID PK
        int CategoryID FK
        nvarchar Name UK
        varchar PetType
        decimal Price
        int Stock
        varchar Status
    }
    Orders {
        int OrderID PK
        int UserID FK
        datetime2 OrderDate
        nvarchar CustomerName
        nvarchar Address
        int GovernorateID FK
        varchar PaymentMethod "Card | Cash"
        varchar PromoCode
        decimal Subtotal
        decimal Discount
        decimal Total "computed"
        varchar Status
    }
    OrderItems {
        int OrderID PK,FK
        int ProductID PK,FK
        smallint Quantity
        decimal UnitPrice
        decimal LineTotal "computed"
    }
    Wishlist {
        int UserID PK,FK
        int ProductID PK,FK
        datetime2 AddedAt
    }
    Reviews {
        int ReviewID PK
        int UserID FK
        int ProviderID FK "NULL for Shop / Website"
        int BookingID FK
        varchar ServiceType
        tinyint Rating "1 - 5"
        nvarchar Message
        varchar Status "Pending | Published | Hidden"
    }
```

### Standalone table (no relations)

The blog table is not linked to any other table, so it is drawn on its own.

```mermaid
erDiagram
    Articles {
        int ArticleID PK
        nvarchar Title UK
        varchar Slug UK
        nvarchar Category
        nvarchar AuthorName
        nvarchar Content
        varchar Status "Draft | Published"
        date PublishedAt
    }
```

## Relationships

| Relation | Type | How it is built |
|---|---|---|
| Users – Providers | **one-to-one** | `Providers.UserID` is a FOREIGN KEY **and** UNIQUE |
| Governorates – Areas | one-to-many | `Areas.GovernorateID` |
| Areas – Providers | one-to-many | `Providers.AreaID` |
| Users – Pets | one-to-many | `Pets.OwnerID` |
| Pets – Bookings | one-to-many | `Bookings.PetID` |
| Providers – Bookings | one-to-many | `Bookings.ProviderID` |
| Providers – ProviderHours / ProviderDaysOff | one-to-many | `ProviderID` |
| Providers (shelters) – ShelterPets | one-to-many | `ShelterPets.ShelterID` |
| Bookings – BookingStatusLog | one-to-many | `BookingStatusLog.BookingID` (filled by a trigger) |
| Categories – Products | one-to-many | `Products.CategoryID` |
| Users – Orders | one-to-many | `Orders.UserID` |
| Users – Reviews, Providers – Reviews | one-to-many | `Reviews.UserID`, `Reviews.ProviderID` |
| Bookings – Reviews | one-to-one (optional) | filtered UNIQUE index on `Reviews.BookingID` |
| **Orders – Products** | **many-to-many** | junction table `OrderItems` (PK = OrderID + ProductID) |
| **Users – Products** | **many-to-many** | junction table `Wishlist` (PK = UserID + ProductID) |
| **Users – ShelterPets** | **many-to-many** | junction table `AdoptionRequests` (UNIQUE UserID + ShelterPetID) |
| Articles | standalone | no relations |
