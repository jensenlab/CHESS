# Synthetic ledger of N ledger rows on CHESS's real schema, generated entirely by SQL (recursive CTEs) into a
# database made by `create_db`. Deterministic: the "random" numbers are integer hashes of the row number.
#
# The mix follows plan section 9, read as shares of *operation rows*: 55% environment samples, 28% reads,
# 12% transfers, 2% movements/locks/activity, and 0.5% (of N) amendments of earlier slots, plus caches on
# 1% of the wells. Reads share ledger rows in batches of 96 (one tick per plate), so they take few ledger
# rows; N counts ledger rows (including the amendment rows), not operation rows.
#
#   locations   1-40 incubators; 41-240 shelves/rooms; 241-440 reservoirs; 441-740 plates (96 wells each:
#               741 ... 741+300*96-1); then experiment wells, 96 per experiment
#   environment one series per (location, attribute): 240 locations x {Temperature, Humidity}
#   transfers   experiments of 96 wells: 8 reservoir -> well transfers (100 µL), then 11 halving dilution steps in each
#               of 8 rows (so a well never gives more than it holds); the reservoir is drawn from 200 with Zipf(1) weights, so reservoir 1 is a hub
#   reads       one tick = 96 wells of one plate
#   settings    about 1% of the slots set one of three settings of instruments 1-3
#   amendments  new revisions (same SequenceID, higher ID, later Time) of environment and transfer slots
#   deep chain  BENCH_DEEP (default 5000) transfers in a line: source -> w1 -> w2 -> ... , each well passing on all it received
#
# generate_ledger_scale(path, N) -> NamedTuple of row counts

using SQLite, DBInterface, DataFrames, CHESSDatabase

const LS_ORIGIN = 1.7e9          # Ledger.Time of ID 0; each row is 0.01 s after the previous one
const LS_INCUBATORS, LS_ROOMS, LS_RESERVOIRS, LS_PLATES = 40, 200, 200, 300
# steps of the deep chain: a source reservoir followed by wells w1, w2, ... each of which hands its whole contents to the
# next (0 leaves it out). Its ledger rows come after the N rows of the mix, so N counts the mix only.
const LS_DEEP = parse(Int,get(ENV,"BENCH_DEEP","5000"))

# integer hash of expression `i` and `salt` as a uniform number in [0, 1); no SQLite random() so runs repeat
ls_rnd(i,salt) = "(((((($i)*2654435761+$(salt)*1000003+12345) % 4294967296)*1664525+1013904223) % 4294967296)/4294967296.0)"

"""
    ls_layout(N) -> NamedTuple

Where things are in the database `generate_ledger_scale(path, N)` makes: location id ranges, slot counts,
and the number of experiments (96 wells each).
"""
function ls_layout(N::Integer)
    A = round(Int,0.005N); B = N - A
    n_exp = ceil(Int,0.18B/96) + 3
    plate_base = LS_INCUBATORS + LS_ROOMS + LS_RESERVOIRS + 1
    well_base = plate_base + LS_PLATES
    exp_base = well_base + LS_PLATES*96
    n_loc = exp_base + n_exp*96 - 1
    return (; N, amendments=A, slots=B, n_exp, incubators=1:LS_INCUBATORS, rooms=LS_INCUBATORS+1:LS_INCUBATORS+LS_ROOMS,
        reservoirs=LS_INCUBATORS+LS_ROOMS+1:LS_INCUBATORS+LS_ROOMS+LS_RESERVOIRS, plates=plate_base:plate_base+LS_PLATES-1,
        plate_wells=well_base:exp_base-1, exp_base, n_loc, deep=LS_DEEP, chain_source=n_loc+1, chain_head=n_loc+2, chain_tail=n_loc+1+LS_DEEP)
end

function generate_ledger_scale(path::AbstractString,N::Integer)
    isfile(path) && rm(path)
    create_db(path)
    db = SQLite.DB(path)
    exec(sql) = DBInterface.execute(db,sql)
    # a database as it was before the CHESS indexes existed; the benchmark adds them back to compare
    for r in eachrow(DataFrame(exec("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx\\_chess\\_%' ESCAPE '\\'")))
        exec("DROP INDEX $(r.name)")
    end
    exec("PRAGMA journal_mode = OFF"); exec("PRAGMA synchronous = OFF"); exec("PRAGMA temp_store = MEMORY")
    exec("DELETE FROM Ledger")

    lay = ls_layout(N)
    A, B = lay.amendments, lay.slots
    plate_base, well_base, exp_base, n_loc = first(lay.plates), first(lay.plate_wells), lay.exp_base, lay.n_loc

    exec("INSERT INTO LocationTypes(Name) VALUES ('Room'),('Incubator'),('Reservoir'),('WP96'),('Well200')")
    exec("INSERT INTO Attributes(Attribute,BaseUnit) VALUES ('Temperature','°C'),('Humidity','percent')")
    exec("""
    WITH RECURSIVE s(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM s WHERE i < $n_loc)
    INSERT INTO Locations(ID,Name,Type)
    SELECT i, 'loc'||i, CASE WHEN i <= $LS_INCUBATORS THEN 'Incubator'
                             WHEN i <= $(LS_INCUBATORS+LS_ROOMS) THEN 'Room'
                             WHEN i < $plate_base THEN 'Reservoir'
                             WHEN i < $well_base THEN 'WP96' ELSE 'Well200' END FROM s""")

    # which kind of operation each slot holds
    exec("""
    CREATE TEMP TABLE slots AS
    WITH RECURSIVE s(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM s WHERE i < $B)
    SELECT i, CASE WHEN r < 0.788 THEN 'e' WHEN r < 0.960 THEN 't' WHEN r < 0.9642 THEN 'r'
                   WHEN r < 0.9785 THEN 'm' WHEN r < 0.9857 THEN 'l' WHEN r < 0.9885 THEN 'a' ELSE 's' END AS k
    FROM (SELECT i, $(ls_rnd("i",1)) AS r FROM s)""")
    exec("CREATE TEMP TABLE ord AS SELECT i, k, ROW_NUMBER() OVER (PARTITION BY k ORDER BY i) AS n FROM slots")
    exec("CREATE INDEX temp_ord_k ON ord(k,n)")

    exec("INSERT INTO Ledger(ID,SequenceID,Time) SELECT i, i, $LS_ORIGIN + i*0.01 FROM slots")

    exec("""
    INSERT INTO EnvironmentAttributes(LedgerID,LocationID,Attribute,Value,Unit,Time)
    SELECT i, loc, attr, 10 + 30*$(ls_rnd("i",4)), CASE attr WHEN 'Temperature' THEN '°C' ELSE 'percent' END, $LS_ORIGIN + i*0.01
    FROM (SELECT i, 1 + CAST($(ls_rnd("i",2))*$(LS_INCUBATORS+LS_ROOMS) AS INTEGER) AS loc,
                 CASE WHEN $(ls_rnd("i",3)) < 0.5 THEN 'Temperature' ELSE 'Humidity' END AS attr FROM ord WHERE k = 'e')""")

    # transfers: ordinal n -> experiment e = (n-1)/96, position q = (n-1)%96
    exec("""
    INSERT INTO Transfers(LedgerID,Source,Destination,Quantity,Unit,Time)
    WITH t AS (SELECT i, (n-1)/96 AS e, (n-1)%96 AS q FROM ord WHERE k = 't'),
         w AS (SELECT i, e, q, CASE WHEN q < 8 THEN q ELSE (q-8)%8 END AS row_, CASE WHEN q < 8 THEN 0 ELSE (q-8)/8 END AS col FROM t)
    SELECT i,
           CASE WHEN q < 8 THEN $(LS_INCUBATORS+LS_ROOMS) + 1 + MIN($(LS_RESERVOIRS-1), CAST(POWER($LS_RESERVOIRS, $(ls_rnd("e",5))) AS INTEGER) - 1)
                ELSE $exp_base + e*96 + row_*12 + col END,
           $exp_base + e*96 + row_*12 + CASE WHEN q < 8 THEN 0 ELSE col + 1 END,
           CASE WHEN q < 8 THEN 100.0 ELSE 100.0 / (1 << (col + 1)) END, 'µL', $LS_ORIGIN + i*0.01
    FROM w""")

    # reads: ordinal b -> plate (b-1) % LS_PLATES, one row per well
    exec("""
    INSERT INTO Reads(LedgerID,LocationID,Type,Value,Unit,Time)
    WITH RECURSIVE wl(w) AS (SELECT 0 UNION ALL SELECT w+1 FROM wl WHERE w < 95)
    SELECT i, $well_base + ((n-1) % $LS_PLATES)*96 + w, 'Absorbance', CAST($(ls_rnd("i*100+w",7)) AS TEXT), 'percent', $LS_ORIGIN + i*0.01
    FROM ord, wl WHERE k = 'r'""")

    exec("""
    INSERT INTO Movements(LedgerID,Parent,Child,Time)
    SELECT i, 1 + CAST($(ls_rnd("i",8))*$(LS_INCUBATORS+LS_ROOMS) AS INTEGER), $plate_base + CAST($(ls_rnd("i",9))*$LS_PLATES AS INTEGER), $LS_ORIGIN + i*0.01
    FROM ord WHERE k = 'm'""")
    exec("""
    INSERT INTO Locks(LedgerID,LocationID,IsLocked,Time)
    SELECT i, $plate_base + CAST($(ls_rnd("i",10))*$LS_PLATES AS INTEGER), n % 2, $LS_ORIGIN + i*0.01 FROM ord WHERE k = 'l'""")
    exec("""
    INSERT INTO Activity(LedgerID,LocationID,IsActive,Time)
    SELECT i, $plate_base + CAST($(ls_rnd("i",11))*$LS_PLATES AS INTEGER), n % 2, $LS_ORIGIN + i*0.01 FROM ord WHERE k = 'a'""")

    exec("""
    INSERT INTO InstrumentSettings(LedgerID,InstrumentID,Setting,Value,Time)
    SELECT i, 1 + CAST($(ls_rnd("i",15))*3 AS INTEGER), CASE n % 3 WHEN 0 THEN 'Gain' WHEN 1 THEN 'Filter' ELSE 'Mode' END,
           CAST(n AS TEXT), $LS_ORIGIN + i*0.01 FROM ord WHERE k = 's'""")

    # amendments: the j-th amendment row has ID B+j and revises a hash-chosen environment or transfer slot
    exec("""
    CREATE TEMP TABLE amend AS
    SELECT B_ + ROW_NUMBER() OVER (ORDER BY h) AS id, i, k FROM
        (SELECT $B AS B_, i, k, $(ls_rnd("i",12)) AS h FROM slots WHERE k IN ('e','t') ORDER BY h LIMIT $A)""")
    exec("INSERT INTO Ledger(ID,SequenceID,Time) SELECT id, i, $LS_ORIGIN + id*0.01 FROM amend")
    exec("""
    INSERT INTO EnvironmentAttributes(LedgerID,LocationID,Attribute,Value,Unit,Time)
    SELECT a.id, e.LocationID, e.Attribute, e.Value + 1, e.Unit, $LS_ORIGIN + a.id*0.01
    FROM amend a INNER JOIN EnvironmentAttributes e ON e.LedgerID = a.i WHERE a.k = 'e'""")
    exec("""
    INSERT INTO Transfers(LedgerID,Source,Destination,Quantity,Unit,Time)
    SELECT a.id, t.Source, t.Destination, t.Quantity*1.1, t.Unit, $LS_ORIGIN + a.id*0.01
    FROM amend a INNER JOIN Transfers t ON t.LedgerID = a.i WHERE a.k = 't'""")

    # the deep chain: slots B+1 ... B+D, written after the amendments (so their ledger IDs are B+A+1 ...)
    if LS_DEEP > 0
        D, src = LS_DEEP, lay.chain_source
        exec("""
        WITH RECURSIVE s(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM s WHERE k < $D)
        INSERT INTO Locations(ID,Name,Type) SELECT $src + k - 1, 'chain'||k, CASE WHEN k = 1 THEN 'Reservoir' ELSE 'Well200' END FROM s""")
        exec("INSERT INTO Locations(ID,Name,Type) VALUES ($(src+D),'chain end','Well200')")
        exec("""
        WITH RECURSIVE s(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM s WHERE k < $D)
        INSERT INTO Ledger(ID,SequenceID,Time) SELECT $B + $A + k, $B + k, $LS_ORIGIN + ($B + $A + k)*0.01 FROM s""")
        exec("""
        WITH RECURSIVE s(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM s WHERE k < $D)
        INSERT INTO Transfers(LedgerID,Source,Destination,Quantity,Unit,Time)
        SELECT $B + $A + k, $src + k - 1, $src + k, 100.0, 'µL', $LS_ORIGIN + ($B + $A + k)*0.01 FROM s""")
    end

    # caches on 1% of the wells, taken at a random slot
    exec("INSERT INTO CachedStocks(ID,StockHash) VALUES (1, x'0000000000000000')")
    exec("""
    WITH RECURSIVE s(i) AS (SELECT $well_base UNION ALL SELECT i+1 FROM s WHERE i < $n_loc)
    INSERT INTO CachedContents(LocationID,StockID,LedgerID,Time)
    SELECT i, 1, 1 + CAST($(ls_rnd("i",13))*$B AS INTEGER), $LS_ORIGIN FROM s WHERE $(ls_rnd("i",14)) < 0.01""")

    counts = NamedTuple(Symbol(t) => DataFrame(exec("SELECT COUNT(*) AS n FROM $t")).n[1] for t in
        ("Ledger","EnvironmentAttributes","Reads","Transfers","Movements","Locks","Activity","InstrumentSettings","CachedContents","Locations"))
    exec("ANALYZE")   # stats on the unindexed tables, as a database in use would have
    DBInterface.close!(db)
    return counts
end
