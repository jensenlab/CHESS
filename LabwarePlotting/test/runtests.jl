using Test, LabwarePlotting, Plots

@testset "letter_code" begin
    @test letter_code(1) == "A"
    @test letter_code(26) == "Z"
    @test letter_code(27) == "AA"
    @test letter_code(28) == "AB"
    @test letter_code(52) == "AZ"
    @test letter_code(53) == "BA"
    @test_throws DomainError letter_code(0)
end

@testset "wellnames" begin
    names = wellnames(trues(2,3))
    @test names == ["A1" "A2" "A3"; "B1" "B2" "B3"]
end

@testset "shape primitives" begin
    @test rectangle(0,0,1,1) isa Shape
    xs,ys = circle(0,0,2)
    @test length(xs) == length(ys) == 500
    xs,ys = square(0,0,2)
    @test length(xs) == length(ys) == 4
    xs,ys = slas_rectangle(0,0,2)
    @test length(xs) == length(ys) == 4
end

@testset "plot_grid/plot_grid!" begin
    @test plot_grid(trues(2,2)) isa Plots.Plot
    @test plot_grid(trues(2,2);fillcolors=fill("steelblue",2,2)) isa Plots.Plot
    plt = plot()
    @test plot_grid!(plt,trues(3,3)) isa Plots.Plot
end

@testset "plot_grid: haloframe" begin
    fillcolors = fill("white",2,2)
    @test plot_grid(trues(2,2);fillcolors=fillcolors,haloframe=nothing) isa Plots.Plot

    halo = Matrix{Union{Nothing,String}}(nothing,2,2)
    halo[1,1] = "blue"
    @test plot_grid(trues(2,2);fillcolors=fillcolors,haloframe=halo) isa Plots.Plot
    @test plot_grid(trues(2,2);fillcolors=fillcolors,haloframe=halo,halo_inset=0.4) isa Plots.Plot

    # a haloframe that's `missing` everywhere behaves like no halo at all
    halo_missing = Matrix{Union{Missing,String}}(missing,2,2)
    @test plot_grid(trues(2,2);fillcolors=fillcolors,haloframe=halo_missing) isa Plots.Plot
end

@testset "place_shape!" begin
    plt = plot_grid(trues(2,2))
    @test place_shape!(plt,circle,1,1,0.8;color="black") isa Plots.Plot
end

@testset "plot_heatmap!" begin
    plt = plot_grid(trues(2,2))
    @test plot_heatmap!(plt,[1.0 NaN; 2.0 3.0]) isa Plots.Plot
end

@testset "role_palette" begin
    colors = role_palette([:positive,:negative])
    @test Set(keys(colors)) == Set([:positive,:negative])
    @test colors[:positive] != colors[:negative]
    overridden = role_palette([:positive,:negative];overrides=Dict(:positive=>"red"))
    @test overridden[:positive] == "red"

    @testset "non-Symbol keys and a named palette (group coloring)" begin
        group_colors = role_palette(1:4;palette="Pastel2")
        @test Set(keys(group_colors)) == Set(1:4)
        @test length(unique(values(group_colors))) == 4
        # default palette is unchanged for existing (Symbol-keyed, role) callers
        @test role_palette([:positive,:negative]) == role_palette([:positive,:negative];palette="Set2")
    end
end
