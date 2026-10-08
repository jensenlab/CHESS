# CHESSExperiments API Reference

Experimental designs: the [`Experiment`](@ref) type and its parameters, factors and design parsing,
resolving rows into stocks and conditions, and control expansion and blocking. See
[Experimental Designs](../manual/experiments.md) for a worked example. The main entry points are
[`parse_design`](@ref), [`resolve_stock`](@ref), and [`schedule_blocked_layout`](@ref).

```@autodocs
Modules = [CHESSExperiments]
```

## Scheduling (with RunMaps and PlateMaps)

These methods are defined in the `CHESSExperimentsRunMapsExt` extension, which loads when
`RunMaps` and `PlateMaps` are loaded alongside `CHESSExperiments`.

```@autodocs
Modules = [Base.get_extension(CHESSExperiments, :CHESSExperimentsRunMapsExt)]
```
