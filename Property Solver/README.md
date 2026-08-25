# MCET 530 Water State Explorer

This package is an SI-unit minimum viable product for teaching thermodynamic state identification with the supplied textbook tables. It uses ordinary MATLAB functions and CSV files; it does not require CoolProp, Python, REFPROP, or a MATLAB toolbox.

## Start here

1. Keep the entire `MCET530_WaterStateTool` folder together.
2. Open `WaterStateExplorer.m` in MATLAB.
3. Open it in the Live Editor and save it as an `.mlx` file when desired.
4. Edit the two declared quantities in the **Declare any two supported quantities** section.
5. Run the sections in order.

The default example is:

```matlab
state = waterState("P",500,"u",2000);
```

For the supplied A-5 data, this should return approximately `T = 151.83 °C`, `x = 0.70813`, and `v = 0.26575 m³/kg`. This gives a quick installation check before trying other states.

All pressures are **absolute**.

## Main files

- `WaterStateExplorer.m` — sectioned, Live Script–ready teaching workflow.
- `waterState.m` — state-identification and interpolation engine.
- `waterStateTable.m` — concise result table for display.
- `plotWaterState.m` — P-v and T-v saturation diagrams.
- `runWaterStateTests.m` — regression tests built from exact source-table entries.
- `validateWaterTables.m` — structural checks and known-data warnings.
- `data/` — the original CSV files supplied for this project.

## Function syntax

```matlab
state = waterState(name1,value1,name2,value2)
```

Examples:

```matlab
state = waterState("T",100,"x",0.50);
state = waterState("P",500,"u",2000);
state = waterState("T",300,"P",500);
state = waterState("T",100,"phase","SV");
```

When the files are stored elsewhere:

```matlab
state = waterState("P",500,"u",2000, ...
    "DataFolder","C:\myCourse\waterTables");
```

## Units and returned properties

The MVP uses SI units:

| Quantity | Unit |
|---|---|
| `T` | °C |
| `P` | kPa absolute |
| `v` | m³/kg |
| `u`, `h` | kJ/kg |
| `s` | kJ/(kg·K) |
| `x` | dimensionless, 0–1 |

The returned structure contains:

```text
isComplete, phase, phaseCode, T_C, P_kPa, v_m3_kg,
u_kJ_kg, h_kJ_kg, s_kJ_kg_K, x, source,
notes, bounds, candidates
```

`isComplete = false` is often a thermodynamic result rather than a programming error. The function then explains what information is missing.

## Which input pairs are supported?

| Pair | Behavior |
|---|---|
| `T, P` | Determines a complete compressed-liquid, superheated, or supercritical state when covered by the tables. On the saturation line, quality is still required. |
| `P, u` | Determines compressed liquid, saturated mixture, saturated endpoints, or superheated vapor when the state is within the available data. This is the most robust general pair in the MVP. |
| `T, u` | Determines a saturated mixture directly. It searches A-6/A-7 for a unique pressure outside the dome; some compressed-liquid cases remain underdetermined. |
| `T, x` | Complete saturation state from A-4. |
| `P, x` | Complete saturation state from A-5. |
| `u, x` | Searches the saturation curve. It reports candidates rather than selecting arbitrarily when multiple roots exist. |
| `T, phase` | Complete only for saturated liquid or saturated vapor. A saturated mixture still needs `x`; CL/SHV still need another independent property. |
| `P, phase` | Same limitation as `T, phase`. |
| `u, phase` | Can solve saturated-liquid or saturated-vapor candidates; broader phase labels are underdetermined. |
| `x, phase` | Underdetermined because the saturation temperature/pressure is unknown. |

Accepted phase codes and names:

- `CL` — compressed liquid
- `SL` — saturated liquid
- `SLVM` — saturated liquid-vapor mixture
- `SV` — saturated vapor
- `SHV` — superheated vapor
- `SC` — supercritical fluid

## Interpolation rules

The solver follows these rules:

1. A-4 is used for saturation lookup by temperature.
2. A-5 is used for saturation lookup by pressure. For a declared T-P pair, the solver checks both A-4 and A-5 so a pair copied from either rounded printed table is recognized as saturation.
3. Saturated mixtures use

   ```text
   y = y_f + x(y_g - y_f)
   ```

   for `v`, `u`, `h`, and `s`.
4. A-6 and A-7 use sequential linear interpolation: first within temperature columns at each usable pressure block, then between pressure blocks.
5. A-6/A-7 `Sat.` reference rows are assigned their saturation temperatures from A-5 and used as interpolation boundaries.
6. No table extrapolation is performed.
7. For compressed-liquid pressures at or below 2500 kPa, when A-7 does not cover the state, the solver uses the documented approximation

   ```text
   v ≈ v_f(T)
   u ≈ u_f(T)
   s ≈ s_f(T)
   h ≈ h_f(T) + v_f(T)[P - P_sat(T)]
   ```

## Why some “two-variable” combinations do not work

A phase label is a region constraint, not generally an independent intensive property. For example, `T = 300 °C` and `phase = SHV` describe many possible pressures. Likewise, `T` and `P` are dependent on the saturation line, so they do not identify quality.

The solver returns an incomplete state instead of inventing a value. If a lookup yields more than one mathematical state, the alternatives are placed in `state.candidates`.

## Plotting

```matlab
plotWaterState(state,"Diagram","Pv");
plotWaterState(state,"Diagram","Tv");
```

The P-v plot uses logarithmic axes because the saturated specific-volume range spans several orders of magnitude. For a mixture, the plot also shows the saturation tie line.

## Verification

Run:

```matlab
runWaterStateTests
validateWaterTables
```

The tests use exact entries from A-4 through A-7, including saturation, superheated, compressed-liquid, inverse lookup, and underdetermined cases.

## Current limits

- SI units only in the state solver.
- Water only.
- A-8 ice-water-vapor states are not implemented.
- No extrapolation outside the supplied table ranges. The interval above the 2500 kPa approximation limit and below the first 5000 kPa A-7 pressure block can therefore return an incomplete state.
- English-unit mode is intentionally disabled until the malformed A-6E temperature cells are repaired from the original source.
- This is a table-based educational tool, not a replacement for a validated equation-of-state package in safety-critical design.

See `DATA_QA.md` for source-data findings.
