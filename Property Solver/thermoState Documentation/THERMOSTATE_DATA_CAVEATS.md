# Deep-Dive Note: Numerical Tolerances, Entropy, and Table Quality in `thermoState`

## Why this note exists

The final student-facing `thermoState` API intentionally does **not** expose numerical tolerance controls.

That decision is not because numerical comparisons are unnecessary. Any table-based state solver must make small implementation decisions about questions such as:

- when a computed pressure is considered equal to a printed saturation pressure;
- whether a supplied property is effectively equal to a saturated-liquid or saturated-vapor value;
- whether two independently interpolated values are close enough to represent the same state;
- how closely an inverse interpolation root must satisfy a target value.

The reason those settings are hidden is that the precision of the source data does not justify presenting them to students as meaningful physical accuracy controls.

The current CSV package originates from printed textbook tables and includes rounded values, different grid spacings, and several known extraction defects. A user-adjustable tolerance of `1e-6` versus `1e-4` can create an illusion of numerical sophistication that exceeds the information content of the tables themselves.

Small fixed thresholds therefore remain inside the implementation as **software safeguards**, not as uncertainty estimates and not as claims about thermodynamic accuracy.

---

## 1. Printed tables have finite resolution

A printed property table is already a sampled representation of a more complete thermodynamic model.

For example, a table may report:

```text
P = 500 kPa
T = 300 deg C
h = 3064.6 kJ/kg
s = 7.4614 kJ/(kg K)
```

The displayed digits are not proof that the underlying state is known to arbitrarily many decimal places. They reflect the table author's calculation, rounding convention, and chosen print precision.

Linear interpolation adds another approximation on top of that tabulation.

Consequently, a result such as

```text
T = 287.438219 deg C
```

should not be interpreted as having six meaningful decimal places simply because MATLAB can display them.

---

## 2. Why exact equality is dangerous near saturation

For a pure substance, `T` and `P` are dependent on the saturation line.

In exact thermodynamics:

```text
P = Psat(T)
```

identifies a saturated state, but does not identify quality.

With printed tables, however, one lookup path might produce `Psat = 101.42 kPa`, while another independently interpolated path could produce a value differing slightly because of rounding or table spacing.

A program that requires exact binary floating-point equality would incorrectly classify some saturated states as compressed liquid or superheated vapor.

Therefore `thermoState` uses small internal numerical allowances when comparing table-derived values. Those allowances exist to make the discrete tables computationally usable. They should not be interpreted as a thermodynamic uncertainty band around the saturation curve.

---

## 3. Why user-adjustable tolerances were removed

Earlier development versions exposed optional tolerance parameters. That was useful while debugging the interpolation engine, but it is a poor final instructional interface for this dataset.

If students could write:

```matlab
thermoState(...,"EntropyTolerance",1e-9)
```

there would be no physical basis for claiming that `1e-9 kJ/(kg K)` is more correct than a larger threshold when the underlying table may only report entropy to four or five decimal places and may itself contain rounded/interpolated source values.

The final design therefore separates two concepts:

1. **Numerical implementation safeguards** — fixed inside the function.
2. **Physical/data uncertainty** — not quantified by the current source tables and therefore not represented by a user setting.

A rigorous uncertainty model would require substantially better source metadata or direct access to the underlying equation of state.

---

## 4. Entropy as an input is valid and essential

Entropy is intentionally supported as a state input.

For an isentropic ideal device state, the standard workflow is:

```matlab
state1 = thermoState(fluid,units,"P",P1,"T",T1);
state2s = thermoState(fluid,units,"P",P2,"s",state1.s);
```

This implements the ideal-device condition:

```text
s2s = s1
```

At the specified outlet pressure, the solver then determines which region contains that entropy.

For water or R-134a:

```text
s < sf        -> compressed liquid region
sf < s < sg   -> saturated mixture
s > sg        -> superheated region
```

If the entropy lies in the two-phase region, quality is obtained from the standard mixture relation:

```text
x = (s - sf)/(sg - sf)
```

and the remaining mixture properties are calculated from the same quality.

This is a legitimate table-based way to determine an isentropic reference state.

---

## 5. The isentropic state is only as accurate as the property model

`state2s` is not an experimentally measured device state. It is a constructed reference state satisfying the model condition `s2s = s1`.

Its accuracy therefore depends on:

- the accuracy of the source property tables;
- the spacing of tabulated pressure and temperature values;
- rounding in the printed values;
- linear-interpolation error;
- whether the queried state lies near a region boundary or critical region;
- data-extraction errors in the CSV package.

This is sufficient for the intended MCET 530 instructional calculations, but it is different from using a high-accuracy equation-of-state library.

---

## 6. Entropy reference states matter

Specific entropy values depend on a chosen reference convention. Within one internally consistent property table, this is normally not a problem because thermodynamic calculations use entropy differences or compare entropy values generated under the same convention.

The important rule is:

> Do not mix entropy values from different property sources unless their reference conventions are known to be compatible.

For example, it is safe to calculate `state1.s` with `thermoState` and then use that value as the entropy input to another `thermoState` call for the same fluid.

It is **not automatically safe** to copy an absolute entropy value from CoolProp, REFPROP, EES, a different textbook, or a web table and combine it with the current CSV package.

The reference zeros may differ even when all sources describe the same physical fluid.

---

## 7. Special caveat for ideal-gas air entropy

The air solver uses the A-21 ideal-gas standard-state entropy function `s0(T)` together with the pressure correction

```text
s = s0(T) - R ln(P/Pref)
```

The current implementation uses an internal reference pressure of:

```text
Pref = 100 kPa
```

This is computationally self-consistent when both states in a calculation are produced by the same solver. A constant reference shift cancels when comparing entropy changes and when imposing `s2 = s1`.

However, the original textbook convention underlying the printed `s0` table should be checked before interpreting the returned **absolute** air entropy as directly interchangeable with another property database. Some ideal-gas tables use 1 bar, some use 1 atm, and conventions can differ by source.

This issue is especially important when importing an externally supplied `s` value into `thermoState`.

---

## 8. Property pairs can become ill-conditioned near boundaries

Even when two properties are theoretically independent, numerical inversion can be sensitive when:

- the two properties change very slowly over part of the table;
- the query lies close to the critical point;
- the query lies close to saturated liquid or saturated vapor;
- adjacent table rows have very similar values;
- a bilinear table cell is large relative to local property curvature.

For cycle calculations, this means a very small change in an input entropy or enthalpy can occasionally produce a visibly larger change in an inferred temperature, pressure, or quality.

This is not necessarily a coding bug. It can be a consequence of the conditioning of the inverse lookup combined with coarse tabulation.

---

## 9. Known source-data problems are handled conservatively

The solver deliberately avoids silent corrections when the extraction appears questionable.

Current examples include:

- a malformed water compressed-liquid entropy value;
- an R-134a saturation row that fails basic thermodynamic identities;
- repeated nonmonotonic R-134a superheated temperature labels;
- an air enthalpy cell inconsistent with the surrounding `h-u = RT` trend.

Where practical, suspect values are excluded and interpolation proceeds across neighboring valid data. The source CSV itself is not rewritten.

This approach favors traceability over pretending the original data are cleaner than they are.

---

## 10. No extrapolation is a deliberate safety boundary

`thermoState` is intended to interpolate within the supplied course tables.

It does not intentionally extend those tables into unrepresented states. If an iterative cycle solver pushes a state beyond the usable range, the preferred response is:

```matlab
state.isComplete = false;
state.status = "OUT_OF_RANGE";
```

The student's cycle code should then stop, revise the iteration bounds, or report that the proposed design cannot be evaluated with the available property package.

This is preferable to a smooth-looking extrapolated answer with unknown physical validity.

---

## 11. What would be needed for a more rigorous future version

A higher-confidence engineering property engine would require one of the following:

- direct use of IAPWS, Helmholtz-energy, or other published equations of state;
- CoolProp/REFPROP integration;
- manufacturer or standards-body property data;
- source tables with documented uncertainties and reference-state conventions;
- an explicit numerical uncertainty model for interpolation and inverse lookup.

That would be a different project from the current instructional solver.

The present design intentionally prioritizes transparency, table-reading logic, and compatibility with the course's printed property data.

---

## Practical rule for MCET 530

For course cycle analysis:

1. use `thermoState` consistently for all states of a given fluid;
2. use `P+s` to construct ideal isentropic states;
3. use `P+h` to reconstruct actual device states after applying efficiency equations;
4. check `state.isComplete` / `state.status` inside iterative code;
5. do not claim more precision than the source tables reasonably support;
6. do not mix absolute entropy values from different property databases without checking reference conventions.

Those practices preserve the instructional value of the table-based model without overstating its numerical authority.
