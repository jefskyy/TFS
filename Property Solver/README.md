# MCET 530 `thermoState` — Final Unified Property Solver

## Purpose

`thermoState.m` is a table-driven thermodynamic state lookup/interpolation function for MCET 530. It is intended to act as a stable computational primitive inside larger MATLAB analyses, including iterative power-cycle and refrigeration-cycle solvers.

The public interface is intentionally narrow:

```matlab
state = thermoState(fluid, units, property1, value1, property2, value2)
```

Optional data-folder override:

```matlab
state = thermoState(fluid, units, property1, value1, property2, value2, ...
    'DataFolder', dataFolder)
```

The function determines the thermodynamic state from two declared properties, identifies the applicable phase/region when possible, interpolates the supplied textbook tables, and returns the remaining properties.

It does **not** solve device equations, efficiencies, energy balances, cycle performance, or iterative constraints. Those calculations belong in the student's calling script.

---

## Supported fluids

```text
water / H2O / steam
R134 / R134a / R-134a
air / dry air
```

Additional fluids should be patched into the internal loader/model layer without changing the public function name or calling pattern.

---

## Unit systems

The second argument is the unit system:

```matlab
"SI"
"EN"
```

Aliases such as `"metric"`, `"english"`, and `"USCS"` are accepted, but student examples should use `"SI"` or `"EN"`.

### SI interpretation

| Property | Units |
|---|---|
| `T` | deg C |
| `T_K` | K |
| `P` | kPa absolute |
| `v` | m^3/kg |
| `rho` | kg/m^3 |
| `u` | kJ/kg |
| `h` | kJ/kg |
| `s` | kJ/(kg K) |
| `s0` | kJ/(kg K), air only |
| `x` | dimensionless |

### English interpretation

| Property | Units |
|---|---|
| `T` | deg F |
| `T_R` | deg R |
| `P` | psia |
| `v` | ft^3/lbm |
| `rho` | lbm/ft^3 |
| `u` | Btu/lbm |
| `h` | Btu/lbm |
| `s` | Btu/(lbm R) |
| `s0` | Btu/(lbm R), air only |
| `x` | dimensionless |

Pressure input is always absolute. Gauge-pressure conversion is intentionally outside `thermoState`.

### Canonical internal architecture

All numerical state determination is performed internally in SI units. English input values are converted once at the public boundary, the same SI property solver is used, and the completed state is converted back for English outputs.

This avoids maintaining two independent interpolation engines and prevents SI and English calls from diverging because of different printed-table spacings or rounding.

---

## Supported state properties

### All fluids

```text
T, P, v, rho, u, h, s
```

### Water and R-134a

```text
x
phase
```

Common phase aliases include:

```text
CL    compressed liquid
SL    saturated liquid
SLVM  saturated liquid-vapor mixture
SV    saturated vapor
SHV   superheated vapor
SC    supercritical fluid, where supported
```

### Air

Air also accepts:

```text
s0
```

where `s0` is the ideal-gas standard-state entropy function from the supplied A-21 table.

---

## Important cycle-analysis pathways

The final release explicitly supports the state lookups needed for second-law cycle analysis.

### Isentropic turbine/compressor outlet: `P + s`

```matlab
state1 = thermoState("water","SI","P",P1,"T",T1);

state2s = thermoState("water","SI", ...
    "P",P2, ...
    "s",state1.s);
```

For water/R-134a, the solver determines whether the new `P+s` state is compressed liquid, two-phase, or superheated and returns the corresponding enthalpy.

For air, `P+s` is inverted using the ideal-gas entropy relation and the A-21 `s0(T)` data.

### Actual turbine outlet: `P + h`

```matlab
h2 = state1.h - eta_t*(state1.h-state2s.h);

state2 = thermoState("water","SI", ...
    "P",P2, ...
    "h",h2);
```

### Actual compressor outlet: `P + h`

```matlab
h2 = state1.h + (state2s.h-state1.h)/eta_c;

state2 = thermoState("R134a","SI", ...
    "P",P2, ...
    "h",h2);
```

### Throttle valve: constant enthalpy

```matlab
state3 = thermoState("R134a","SI","P",P3,"x",0);
state4 = thermoState("R134a","SI","P",P4,"h",state3.h);
```

Device physics remains visible in the calling code rather than being hidden inside the property function.

---

## Output structure

All fluids return a common core structure. Properties that do not apply are `NaN` rather than disappearing from the structure.

### Generic computational fields

These fields use the unit system selected in the function call:

```matlab
state.T
state.T_abs
state.P
state.v
state.rho
state.u
state.h
state.s
state.s0
state.x
```

This makes cycle code unit-system independent. For example:

```matlab
eta_t = (state1.h-state2.h)/(state1.h-state2s.h);
```

works whether the states were requested in `"SI"` or `"EN"`, provided all states in the calculation use the same unit system.

### Unit-explicit fields

The function also retains explicit fields in both systems.

SI examples:

```matlab
state.T_C
state.T_K
state.P_kPa
state.v_m3_kg
state.rho_kg_m3
state.u_kJ_kg
state.h_kJ_kg
state.s_kJ_kg_K
```

English examples:

```matlab
state.T_F
state.T_R
state.P_psia
state.v_ft3_lbm
state.rho_lbm_ft3
state.u_Btu_lbm
state.h_Btu_lbm
state.s_Btu_lbm_R
```

Air retains its ideal-gas and transport-property fields. English conversions are also provided for the populated air transport/specific-heat quantities.

### State metadata

```matlab
state.fluid
state.units
state.model
state.isComplete
state.status
state.phaseCode
state.phase
state.source
state.inputPair
state.notes
state.bounds
state.candidates
```

`state.status` is intended for programmatic checking:

```text
OK
UNDERDETERMINED
AMBIGUOUS
OUT_OF_RANGE
INVALID_PAIR
```

A cycle solver should check the result before using it:

```matlab
state2s = thermoState("water","SI","P",P2,"s",state1.s);

if ~state2s.isComplete
    error("State 2s failed: %s", state2s.status);
end
```

---

## What `thermoState` can and cannot do

### Appropriate uses

- determine a state from two supported independent properties;
- identify liquid/two-phase/vapor regions for the supported pure fluids;
- calculate mixture quality where appropriate;
- linearly interpolate the supplied property tables;
- back-calculate an isentropic state using `P+s`;
- back-calculate a state using `P+h`, including throttling and actual device outlet calculations;
- support repeated calls inside student-written cycle solvers.

### Outside the function's scope

- turbine/compressor/pump efficiency equations;
- energy or entropy balances;
- heat-exchanger calculations;
- cycle thermal efficiency or COP;
- nonlinear iteration strategy;
- optimization;
- plotting;
- extrapolation outside the supplied tables;
- replacing an equation-of-state package such as EES, REFPROP, or CoolProp.

---

## Data model and current source files

The canonical SI solver expects the existing textbook CSV package in a `data` folder beside `thermoState.m`.

Primary files currently used:

```text
a4_saturated_water_temperature.csv
a5_saturated_water_pressure.csv
a6_superheated_water.csv
a7_compressed_liquid_water.csv

a11_saturated_r134a_temperature.csv
a13e_superheated_r134a.csv

a21_air_ideal_gas_properties - Copy.csv
a22_air_1atm_properties - Copy.csv
```

R-134a A-13E is an English source table but is converted into the internal SI model during loading.

English duplicate tables are not required for EN-mode operation. They are useful as independent validation references.

---

## Source-data safeguards retained

The final solver retains the prior data-quality decisions rather than silently correcting questionable textbook-extraction values:

- Water A-7: a malformed entropy value at 50 MPa and 0 deg C is suppressed rather than replaced.
- R-134a A-11: rows failing basic thermodynamic identities are excluded without replacement.
- R-134a A-13E: repeated nonmonotonic `-20 deg F` rows following `200 deg F` are excluded rather than guessed to be another temperature.
- R-134a A-12 is not required; pressure-indexed saturation lookup is obtained by inverting the cleaned A-11 saturation curve.
- Air A-21: enthalpy cells strongly inconsistent with the dominant `h-u = RT` trend are excluded from enthalpy interpolation rather than silently overwritten.

See `THERMOSTATE_DATA_CAVEATS.md` for a deeper discussion of interpolation, entropy, reference states, and what numerical precision can reasonably be inferred from these tables.

---

## Final release patch notes

### Final API stabilization

New preferred form:

```matlab
thermoState(fluid, units, property1, value1, property2, value2)
```

A legacy five-argument SI call is still accepted for prior course files:

```matlab
thermoState(fluid, property1, value1, property2, value2)
```

It is interpreted as SI. New student work should use the explicit unit-system argument.

### Added SI/English switching

- one canonical SI calculation path;
- English inputs converted at the public boundary;
- generic outputs follow the selected units;
- explicit SI and English fields are both retained.

### Added generic cycle-friendly aliases

```matlab
state.P
state.T
state.v
state.rho
state.u
state.h
state.s
```

### Added machine-readable status

```matlab
state.status
```

### Preserved enthalpy, entropy, and specific-volume inversion

`h`, `s`, and `v` remain valid state inputs. `P+s` and `P+h` are specifically covered by the regression tests because they are central to isentropic and actual device-state calculations.

### Removed public tolerance controls

The previous development version exposed interpolation/consistency tolerances as optional arguments. Those controls are no longer part of the public API. The source tables do not justify presenting user-adjustable numerical thresholds as physical precision controls.

Small fixed thresholds remain internally as implementation safeguards. They are discussed in `THERMOSTATE_DATA_CAVEATS.md` and should not be interpreted as uncertainty estimates or accuracy claims.

---

## Optional development files

`thermoState.m` is the only required code file during normal use.

Optional QA files:

```text
runThermoStateTests.m
validateThermoStateTables.m
```

Run regression tests:

```matlab
runThermoStateTests(dataFolder)
```

Run source-table QA:

```matlab
validateThermoStateTables(dataFolder)
```

Neither is called by `thermoState`.

---

## AI-use context file

`THERMOSTATE_AI_CONTEXT.md` is a deliberately concise specification students can provide to an AI coding assistant instead of uploading `thermoState.m`.

Its purpose is to establish `thermoState` as a **fixed dependency**. The AI should write code that calls the function, not rewrite or edit the property solver.
