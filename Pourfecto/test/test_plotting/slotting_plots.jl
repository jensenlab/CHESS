using Pourfecto , CHESSCore, Unitful 


d = configurations["cobra"].deck


lw1 = generate(DeepWP96,"source plate")
lw2 = generate(WP96,"destination plate")


s = Pourfecto.SlottingDict(lw1 => (d[1],1), lw2 => (d[2],1))


Pourfecto.plot_slotting(d,s)


d2 = configurations["nimbus"].deck 

s2 = Pourfecto.SlottingDict(lw2 => (d2[1],1))

Pourfecto.plot_slotting(d2,s2)

Pourfecto.plot_slotting(configurations["mantis"].deck,Pourfecto.SlottingDict())
Pourfecto.plot_slotting(configurations["single_channel"].deck,Pourfecto.SlottingDict())
Pourfecto.plot_slotting(configurations["plate_master"].deck,Pourfecto.SlottingDict())
Pourfecto.plot_slotting(configurations["tempest"].deck,Pourfecto.SlottingDict())