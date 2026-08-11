using PlateArrays ,Plots



expt1 = Experiment(92,12,12) # an experiment that has 128 total runs. Each plate that has runs from this experiment should have 12 positive and 12 negative controls 
expt2 = Experiment(24, 6,6) 
expt3 = Experiment(72,12,12)
plate = trues(8,12) # a standard 96 well plate 

plate_arrays = arrayer(plate,expt1,expt2,expt3) 

plts = plot(plate_arrays)
for p in eachindex(plts) 

        savefig(plts[p],"./readme_figs/plate$(p).svg")
end 

