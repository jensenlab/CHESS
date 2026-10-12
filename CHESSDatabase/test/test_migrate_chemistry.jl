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
