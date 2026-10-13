# migrate_chemistry!: converts a database written with the old Chemicals/CompositionRules tables.
# Runs against throwaway databases, then reconnects to the database the other tests use.
function _old_chemistry_db(path)
    db = SQLite.DB(path)
    DBInterface.execute(db,"CREATE TABLE Chemicals(ID INTEGER PRIMARY KEY NOT NULL, Name TEXT, Charge INTEGER, MolecularWeight REAL, Unique(Name,Charge,MolecularWeight))")
    DBInterface.execute(db,"""
        CREATE TABLE CompositionRules(
            ID INTEGER PRIMARY KEY NOT NULL, ReagentComponentID INTEGER, ChemicalID INTEGER, Coefficient INTEGER,
            FOREIGN KEY(ChemicalID) REFERENCES Chemicals(ID) ON UPDATE CASCADE ON DELETE RESTRICT)""")
    DBInterface.execute(db,"INSERT INTO Chemicals(Name,Charge,MolecularWeight) VALUES('Na+',1,22.99)")
    DBInterface.execute(db,"INSERT INTO CompositionRules(ReagentComponentID,ChemicalID,Coefficient) VALUES(1,1,1)")
    return db
end

@testset "migrate_chemistry!" begin
    previous = CHESSDatabase._current_db[]
    old_path = tempname()*".db"
    half_path = tempname()*".db"
    try
        close(_old_chemistry_db(old_path))

        @test_logs (:warn,r"migrate_chemistry!") connect_SQLite(old_path)
        @test CHESSDatabase.migrate_chemistry!() === true
        @test CHESSDatabase.migrate_chemistry!() === false # already migrated
        @test "Formula" in query_db("SELECT name FROM pragma_table_info('Species')").name
        @test "CID" in query_db("SELECT name FROM pragma_table_info('Species')").name
        tables = query_db("SELECT name FROM sqlite_master WHERE type='table'").name
        @test !("Chemicals" in tables) && !("CompositionRules" in tables)
        rows = query_db("SELECT s.Name, s.MolecularWeight, s.Formula, r.Coefficient FROM Dissolutions r INNER JOIN Species s ON r.SpeciesID = s.ID")
        @test rows.Name == ["Na+"] && rows.MolecularWeight == [22.99] && ismissing(rows.Formula[1])
        @test CHESSDatabase.get_species(1) == Species("Na+",1,22.99u"g/mol") # old rows read back as stored-weight species
        @test_logs connect_SQLite(old_path) # no warning once migrated

        # a database that already has Species but still has CompositionRules is also converted
        db = _old_chemistry_db(half_path)
        DBInterface.execute(db,"ALTER TABLE Chemicals RENAME TO Species")
        DBInterface.execute(db,"ALTER TABLE Species ADD COLUMN Formula TEXT")
        DBInterface.execute(db,"ALTER TABLE CompositionRules RENAME COLUMN ChemicalID TO SpeciesID")
        close(db)
        connect_SQLite(half_path)
        @test CHESSDatabase.migrate_chemistry!() === true
        @test "Dissolutions" in query_db("SELECT name FROM sqlite_master WHERE type='table'").name
    finally
        CHESSDatabase._current_db[] = previous
        rm(old_path,force=true)
        rm(half_path,force=true)
    end
end

@testset "migrate_chemistry! adds Species.CID from single-species reagents" begin
    previous = CHESSDatabase._current_db[]
    path = tempname()*".db"
    try
        db = SQLite.DB(path)
        DBInterface.execute(db,"CREATE TABLE Species(ID INTEGER PRIMARY KEY NOT NULL, Name TEXT, Charge INTEGER, Formula TEXT, MolecularWeight REAL)")
        DBInterface.execute(db,"CREATE TABLE Reagents(ComponentID INTEGER PRIMARY KEY NOT NULL, Name TEXT, Type TEXT, MolecularWeight REAL, Density REAL, CID INTEGER)")
        DBInterface.execute(db,"CREATE TABLE Dissolutions(ID INTEGER PRIMARY KEY NOT NULL, ReagentComponentID INTEGER, SpeciesID INTEGER, Coefficient INTEGER)")
        DBInterface.execute(db,"INSERT INTO Species(Name,Charge,Formula) VALUES('urea',0,'CH4N2O'),('Na+',1,'Na'),('Cl-',-1,'Cl')")
        DBInterface.execute(db,"INSERT INTO Reagents(ComponentID,Name,Type,CID) VALUES(1,'urea','Solid',1176),(2,'sodium chloride','Solid',5234)")
        DBInterface.execute(db,"INSERT INTO Dissolutions(ReagentComponentID,SpeciesID,Coefficient) VALUES(1,1,1),(2,2,1),(2,3,1)")
        close(db)

        @test_logs (:warn,r"migrate_chemistry!") connect_SQLite(path)
        @test CHESSDatabase.migrate_chemistry!() === true
        @test CHESSDatabase.migrate_chemistry!() === false
        cids = query_db("SELECT Name, CID FROM Species ORDER BY ID")
        @test cids.CID[1] == 1176 # the one species of urea takes urea's ID
        @test ismissing(cids.CID[2]) && ismissing(cids.CID[3]) # a two-species reagent's ID belongs to neither
        @test_logs connect_SQLite(path)
    finally
        CHESSDatabase._current_db[] = previous
        rm(path,force=true)
    end
end
