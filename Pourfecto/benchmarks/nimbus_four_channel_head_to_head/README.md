# Single-channel vs 4-channel Nimbus: operation counts

Compares the operations needed to run the same transfer designs on the single-channel Nimbus
(`configurations["nimbus"]`) and the 4-channel Nimbus (`configurations["nimbus_four_channel"]`), and
measures what two of the 4-channel compiler's optimizations save by switching each one off.

## Why no solver is needed

Operation counts depend only on the compile stage. `generate_instances.jl` builds each transfer design
directly as a reagents × wells volume matrix, and `run_benchmark.jl` compiles it with the
instruments' compile-stage functions (`convert_design`/`batch_design` for single-channel;
`place_labware`/`convert_design_four_channel`/`batch_design_four_channel` for 4-channel). No
`pourfecto()` call and no solver license is involved.

## Instances

Every transfer is 30 µL, from 50 mL conicals (one per reagent) into one 96-well deep-well plate. Three
pipetting schemes set the probability that a reagent goes into any given well:

- `uniform50`: every reagent 0.5.
- `split25_75`: the first half of the reagents (rounded up) 0.25, the rest 0.75.
- `random10_90`: each reagent its own probability, drawn uniformly from [0.1, 0.9].

Reagent counts 1, 2, 4, 8, 12, 16, 20, 24 × 3 seeds × 3 schemes = 72 instances. Each instance is
seeded per (scheme, reagent count, seed).

## Variants

| Variant | What it is |
|---|---|
| `single_channel` | Single-channel Nimbus, default settings |
| `four_channel` | 4-channel Nimbus with every optimization |
| `no_placement` | 4-channel without `place_labware`: tubes stay where greedy slotting puts them, so there is no grouping search, no channel-order search, and no head-aligned tube layout |
| `no_sync_reloads` | 4-channel with `synchronize_reloads=false`: each channel reloads, picks up and disposes on its own schedule instead of on shared trips |

Shared dispense windows and cross-channel action merging aren't ablated: they're what makes the
instrument a 4-channel rather than optimizations layered on top.

## Counts

`results/operation_counts.csv` has one row per instance × variant, with `tips_used`, `tip_pickups`,
`tip_disposals`, `aspirates`, `aspirate_motions`, `dispenses`, `blowouts` and `total_operations`.

- Operations are rows of the compiled protocol. For the 4-channel, one row can act on several
  channels at once (a merged `TipPickup`, a shared `Dispense` window).
- `aspirate_motions` counts distinct rack columns per `Aspirate` row: tubes in different columns
  can't be aspirated in one motion even when the Nimbus runs them from one row.
- `total_operations` = pickups + disposals + aspirates + dispenses + blowouts.
- The single-channel compiler doesn't write its first tip pickup, so its pickups are reconstructed as
  1 + the number of tip changes, with disposals equal to pickups.

Every variant is checked to dispense exactly the design's total volume.

## Running

```bash
julia --project=Pourfecto Pourfecto/benchmarks/nimbus_four_channel_head_to_head/run_benchmark.jl
```

Takes about 3 minutes, most of it the grouping search at 20–24 reagents (about 6–8 s per instance).

## Results

Mean total operations over 3 seeds. "vs single" is the 4-channel's saving over single-channel;
"placement" and "sync" are how much the full 4-channel saves over the variant with that optimization
switched off.

**`uniform50`**

| Reagents | Single | 4-channel | No placement | No sync | vs single | Placement | Sync |
|---|---|---|---|---|---|---|---|
| 1 | 52.7 | 52.7 | 52.7 | 52.7 | 0.0% | 0.0% | 0.0% |
| 2 | 106.3 | 81.3 | 85.0 | 84.3 | 23.5% | 4.3% | 3.6% |
| 4 | 214.0 | 125.0 | 133.0 | 135.7 | 41.6% | 6.0% | 7.9% |
| 8 | 431.7 | 242.7 | 270.0 | 262.7 | 43.8% | 10.1% | 7.6% |
| 12 | 648.3 | 365.7 | 410.3 | 396.0 | 43.6% | 10.9% | 7.7% |
| 16 | 846.0 | 477.7 | 532.3 | 517.0 | 43.5% | 10.3% | 7.6% |
| 20 | 1045.3 | 593.3 | 654.7 | 644.0 | 43.2% | 9.4% | 7.9% |
| 24 | 1288.3 | 720.7 | 779.0 | 776.7 | 44.1% | 7.5% | 7.2% |

**`split25_75`**

| Reagents | Single | 4-channel | No placement | No sync | vs single | Placement | Sync |
|---|---|---|---|---|---|---|---|
| 1 | 26.3 | 26.3 | 26.3 | 26.3 | 0.0% | 0.0% | 0.0% |
| 2 | 107.3 | 90.7 | 91.7 | 92.3 | 15.5% | 1.1% | 1.8% |
| 4 | 219.7 | 125.0 | 142.7 | 133.3 | 43.1% | 12.4% | 6.3% |
| 8 | 411.3 | 223.7 | 267.7 | 244.3 | 45.6% | 16.4% | 8.5% |
| 12 | 633.3 | 347.0 | 387.7 | 372.7 | 45.2% | 10.5% | 6.9% |
| 16 | 841.7 | 452.7 | 517.0 | 489.7 | 46.2% | 12.4% | 7.6% |
| 20 | 1068.7 | 571.0 | 665.7 | 619.0 | 46.6% | 14.2% | 7.8% |
| 24 | 1252.3 | 663.3 | 779.7 | 720.0 | 47.0% | 14.9% | 7.9% |

**`random10_90`**

| Reagents | Single | 4-channel | No placement | No sync | vs single | Placement | Sync |
|---|---|---|---|---|---|---|---|
| 1 | 63.0 | 63.0 | 63.0 | 63.0 | 0.0% | 0.0% | 0.0% |
| 2 | 146.0 | 105.0 | 109.0 | 108.7 | 28.1% | 3.7% | 3.4% |
| 4 | 198.7 | 112.7 | 123.0 | 122.3 | 43.3% | 8.4% | 7.9% |
| 8 | 495.3 | 258.7 | 295.3 | 277.7 | 47.8% | 12.4% | 6.8% |
| 12 | 630.7 | 346.7 | 402.3 | 376.3 | 45.0% | 13.8% | 7.9% |
| 16 | 730.7 | 417.0 | 479.0 | 453.7 | 42.9% | 12.9% | 8.1% |
| 20 | 960.7 | 534.3 | 618.7 | 581.3 | 44.4% | 13.6% | 8.1% |
| 24 | 1223.7 | 663.3 | 777.0 | 718.0 | 45.8% | 14.6% | 7.6% |

The full 4-channel has the fewest operations of all four variants in all 72 instances.

**Breakdown at 24 reagents** (mean over seeds):

| Scheme | Variant | Pickups | Disposals | Aspirates | Aspirate motions | Dispenses | Blowouts | Total |
|---|---|---|---|---|---|---|---|---|
| uniform50 | single_channel | 24.0 | 24.0 | 48.0 | 48.0 | 1168.3 | 24.0 | 1288.3 |
| uniform50 | four_channel | 6.0 | 6.0 | 16.0 | 24.0 | 686.7 | 6.0 | 720.7 |
| uniform50 | no_placement | 6.0 | 6.0 | 16.0 | 34.0 | 745.0 | 6.0 | 779.0 |
| uniform50 | no_sync_reloads | 11.0 | 20.7 | 35.7 | 40.3 | 686.7 | 22.7 | 776.7 |
| split25_75 | single_channel | 24.0 | 24.0 | 48.0 | 48.0 | 1132.3 | 24.0 | 1252.3 |
| split25_75 | four_channel | 6.0 | 6.0 | 17.3 | 25.3 | 627.3 | 6.7 | 663.3 |
| split25_75 | no_placement | 6.0 | 6.3 | 22.0 | 37.0 | 733.3 | 12.0 | 779.7 |
| split25_75 | no_sync_reloads | 12.0 | 21.0 | 37.0 | 40.3 | 627.3 | 22.7 | 720.0 |
| random10_90 | single_channel | 24.0 | 24.0 | 45.3 | 45.3 | 1109.0 | 21.3 | 1223.7 |
| random10_90 | four_channel | 6.0 | 6.3 | 18.3 | 24.3 | 626.3 | 6.3 | 663.3 |
| random10_90 | no_placement | 6.0 | 7.3 | 19.7 | 34.0 | 733.3 | 10.7 | 777.0 |
| random10_90 | no_sync_reloads | 13.3 | 21.3 | 36.3 | 39.0 | 626.3 | 20.7 | 718.0 |

All variants use one tip per reagent (24 at 24 reagents), so the savings come from motions, not
consumables.

### Observations

- **The 4-channel needs roughly 43–47% fewer operations than single-channel from 4 reagents up**, in
  every scheme. Below 4 reagents, fewer channels are in use: at 1 reagent all variants are identical,
  as expected, and at 2 the saving is 15–28%.
- **Dispenses dominate the total and account for most of the saving.** At 24 reagents, about 1,100
  single-channel dispenses become 630–690 shared-window dispenses, about 1.7 channels per dispense
  motion.
- **Placement (grouping, channel order and head-aligned tubes) saves 7–16% at 8+ reagents.** Most of
  it is fewer dispenses: better grouping and channel order put more wells into shared windows. It
  also cuts aspirate motions (about 24–25 vs 34–37 at 24 reagents). Placement matters most when
  reagent demand is uneven (`split25_75`, `random10_90`: 13–15% at 20–24 reagents): grouping similar
  volumes together also avoids extra reload waves (blowouts drop from 11–12 to 6–7).
- **Synchronized reloads save a steady 6–8% from 4 reagents up.** They don't change dispenses at all;
  they collapse per-channel tip pickups, disposals, aspirates and blowouts onto shared trips (at 24
  reagents: about 11–13 pickups, 21 disposals, 36–37 aspirates and 21–23 blowouts down to 6, 6, 16–18
  and 6–7).
