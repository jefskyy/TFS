# thermoState.m — AI Context for Student MATLAB Code

## Instruction to the AI

Treat `thermoState.m` as an existing, fixed MATLAB dependency.

**Do not rewrite, modify, replace, inline, or reproduce `thermoState.m`.**

Write the student's solution around calls to this function. Device equations, balances, efficiencies, iteration, plotting, and engineering judgment belong in the student's code, not inside `thermoState`.

## Function signature

```matlab
state = thermoState(fluid, units, property1, value1, property2, value2)
```

Optional non-thermodynamic path argument:

```matlab
state = thermoState(..., 'DataFolder', dataFolder)
```

## Supported fluids

```text
water
R134a
air
```

Common aliases such as `H2O`, `R134`, and `R-134a` are accepted.

## Unit systems

Use exactly one unit system consistently in a calculation:

```text
SI
EN
```

### SI

```text
T     deg C
T_K   K
P     kPa absolute
v     m^3/kg
rho   kg/m^3
u     kJ/kg
h     kJ/kg
s     kJ/(kg K)
```

### EN

```text
T     deg F
T_R   deg R
P     psia
v     ft^3/lbm
rho   lbm/ft^3
u     Btu/lbm
h     Btu/lbm
s     Btu/(lbm R)
```

`x` is dimensionless.

## Supported input properties

All fluids:

```text
T, P, v, rho, u, h, s
```

Water and R134a additionally support:

```text
x, phase
```

Air additionally supports:

```text
s0
```

## Primary output fields

Use the generic fields in student calculations:

```matlab
state.T
state.T_abs
state.P
state.v
state.rho
state.u
state.h
state.s
state.x
```

These fields use the unit system requested in the call.

The structure also contains unit-explicit fields such as:

```matlab
state.h_kJ_kg
state.h_Btu_lbm
state.s_kJ_kg_K
state.s_Btu_lbm_R
```

## State validity

Before using a returned state in an iterative or multi-state calculation, check:

```matlab
state.isComplete
state.status
```

Possible status values:

```text
OK
UNDERDETERMINED
AMBIGUOUS
OUT_OF_RANGE
INVALID_PAIR
```

Recommended pattern:

```matlab
st = thermoState("water","SI","P",P2,"s",state1.s);

if ~st.isComplete
    error("Property lookup failed: %s", st.status);
end
```

## Isentropic-state pattern

Entropy is a valid input.

For an ideal turbine/compressor outlet at a known outlet pressure:

```matlab
state2s = thermoState(fluid, units, ...
    "P", P2, ...
    "s", state1.s);
```

Do not put turbine/compressor efficiency inside `thermoState`.

Example turbine calculation:

```matlab
state1 = thermoState("water","SI","P",P1,"T",T1);
state2s = thermoState("water","SI","P",P2,"s",state1.s);

h2 = state1.h - eta_t*(state1.h-state2s.h);
state2 = thermoState("water","SI","P",P2,"h",h2);
```

Example compressor calculation:

```matlab
state1 = thermoState("R134a","SI","P",P1,"T",T1);
state2s = thermoState("R134a","SI","P",P2,"s",state1.s);

h2 = state1.h + (state2s.h-state1.h)/eta_c;
state2 = thermoState("R134a","SI","P",P2,"h",h2);
```

## Throttle pattern

```matlab
state3 = thermoState("R134a","SI","P",P3,"x",0);
state4 = thermoState("R134a","SI","P",P4,"h",state3.h);
```

## What thermoState does

- table lookup and linear interpolation;
- phase/state identification for supported fluids;
- quality calculation in a saturated mixture;
- inversion from supported pairs such as `P+h`, `P+s`, `T+h`, `T+s`, and selected property-only pairs;
- SI/English input-output conversion.

## What thermoState does NOT do

Do not ask the AI to modify `thermoState` to perform these tasks:

- energy balances;
- entropy balances;
- mass balances;
- turbine/compressor/pump efficiency calculations;
- heat-exchanger calculations;
- thermal efficiency or COP;
- iterative convergence logic;
- optimization;
- plotting;
- extrapolation outside the property tables.

These belong in the student's calling code.

## Important limitations

- The solver is based on course CSV property tables, not a full equation of state.
- It uses linear interpolation only.
- It does not extrapolate outside usable table ranges.
- A pair of supplied properties is not guaranteed to define one unique state.
- `T+P` on a saturation line does not determine quality.
- If `state.status` is not `"OK"`, do not silently continue a cycle calculation.
- Keep entropy values within the same property-reference system. Do not mix entropy from unrelated external databases with this solver without checking reference conventions.

## AI coding rule

When solving a student problem, assume `thermoState.m` is correct and available on the MATLAB path. If a requested state cannot be obtained with the documented interface, explain the limitation in the student's calling code rather than proposing edits to `thermoState.m`.
