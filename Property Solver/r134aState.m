function state = r134aState(name1, value1, name2, value2, varargin)
%R134ASTATE Determine an R-134a state from two declared quantities.
%
%   state = r134aState("P",500,"u",250)
%   state = r134aState("T",20,"x",0.40)
%   state = r134aState("T",80,"P",500)
%   state = r134aState("T",20,"phase","SV")
%
% Supported declared quantities (SI interface):
%   T      temperature, deg C
%   P      absolute pressure, kPa
%   u      specific internal energy, kJ/kg
%   x      vapor quality, 0 <= x <= 1
%   phase  CL, SL, SLVM, SV, SHV, SC, saturated, or a full name
%
% Data sources used by this function:
%   A-11   saturated R-134a indexed by temperature (SI)
%   A-13E  superheated R-134a (English units, converted internally to SI)
%
% The supplied A-12 pressure table is not required. Pressure-indexed
% saturation lookups are obtained by inverting/interpolating A-11 because
% several T_sat entries in the supplied A-12 CSV are nonmonotonic.
%
% No compressed-liquid R-134a table was supplied. Compressed-liquid states
% therefore use the textbook incompressible approximation based on the
% saturated-liquid properties at the declared or inferred temperature.
%
% The function uses linear interpolation and does not extrapolate beyond
% the usable saturation or superheated tables. Some declared pairs are
% thermodynamically underdetermined; in those cases state.isComplete is
% false and state.notes explains what additional information is required.
%
% Optional name-value argument:
%   "DataFolder"  folder containing the R-134a CSV files.
%
% Output fields match waterState so the same Live Script display logic can
% be reused: T_C, P_kPa, v_m3_kg, u_kJ_kg, h_kJ_kg, s_kJ_kg_K, x,
% phase, source, bounds, candidates, and notes.

    narginchk(4, 20);

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    opts = parseOptions(defaultFolder, varargin{:});

    n1 = normalizePropertyName(name1);
    n2 = normalizePropertyName(name2);
    if n1 == n2
        error('r134aState:DuplicateInput', ...
            'Specify two different quantities, not two values of %s.', n1);
    end

    validateDeclaredValue(n1, value1);
    validateDeclaredValue(n2, value2);

    names = [n1, n2];
    values = {value1, value2};
    tables = loadR134aTables(opts.DataFolder);

    if hasInput(names, "T") && hasInput(names, "P")
        state = solveTP(getInput(names, values, "T"), ...
                        getInput(names, values, "P"), tables, opts);
    elseif hasInput(names, "T") && hasInput(names, "u")
        state = solveTU(getInput(names, values, "T"), ...
                        getInput(names, values, "u"), tables, opts);
    elseif hasInput(names, "P") && hasInput(names, "u")
        state = solvePU(getInput(names, values, "P"), ...
                        getInput(names, values, "u"), tables, opts);
    elseif hasInput(names, "T") && hasInput(names, "x")
        state = solveTX(getInput(names, values, "T"), ...
                        getInput(names, values, "x"), tables);
    elseif hasInput(names, "P") && hasInput(names, "x")
        state = solvePX(getInput(names, values, "P"), ...
                        getInput(names, values, "x"), tables);
    elseif hasInput(names, "u") && hasInput(names, "x")
        state = solveUX(getInput(names, values, "u"), ...
                        getInput(names, values, "x"), tables, opts);
    elseif hasInput(names, "phase")
        otherName = names(names ~= "phase");
        otherValue = getInput(names, values, otherName);
        phaseValue = getInput(names, values, "phase");
        state = solvePhasePair(otherName, otherValue, phaseValue, ...
                               tables, opts);
    else
        state = emptyState();
        state.notes(end+1,1) = ...
            "This input pair is not implemented in the R-134a SI version.";
    end

    state.inputPair = n1 + " + " + n2;
    state = preserveDeclaredInputs(state, names, values);
end

function opts = parseOptions(defaultFolder, varargin)
    p = inputParser;
    p.FunctionName = 'r134aState';
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'SaturationTolerance_C', 0.05, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'SaturationTolerance_kPa', 0.05, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'SaturationRelativeTolerance', 2e-4, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'EnergyTolerance_kJ_kg', 0.10, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    parse(p, varargin{:});
    opts = p.Results;
    opts.DataFolder = char(opts.DataFolder);
end

function name = normalizePropertyName(rawName)
    token = lower(strtrim(string(rawName)));
    switch token
        case {"t", "temperature", "temperature_c", "t_c"}
            name = "T";
        case {"p", "pressure", "pressure_kpa", "p_kpa"}
            name = "P";
        case {"u", "internalenergy", "internal_energy", "u_kj_kg"}
            name = "u";
        case {"x", "quality", "vaporquality", "vapourquality"}
            name = "x";
        case {"phase", "region"}
            name = "phase";
        otherwise
            error('r134aState:UnknownProperty', ...
                'Unknown quantity "%s". Use T, P, u, x, or phase.', token);
    end
end

function validateDeclaredValue(name, value)
    if name == "phase"
        if ~(ischar(value) || (isstring(value) && isscalar(value)))
            error('r134aState:InvalidPhase', ...
                'The phase value must be text such as "SHV" or "saturated vapor".');
        end
        normalizePhase(value);
        return
    end

    if ~(isnumeric(value) && isscalar(value) && isfinite(value))
        error('r134aState:InvalidNumericInput', ...
            '%s must be a finite numeric scalar.', name);
    end
    if name == "P" && value <= 0
        error('r134aState:InvalidPressure', ...
            'Pressure must be absolute and greater than zero.');
    end
    if name == "x" && (value < 0 || value > 1)
        error('r134aState:InvalidQuality', ...
            'Quality x must satisfy 0 <= x <= 1.');
    end
end

function tf = hasInput(names, target)
    tf = any(names == target);
end

function value = getInput(names, values, target)
    idx = find(names == target, 1, 'first');
    if isempty(idx)
        error('r134aState:InternalInputError', ...
            'The requested input %s was not supplied.', target);
    end
    value = values{idx};
end

function state = solveTP(T, P, tables, opts)
    state = emptyState();
    state.T_C = T;
    state.P_kPa = P;

    haveSatT = T >= tables.minSaturationT && T <= tables.maxSaturationT;
    haveSatP = P >= tables.minSaturationP && P <= tables.maxSaturationP;

    onSatByT = false;
    onSatByP = false;
    satT = struct();
    satP = struct();

    if haveSatT
        satT = saturationAtT(T, tables);
        pTol = max(opts.SaturationTolerance_kPa, ...
            opts.SaturationRelativeTolerance * satT.P_kPa);
        onSatByT = abs(P - satT.P_kPa) <= pTol;
    else
        pTol = NaN;
    end

    if haveSatP
        satP = saturationAtP(P, tables);
        onSatByP = abs(T - satP.T_C) <= opts.SaturationTolerance_C;
    end

    if onSatByT || onSatByP
        if onSatByP
            sat = satP;
        else
            sat = satT;
        end
        state = partialSaturatedState(sat, ...
            "T and P are dependent on the saturation line. Supply x or another specific property to locate the state inside the dome.");
        return
    end

    if haveSatT && haveSatP
        compressed = T < satP.T_C - opts.SaturationTolerance_C && ...
                     P > satT.P_kPa + pTol;
        superheated = T > satP.T_C + opts.SaturationTolerance_C && ...
                      P < satT.P_kPa - pTol;

        if compressed
            state = compressedLiquidApproximation(T, P, satT);
        elseif superheated
            state = superheatedStateAtTP(T, P, tables);
        else
            state = partialSaturatedState(satP, ...
                "The rounded T-P pair lies in a narrow near-saturation band. Supply x or another property instead of forcing a phase classification.");
        end
        return
    end

    if haveSatT
        if P > satT.P_kPa + pTol
            state = compressedLiquidApproximation(T, P, satT);
        elseif P < satT.P_kPa - pTol
            state = superheatedStateAtTP(T, P, tables);
        else
            state = partialSaturatedState(satT, ...
                "T and P identify the saturation line but not quality x.");
        end
        return
    end

    if T > tables.maxSaturationT && P < tables.maxSaturationP
        state = superheatedStateAtTP(T, P, tables);
        return
    end

    if T < tables.minSaturationT
        try
            state = superheatedStateAtTP(T, P, tables);
        catch
            state.notes(end+1,1) = ...
                "The declared temperature is below the usable A-11 saturation range and is not covered by the supplied A-13E superheated table.";
        end
        return
    end

    state.notes(end+1,1) = ...
        "The declared T-P pair is outside the supplied saturation and superheated table ranges. The near-critical/supercritical region is not implemented from these files.";
end

function state = superheatedStateAtTP(T, P, tables)
    state = emptyState();
    state.T_C = T;
    state.P_kPa = P;
    state.phaseCode = "SHV";
    state.phase = phaseLabel("SHV");

    try
        [props, meta] = regionAtTP(tables.superheated, T, P);
        state = regionState(T, P, props, "SHV", ...
            tables.superheatedSource + "; " + meta.method);
    catch ME
        state.notes(end+1,1) = string(ME.message);
    end
end

function state = solveTX(T, x, tables)
    sat = saturationAtT(T, tables);
    state = saturatedState(sat, x);
end

function state = solvePX(P, x, tables)
    sat = saturationAtP(P, tables);
    state = saturatedState(sat, x);
end

function state = solvePU(P, u, tables, opts)
    state = emptyState();
    state.P_kPa = P;
    state.u_kJ_kg = u;

    if P >= tables.minSaturationP && P <= tables.maxSaturationP
        sat = saturationAtP(P, tables);
        eTol = opts.EnergyTolerance_kJ_kg;

        if u >= sat.uf - eTol && u <= sat.ug + eTol
            x = (u - sat.uf) / sat.ufg;
            x = min(max(x, 0), 1);
            state = saturatedState(sat, x);
            return
        elseif u < sat.uf
            T = inverseMonotonic(tables.satT.u_f_kJ_kg, ...
                                 tables.satT.T_C, u);
            if isfinite(T)
                satT = saturationAtT(T, tables);
                if P > satT.P_kPa
                    state = compressedLiquidApproximation(T, P, satT);
                    state.notes(end+1,1) = ...
                        "Temperature was obtained by inverting u_f(T); pressure dependence of u was neglected in the compressed-liquid approximation.";
                    return
                end
            end

            state.phaseCode = "CL";
            state.phase = phaseLabel("CL");
            state.notes(end+1,1) = ...
                "No unique compressed-liquid state was found from P and u inside the usable saturated-liquid range.";
            return
        else
            candidates = candidatesAtP(tables.superheated, P, u, ...
                "SHV", tables.superheatedSource, opts);
            state = chooseCandidates(candidates, state, ...
                "No unique superheated state was found inside the supplied A-13E range.");
            return
        end
    end

    if P > tables.maxSaturationP
        T = inverseMonotonic(tables.satT.u_f_kJ_kg, ...
                             tables.satT.T_C, u);
        if isfinite(T)
            satT = saturationAtT(T, tables);
            if P > satT.P_kPa
                state = compressedLiquidApproximation(T, P, satT);
                state.notes(end+1,1) = ...
                    "Temperature was obtained by inverting u_f(T); pressure dependence of u was neglected in the compressed-liquid approximation.";
                return
            end
        end
    end

    candidates = candidatesAtP(tables.superheated, P, u, ...
        "SHV", tables.superheatedSource, opts);
    state = chooseCandidates(candidates, state, ...
        "The requested P-u state is outside the supplied R-134a table ranges or is not unique.");
end

function state = solveTU(T, u, tables, opts)
    state = emptyState();
    state.T_C = T;
    state.u_kJ_kg = u;

    if T >= tables.minSaturationT && T <= tables.maxSaturationT
        sat = saturationAtT(T, tables);
        eTol = opts.EnergyTolerance_kJ_kg;

        if u >= sat.uf - eTol && u <= sat.ug + eTol
            x = (u - sat.uf) / sat.ufg;
            x = min(max(x, 0), 1);
            state = saturatedState(sat, x);
            return
        elseif u < sat.uf
            state.phaseCode = "CL";
            state.phase = phaseLabel("CL");
            state.notes(end+1,1) = ...
                "With the compressed-liquid approximation, u is approximately a function of T only. Therefore T and u do not uniquely determine pressure without a compressed-liquid table.";
            return
        else
            candidates = candidatesAtT(tables.superheated, T, u, ...
                "SHV", tables.superheatedSource, opts);
            state = chooseCandidates(candidates, state, ...
                "No unique superheated state was found inside the supplied A-13E range.");
            return
        end
    end

    candidates = candidatesAtT(tables.superheated, T, u, ...
        "SHV", tables.superheatedSource, opts);
    state = chooseCandidates(candidates, state, ...
        "The requested T-u state is outside the supplied R-134a table ranges or is not unique.");
end

function state = solveUX(u, x, tables, opts)
    uMix = tables.satT.u_f_kJ_kg + x .* tables.satT.u_fg_kJ_kg;
    rootsT = piecewiseLinearRoots(tables.satT.T_C, uMix, u, ...
                                  opts.EnergyTolerance_kJ_kg);
    candidates = emptyCandidateTable();

    for k = 1:numel(rootsT)
        sat = saturationAtT(rootsT(k), tables);
        s = saturatedState(sat, x);
        candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
    end

    base = emptyState();
    base.u_kJ_kg = u;
    base.x = x;
    state = chooseCandidates(candidates, base, ...
        "The pair u-x did not produce a unique saturation state. This may occur because vapor and mixture-energy curves are not monotonic near the upper end of the supplied saturation table.");
end

function state = solvePhasePair(otherName, otherValue, phaseValue, tables, opts)
    [phaseCode, phaseText] = normalizePhase(phaseValue);
    state = emptyState();
    state.phaseCode = phaseCode;
    state.phase = phaseText;

    if phaseCode == "SC"
        state.notes(end+1,1) = ...
            "The supplied files do not provide a supercritical R-134a table. Supply a source that covers that region before using SC as a calculable phase.";
        return
    end

    switch otherName
        case "T"
            T = otherValue;
            state.T_C = T;
            if ismember(phaseCode, ["SL", "SV", "SLVM", "SAT"])
                sat = saturationAtT(T, tables);
                if phaseCode == "SL"
                    state = saturatedState(sat, 0);
                elseif phaseCode == "SV"
                    state = saturatedState(sat, 1);
                else
                    state = partialSaturatedState(sat, ...
                        "A saturated-mixture phase and temperature determine saturation pressure, but quality x is still required for v, u, h, and s.");
                end
            else
                state.notes(end+1,1) = ...
                    "Phase plus one intensive property does not fix a compressed-liquid or superheated-vapor state. Supply P or another independent property.";
            end

        case "P"
            P = otherValue;
            state.P_kPa = P;
            if ismember(phaseCode, ["SL", "SV", "SLVM", "SAT"])
                sat = saturationAtP(P, tables);
                if phaseCode == "SL"
                    state = saturatedState(sat, 0);
                elseif phaseCode == "SV"
                    state = saturatedState(sat, 1);
                else
                    state = partialSaturatedState(sat, ...
                        "A saturated-mixture phase and pressure determine saturation temperature, but quality x is still required for v, u, h, and s.");
                end
            else
                state.notes(end+1,1) = ...
                    "Phase plus one intensive property does not fix a compressed-liquid or superheated-vapor state. Supply T or another independent property.";
            end

        case "u"
            u = otherValue;
            state.u_kJ_kg = u;
            if phaseCode == "SL"
                state = solveUX(u, 0, tables, opts);
            elseif phaseCode == "SV"
                state = solveUX(u, 1, tables, opts);
            else
                state.notes(end+1,1) = ...
                    "u and a broad phase label do not generally fix a state. For a two-phase mixture, supply T, P, or x; for CL/SHV, supply another independent intensive property.";
            end

        case "x"
            state.x = otherValue;
            state.notes(end+1,1) = ...
                "Quality and a phase label do not identify the saturation temperature or pressure. Supply T or P.";

        otherwise
            state.notes(end+1,1) = "Unsupported phase-input combination.";
    end
end

function state = chooseCandidates(candidates, baseState, noUniqueMessage)
    state = baseState;
    if height(candidates) == 1
        state = candidateToState(candidates(1,:));
    elseif height(candidates) > 1
        state.candidates = candidates;
        state.notes(end+1,1) = ...
            "More than one table-interpolated state satisfies the declared pair. Review state.candidates and add another independent property.";
    else
        state.notes(end+1,1) = string(noUniqueMessage);
    end
end

function candidates = candidatesAtP(regionTable, P, uTarget, phaseCode, source, opts)
    candidates = emptyCandidateTable();
    [Tgrid, Ugrid] = virtualSliceAtP(regionTable, P);
    if numel(Tgrid) < 2
        return
    end

    rootsT = piecewiseLinearRoots(Tgrid, Ugrid, uTarget, ...
                                  opts.EnergyTolerance_kJ_kg);
    for k = 1:numel(rootsT)
        try
            [props, meta] = regionAtTP(regionTable, rootsT(k), P);
            s = regionState(rootsT(k), P, props, phaseCode, ...
                source + "; inverse interpolation in u followed by " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
            % A root at an unsupported boundary is not a valid candidate.
        end
    end
end

function candidates = candidatesAtT(regionTable, T, uTarget, phaseCode, source, opts)
    candidates = emptyCandidateTable();
    [Pgrid, Ugrid] = virtualSliceAtT(regionTable, T);
    if numel(Pgrid) < 2
        return
    end

    rootsP = piecewiseLinearRoots(Pgrid, Ugrid, uTarget, ...
                                  opts.EnergyTolerance_kJ_kg);
    for k = 1:numel(rootsP)
        try
            [props, meta] = regionAtTP(regionTable, T, rootsP(k));
            s = regionState(T, rootsP(k), props, phaseCode, ...
                source + "; inverse interpolation in u followed by " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
            % Ignore unsupported boundary roots.
        end
    end
end

function [Tgrid, Ugrid] = virtualSliceAtP(regionTable, P)
    candidateT = unique(regionTable.T_C);
    Tgrid = zeros(0,1);
    Ugrid = zeros(0,1);
    for k = 1:numel(candidateT)
        try
            [props, ~] = regionAtTP(regionTable, candidateT(k), P);
            if isfinite(props.u)
                Tgrid(end+1,1) = candidateT(k); %#ok<AGROW>
                Ugrid(end+1,1) = props.u; %#ok<AGROW>
            end
        catch
        end
    end
    [Tgrid, order] = sort(Tgrid);
    Ugrid = Ugrid(order);
end

function [Pgrid, Ugrid] = virtualSliceAtT(regionTable, T)
    candidateP = unique(regionTable.P_kPa);
    Pgrid = zeros(0,1);
    Ugrid = zeros(0,1);
    for k = 1:numel(candidateP)
        try
            [props, ~] = regionAtTP(regionTable, T, candidateP(k));
            if isfinite(props.u)
                Pgrid(end+1,1) = candidateP(k); %#ok<AGROW>
                Ugrid(end+1,1) = props.u; %#ok<AGROW>
            end
        catch
        end
    end
    [Pgrid, order] = sort(Pgrid);
    Ugrid = Ugrid(order);
end

function [props, meta] = regionAtTP(regionTable, T, P)
%REGIONATTP Sequential linear interpolation: first in T, then in P.
    pressureLevels = unique(regionTable.P_kPa);
    values = nan(numel(pressureLevels), 4);
    valid = false(numel(pressureLevels), 1);

    for k = 1:numel(pressureLevels)
        block = regionTable(regionTable.P_kPa == pressureLevels(k), :);
        block = sortrows(block, 'T_C');
        [tUnique, ia] = unique(block.T_C, 'stable');
        block = block(ia,:);

        if T >= min(tUnique) - 1e-10 && T <= max(tUnique) + 1e-10
            values(k,1) = interp1(tUnique, block.v_m3_kg, T, 'linear');
            values(k,2) = interp1(tUnique, block.u_kJ_kg, T, 'linear');
            values(k,3) = interp1(tUnique, block.h_kJ_kg, T, 'linear');
            values(k,4) = interp1(tUnique, block.s_kJ_kg_K, T, 'linear');
            valid(k) = all(isfinite(values(k,1:3)));
        end
    end

    pValid = pressureLevels(valid);
    values = values(valid,:);
    if isempty(pValid) || P < min(pValid) - 1e-10 || P > max(pValid) + 1e-10
        error('r134aState:OutOfTableRange', ...
            'T = %.6g deg C and P = %.6g kPa are outside the usable A-13E region. No extrapolation was performed.', T, P);
    end

    exactIdx = find(abs(pValid - P) <= max(1e-9, 1e-12*abs(P)), 1);
    if ~isempty(exactIdx)
        result = values(exactIdx,:);
        method = "linear interpolation in temperature at a tabulated pressure";
    else
        lowerIdx = find(pValid < P, 1, 'last');
        upperIdx = find(pValid > P, 1, 'first');
        if isempty(lowerIdx) || isempty(upperIdx)
            error('r134aState:OutOfTableRange', ...
                'The requested pressure is not bracketed by usable A-13E blocks at T = %.6g deg C.', T);
        end
        pPair = pValid([lowerIdx, upperIdx]);
        valuePair = values([lowerIdx, upperIdx],:);
        result = nan(1,4);
        for j = 1:4
            if all(isfinite(valuePair(:,j)))
                result(j) = interp1(pPair, valuePair(:,j), P, 'linear');
            end
        end
        method = "sequential linear interpolation in temperature and pressure";
    end

    props = struct('v', result(1), 'u', result(2), ...
                   'h', result(3), 's', result(4));
    meta = struct('method', method);
end

function roots = piecewiseLinearRoots(x, y, target, tolerance)
    mask = isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    [x, order] = sort(x);
    y = y(order);

    roots = zeros(0,1);
    exactTol = max(1e-10, 1e-10 * max(abs(target), 1));
    for k = 1:numel(x)
        if abs(y(k) - target) <= exactTol
            roots(end+1,1) = x(k); %#ok<AGROW>
        end
        if k == numel(x)
            continue
        end

        y1 = y(k) - target;
        y2 = y(k+1) - target;
        if y1 * y2 < 0
            root = x(k) + (target - y(k)) * ...
                   (x(k+1) - x(k)) / (y(k+1) - y(k));
            roots(end+1,1) = root; %#ok<AGROW>
        elseif abs(y1) <= exactTol && abs(y2) <= exactTol && ...
                abs(y(k+1)-y(k)) <= exactTol
            roots(end+1,1) = x(k+1); %#ok<AGROW>
        end
    end

    if isempty(roots) && ~isempty(y)
        [nearestError, nearestIdx] = min(abs(y - target));
        if nearestError <= tolerance
            roots = x(nearestIdx);
        end
    end
    roots = uniqueWithTolerance(roots, 1e-8);
end

function out = uniqueWithTolerance(values, tolerance)
    values = sort(values(:));
    out = zeros(0,1);
    for k = 1:numel(values)
        if isempty(out) || abs(values(k) - out(end)) > tolerance
            out(end+1,1) = values(k); %#ok<AGROW>
        end
    end
end

function value = inverseMonotonic(x, y, target)
    mask = isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    [x, order] = sort(x);
    y = y(order);
    [x, ia] = unique(x, 'stable');
    y = y(ia);
    if isempty(x) || target < min(x) || target > max(x)
        value = NaN;
    else
        value = interp1(x, y, target, 'linear');
    end
end

function sat = saturationAtT(T, tables)
    tab = tables.satT;
    if T < min(tab.T_C) || T > max(tab.T_C)
        error('r134aState:SaturationRange', ...
            'T = %.6g deg C is outside the usable A-11 range [%.6g, %.6g] deg C.', ...
            T, min(tab.T_C), max(tab.T_C));
    end

    sat = struct();
    sat.T_C = T;
    sat.P_kPa = interp1(tab.T_C, tab.P_sat_kPa, T, 'linear');
    sat.vf = interp1(tab.T_C, tab.v_f_m3_kg, T, 'linear');
    sat.vg = interp1(tab.T_C, tab.v_g_m3_kg, T, 'linear');
    sat.uf = interp1(tab.T_C, tab.u_f_kJ_kg, T, 'linear');
    sat.ufg = interp1(tab.T_C, tab.u_fg_kJ_kg, T, 'linear');
    sat.ug = interp1(tab.T_C, tab.u_g_kJ_kg, T, 'linear');
    sat.hf = interp1(tab.T_C, tab.h_f_kJ_kg, T, 'linear');
    sat.hfg = interp1(tab.T_C, tab.h_fg_kJ_kg, T, 'linear');
    sat.hg = interp1(tab.T_C, tab.h_g_kJ_kg, T, 'linear');
    sat.sf = interp1(tab.T_C, tab.s_f_kJ_kg_K, T, 'linear');
    sat.sfg = interp1(tab.T_C, tab.s_fg_kJ_kg_K, T, 'linear');
    sat.sg = interp1(tab.T_C, tab.s_g_kJ_kg_K, T, 'linear');
    sat.source = "A-11 saturated R-134a table; linear interpolation in temperature";
    sat.notes = saturationGapNotes(T, tab.T_C, tables.removedSatT_C, "temperature");
end

function sat = saturationAtP(P, tables)
    tab = tables.satT;
    if P < min(tab.P_sat_kPa) || P > max(tab.P_sat_kPa)
        error('r134aState:SaturationRange', ...
            'P = %.6g kPa is outside the usable A-11 pressure range [%.6g, %.6g] kPa.', ...
            P, min(tab.P_sat_kPa), max(tab.P_sat_kPa));
    end

    sat = struct();
    sat.P_kPa = P;
    sat.T_C = interp1(tab.P_sat_kPa, tab.T_C, P, 'linear');
    sat.vf = interp1(tab.P_sat_kPa, tab.v_f_m3_kg, P, 'linear');
    sat.vg = interp1(tab.P_sat_kPa, tab.v_g_m3_kg, P, 'linear');
    sat.uf = interp1(tab.P_sat_kPa, tab.u_f_kJ_kg, P, 'linear');
    sat.ufg = interp1(tab.P_sat_kPa, tab.u_fg_kJ_kg, P, 'linear');
    sat.ug = interp1(tab.P_sat_kPa, tab.u_g_kJ_kg, P, 'linear');
    sat.hf = interp1(tab.P_sat_kPa, tab.h_f_kJ_kg, P, 'linear');
    sat.hfg = interp1(tab.P_sat_kPa, tab.h_fg_kJ_kg, P, 'linear');
    sat.hg = interp1(tab.P_sat_kPa, tab.h_g_kJ_kg, P, 'linear');
    sat.sf = interp1(tab.P_sat_kPa, tab.s_f_kJ_kg_K, P, 'linear');
    sat.sfg = interp1(tab.P_sat_kPa, tab.s_fg_kJ_kg_K, P, 'linear');
    sat.sg = interp1(tab.P_sat_kPa, tab.s_g_kJ_kg_K, P, 'linear');
    sat.source = "A-11 saturated R-134a table inverted by pressure; linear interpolation";
    sat.notes = saturationGapNotes(P, tab.P_sat_kPa, tables.removedSatP_kPa, "pressure");
end

function notes = saturationGapNotes(query, goodGrid, removedGrid, mode)
    notes = strings(0,1);
    if isempty(removedGrid)
        return
    end

    lower = max(goodGrid(goodGrid <= query));
    upper = min(goodGrid(goodGrid >= query));
    if isempty(lower) || isempty(upper)
        return
    end

    crossesRemoved = any(removedGrid > lower & removedGrid < upper) || ...
                     any(abs(removedGrid - query) <= 1e-10);
    if crossesRemoved
        notes(end+1,1) = ...
            "Interpolation spans an excluded A-11 source row whose u_f value violated the table property identities; no replacement value was inferred.";
    elseif mode == "temperature" && any(abs(removedGrid - query) < 1e-10)
        notes(end+1,1) = ...
            "The requested temperature coincides with an excluded malformed A-11 source row.";
    end
end

function state = saturatedState(sat, x)
    state = emptyState();
    state.isComplete = true;
    state.T_C = sat.T_C;
    state.P_kPa = sat.P_kPa;
    state.v_m3_kg = sat.vf + x * (sat.vg - sat.vf);
    state.u_kJ_kg = sat.uf + x * sat.ufg;
    state.h_kJ_kg = sat.hf + x * sat.hfg;
    state.s_kJ_kg_K = sat.sf + x * sat.sfg;
    state.x = x;
    state.bounds = saturationBounds(sat);

    if x <= 1e-10
        state.phaseCode = "SL";
    elseif x >= 1 - 1e-10
        state.phaseCode = "SV";
    else
        state.phaseCode = "SLVM";
    end
    state.phase = phaseLabel(state.phaseCode);
    state.source = sat.source + "; quality relation y = y_f + x y_fg";
    state = appendNotes(state, sat.notes);
end

function state = partialSaturatedState(sat, note)
    state = emptyState();
    state.T_C = sat.T_C;
    state.P_kPa = sat.P_kPa;
    state.phaseCode = "SAT";
    state.phase = phaseLabel("SAT");
    state.source = sat.source;
    state.bounds = saturationBounds(sat);
    state.notes(end+1,1) = string(note);
    state = appendNotes(state, sat.notes);
end

function state = compressedLiquidApproximation(T, P, sat)
    state = emptyState();
    state.isComplete = true;
    state.phaseCode = "CL";
    state.phase = phaseLabel("CL");
    state.T_C = T;
    state.P_kPa = P;
    state.v_m3_kg = sat.vf;
    state.u_kJ_kg = sat.uf;
    state.h_kJ_kg = sat.hf + sat.vf * (P - sat.P_kPa);
    state.s_kJ_kg_K = sat.sf;
    state.x = NaN;
    state.source = ...
        "A-11 saturated-liquid values at T plus the incompressible compressed-liquid approximation";
    state.notes(end+1,1) = ...
        "No compressed-liquid R-134a table was supplied. Approximation used: v ~= v_f(T), u ~= u_f(T), s ~= s_f(T), and h ~= h_f(T) + v_f(T)[P-P_sat(T)].";
    state = appendNotes(state, sat.notes);
end

function state = regionState(T, P, props, phaseCode, source)
    state = emptyState();
    state.isComplete = true;
    state.phaseCode = phaseCode;
    state.phase = phaseLabel(phaseCode);
    state.T_C = T;
    state.P_kPa = P;
    state.v_m3_kg = props.v;
    state.u_kJ_kg = props.u;
    state.h_kJ_kg = props.h;
    state.s_kJ_kg_K = props.s;
    state.x = NaN;
    state.source = string(source);
end

function state = appendNotes(state, newNotes)
    if ~isempty(newNotes)
        state.notes = [state.notes; string(newNotes(:))];
    end
end

function bounds = saturationBounds(sat)
    Boundary = ["saturated liquid"; "saturated vapor"];
    v_m3_kg = [sat.vf; sat.vg];
    u_kJ_kg = [sat.uf; sat.ug];
    h_kJ_kg = [sat.hf; sat.hg];
    s_kJ_kg_K = [sat.sf; sat.sg];
    bounds = table(Boundary, v_m3_kg, u_kJ_kg, h_kJ_kg, s_kJ_kg_K);
end

function [code, label] = normalizePhase(rawPhase)
    token = regexprep(lower(strtrim(string(rawPhase))), '[^a-z0-9]', '');
    switch token
        case {"cl", "compressedliquid", "subcooledliquid"}
            code = "CL";
        case {"sl", "saturatedliquid"}
            code = "SL";
        case {"slvm", "saturatedmixture", "saturatedliquidvapormixture", ...
              "saturatedliquidvapourmixture", "twophase", "mixture"}
            code = "SLVM";
        case {"sv", "saturatedvapor", "saturatedvapour"}
            code = "SV";
        case {"shv", "superheatedvapor", "superheatedvapour"}
            code = "SHV";
        case {"sc", "supercritical", "supercriticalfluid"}
            code = "SC";
        case {"sat", "saturated", "saturatedstate", ...
              "saturatedstatequalityrequired"}
            code = "SAT";
        otherwise
            error('r134aState:UnknownPhase', ...
                ['Unknown phase "%s". Use CL, SL, SLVM, SV, SHV, ' ...
                 'SC, saturated, or a full phase name.'], rawPhase);
    end
    label = phaseLabel(code);
end

function label = phaseLabel(code)
    switch string(code)
        case "CL"
            label = "Compressed liquid";
        case "SL"
            label = "Saturated liquid";
        case "SLVM"
            label = "Saturated liquid-vapor mixture";
        case "SV"
            label = "Saturated vapor";
        case "SHV"
            label = "Superheated vapor";
        case "SC"
            label = "Supercritical fluid";
        case "SAT"
            label = "Saturated state; quality required";
        otherwise
            label = "Undetermined";
    end
end

function state = emptyState()
    state = struct();
    state.fluid = "R-134a";
    state.units = "SI";
    state.isComplete = false;
    state.phaseCode = "UNDET";
    state.phase = "Undetermined";
    state.T_C = NaN;
    state.P_kPa = NaN;
    state.v_m3_kg = NaN;
    state.u_kJ_kg = NaN;
    state.h_kJ_kg = NaN;
    state.s_kJ_kg_K = NaN;
    state.x = NaN;
    state.source = "";
    state.inputPair = "";
    state.notes = strings(0,1);
    state.bounds = table();
    state.candidates = emptyCandidateTable();
end

function candidates = emptyCandidateTable()
    candidates = table('Size', [0, 9], ...
        'VariableTypes', {'double','double','double','double','double', ...
                          'double','double','string','string'}, ...
        'VariableNames', {'T_C','P_kPa','v_m3_kg','u_kJ_kg','h_kJ_kg', ...
                          's_kJ_kg_K','x','phase','source'});
end

function row = stateToCandidate(state)
    row = table(state.T_C, state.P_kPa, state.v_m3_kg, ...
        state.u_kJ_kg, state.h_kJ_kg, state.s_kJ_kg_K, state.x, ...
        string(state.phase), string(state.source), ...
        'VariableNames', {'T_C','P_kPa','v_m3_kg','u_kJ_kg','h_kJ_kg', ...
                          's_kJ_kg_K','x','phase','source'});
end

function state = candidateToState(row)
    state = emptyState();
    state.isComplete = true;
    state.T_C = row.T_C(1);
    state.P_kPa = row.P_kPa(1);
    state.v_m3_kg = row.v_m3_kg(1);
    state.u_kJ_kg = row.u_kJ_kg(1);
    state.h_kJ_kg = row.h_kJ_kg(1);
    state.s_kJ_kg_K = row.s_kJ_kg_K(1);
    state.x = row.x(1);
    state.phase = row.phase(1);
    state.source = row.source(1);
    [state.phaseCode, ~] = normalizePhase(row.phase(1));
end

function state = preserveDeclaredInputs(state, names, values)
    for k = 1:numel(names)
        switch names(k)
            case "T"
                if ~isfinite(state.T_C), state.T_C = values{k}; end
            case "P"
                if ~isfinite(state.P_kPa), state.P_kPa = values{k}; end
            case "u"
                if ~isfinite(state.u_kJ_kg), state.u_kJ_kg = values{k}; end
            case "x"
                if ~isfinite(state.x), state.x = values{k}; end
            case "phase"
                if state.phaseCode == "UNDET"
                    [state.phaseCode, state.phase] = normalizePhase(values{k});
                end
        end
    end
end

function tables = loadR134aTables(dataFolder)
    required = { ...
        'a11_saturated_r134a_temperature.csv', ...
        'a13e_superheated_r134a.csv'};

    for k = 1:numel(required)
        path = fullfile(dataFolder, required{k});
        if ~isfile(path)
            error('r134aState:MissingDataFile', ...
                'Required data file not found: %s', path);
        end
    end

    satRaw = readtable(fullfile(dataFolder, required{1}));
    [satT, removedT, removedP] = cleanSaturationTable(satRaw);

    rawSH = readtable(fullfile(dataFolder, required{2}), ...
        'TextType', 'string');
    [superheated, malformedCount] = canonicalSuperheatedTable(rawSH, satT);

    tables = struct();
    tables.satT = sortrows(satT, 'T_C');
    tables.superheated = sortrows(superheated, {'P_kPa','T_C'});
    tables.minSaturationT = min(satT.T_C);
    tables.maxSaturationT = max(satT.T_C);
    tables.minSaturationP = min(satT.P_sat_kPa);
    tables.maxSaturationP = max(satT.P_sat_kPa);
    tables.removedSatT_C = removedT;
    tables.removedSatP_kPa = removedP;

    if malformedCount > 0
        tables.superheatedSource = ...
            "A-13E superheated R-134a table converted internally to SI; malformed duplicate -20 deg F rows following 200 deg F were excluded without replacement";
    else
        tables.superheatedSource = ...
            "A-13E superheated R-134a table converted internally to SI";
    end
end

function [sat, removedT, removedP] = cleanSaturationTable(raw)
    requiredNames = { ...
        'T_C','P_sat_kPa','v_f_m3_kg','v_g_m3_kg', ...
        'u_f_kJ_kg','u_fg_kJ_kg','u_g_kJ_kg', ...
        'h_f_kJ_kg','h_fg_kJ_kg','h_g_kJ_kg', ...
        's_f_kJ_kg_K','s_fg_kJ_kg_K','s_g_kJ_kg_K'};
    assertRequiredColumns(raw, requiredNames, ...
        'a11_saturated_r134a_temperature.csv');

    uIdentityError = abs(raw.u_g_kJ_kg - ...
        (raw.u_f_kJ_kg + raw.u_fg_kJ_kg));
    hIdentityError = abs(raw.h_g_kJ_kg - ...
        (raw.h_f_kJ_kg + raw.h_fg_kJ_kg));
    sIdentityError = abs(raw.s_g_kJ_kg_K - ...
        (raw.s_f_kJ_kg_K + raw.s_fg_kJ_kg_K));
    liquidEnthalpyError = abs(raw.h_f_kJ_kg - ...
        (raw.u_f_kJ_kg + raw.P_sat_kPa .* raw.v_f_m3_kg));

    malformed = uIdentityError > 0.10 | ...
                hIdentityError > 0.10 | ...
                sIdentityError > 0.002 | ...
                liquidEnthalpyError > 0.10;

    removedT = raw.T_C(malformed);
    removedP = raw.P_sat_kPa(malformed);
    sat = raw(~malformed, requiredNames);
    sat = sortrows(sat, 'T_C');

    if height(sat) < 2 || any(diff(sat.T_C) <= 0) || ...
            any(diff(sat.P_sat_kPa) <= 0)
        error('r134aState:InvalidSaturationTable', ...
            'The usable A-11 rows are not strictly monotonic in T and P.');
    end
end

function [region, malformedCount] = canonicalSuperheatedTable(raw, satT)
    requiredNames = { ...
        'pressure_psia','T_F','row_type','v_ft3_lbm', ...
        'u_Btu_lbm','h_Btu_lbm','s_Btu_lbm_R'};
    assertRequiredColumns(raw, requiredNames, ...
        'a13e_superheated_r134a.csv');

    pPsia = str2double(string(raw.pressure_psia));
    tF = str2double(string(raw.T_F));
    rowType = lower(strtrim(string(raw.row_type)));

    % The supplied CSV contains a second -20 deg F row after the 200 deg F
    % row in every pressure block. Those rows make each block nonmonotonic
    % and are likely truncated 220 deg F labels. They are excluded rather
    % than silently relabeled.
    malformed = false(height(raw),1);
    pressureLevels = unique(pPsia(isfinite(pPsia)), 'stable');
    for k = 1:numel(pressureLevels)
        idx = find(pPsia == pressureLevels(k) & rowType == "superheated");
        for j = 2:numel(idx)
            if abs(tF(idx(j)) + 20) < 1e-10 && ...
                    abs(tF(idx(j-1)) - 200) < 1e-10
                malformed(idx(j)) = true;
            end
        end
    end
    malformedCount = sum(malformed);

    isReference = rowType == "saturated_reference";
    isSuperheated = rowType == "superheated";

    kPaPerPsia = 6.894757293168361;
    m3kgPerFt3lbm = 0.0624279605761;
    kJkgPerBtuLbm = 2.326000324917;
    kJkgKPerBtuLbmR = 4.1868005848506;

    P_kPa_all = pPsia * kPaPerPsia;
    T_C_all = (tF - 32) * (5/9);

    for k = find(isReference(:))'
        if P_kPa_all(k) >= min(satT.P_sat_kPa) && ...
                P_kPa_all(k) <= max(satT.P_sat_kPa)
            T_C_all(k) = interp1(satT.P_sat_kPa, satT.T_C, ...
                P_kPa_all(k), 'linear');
        else
            T_C_all(k) = NaN;
        end
    end

    v_all = str2double(string(raw.v_ft3_lbm)) * m3kgPerFt3lbm;
    u_all = str2double(string(raw.u_Btu_lbm)) * kJkgPerBtuLbm;
    h_all = str2double(string(raw.h_Btu_lbm)) * kJkgPerBtuLbm;
    s_all = str2double(string(raw.s_Btu_lbm_R)) * kJkgKPerBtuLbmR;

    keep = ~malformed & (isReference | isSuperheated) & ...
           isfinite(P_kPa_all) & isfinite(T_C_all) & ...
           isfinite(v_all) & isfinite(u_all) & ...
           isfinite(h_all) & isfinite(s_all);

    P_kPa = P_kPa_all(keep);
    T_C = T_C_all(keep);
    v_m3_kg = v_all(keep);
    u_kJ_kg = u_all(keep);
    h_kJ_kg = h_all(keep);
    s_kJ_kg_K = s_all(keep);
    retainedType = rowType(keep);

    % Remove any row that is below its saturation temperature after unit
    % conversion. Saturated-reference rows are retained as boundary anchors.
    Tsat = interp1(satT.P_sat_kPa, satT.T_C, P_kPa, 'linear');
    physical = retainedType == "saturated_reference" | T_C >= Tsat - 1e-8;

    P_kPa = P_kPa(physical);
    T_C = T_C(physical);
    v_m3_kg = v_m3_kg(physical);
    u_kJ_kg = u_kJ_kg(physical);
    h_kJ_kg = h_kJ_kg(physical);
    s_kJ_kg_K = s_kJ_kg_K(physical);

    region = table(P_kPa, T_C, v_m3_kg, u_kJ_kg, ...
                   h_kJ_kg, s_kJ_kg_K);
    region = sortrows(region, {'P_kPa','T_C'});
    [~, ia] = unique([region.P_kPa, region.T_C], 'rows', 'stable');
    region = region(ia,:);
end

function assertRequiredColumns(T, names, fileName)
    missing = setdiff(string(names), string(T.Properties.VariableNames));
    if ~isempty(missing)
        error('r134aState:InvalidDataSchema', ...
            'File %s is missing required column(s): %s', ...
            fileName, strjoin(missing, ', '));
    end
end
