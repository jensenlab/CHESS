

The workflow for using Pourfecto is: 

1. Define source labware containing reagent stocks.
2. Define target labware.
3. Select available instrument configurations.
4. Run the Pourfecto planning and scheduling algorithm to create a solved [`Pourcast`](@ref)
5. Compile and Inspect the resulting `Pourcast`.


## Defining Source and Labware

The easiest way to define the source and target labware inputs is to use Pourfecto's DataFrame interface. 

```julia
using Pourfecto, CSV, DataFrames

# load properly formatted source DataFrames 
source_value_df = CSV.read("<source_value_file>.csv",DataFrame)
source_unit_df = CSV.read("<source_unit_file>.csv",DataFrame)
# generate source labware 
sources = df_to_labware(source_value_df,source_unit_df)
# load target DataFrames
target_value_df = CSV.read("<target_value_file>.csv")
target_unit_df = CSV.read("<target_unit_file>.csv")
# generate target labware 
targets = df_to_labware(target_value_df,target_unit_df)
```
!!! note 
    Pourfecto internally converts the DataFrames into [JLIMS](https://github.com/jensenlab/JLIMS) Labware objects.  

## Selecting Available Configurations 

Pourfecto defines liquid handler instances as [`Configuration`](@ref) objects. Configurations combine an instrument's pipetting [`Head`](@ref) with a [`Deck`](@ref) that can hold the source and target labware. Users can define custom configurations, but Pourfecto provides an assortment of default configurations in the [`configurations`](@ref) dictionary.

In this example we will select two defualt Configurations: 
1) an eight channel pipette (oriented in the vertical direction)
2) a Hamilton Nimbus (configured with slots for 50 mL conical tubes and a single SLAS plate slot, a common configuration in the Jensen Lab)

```julia 
 
available_configs = [configurations["eight_channel_vertical"],configurations["nimbus"]] 
```

## Running the Pourfecto algorithm 

Pourfecto's main function, [`pourfecto`](@ref), is a flexible method for running the Pourfecto algorithm and compiling Pourcasts. Given an output directory, `pourfecto` creates an optimal liquid handling plan and schedule, saves it as a `Pourcast`, and compiles the Pourcast into executable instrument files. When run in this mode, the pourfecto method automatically checks the solution quality before compiling, and throws errors if the solution falls outside a pre-specified tolerance. 

```julia 
pourcast = pourfecto("<output_directory>", sources, targets, available_configs) 
```

Pourcasts can also be generated without providing an output directory. In this case, the pourcast must be manually compiled.

```julia 
pourcast = pourfecto(sources,targets,available_configs) 
compile("<output_directory>",pourcast) 
```
!!! warning 
    Pourfecto does not guarantee solutions that perfectly generate targets or make efficient use of resources. It is highly recommended that users check solutions before compiling Pourcasts and executing them in the lab. 


## Inspecting Solutions 

`pourfecto` creates the following file structure when provided with an `<output_directory>` 

```
<output_directory>/
├── pourcast.json
├── target_plate_images/
│   ├── <plate name 1>.png
│   └── ... 
├── <Configuration 1>/
│   ├── <protocol 1>/  
│   │   ├── loading_instructions.png 
│   │   ├── loading_table.csv
│   │   └── instrument files ... 
│   ├── <protocol2>/  ... 
│   └── ... 
├── <Configuration 2>/
│   ├── <protocol 1>/  
│   │   ├── loading_instructions.png 
│   │   ├── loading_table.csv
│   │   └── instrument files ... 
│   └── ...
└── ...
``` 

- `pourcast.json`: The Pourcast is automatically saved in a .json format
- `target_plate_images/`: A heatmap of each target plate is generated showing the planned final volume of each well, which is helpful for verifying solutions visually. 
- `<Configuration>/`: Instrument files are written into Configuration-specific folders, where each subfolder within is an executable protocol with a randomly generated name. Protocol subfolders each contain instrument loading instructions in table and image formats. 

