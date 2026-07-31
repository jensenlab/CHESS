using Pourfecto, JLIMS, Unitful, Random, DataFrames, CSV
Random.seed!(48207531)

reagents = [string_to_reagent("R$i",Solid) for i in 1:48]
water = string_to_reagent("water",Liquid)


source_deep_well = generate(labwares["DeepWP96"])



for r in eachindex(reagents)
    st = 2u"ml" * water  + 1u"g" * reagents[r] 
    well = children(source_deep_well)[r]
    well.stock = st
    well2 = children(source_deep_well)[r+length(reagents)]
    well2.stock =st 
end 

water_deep_reservoir = generate(labwares["DeepReservoir"])

children(water_deep_reservoir)[1].stock = 100u"mL" * water 

water_bottle = generate(labwares["Bottle1L"])
children(water_bottle)[1].stock = 1u"L" * water 


n_plates = 5 
target_plates = Labware[]

for p in 1:n_plates 
    plt = generate(labwares["WP96"])
    for well in children(plt) 
        well.stock = 200u"µL" * water 
        for r in reagents 
            if rand() <= 0.5
                well.stock += 0.1u"mg" * r 
            end 
        end 
    end 
    push!(target_plates,plt)
end 


priority = PriorityDict("water" => typemax(UInt64))
source_labware = [source_deep_well,water_deep_reservoir,water_bottle]
source_labware2 = [source_deep_well,water_bottle]
configs = ["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master","cobra","nimbus","tempest"]

pc1,time1 = @timed pourfecto(source_labware,target_plates ,configs;priority=priority,grb_timelimit=45) # run once bc of precompile 


pc1,time1 = @timed pourfecto(source_labware,target_plates ,configs;priority=priority,grb_timelimit=45)


pc2 ,time2 = @timed pourfecto(source_labware2,target_plates,configs;priority=priority,grb_timelimit=45)

pc3, time3 = @timed  pourfecto(source_labware,target_plates,configs;priority=priority,objective="min_active_flow",quiet=false,grb_timelimit=100)

pc4, time4 = @timed pourfecto(source_labware,target_plates,configs;priority=priority,objective="min_config",quiet=false,grb_timelimit=100)

pcs = [pc1,pc2,pc3,pc4]
tms = [time1,time2,time3,time4]

names = ["All Sources" ,"No Reservoir", "Minimize Active Flows","Minimize Configurations"]

ts = transfers.(pcs)
fs = flows.(pcs) 
as = map(x->flows(x) .> 1e-4,pcs)

config_trfs = map(x-> sum.(transfers_by_config(x)),pcs) 


df = DataFrame()

## Benchmarking experiment output 

for i in eachindex(pcs) 

    d = (name = names[i], single_channel = config_trfs[i][1], eight_channel = sum(config_trfs[i][2:3]),plate_master = config_trfs[i][4],cobra= config_trfs[i][5],nimbus=config_trfs[i][6], tempest=config_trfs[i][7],transfers= sum(ts[i]),flows=sum(fs[i]),active_flows = sum(as[i]),time = tms[i])
    push!(df,d)
end 


CSV.write("./benchmarking/combinatorial_media_results.csv",df)

