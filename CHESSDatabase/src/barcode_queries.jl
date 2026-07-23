

function get_barcode(barcode::String)

    x="""SELECT Name, LocationID FROM Barcodes WHERE Barcode = ? LIMIT 1"""
    out_db=query_db(x,(barcode,))
    if nrow(out_db) == 0 
        error("Invalid Barcode: $barcode not found in database")
    end 
    out=out_db[1,:]

    bc= Barcode(barcode,out.Name,out.LocationID)

    return bc 
end 

function get_all_barcodes(location_id::Integer;return_limit::Integer=3)

    x="""SELECT Barcode,Name FROM Barcodes WHERE LocationID = ? LIMIT ?"""

    out=query_db(x,(location_id,return_limit))
    bcs = Barcode[] 
    for row in eachrow(out) 
        bc = Barcode(row.Barcode,row.Name,location_id)
        push!(bcs,bc)
    end 
    return bcs 
end 
