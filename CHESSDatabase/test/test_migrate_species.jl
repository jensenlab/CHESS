# migrate_species!: converts a database written with the old Chemicals table. Runs against a
# throwaway database, then reconnects to the database the other tests use.
@testset "migrate_species!" begin
    old_path = tempname()*".db"
    previous = CHESSDatabase._current_db[]
    try
        db = SQLite.DB(old_path)
        DBInterface.execute(db,"CREATE TABLE Chemicals(ID INTEGER PRIMARY KEY NOT NULL, Name TEXT, Charge INTEGER, MolecularWeight REAL, Unique(Name,Charge,MolecularWeight))")
        DBInterface.execute(db,"""
            CREATE TABLE CompositionRules(
                ID INTEGER PRIMARY KEY NOT NULL, ReagentComponentID INTEGER, ChemicalID INTEGER, Coefficient INTEGER,
                FOREIGN KEY(ChemicalID) REFERENCES Chemicals(ID) ON UPDATE CASCADE ON DELETE RESTRICT)""")
        DBInterface.execute(db,"INSERT INTO Chemicals(Name,Charge,MolecularWeight) VALUES('Na+',1,22.99)")
        DBInterface.execute(db,"INSERT INTO CompositionRules(ReagentComponentID,ChemicalID,Coefficient) VALUES(1,1,1)")
        close(db)

        @test_logs (:warn,r"migrate_species!") connect_SQLite(old_path)
        @test CHESSDatabase.migrate_species!() === true
        @test CHESSDatabase.migrate_species!() === false # already migrated
        cols = query_db("SELECT name FROM pragma_table_info('Species')").name
        @test "Formula" in cols
        @test !("Chemicals" in query_db("SELECT name FROM sqlite_master WHERE type='table'").name)
        rows = query_db("SELECT s.Name, s.MolecularWeight, s.Formula, r.Coefficient FROM CompositionRules r INNER JOIN Species s ON r.SpeciesID = s.ID")
        @test rows.Name == ["Na+"] && rows.MolecularWeight == [22.99] && ismissing(rows.Formula[1])
        @test CHESSDatabase.get_species(1) == Species("Na+",1,22.99u"g/mol") # old rows read back as stored-weight species
        @test_logs connect_SQLite(old_path) # no warning once migrated
    finally
        CHESSDatabase._current_db[] = previous
        rm(old_path,force=true)
    end
end
