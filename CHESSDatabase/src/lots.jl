# Lots: where a received piece of labware (a reagent bottle) came from. A `Lot` is observed on a
# `Labware` and recorded in `ObservedLots` with the ledger entry that states it; the most recent
# observation as of a sequence position is the labware's lot. `Products` holds each supplier product
# that a lot refers to, once, and links it to the reagent it is a product of when that is registered.

const _lot_table_statements = (
    """
    CREATE TABLE IF NOT EXISTS Products(
        ID INTEGER PRIMARY KEY NOT NULL,
        Supplier TEXT NOT NULL,
        CatalogNumber TEXT NOT NULL,
        ProductName TEXT,
        ManufacturerNumber TEXT,
        Grade TEXT,
        Notes TEXT,
        ReagentComponentID INTEGER,
        FOREIGN KEY(ReagentComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        UNIQUE(Supplier,CatalogNumber)
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS ObservedLots(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        LocationID INTEGER,
        ProductID INTEGER,
        Lot TEXT NOT NULL,
        GTIN TEXT,
        Quantity REAL,
        Unit TEXT,
        Cost REAL,
        Received TEXT,
        Notes TEXT,
        Time INTEGER,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        ReadLedgerID INTEGER,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ReadLedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ProductID) REFERENCES Products(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """,
    "CREATE INDEX IF NOT EXISTS idx_observedlots_ledger ON ObservedLots(LedgerID);",
    "CREATE INDEX IF NOT EXISTS idx_observedlots_location ON ObservedLots(LocationID);",
)

_create_lot_tables!(db) = foreach(s->DBInterface.execute(db,s),_lot_table_statements)

# a database made before lots existed gains the tables when it is connected to
function _ensure_lot_tables!()
    _table_exists("Locations") && !_table_exists("ObservedLots") && foreach(execute_db,_lot_table_statements)
    _table_exists("ObservedLots") && !_column_exists("ObservedLots","Cost") && execute_db("ALTER TABLE ObservedLots ADD COLUMN Cost REAL")
    return nothing
end

"""
    get_product_id(lot::Lot) -> Integer

The `Products.ID` of the supplier product that `lot` is a lot of, uploading it first if there is no row
for its supplier and catalog number. When the product is registered as a [`ReagentProduct`](@ref) of a
reagent, the row takes the product's details and links to the reagent's component.
"""
function get_product_id(lot::Lot)
    key=(lot.supplier,lot.catalog_number)
    id=query_db("SELECT ID FROM Products WHERE Supplier = ? AND CatalogNumber = ?",key)
    nrow(id)==1 && return id[1,1]
    reagent,product=_registered_product(lot)
    component_id = isnothing(reagent) ? missing : get_component_id(reagent)
    details = isnothing(product) ? (missing,missing,missing,missing) :
        (product.product_name,product.manufacturer_number,product.grade,product.notes)
    execute_db("INSERT INTO Products(Supplier,CatalogNumber,ProductName,ManufacturerNumber,Grade,Notes,ReagentComponentID) Values(?,?,?,?,?,?,?)",
        (key...,details...,component_id))
    return query_db("SELECT ID FROM Products WHERE Supplier = ? AND CatalogNumber = ?",key)[1,1]
end

# the reagent and product registered for a lot's supplier and catalog number, or `(nothing,nothing)`
function _registered_product(lot::Lot)
    for (reagent,products) in CHESSCore.product_registry, product in products
        isequal(product.supplier,lot.supplier) && isequal(product.catalog_number,lot.catalog_number) &&
            return reagent,product
    end
    return nothing,nothing
end

function upload_observation(labware::Labware,lot::Lot;ledger_id::Integer=append_ledger(),kwargs...)
    product_id=get_product_id(lot)
    quantity = ismissing(lot.quantity) ? (missing,missing) : (Float64(ustrip(lot.quantity)),string(unit(lot.quantity)))
    received = ismissing(lot.received) ? missing : string(lot.received)
    _insert_observation("ObservedLots",["LocationID","ProductID","Lot","GTIN","Quantity","Unit","Cost","Received","Notes"],
        (location_id(labware),product_id,lot.lot,lot.gtin,quantity...,lot.cost,received,lot.notes);ledger_id=ledger_id,kwargs...)
end

"""
    reconstruct_lot(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> Union{Lot,Nothing}

The [`Lot`](@ref) most recently observed for the location as of `sequence_id` and `time`, or `nothing`
when none was observed.

See also: [`reconstruct_lot!`](@ref).
"""
function reconstruct_lot(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    rows = if reconstruction_mode[] === :legacy
        _reconstruct_lot_rows_global(location_id,sequence_id,time)
    else
        # the location's own observations first, then the visibility rule on those rows
        query_db("""
            SELECT p.Supplier, p.CatalogNumber, o.Lot, o.GTIN, o.Quantity, o.Unit, o.Cost, o.Received, o.Notes
            FROM ObservedLots o CROSS JOIN Ledger vl ON vl.ID = o.LedgerID AND $(_visible_predicate("vl","?","?","?"))
            INNER JOIN Products p ON o.ProductID = p.ID
            WHERE o.LocationID = ? ORDER BY vl.SequenceID DESC, o.ID DESC LIMIT 1
            """,(typemin(Int64),sequence_id,db_time(time),db_time(time),location_id))
    end
    nrow(rows)==0 && return nothing
    r=rows[1,:]
    quantity = ismissing(r.Quantity) ? missing : r.Quantity*_parse_unit(r.Unit)
    received = ismissing(r.Received) ? missing : Date(r.Received)
    return Lot(r.Supplier,r.CatalogNumber,r.Lot;gtin=r.GTIN,quantity,cost=r.Cost,received,notes=r.Notes)
end

function _reconstruct_lot_rows_global(location_id::Integer,sequence_id::Integer,time::DateTime)
    return query_db("""
        WITH ledger_subset (ID,SequenceID) AS (
            SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
        SELECT p.Supplier, p.CatalogNumber, o.Lot, o.GTIN, o.Quantity, o.Unit, o.Cost, o.Received, o.Notes
        FROM ObservedLots o INNER JOIN ledger_subset l ON o.LedgerID = l.ID INNER JOIN Products p ON o.ProductID = p.ID
        WHERE o.LocationID = ? ORDER BY l.SequenceID DESC, o.ID DESC LIMIT 1
        """,(db_time(time),sequence_id,location_id))
end

"""
    reconstruct_lot!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now())

Set the lot of a [`Labware`](@ref) to its reconstructed lot. Other locations have no lot and are left
unchanged. Arguments work as in [`reconstruct_lot`](@ref).
"""
function reconstruct_lot!(location::Labware,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    location.lot=reconstruct_lot(location_id(location),sequence_id,time)
    return nothing
end
reconstruct_lot!(::Location,args...) = nothing
