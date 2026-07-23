
function create_db(path)
    # Create database connection
    db = SQLite.DB(path)
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
    
    
    create_Experiments = """
    CREATE TABLE Experiments (
        ID INTEGER PRIMARY KEY NOT NULL ,
        Name Text, 
        User TEXT,
        IsPublic INTEGER,
        Time INTEGER
    );
    """
    
    create_Runs= """
    CREATE TABLE Runs ( 
        ID INTEGER PRIMARY KEY NOT NULL ,
        ExperimentID INTEGER, 
        LocationID INTEGER,
        Controls Text, 
        Blanks Text,
        FOREIGN KEY (ExperimentID) REFERENCES Experiments(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    
    """
    

    create_Components="""
        CREATE TABLE Components(
            ID INTEGER PRIMARY KEY NOT NULL,
            Type TEXT
            );
    """

    create_Reagents="""
        CREATE TABLE Reagents(
            ComponentID INTEGER PRIMARY KEY NOT NULL,
            Name TEXT,
            Type TEXT,
            MolecularWeight REAL,
            Density REAL,
            CID INTEGER,
            FOREIGN KEY(ComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
            Unique(Name,Type,MolecularWeight,Density,CID)
        );
        """

    create_Chemicals="""
        CREATE TABLE Chemicals(
            ID INTEGER PRIMARY KEY NOT NULL,
            Name TEXT,
            Charge INTEGER,
            MolecularWeight REAL,
            Unique(Name,Charge,MolecularWeight)
        );
        """

    create_CompositionRules="""
        CREATE TABLE CompositionRules(
            ID INTEGER PRIMARY KEY NOT NULL,
            ReagentComponentID INTEGER,
            ChemicalID INTEGER,
            Coefficient INTEGER,
            FOREIGN KEY(ReagentComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY(ChemicalID) REFERENCES Chemicals(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
            Unique(ReagentComponentID,ChemicalID)
        );
        """

    create_Organisms="""
        CREATE TABLE Organisms(
            ID INTEGER PRIMARY KEY NOT NULL,
            ComponentID INTEGER,
            Genus TEXT,
            Species TEXT,
            Strain TEXT,
            FOREIGN KEY(ComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
            Unique(Genus,Species,Strain)
        );
        """


    create_CachedDescendants="""
    CREATE TABLE CachedDescendants(
        ID INTEGER PRIMARY KEY NOT NULL,
        LocationID INTEGER,
        ChildSetID INTEGER,
        LedgerID INTEGER,
        Time INTEGER,
         FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ChildSetID) REFERENCES CachedChildSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
        );
    """

    create_CachedAncestors="""
    CREATE TABLE CachedAncestors(
        ID INTEGER PRIMARY KEY NOT NULL,
        LocationID INTEGER,
        ParentID INTEGER,
        LedgerID INTEGER,
        Time Integer,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ParentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """




    create_CachedChildSets="""
    CREATE TABLE CachedChildSets(
        ID INTEGER PRIMARY KEY NOT NULL,
        ChildSetHash BLOB
    );
    """

    create_CachedChildren="""
    CREATE TABLE CachedChildren(
        ID INTEGER PRIMARY KEY NOT NULL,
        CachedChildSetID INTEGER,
        ChildID INTEGER,
        RowIdx INTEGER,
        ColIdx INTEGER,
        FOREIGN KEY(CachedChildSetID) REFERENCES CachedChildSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ChildID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_CachedEnvironments="""
    CREATE TABLE CachedEnvironments(
        ID INTEGER PRIMARY KEY NOT NULL,
        LocationID INTEGER,
        AttributeSetID INTEGER,
        LedgerID INTEGER,
        Time Integer,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(AttributeSetID) REFERENCES CachedAttributeSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
"""




    create_CachedAttributeSets="""
    CREATE TABLE CachedAttributeSets(
        ID INTEGER PRIMARY KEY NOT NULL,
        AttributeSetHash BLOB

        );
    """
    create_CachedAttributes="""
    CREATE TABLE CachedAttributes(
        ID INTEGER PRIMARY KEY NOT NULL,
        AttributeSetID INTEGER,
        AttributeID TEXT,
        Value REAL,
        Unit TEXT,
        FOREIGN KEY(AttributeSetID) REFERENCES CachedAttributeSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(AttributeID) REFERENCES Attributes(Attribute) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """


    create_CachedContents="""
    CREATE TABLE CachedContents(
        ID INTEGER PRIMARY KEY NOT NULL,
        LocationID INTEGER,
        StockID INTEGER, 
        LedgerID INTEGER,
        Cost REAL,
        Time INTEGER,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(StockID) REFERENCES CachedStocks(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
        );
    """


    create_CachedStocks="""
    CREATE TABLE CachedStocks(
        ID INTEGER PRIMARY KEY NOT NULL,
        StockHash BLOB
    );
    """

    create_CachedComponents="""
    CREATE TABLE CachedComponents(
        ID INTEGER PRIMARY KEY NOT NULL,
        StockID INTEGER,
        ComponentID INTEGER, 
        Quantity REAl,
        Unit TEXT,
        FOREIGN KEY(StockID) REFERENCES CachedStocks(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
"""

    create_CachedLockActivity="""
    CREATE TABLE CachedLockActivity(
        ID INTEGER PRIMARY KEY NOT NULL,
        LocationID INTEGER,
        IsLocked INTEGER,
        IsActive INTEGER,
        LedgerID INTEGER,
        Time INTEGER,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """


    create_LocationTypes="""
    CREATE TABLE LocationTypes( 
        Name TEXT PRIMARY KEY
    );
    """
  
    create_Locations="""
    CREATE TABLE Locations(
        ID INTEGER PRIMARY KEY NOT NULL,
        Name TEXT,
        Type TEXT,
        FOREIGN KEY(Type) REFERENCES LocationTypes(Name) ON UPDATE CASCADE ON DELETE RESTRICT 
    )
    """

    create_Attributes="""
    CREATE TABLE Attributes(
        Attribute TEXT PRIMARY KEY,
        BaseUnit TEXT
    );
    """

    create_EnvironmentAttributes="""
    CREATE TABLE EnvironmentAttributes(
        ID Integer PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        LocationID INTEGER,
        Attribute TEXT,
        Value Real,
        Unit TEXT,
        Time Integer,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(Attribute) REFERENCES Attributes(Attribute) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """


    

    create_Transfers= """
    CREATE TABLE Transfers(
        ID INTEGER PRIMARY KEY NOT NULL ,
        LedgerID INTEGER,
        Source INTEGER,
        Destination INTEGER,
        Quantity REAL,
        Unit TEXT,
        Time Integer,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        FOREIGN KEY(Source) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(Destination) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,

        CHECK (Source != Destination)
    );
    """



    create_Movements="""
    CREATE TABLE Movements(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        Parent Integer,
        Child Integer,
        Time Integer,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        FOREIGN KEY(Child) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(Parent) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        CHECK (Parent != Child)
    );
    """

    create_Locks="""
    CREATE TABLE Locks(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        LocationID INTEGER,
        IsLocked INTEGER,
        Time Integer,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    

    create_Reads="""
    CREATE TABLE Reads(
        ID INTEGER PRIMARY KEY NOT NULL ,
        LedgerID INTEGER,
        LocationID INTEGER,
        Type TEXT,
        Value TEXT,
        Unit TEXT,
        Time INTEGER,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_InstrumentSettings="""
    CREATE TABLE InstrumentSettings(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        InstrumentID INTEGER,
        Setting TEXT,
        Value TEXT,
        InstrumentTime INTEGER,
        Time INTEGER,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_Ledger="""
    CREATE TABLE Ledger(
        ID INTEGER PRIMARY KEY NOT NULL ,
        SequenceID INTEGER,
        Time INTEGER
    );
    """

    create_Barcodes="""
    CREATE TABLE Barcodes(
        Barcode TEXT PRIMARY KEY,
        LocationID Integer,
        Name TEXT,
        FOREIGN KEY (LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT  
    );
    """

    create_Activity="""
    CREATE TABLE Activity(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        LocationID INTEGER,
        IsActive INTEGER,
        Time INTEGER,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """


    create_Protocols="""
    CREATE TABLE Protocols( 
        ID INTEGER PRIMARY KEY NOT NULL, 
        ExperimentID INTEGER,
        Name Text,
        LedgerIDCreatedAt INTEGER,
        EstimatedTime Real,
        FOREIGN KEY (ExperimentID) REFERENCES Experiments(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (LedgerIDCreatedAt) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        Unique(ExperimentID,Name)
    );
    """

    create_ProtocolEnforcement="""
    CREATE TABLE ProtocolEnforcement(
        ID INTEGER PRIMARY KEY NOT NULL,
        ProtocolID INTEGER, 
        LedgerID INTEGER,
        IsEnforced INTEGER,
        Time INTEGER,
        FOREIGN KEY (ProtocolID) REFERENCES Protocols(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_Encumbrances="""
    CREATE TABLE Encumbrances( 
        ID INTEGER PRIMARY KEY NOT NULL,
        ProtocolID INTEGER,  
        FOREIGN KEY(ProtocolID) REFERENCES Protocols(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_EncumbranceCompletion="""
    CREATE TABLE EncumbranceCompletion(
        ID INTEGER PRIMARY KEY NOT NULL ,
        LedgerID INTEGER,
        EncumbranceID INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID)ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """



    create_EncumberedCachedContents="""
    CREATE TABLE EncumberedCachedContents(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        StockID INTEGER,
        Cost REAL,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(StockID) REFERENCES CachedStocks(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """


    create_EncumberedCachedEnvironments="""
    CREATE TABLE EncumberedCachedEnvironments(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        AttributeSetID INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(AttributeSetID) REFERENCES CachedAttributeSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """
    create_EncumberedCachedAncestors="""
    CREATE TABLE EncumberedCachedAncestors(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        ParentID INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ParentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """
    create_EncumberedCachedDescendants="""
    CREATE TABLE EncumberedCachedDescendants(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        ChildSetID INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ChildSetID) REFERENCES CachedChildSets(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """
    create_EncumberedCachedLockActivity="""
    CREATE TABLE EncumberedCachedLockActivity(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER, 
        LocationID INTEGER,
        IsLocked INTEGER,
        IsActive INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
        );
        """



    create_EncumberedTransfers="""
    CREATE TABLE EncumberedTransfers( 
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        Source INTEGER,
        Destination INTEGER, 
        Quantity REAL,
        Unit TEXT,
        Configuration TEXT,
        FOREIGN KEY(Source) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(Destination) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        
        CHECK (Source != Destination)
    );
    """
    #FOREIGN KEY(Configuration) REFERENCES Configuration(ID) ON UPDATE CASCADE ON DELETE RESTRICT,


    create_EncumberedEnvironments="""
    CREATE TABLE EncumberedEnvironments( 
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        Attribute TEXT,
        Value Real,
        Unit,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT, 
        FOREIGN KEY(Attribute) REFERENCES Attributes(Attribute) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT 
    )
    """

    create_EncumberedMovements="""
    CREATE TABLE EncumberedMovements(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        Parent INTEGER,
        Child INTEGER,
        FOREIGN KEY(Child) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(Parent) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        CHECK (Parent != Child) 
    )
    """ 

    create_EncumberedActivity="""
    CREATE TABLE EncumberedActivity(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        Activate INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    create_EncumberedLocks="""
    CREATE TABLE EncumberedLocks(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        Lock INTEGER,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """

    #main 
    DBInterface.execute(db,create_Ledger)
    DBInterface.execute(db,create_Barcodes)
    DBInterface.execute(db,create_LocationTypes)
    DBInterface.execute(db,create_Locations)
    DBInterface.execute(db, create_Components)
    DBInterface.execute(db,create_Reagents)
    DBInterface.execute(db,create_Chemicals)
    DBInterface.execute(db,create_CompositionRules)
    DBInterface.execute(db,create_Organisms)
    DBInterface.execute(db,create_Attributes)
    DBInterface.execute(db,create_EnvironmentAttributes)
    #operations
    DBInterface.execute(db, create_Transfers)
    DBInterface.execute(db,create_Movements)
    DBInterface.execute(db, create_Reads)
    DBInterface.execute(db, create_Activity)
    DBInterface.execute(db,create_Locks)
    DBInterface.execute(db,create_InstrumentSettings)

    # indexes on InstrumentID columns -- added from day one, unlike the rest of the schema (see the
    # earlier caching/indexing critique this design followed from)
    DBInterface.execute(db,"CREATE INDEX idx_movements_instrument ON Movements(InstrumentID);")
    DBInterface.execute(db,"CREATE INDEX idx_transfers_instrument ON Transfers(InstrumentID);")
    DBInterface.execute(db,"CREATE INDEX idx_environmentattributes_instrument ON EnvironmentAttributes(InstrumentID);")
    DBInterface.execute(db,"CREATE INDEX idx_reads_instrument ON Reads(InstrumentID);")
    DBInterface.execute(db,"CREATE INDEX idx_instrumentsettings_instrument ON InstrumentSettings(InstrumentID);")
    # caching 
    DBInterface.execute(db,create_CachedChildSets)
    DBInterface.execute(db,create_CachedChildren)
    DBInterface.execute(db,create_CachedAttributeSets)
    DBInterface.execute(db,create_CachedAttributes)
    DBInterface.execute(db,create_CachedStocks)
    DBInterface.execute(db,create_CachedComponents)
    DBInterface.execute(db,create_CachedContents)
    DBInterface.execute(db,create_CachedDescendants)
    DBInterface.execute(db,create_CachedEnvironments)
    DBInterface.execute(db,create_CachedAncestors)
    DBInterface.execute(db,create_CachedLockActivity)

    # experiments and encumbrances
    DBInterface.execute(db, create_Experiments)
    DBInterface.execute(db, create_Runs)
    DBInterface.execute(db,create_Protocols)
    DBInterface.execute(db,create_ProtocolEnforcement)
    DBInterface.execute(db,create_Encumbrances)
    DBInterface.execute(db,create_EncumbranceCompletion)
    DBInterface.execute(db,create_EncumberedTransfers)
    DBInterface.execute(db,create_EncumberedLocks)
    DBInterface.execute(db,create_EncumberedMovements)
    DBInterface.execute(db,create_EncumberedEnvironments)
    DBInterface.execute(db,create_EncumberedActivity)
    DBInterface.execute(db, create_EncumberedCachedContents)
    DBInterface.execute(db, create_EncumberedCachedAncestors)
    DBInterface.execute(db, create_EncumberedCachedDescendants)
    DBInterface.execute(db,create_EncumberedCachedEnvironments)
    DBInterface.execute(db,create_EncumberedCachedLockActivity)



    init_time=db_time(Dates.now())
    DBInterface.execute(db,"""INSERT INTO Ledger(SequenceID, Time) Values(1,$init_time)""")
end
#=
file="./src/database/test_create_db.db"
rm(file)
create_db(file)
=#