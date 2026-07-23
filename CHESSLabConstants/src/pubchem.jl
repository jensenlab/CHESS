#### Taken from PubChem.jl package ###########################################
function get_json_from_url(url)
    # Send HTTP GET request
    resp = HTTP.get(url)

    # Convert HTTP response to a string and parse it as JSON
    return JSON.parse(String(resp.body))
end

# Get JSON using the CID of the compound
function get_all_data_json(cid)
    return get_json_from_url("https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/$cid/json")
end

function get_pug_rest_json(cid)
    pug_rest_properties=["MolecularWeight"]
    prop_string=join(pug_rest_properties,",")
    return get_json_from_url("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$cid/property/$prop_string/json")
end




# Taken from pubchemprops.py

# Extracts chemical properties from the full JSON
function get_compound_properties(cid::Integer)

    pug_rest_properties=get_pug_rest_json(cid)["PropertyTable"]["Properties"][1] # has molecular weight in dict as a string

    all_data=get_all_data_json(cid)
    all_data_sections=all_data["Record"]["Section"]
    sections_of_interest=["Names and Identifiers","Chemical and Physical Properties"]

    sections_of_interest_data=[]

    for sec in sections_of_interest
        samples = filter(x->x["TOCHeading"]==sec, all_data_sections)
        push!(sections_of_interest_data,samples...)
    end

    ids = ["Experimental Properties"]

    all_data_for_section=[]
    for section_dict in sections_of_interest_data
        samples = filter(x->x["TOCHeading"] in ids, section_dict["Section"])
        push!(all_data_for_section,samples...)
    end

    properties_of_interest=["Density"] #,"Melting Point","Boiling Point","Solubility"]

    property_data=[]
    for object in all_data_for_section
        samples = filter(x->x["TOCHeading"] in properties_of_interest,object["Section"])
        push!(property_data,samples...)
    end

    properties =Dict()
    for property in property_data
        properties[property["TOCHeading"]]=property["Information"][1]["Value"]["StringWithMarkup"][1]["String"]
    end

    return merge(pug_rest_properties, properties)




end


"""
    get_mw_density(cid::Integer)

Query the [PubChem](https://pubchem.ncbi.nlm.nih.gov) database for the checmical properties of the compound with PubChem ID `cid`,

`get_mw_density` returns the molecular weight (g/mol) and density (g/mL) as a Tuple.
"""
function get_mw_density(cid::Integer)
    try
        properties=get_compound_properties(cid);
    catch
        throw(ArgumentError("compound $cid not found, enter chemical properties manually"))
        return(nothing)
    end
    properties=get_compound_properties(cid)
    props=collect(keys(properties))
    density=missing
    molecular_weight=missing
    if "Density" in props
        density = parse(Float64,split(properties["Density"]," ")[1])
    end
    if "MolecularWeight" in props
        molecular_weight=parse(Float64,properties["MolecularWeight"])
    end

    return molecular_weight,density
end
