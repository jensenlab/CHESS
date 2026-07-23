module CHESSDatabase

using CHESSCore
import CHESSCore: children, parent, location_id, name # extend rather than shadow (Barcode/Run also define these)
using
    SQLite, # database framework CHESS uses.
    DBInterface, # standard interface for database connections
    DataFrames, # for SQL returns
    UUIDs, # used for generating default location names
    Dates, # used for converting time objects.
    Unitful # unit tracking for transfer quantities, timestamps, etc.

include("./database.jl")
include("./db_utils.jl")
include("./ledger.jl")
include("./barcodes/barcodes.jl")
include("./runs/run.jl")
include("./caching.jl")
include("./uploads.jl")
include("./generate_location.jl")
include("./commit_location.jl")

include("./barcode_queries.jl")
include("./experiment_run_queries.jl")
include("./instrument_settings.jl")

include("./encumbrances.jl")

# reconstruction
include("./reconstruction/reconstruction_utils.jl")
include("./reconstruction/reconstruct_contents.jl")
include("./reconstruction/reconstruct_parent.jl")
include("./reconstruction/reconstruct_children.jl")
include("./reconstruction/reconstruct_attributes.jl")
include("./reconstruction/reconstruct_environment.jl")
include("./reconstruction/reconstruct_lock.jl")
include("./reconstruction/reconstruct_activity.jl")
include("./reconstruction/reconstruct_reads.jl")
include("./reconstruction/reconstruct_location.jl")
# cache repair
include("./validation_and_repair/repair_content_caches.jl")
include("./validation_and_repair/repair_movement_caches.jl")
include("./validation_and_repair/repair_environment_attribute_caches.jl")
include("./validation_and_repair/repair_activity_caches.jl")
include("./validation_and_repair/repair_lock_caches.jl")
include("./validation_and_repair/cache_repair.jl")
include("./validation_and_repair/validation.jl")

# ledger updates
include("./update_operation.jl")

#database
export create_db
#ledger.jl
export append_ledger,insert_ledger,update_ledger,replace_ledger
#db_utils
export connect_SQLite, execute_db, query_db,sql_transaction,sql_commit,sql_rollback,julia_time,db_time, get_all_attributes
#uploads
export  update,upload, upload_barcode, update_barcode , process_update,upload_read
export upload_instrument_setting, get_instrument_settings, get_reads, reconstruct_reads, reconstruct_reads!
#queries
export get_last_ledger_id,get_last_sequence_id,get_last_encumbrance_id,get_last_protocol_id,get_sequence_id
#generate_location
export generate_location
#commit_location
export commit_location!, release_location
#caching and fetching
export cache , get_location_info
#reconstruct_location.jl
export reconstruct_location,reconstruct_location!
#reconstruct_contents.jl
export reconstruct_contents, reconstruct_contents!
#reconstruct_parent.jl
export reconstruct_parent , reconstruct_parent!
#reconstruct_children.jl
export reconstruct_children,reconstruct_children!
#reconstruct_attributes.jl
export reconstruct_attributes,reconstruct_attributes!
#reconstruct_environment
export reconstruct_environment,reconstruct_environment!
#reconstruct_lock.jl
export reconstruct_lock,reconstruct_lock!
#reconstruct_activity.jl
export reconstruct_activity,reconstruct_activity!
#barcodes
export Barcode, assign_barcode!,assign_barcode,barcode
#barcode queries
export get_barcode
export upload_protocol,upload_experiment, encumber, upload_encumbrance,encumber_cache, upload_run
# run queries
export get_run, get_all_runs
# runs
export Run

end # module CHESSDatabase
