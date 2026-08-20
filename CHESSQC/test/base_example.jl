using CHESSQC, CHESSExperiments, RunMaps, PlateMaps, DataFrames, Distributions, Random

R,C= 16,24

wells = trues(R,C)

pltval(r,c) = pdf(MvNormal([mean([1,R]),mean([1,C])],[3*R 0 ; 0 4*C]),[r,c])

data = [pltval(i,j) for i in 1:R, j in 1:C]
data = data./maximum(data)

n_pos, n_neg = 16, 16
n_runs = R*C - n_pos - n_neg
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
pm = only(schedule_platemap(wells, rm, (:positive, :negative)))

experiment = Experiment(DataFrame(x = 1:n_runs); name = "base_example")
scheduled = schedule_layout(experiment, pm, rm)
layout = CHESSExperiments.layout(scheduled) # qualified: local `layout` below would otherwise shadow the accessor mid-assignment

p = plot_control_data(data,layout)

p2 = plot_plate_data(data,layout)

corrected = data_correction(data,layout,GPCorrection())




p3 = plot_plate_data(corrected,layout)

control_summary(data,layout)

plot(p,p2,p3)


neg_mask = CHESSQC.control_bitmatrix(layout, :negative)
correct, out = CHESSQC.plateerrorGP(data,neg_mask,CHESSQC.absolute;verbose=true)

coords = [transpose(Matrix{Float64}([j i])) for i in 1:R, j in 1:C]

ys = predict_y.((out["gp"],),coords)

yvals = map(x->x[1][1],ys)

avg_neg = mean(data[findall(x->x==true,neg_mask)])

gp_pred = yvals .+ avg_neg

p4 = plot_plate_data(gp_pred,layout)
