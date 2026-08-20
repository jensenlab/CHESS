using CHESSQC, CHESSExperiments, RunMaps, PlateMaps, DataFrames, Distributions, Random

Random.seed!(123345)

R,C = 8,12

wells = trues(R,C)

pos_dist = Normal(1.5,0.15)

neg_dist = Normal(0.12,0.06)
rundist = Uniform(0.25,1.6)

n_pos,n_neg = 8,8

nruns = R*C - n_pos - n_neg

function mock_runmap(n_runs, n_pos, n_neg)
    rm = RunMap{Any}()
    for i in 1:n_runs
        add_run!(rm, i)
        for p in 1:n_pos
            link!(rm, i, Symbol("pos$p"), :positive)
        end
        for n in 1:n_neg
            link!(rm, i, Symbol("neg$n"), :negative)
        end
    end
    return rm
end

rm = mock_runmap(nruns, n_pos, n_neg)
pm = only(schedule_platemap(wells, rm, (:positive, :negative)))
experiment = Experiment(DataFrame(x = 1:nruns); name = "autosci_example")
scheduled = schedule_layout(experiment, pm, rm)
layout = CHESSExperiments.layout(scheduled) # qualified: local `layout` below would otherwise shadow the accessor mid-assignment

posvals = rand(pos_dist,n_pos)
negvals = rand(neg_dist,n_neg)
runvals = rand(rundist,nruns)

data = zeros(R,C)
for i in 1:nrow(layout)
    r, c = layout.row[i], layout.col[i]
    if layout.positive[i]
        data[r,c] = popfirst!(posvals)
    elseif layout.negative[i]
        data[r,c] = popfirst!(negvals)
    else
        data[r,c] = popfirst!(runvals)
    end
end

p1 = plot_plate_data(data,layout)

p2 = plot_control_data(data,layout)
hline!([0.25],color="red")


savefig(plot(p1,p2,layout=grid(1,2, widths=(4.5/6.5,2/6.5)),size=(1600,400)),"/Users/BDavid/Desktop/auto_sci_controls.svg")


rm2 = mock_runmap(nruns, n_pos, n_neg)
pm2 = only(schedule_platemap(wells, rm2, (:positive, :negative)))
experiment2 = Experiment(DataFrame(x = 1:nruns); name = "autosci_example_bad")
scheduled2 = schedule_layout(experiment2, pm2, rm2)
layout2 = CHESSExperiments.layout(scheduled2) # qualified: local `layout` below would otherwise shadow the accessor mid-assignment

posvals = rand(pos_dist,n_pos)
negvals = rand(neg_dist,n_neg)

negvals[1:2] .= 0.3 .+ 0.3* rand(2)
runvals = rand(rundist,nruns)

data = zeros(R,C)
for i in 1:nrow(layout2)
    r, c = layout2.row[i], layout2.col[i]
    if layout2.positive[i]
        data[r,c] = popfirst!(posvals)
    elseif layout2.negative[i]
        data[r,c] = popfirst!(negvals)
    else
        data[r,c] = popfirst!(runvals)
    end
end

p1 = plot_plate_data(data,layout2)

p2 = plot_control_data(data,layout2)
hline!([0.25],color="red")


savefig(plot(p1,p2,layout=grid(1,2, widths=(4.5/6.5,2/6.5)),size=(1600,400)),"/Users/BDavid/Desktop/auto_sci_controls_bad.svg")
