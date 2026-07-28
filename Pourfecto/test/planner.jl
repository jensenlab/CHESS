
## Pourcast to json 

using Pourfecto, CSV, DataFrames , Unitful,CHESSCore

srcs1_vc = CSV.read("test/test_stocks/sources1_vc.csv",DataFrame)
srcs1_vc_units = CSV.read("test/test_stocks/sources1_vc_units.csv",DataFrame)
tgts1_vc = CSV.read("test/test_stocks/targets1_vc.csv",DataFrame)
tgts1_vc_units = CSV.read("test/test_stocks/targets1_vc_units.csv",DataFrame)


sources = df_to_stock(srcs1_vc,srcs1_vc_units)
targets = df_to_stock(tgts1_vc,tgts1_vc_units)



pc = Pourfecto.planner(sources,targets;priority=Pourfecto.PriorityDict("A" => UInt(2)))


j = Pourfecto.pourcast_to_json(pc) 

pc2 =Pourfecto.json_to_pourcast(j) 




## node connections 
using Pourfecto, CSV, DataFrames , Unitful,CHESSCore

c = [configurations["p200"],configurations["plate_master"]]
sl = CHESSCore.build_location(location_kinds[:DeepWP96])
tl = CHESSCore.build_location(location_kinds[:WP96])




asp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.AspNode,c,[sl])
disp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.DispNode,c,[tl])
flow_connections = Pourfecto.compute_flow_connections(Pourfecto.well_names(sl),Pourfecto.well_names(tl),asp_nodes,disp_nodes)
## scheduler 
using Pourfecto, CSV, DataFrames , Unitful,CHESSCore

srcs1_lvc = CSV.read("test/test_stocks/sources1_lvc.csv",DataFrame)
srcs1_lvc_units = CSV.read("test/test_stocks/sources1_lvc_units.csv",DataFrame)

tgts1_lvc = CSV.read("test/test_stocks/targets1_lvc.csv",DataFrame)
tgts1_lvc_units = CSV.read("test/test_stocks/targets1_vc_units.csv",DataFrame)

sl = df_to_labware(srcs1_lvc,srcs1_lvc_units)
tl = df_to_labware(tgts1_lvc,tgts1_lvc_units)

c = [configurations["p200"],configurations["plate_master"]]

pc = Pourfecto.scheduler(sl,tl,c)





