abstract type Cobra <: InstrumentModel end

piston_cobra = Piston{ContinuousActuator,MultiRepeater}(
    (25u"µL",800u"µL"),
    (0.3u"µL",800u"µL"),
    1.125
)


cobra_head_mask = falses(4,4) 
for i in 1:4 
    cobra_head_mask[i,i] = true 
end 



cobra_channels = fill(Channel(1000u"µL"),4) 

cobra_head = Head{Cobra}(fill(piston_cobra,4),cobra_channels, cobra_head_mask)

# Pourfecto-owned, explicit admissibility set -- deliberately decoupled from CHESSCore.LocationKind's
# `categories` field (a different-purpose, externally-owned field with no exclusivity enforced
# between tags). Used for both the deck positions below and the Mask branches further down, so the
# two can't drift apart. Narrower than CHESSLabConstants' :WellPlate category -- Cobra's Mask has no
# support for DeepReservoir/DeepWellColumn/DeepWellRow, so they're deliberately excluded here too.
const cobra_wellplate_kinds = Set([:WP96,:DeepWP96,:WP384])

cobra_deck = [
    ConstrainedPosition("Cobra Source Position",cobra_wellplate_kinds,(1,1),true,false,"rectangle")
    ConstrainedPosition("Cobra Destination Position",cobra_wellplate_kinds,(1,1),false,true,"rectangle")# Only two positions allowed to force new protocols for each pair of labware when slotting
    ]






"""
    cobra_settings 

A dictionary with settings for the cobra 

dictionary keys: 

- `pause=true`: pause over each well before dispensing. If false, the instrument moves continuously while dispensing. 
- `predispenses=0`: force the instrument to predispense a shot of liquid before starting the run. 
- `cobra_path`: the local path the cobra should look for protocol files on the machine running the instrument 
- `washtime`: set how long the wash system should flush the nozzles for 
- `AspPad = 1.125`: Force the cobra to overaspirate by a factor of AspPad. Pourfecto takes this into account when planning 
- `AspDistnace = 1.5`: set how many millimeters above the bottom of the labware the cobra should aspirate from. 


"""
cobra_settings=InstrumentSettings(
    "pause" => true, # pause over each well when dispensing. If false, the instrument sweeps 
    "predispenses" => 0,
    "cobra_path" => "C:\\Users\\Dell\\University of Michigan Dropbox\\Benjamin David\\JensenLab\\Cobra\\",
    "washtime" => 8000, 
    "AspPad" => piston_cobra.deadPad,
    "AspDistance" => 1.5 , 
    "maxShot" => 40
)


configurations["cobra"] = Configuration{Cobra}(cobra_head,cobra_deck,cobra_settings;kind=CHESSCore.location_kinds[:Cobra])


const cobra_names=Dict{Symbol,AbstractString}(
  :DeepWP96=>"Deep Well 2 ml",
  :WP96=>"96 Costar",
  :WP384=>"384 Well p/n 3575 3576")

## Cobra Masks
function Mask(h::Head{Cobra},l::Labware)
    k = kind(l).name

    if k in (:WP96,:DeepWP96)  # 96 well plates only
        asp,asp_positions = sliding_window_mask(h,l,:aspirate)
        disp,disp_positions = sliding_window_mask(h,l,:dispense;v_out=true) # the mask can exit the plate vertically
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    elseif k == :WP384  # 384 well plates only
        asp,asp_positions = sliding_window_mask(h,l,:aspirate;v_spacing=2)
        disp,disp_positions = sliding_window_mask(h,l,:dispense;v_spacing=2,v_out=true) # the mask can exit the plate vertically
        return Mask(h,l,asp,disp,asp_positions,disp_positions)

    else
        Mask(h,l,(x,y,z)->false,(x,y,z)->false,(0,0),(0,0)) # unsupported kind for Cobra -- trivial mask (no aspirate/dispense), matching the generic Head/Labware default in types.jl
    end
end


## Cobra Compiling Functions 

struct CobraProtocolSettings
  source::AbstractString
  destination::AbstractString
  ASPRow::AbstractString
  ASPCol::Integer
  ASPVol::Vector{Real}
  path::Vector{AbstractString}
  liquidclasses::Vector{AbstractString}
end


function fill_protocol_template(settings::InstrumentSettings,protocol::CobraProtocolSettings)
  Source=protocol.source
  Destination=protocol.destination
  ASPRow=protocol.ASPRow
  ASPCol=protocol.ASPCol
  WashTime=settings["washtime"]
  ASPVol=protocol.ASPVol
  Path=protocol.path
  LiquidClass=protocol.liquidclasses
  DispensePause=settings["pause"]
  PredispenseCount=settings["predispenses"]
  distance=settings["AspDistance"]


  template="""
<?xml version="1.0"?>
<Protocol xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <DispenseSpeed>49.6</DispenseSpeed>
  <DispenseOffset>0.25</DispenseOffset>
  <UseDispensePauseMode>$(DispensePause)</UseDispensePauseMode>
  <PredispenseCount>$(PredispenseCount)</PredispenseCount>
  <PredispenseLocation>Source</PredispenseLocation>
  <DeckLocations>
    <PlateSelection>
      <DeckNumber>1</DeckNumber>
      <AdapterName>None</AdapterName>
      <Plates>
        <PlateUseDescription>
          <Name>$(Source)</Name>
          <Use>Aspirate</Use>
        </PlateUseDescription>
      </Plates>
    </PlateSelection>
    <PlateSelection>
      <DeckNumber>2</DeckNumber>
      <AdapterName>None</AdapterName>
      <Plates>
        <PlateUseDescription>
          <Name>$(Destination)</Name>
          <Use>Dispense</Use>
        </PlateUseDescription>
      </Plates>
    </PlateSelection>
  </DeckLocations>
  <RepeatCount>1</RepeatCount>
  <ASPDistanceToBottom>$(distance)</ASPDistanceToBottom>
  <AspirateChannel1StartWell>
    <Row>$(ASPRow)</Row>
    <Column>$(ASPCol)</Column>
  </AspirateChannel1StartWell>
  <StagePostionForAspirate>1</StagePostionForAspirate>
  <AspirateIsSelected>true</AspirateIsSelected>
  <DispenseIsSelected>true</DispenseIsSelected>
  <DispensePattern>Serial</DispensePattern>
  <ParallelDispenseChannels>ChannelsAtoD</ParallelDispenseChannels>
  <WashIsSelected>true</WashIsSelected>
  <WashStrategy>ReservoirA</WashStrategy>
  <WashTimeAMsec>$(WashTime)</WashTimeAMsec>
  <WashTimeBMsec>0</WashTimeBMsec>
  <PurgeAfterDispense>false</PurgeAfterDispense>
  <DispenseChannels>
    <DispenseChannelInfo>
      <AspirateVolume>$(ASPVol[1])</AspirateVolume>
      <DispenseType>AirBacked</DispenseType>
      <DispenseVolume>0.1</DispenseVolume>
      <UseBottleCheck>false</UseBottleCheck>
      <UsesCustomFile>true</UsesCustomFile>
      <CustomFileName>$(Path[1])</CustomFileName>
      <LiquidClassName>$(LiquidClass[1])</LiquidClassName>
      <AspirateAdjustPercentage>0</AspirateAdjustPercentage>
      <DispenseAdjustPercentage>0</DispenseAdjustPercentage>
    </DispenseChannelInfo>
    <DispenseChannelInfo>
      <AspirateVolume>$(ASPVol[2])</AspirateVolume>
      <DispenseType>AirBacked</DispenseType>
      <DispenseVolume>0.2</DispenseVolume>
      <UseBottleCheck>false</UseBottleCheck>
      <UsesCustomFile>true</UsesCustomFile>
      <CustomFileName>$(Path[2])</CustomFileName>
      <LiquidClassName>$(LiquidClass[2])</LiquidClassName>
      <AspirateAdjustPercentage>0</AspirateAdjustPercentage>
      <DispenseAdjustPercentage>0</DispenseAdjustPercentage>
    </DispenseChannelInfo>
    <DispenseChannelInfo>
      <AspirateVolume>$(ASPVol[3])</AspirateVolume>
      <DispenseType>AirBacked</DispenseType>
      <DispenseVolume>0.3</DispenseVolume>
      <UseBottleCheck>false</UseBottleCheck>
      <UsesCustomFile>true</UsesCustomFile>
      <CustomFileName>$(Path[3])</CustomFileName>
      <LiquidClassName>$(LiquidClass[3])</LiquidClassName>
      <AspirateAdjustPercentage>0</AspirateAdjustPercentage>
      <DispenseAdjustPercentage>0</DispenseAdjustPercentage>
    </DispenseChannelInfo>
    <DispenseChannelInfo>
      <AspirateVolume>$(ASPVol[4])</AspirateVolume>
      <DispenseType>AirBacked</DispenseType>
      <DispenseVolume>0.5</DispenseVolume>
      <UseBottleCheck>false</UseBottleCheck>
      <UsesCustomFile>true</UsesCustomFile>
      <CustomFileName>$(Path[4])</CustomFileName>
      <LiquidClassName>$(LiquidClass[4])</LiquidClassName>
      <AspirateAdjustPercentage>0</AspirateAdjustPercentage>
      <DispenseAdjustPercentage>0</DispenseAdjustPercentage>
    </DispenseChannelInfo>
  </DispenseChannels>
  <PurgeAfterDispenseHeight>9</PurgeAfterDispenseHeight>
  <DispenseTestMode>None</DispenseTestMode>
</Protocol>
"""

    return template 

end 


struct SoftLinxSettings
  name::AbstractString
  n_loops::AbstractString
  cobrapath::AbstractString
end 


function fill_softlinx_template(settings::SoftLinxSettings)


    name=settings.name
    n_loops=settings.n_loops
    filepath=settings.cobrapath

    template= """
    <Protocol mc:Ignorable="sap sap2010 sads" PreProtocolWizard="{x:Null}" ActivityLabel="" DisplayName="$(name)" HasConstraints="False" sap2010:WorkflowViewState.IdRef="Protocol_1" SLXId="94f2a419-8579-4634-bba3-e4cdb5050ddb" ToolTip="" UserComments="" isActive="True" isSetup="True"
 xmlns="clr-namespace:Hudson.Workflow.Activities;assembly=Hudson.Workflow.Activities"
 xmlns:hcc="clr-namespace:Hudson.Common.Communications;assembly=Hudson.Common"
 xmlns:hwab="clr-namespace:Hudson.Workflow.Activities.Base;assembly=SoftLinxBaseActivities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:p="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:s="clr-namespace:System;assembly=mscorlib"
 xmlns:sads="http://schemas.microsoft.com/netfx/2010/xaml/activities/debugger"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=mscorlib"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Protocol.Activities>
    <scg:List x:TypeArguments="p:Activity" Capacity="4">
      <LoopActivity ActivityLabel="" DisplayName="Loop Process" HasConstraints="False" sap2010:WorkflowViewState.IdRef="LoopActivity_1" SLXId="0859e942-9da6-494a-b0ac-7f2096172081" ToolTip="Loop $(n_loops) times." UserComments="loop through each protocol file in the folder" isActive="True" isSetup="True">
        <LoopActivity.Activities>
          <scg:List x:TypeArguments="p:Activity" Capacity="8">
            <ModifyVariableActivity Text="{x:Null}" CommandLine="dispense_file = path&amp;&quot;DispenseProtocol&quot;&amp;iLoop&amp;&quot;.xml&quot;" Description="" DisplayName="Modify Variable" HasConstraints="False" sap2010:WorkflowViewState.IdRef="ModifyVariableActivity_2" SLXId="4dd62ca7-9f97-4540-af3a-42a0567673d6" ToolTip="" UserComments="rename the dispense file  according to its iLoop number " isActive="True" isCanceled="False" isSetup="True">
              <ModifyVariableActivity.Arguments>
                <ModifyVariableActivityArguments DisplayExpression="path&amp;&quot;DispenseProtocol&quot;&amp;iLoop&amp;&quot;.xml&quot;" DisplayVariable="dispense_file" Expression="path&amp;&quot;DispenseProtocol&quot;&amp;iLoop&amp;&quot;.xml&quot;" VariableName="dispense_file" />
              </ModifyVariableActivity.Arguments>
              <ModifyVariableActivity.TimeConstraints>
                <scg:List x:TypeArguments="hwab:TimeConstraint" Capacity="0" />
              </ModifyVariableActivity.TimeConstraints>
            </ModifyVariableActivity>
            <AdvancedInstrumentActivity CommandLine="Run" Description="Arguments: dispense_file" DisplayName="Advanced Cobra" HasConstraints="False" sap2010:WorkflowViewState.IdRef="AdvancedInstrumentActivity_1" SLXId="431dcce0-f40a-4460-99c3-ac6e02468696" ToolTip="Command: Run&#xA;Arguments: dispense_file" UserComments="" isActive="True" isCanceled="False" isSetup="True">
              <AdvancedInstrumentActivity.Arguments>
                <InstrumentActivityArguments Address="{x:Reference __ReferenceID8}" ResultVariable="{x:Null}" AddinType="Cobra" Command="Run">
                  <InstrumentActivityArguments.Arguments>
                    <scg:List x:TypeArguments="x:Object" Capacity="4">
                      <x:String>dispense_file</x:String>
                    </scg:List>
                  </InstrumentActivityArguments.Arguments>
                  <InstrumentActivityArguments.hWnd>
                    <s:IntPtr />
                  </InstrumentActivityArguments.hWnd>
                </InstrumentActivityArguments>
              </AdvancedInstrumentActivity.Arguments>
              <AdvancedInstrumentActivity.TimeConstraints>
                <scg:List x:TypeArguments="hwab:TimeConstraint" Capacity="0" />
              </AdvancedInstrumentActivity.TimeConstraints>
            </AdvancedInstrumentActivity>
            <ModifyVariableActivity Text="{x:Null}" CommandLine="iLoop = iLoop +1" Description="" DisplayName="Modify Variable" HasConstraints="False" sap2010:WorkflowViewState.IdRef="ModifyVariableActivity_1" SLXId="b2a9e9ea-a7b6-4327-bd6e-8fc370ab7dac" ToolTip="" UserComments="iterate loop" isActive="True" isCanceled="False" isSetup="True">
              <ModifyVariableActivity.Arguments>
                <ModifyVariableActivityArguments DisplayExpression="iLoop +1" DisplayVariable="iLoop" Expression="iLoop +1" VariableName="iLoop" />
              </ModifyVariableActivity.Arguments>
              <ModifyVariableActivity.TimeConstraints>
                <scg:List x:TypeArguments="hwab:TimeConstraint" Capacity="0" />
              </ModifyVariableActivity.TimeConstraints>
            </ModifyVariableActivity>
          </scg:List>
        </LoopActivity.Activities>
        <LoopActivity.Activities2>
          <scg:List x:TypeArguments="p:Activity" Capacity="0" />
        </LoopActivity.Activities2>
        <LoopActivity.Arguments>
          <LoopActivityArguments CountExpression="$(n_loops)" IsBoolean="False" IsCounted="True" IsInfinite="False" TrueExpression="" />
        </LoopActivity.Arguments>
        <LoopActivity.TimeConstraints>
          <scg:List x:TypeArguments="hwab:TimeConstraint" Capacity="0" />
        </LoopActivity.TimeConstraints>
      </LoopActivity>
    </scg:List>
  </Protocol.Activities>
  <Protocol.Activities2>
    <scg:List x:TypeArguments="p:Activity" Capacity="0" />
  </Protocol.Activities2>
  <Protocol.InitialValues>
    <scg:Dictionary x:TypeArguments="x:String, hwab:Variable" />
  </Protocol.InitialValues>
  <Protocol.Interfaces>
    <hwab:Interface x:Key="{x:Reference __ReferenceID4}" SetupData="{x:Array Type=x:String}" AddinType="Cobra">
      <hwab:Interface.Address>
        <hcc:SLAddress x:Name="__ReferenceID4" Name="Cobra" Workcell="SoftLinx" />
      </hwab:Interface.Address>
    </hwab:Interface>
    <hwab:Interface x:Key="{x:Reference __ReferenceID5}" SetupData="{x:Array Type=x:String}" AddinType="Files">
      <hwab:Interface.Address>
        <hcc:SLAddress x:Name="__ReferenceID5" Name="Files" Workcell="SoftLinx" />
      </hwab:Interface.Address>
    </hwab:Interface>
    <hwab:Interface x:Key="{x:Reference __ReferenceID6}" SetupData="{x:Null}" AddinType="FileTemplateEditor">
      <hwab:Interface.Address>
        <hcc:SLAddress x:Name="__ReferenceID6" Name="FileTemplateEditor" Workcell="SoftLinx" />
      </hwab:Interface.Address>
    </hwab:Interface>
    <hwab:Interface x:Key="{x:Reference __ReferenceID7}" SetupData="{x:Null}" AddinType="CSVReader">
      <hwab:Interface.Address>
        <hcc:SLAddress x:Name="__ReferenceID7" Name="CSVReader" Workcell="SoftLinx" />
      </hwab:Interface.Address>
    </hwab:Interface>
  </Protocol.Interfaces>
  <Protocol.TimeConstraints>
    <scg:List x:TypeArguments="hwab:TimeConstraint" Capacity="0" />
  </Protocol.TimeConstraints>
  <Protocol.Variables>
    <hwab:VariableList SLXHost="{x:Null}">
      <hwab:Variable x:TypeArguments="hwab:Interface" Value="{x:Reference __ReferenceID0}" x:Key="SoftLinx.Files" Name="SoftLinx.Files" Prompt="False">
        <hwab:Variable.Default>
          <hwab:Interface SetupData="{x:Null}" x:Name="__ReferenceID0" AddinType="Files">
            <hwab:Interface.Address>
              <hcc:SLAddress Name="Files" Workcell="SoftLinx" />
            </hwab:Interface.Address>
          </hwab:Interface>
        </hwab:Variable.Default>
      </hwab:Variable>
      <hwab:Variable x:TypeArguments="hwab:Interface" Value="{x:Reference __ReferenceID1}" x:Key="SoftLinx.FileTemplateEditor" Name="SoftLinx.FileTemplateEditor" Prompt="False">
        <hwab:Variable.Default>
          <hwab:Interface SetupData="{x:Null}" x:Name="__ReferenceID1" AddinType="FileTemplateEditor">
            <hwab:Interface.Address>
              <hcc:SLAddress Name="FileTemplateEditor" Workcell="SoftLinx" />
            </hwab:Interface.Address>
          </hwab:Interface>
        </hwab:Variable.Default>
      </hwab:Variable>
      <hwab:Variable x:TypeArguments="hwab:Interface" Value="{x:Reference __ReferenceID2}" x:Key="SoftLinx.CSVReader" Name="SoftLinx.CSVReader" Prompt="False">
        <hwab:Variable.Default>
          <hwab:Interface SetupData="{x:Null}" x:Name="__ReferenceID2" AddinType="CSVReader">
            <hwab:Interface.Address>
              <hcc:SLAddress Name="CSVReader" Workcell="SoftLinx" />
            </hwab:Interface.Address>
          </hwab:Interface>
        </hwab:Variable.Default>
      </hwab:Variable>
      <hwab:Variable x:TypeArguments="x:String" x:Key="dispense_file" Default="&quot;&quot;" Name="dispense_file" Prompt="False" Value="&quot;&quot;" />
      <hwab:Variable x:TypeArguments="x:Double" x:Key="iLoop" Default="1" Name="iLoop" Prompt="False" Value="1" />
      <hwab:Variable x:TypeArguments="hwab:Interface" Value="{x:Reference __ReferenceID3}" x:Key="SoftLinx.Cobra" Name="SoftLinx.Cobra" Prompt="False">
        <hwab:Variable.Default>
          <hwab:Interface SetupData="{x:Array Type=x:String}" x:Name="__ReferenceID3" AddinType="Cobra">
            <hwab:Interface.Address>
              <hcc:SLAddress x:Name="__ReferenceID8" Name="Cobra" Workcell="SoftLinx" />
            </hwab:Interface.Address>
          </hwab:Interface>
        </hwab:Variable.Default>
      </hwab:Variable>
      <hwab:Variable x:TypeArguments="x:String" x:Key="path" Default="$(filepath)" Name="path" Prompt="False" Value="$(filepath)" />
    </hwab:VariableList>
  </Protocol.Variables>
  <sap2010:WorkflowViewState.ViewStateManager>
    <sap2010:ViewStateManager>
      <sap2010:ViewStateData Id="ModifyVariableActivity_2" sap:VirtualizedContainerService.HintSize="413,79" />
      <sap2010:ViewStateData Id="AdvancedInstrumentActivity_1" sap:VirtualizedContainerService.HintSize="413,79" />
      <sap2010:ViewStateData Id="ModifyVariableActivity_1" sap:VirtualizedContainerService.HintSize="413,79" />
      <sap2010:ViewStateData Id="LoopActivity_1" sap:VirtualizedContainerService.HintSize="453,461" />
      <sap2010:ViewStateData Id="Protocol_1" sap:VirtualizedContainerService.HintSize="453,597" />
    </sap2010:ViewStateManager>
  </sap2010:WorkflowViewState.ViewStateManager>
  <sads:DebugSymbol.Symbol>dztDOlxVc2Vyc1xEZWxsXERvY3VtZW50c1wyMDIzXzA4XzA4X0plbnNlbkRpc3BlbnNlQ29icmEuc2x2cAUBAZUBDAEBDwc+FgEFEg0ZJgEOGg0qKgELKw0yJgEI</sads:DebugSymbol.Symbol>
</Protocol>

    """

return template

end 



########## Cobra Dispense Files ###########
function snake_order(r,c;channel=isodd) # generate the order of dispenses for a plate of any size. The cobra snakes through each plate: ie. starts in row 1 and goes across the row forward, shifts down to row 2 and goes backward across the row  etc.
  n=r*c
  N=1:n
  N=reshape(N,r,c)
  idxs=[0 for _ in 1:n]
  counter=1
  for i in 1:r
    for j in (channel(i) ? (1:c) : reverse(1:c))
      idxs[counter]=N[i,j]
      counter+=1
    end 
  end 
  return idxs 
end


function design_to_protocols(directory::AbstractString,design::DataFrame,source::CHESSCore.Labware,destination::CHESSCore.Labware,config::Configuration{Cobra})
  pad=settings(config)["AspPad"]
  maxASP=ustrip.(uconvert.(u"µL",map(x->x.asp[2],pistons(head(config))) ))
  maxShot=settings(config)["maxShot"]
  cobra_location=settings(config)["cobra_path"]
  # Check for issues with the design

    r_in,c_in=CHESSCore.shape(source)
    n_in=r_in*c_in
    r_out,c_out=CHESSCore.shape(destination)
    n_out=r_out*c_out
    des=Matrix(design)
    r,c=size(des)
    if r != n_out
      error("output plate size does not match design. Expected design to have $(n_out) rows. Pad design with empty experiments if needed or split the design across multiple destination plates.")
    end 
    if c > n_in 
      error("number of design reagents exceeds the size of the source plate. Split the design across multiple source plates")
    end 
    if mod(r,4) != 0 
        ArgumentError("The number of design columns must be a multiple of 4")
    end 
    filecounter=1
    rows=string.(collect('A':4:'Z'))[1:fld(r_in,4)]
    cols=1:c_in
    pos=collect(Iterators.product(rows,cols))
    positions=reshape(pos,prod(size(pos)),1)
    protocols=String[]
  # Start the protocol generation process  
    for set in 1:fld(c,4) # loop through sets of four locations in the source plate 
      idxs=4*(set-1)+1:4*(set-1)+4
      d = ustrip.(Matrix(des[:,idxs])) # grab the appropriate source wells from the design 
      while sum(d)>0  # while there is still liquid to be dispensed in the set 
        to_dispense=zeros(size(d))
        fileidxs=Int64[]
        for channel in 1:4
          disp_order=snake_order(r_out,c_out; channel= (isodd(channel) ? iseven : isodd)) # the even channels snake opposite to the odd ones ( yes i know this is confusing, I suggest you watch the cobra run)
          total_vols=sum(to_dispense[:,channel])*pad
          for idx in disp_order
            if  total_vols < maxASP[channel]  # grab all of the rows we can complete with a single pass 
                margin= max((maxASP[channel] - total_vols),0)
                to_dispense[idx,channel]=min(d[idx,channel],maxShot,margin/pad)
                total_vols=sum(to_dispense[:,channel])*pad
            else
              break 
            end 
          end 
          x=reshape(to_dispense[:,channel],r_out,c_out)
          x=DataFrame(x,:auto)
          filename=joinpath(directory,"DispenseFile$(filecounter).csv")
          push!(fileidxs,filecounter)
          filecounter+=1
          CSV.write(filename,x;header=false)   
        end 
        d=d.-to_dispense



        ASPRow=positions[set][1]
        ASPCol=positions[set][2]
        ASPVol=vec(sum(to_dispense,dims=1))*pad
        liquidclasses=fill("Water",4)
        src=cobra_names[kind(source).name]
        dst=cobra_names[kind(destination).name]
        protocol_name=basename(directory)
        path=[cobra_location*"$(protocol_name)\\DispenseFile$(k).csv" for k in fileidxs]
        protocol_settings=CobraProtocolSettings(src,dst,ASPRow,ASPCol,ASPVol,path,liquidclasses)
        #settings=CobraSettings(source,destination,positions[set][1],positions[set][2],washtime,vec(sum(to_dispense,dims=1))*pad,cobra_path,liquidclasses[idxs],dispensepause,predispensecount)
        push!(protocols,fill_protocol_template(settings(config),protocol_settings))
      end  
    end 
    return protocols
end 
        


function protocols_to_softlinx(n_protocols::Int64,experiment_name::String,cobra_location::String)
    settings=SoftLinxSettings(experiment_name,string(n_protocols),string(cobra_location,experiment_name,"\\"))
    softlinx_out=fill_softlinx_template(settings)
    return softlinx_out
end 

# SEE /compiler/slotting.jl for main `packing_greedy` definition
function packing_greedy(pairings::Vector{Tuple{Labware,Labware}},config::Configuration{Cobra};kwargs...)

    # cobra only has two slots, one dedicated to source and one to destination. A greedy packing arrangement just loops through the pairings
    slotting_dicts=SlottingDict[]
    remaining= deepcopy(pairings)
    for pairing in pairings
        d=SlottingDict(
            pairing[1] => (deck(config)[1],1),
            pairing[2] => (deck(config)[2],1)
        )
        push!(slotting_dicts,d)
    end 
    return slotting_dicts 
end

#=
function convert_design(design::DataFrame,labware::Vector{<:Labware},slotting::SlottingDict,config::Configuration{Cobra})


  all(map(x-> x[1] in deck(config),values(slotting))) || ArgumentError("All deck positions in the SlottingDict must be present on the deck")
  source_cols=[]
  dispense_rows=[]
  source_names= []
  for col in 1:ncol(design)
      lw=get_labware(labware,col)
      if can_aspirate(head(config),slotting[lw][1],lw) 
          push!(source_cols,col)
          push!(source_names,CHESSCore.name(lw))
      end 
  end 
  for row in 1:nrow(design) 
      lw=get_labware(labware,row)
      if can_dispense(head(config),slotting[lw][1],lw)
          push!(dispense_rows,row)
      end 
  end 

  out_design = design[dispense_rows,source_cols]
  dest_labware= filter(x-> can_dispense(head(config),slotting[x][1],x),labware)
  src_labware =filter(x-> can_aspirate(head(config),slotting[x][1],x),labware)
  if length(dest_labware) > 1 
      error("multiple destination labware detected. Cobra only supports a single destination labware")
  end 

  if length(src_labware) > 1 
    error("multiple source labware detected. Cobra only suppors a single source labware.")
  end 
  return out_design, src_labware[1],dest_labware[1]
end 
=#


function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Cobra},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);kwargs...) 
    if ~isdir(directory)
      mkdir(directory)
    end 
    if length(source) > 1 
      throw(ArgumentError("multiple source labware detected. Cobta only supports a single source labware"))
    end 
    if length(target) > 1 
      throw(ArgumentError("multiple target labware detected. Cobra only supports a single target"))
    end 


    protocols=design_to_protocols(directory,permutedims(design),source[1],target[1],config) # cobras compiler works on a T x S matrix instead of a S x T 
    protocol_names=["DispenseProtocol$(k).xml" for k in 1:length(protocols)]
    full_protocol_names=joinpath.((directory,),protocol_names)
    map((loc,protocol) -> write(loc,protocol),full_protocol_names,protocols)
    n_protocols=length(protocols)
    protocol_name = basename(directory)
    softlinx=protocols_to_softlinx(n_protocols,protocol_name,settings(config)["cobra_path"])
    full_softlinx_name=joinpath(directory,"$(protocol_name).slvp")
    write(full_softlinx_name,softlinx)
    return nothing 
end



