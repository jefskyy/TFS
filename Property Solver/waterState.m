%~~This program was generated using GPT-5.6, and may include mistakes. Validate answers before implementing real world solutions.~~

function state = waterState(name1, value1, name2, value2, varargin)
%WATERSTATE Determine a water state from two declared quantities.
%
%   state = waterState("P",500,"u",2000)
%   state = waterState("T",100,"x",0.40)
%   state = waterState("T",300,"P",500)
%   state = waterState("T",100,"phase","SV")
%
% Supported declared quantities (SI version):
%   T      temperature, deg C
%   P      absolute pressure, kPa
%   u      specific internal energy, kJ/kg
%   x      vapor quality, 0 <= x <= 1
%   phase  CL, SL, SLVM, SV, SHV, or a full phase name
%
% The function uses the supplied textbook CSV files and linear
% interpolation. It never extrapolates beyond a table. Some pairs are
% thermodynamically underdetermined; in those cases state.isComplete is
% false and state.notes explains what additional information is required.
%
% Optional name-value argument:
%   "DataFolder"  Folder containing A-4 through A-7 CSV files.
%   "MaxIncompressibleApproximation_kPa"  Default 2500 kPa.
%
% Output fields include T_C, P_kPa, v_m3_kg, u_kJ_kg, h_kJ_kg,
% s_kJ_kg_K, x, phase, source, bounds, candidates, and notes.

    narginchk(4, 20);

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    opts = parseOptions(defaultFolder, varargin{:});

    n1 = normalizePropertyName(name1);
    n2 = normalizePropertyName(name2);
    if n1 == n2
        error('waterState:DuplicateInput', ...
            'Specify two different quantities, not two values of %s.', n1);
    end

    validateDeclaredValue(n1, value1);
    validateDeclaredValue(n2, value2);

    names = [n1, n2];
    values = {value1, value2};
    tables = loadWaterTables(opts.DataFolder);

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
            "This input pair is not implemented in the SI MVP.";
    end

    state.inputPair = n1 + " + " + n2;
    state = preserveDeclaredInputs(state, names, values);
end

function opts = parseOptions(defaultFolder, varargin)
    p = inputParser;
    p.FunctionName = 'waterState';
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'SaturationTolerance_C', 0.05, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'SaturationTolerance_kPa', 0.01, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'SaturationRelativeTolerance', 1e-4, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'EnergyTolerance_kJ_kg', 0.10, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'MaxIncompressibleApproximation_kPa', 2500, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0);
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
            error('waterState:UnknownProperty', ...
                'Unknown quantity "%s". Use T, P, u, x, or phase.', token);
    end
end

function validateDeclaredValue(name, value)
    if name == "phase"
        if ~(ischar(value) || (isstring(value) && isscalar(value)))
            error('waterState:InvalidPhase', ...
                'The phase value must be text such as "SHV" or "saturated vapor".');
        end
        normalizePhase(value); % Validate now.
        return
    end

    if ~(isnumeric(value) && isscalar(value) && isfinite(value))
        error('waterState:InvalidNumericInput', ...
            '%s must be a finite numeric scalar.', name);
    end
    if name == "P" && value <= 0
        error('waterState:InvalidPressure', ...
            'Pressure must be absolute and greater than zero.');
    end
    if name == "x" && (value < 0 || value > 1)
        error('waterState:InvalidQuality', ...
            'Quality x must satisfy 0 <= x <= 1.');
    end
end

function tf = hasInput(names, target)
    tf = any(names == target);
end

function value = getInput(names, values, target)
    idx = find(names == target, 1, 'first');
    if isempty(idx)
        error('waterState:InternalInputError', ...
            'The requested input %s was not supplied.', target);
    end
    value = values{idx};
end

function state = solveTP(T, P, tables, opts)
    state = emptyState();
    state.T_C = T;
    state.P_kPa = P;

    if T < tables.minSaturationT
        % A-7 contains a limited set of high-pressure liquid states at 0 C.
        % Try that table first; otherwise the ice-water-vapor region needs A-8.
        try
            [props, meta] = regionAtTP(tables.compressed, T, P);
            state = regionState(T, P, props, "CL", ...
                "A-7 compressed-liquid table; " + meta.method);
        catch
            state.notes(end+1,1) = ...
                "This state is below the A-4 saturation range and is not covered by A-7. It requires the A-8 ice-water-vapor model, which is not included in this MVP.";
        end
        return
    end

    % When pressure is within A-5, compare both T to T_sat(P) and P to
    % P_sat(T). Accept a saturation pair copied from either printed table.
    if P >= tables.minSaturationP && P <= tables.Pcrit
        satP = saturationAtP(P, tables);
        onSatByP = abs(T - satP.T_C) <= opts.SaturationTolerance_C;
        haveSatT = T <= tables.Tcrit;

        if haveSatT
            satT = saturationAtT(T, tables);
            pTol = max(opts.SaturationTolerance_kPa, ...
                       opts.SaturationRelativeTolerance * satT.P_kPa);
            onSatByT = abs(P - satT.P_kPa) <= pTol;
        else
            satT = struct();
            pTol = NaN;
            onSatByT = false;
        end

        % Accept a saturation pair copied from either A-4 or A-5. The two
        % printed tables have different grids and rounding, so requiring
        % both interpolation checks to be exact would be inappropriate.
        if onSatByP || onSatByT
            if onSatByP
                sat = satP;
            else
                sat = satT;
            end
            if isCriticalSaturation(sat)
                state = criticalState(sat);
            else
                state = partialSaturatedState(sat, ...
                    "T and P are dependent on the saturation line. Supply x or another specific property to locate the state inside the dome.");
            end
            return
        end

        compressed = T < satP.T_C - opts.SaturationTolerance_C;
        superheated = T > satP.T_C + opts.SaturationTolerance_C;
        if haveSatT
            compressed = compressed && P > satT.P_kPa + pTol;
            superheated = superheated && P < satT.P_kPa - pTol;
        end

        if ~(compressed || superheated)
            % The A-4 and A-5 interpolation tests disagree only in a narrow
            % band caused by source rounding or incompatible declared data.
            state = partialSaturatedState(satP, ...
                "A-4 and A-5 do not give a consistent phase direction for this rounded T-P pair. Treat it as near saturation and supply x or another property rather than forcing a phase classification.");
            return
        elseif compressed
            % Compressed liquid. Prefer A-7 when the state is covered.
            try
                [props, meta] = regionAtTP(tables.compressed, T, P);
                state = regionState(T, P, props, "CL", ...
                    "A-7 compressed-liquid table; " + meta.method);
            catch ME
                if strcmp(ME.identifier, 'waterState:OutOfTableRange') && ...
                        P <= opts.MaxIncompressibleApproximation_kPa
                    satForApprox = saturationAtT(T, tables);
                    state = compressedLiquidApproximation(T, P, satForApprox);
                else
                    state.notes(end+1,1) = string(ME.message);
                    state.phaseCode = "CL";
                    state.phase = phaseLabel("CL");
                end
            end
            return
        else
            phaseCode = "SHV";
            if P >= tables.Pcrit && T > tables.Tcrit
                phaseCode = "SC";
            end
            try
                [props, meta] = regionAtTP(tables.superheated, T, P);
                state = regionState(T, P, props, phaseCode, ...
                    "A-6 superheated-water table; " + meta.method);
            catch ME
                state.notes(end+1,1) = string(ME.message);
                state.phaseCode = phaseCode;
                state.phase = phaseLabel(phaseCode);
            end
            return
        end
    end

    % A-5 begins at 1 kPa, while A-4 extends to the triple-point pressure.
    % Use P relative to P_sat(T) only in this narrow low-pressure interval.
    if P < tables.minSaturationP && T <= tables.Tcrit
        satT = saturationAtT(T, tables);
        pTol = max(opts.SaturationTolerance_kPa, ...
                   opts.SaturationRelativeTolerance * satT.P_kPa);
        if abs(P - satT.P_kPa) <= pTol
            state = partialSaturatedState(satT, ...
                "T and P identify the saturation line but not quality x.");
        elseif P > satT.P_kPa
            state = compressedLiquidApproximation(T, P, satT);
        else
            try
                [props, meta] = regionAtTP(tables.superheated, T, P);
                state = regionState(T, P, props, "SHV", ...
                    "A-6 superheated-water table; " + meta.method);
            catch ME
                state.notes(end+1,1) = string(ME.message);
                state.phaseCode = "SHV";
                state.phase = phaseLabel("SHV");
            end
        end
        return
    end

    % At pressures below A-5 but above the critical temperature, the
    % phase is superheated vapor even though A-6 may not extend that low.
    if P < tables.minSaturationP
        phaseCode = "SHV";
        try
            [props, meta] = regionAtTP(tables.superheated, T, P);
            state = regionState(T, P, props, phaseCode, ...
                "A-6 superheated-water table; " + meta.method);
        catch ME
            state.notes(end+1,1) = string(ME.message);
            state.phaseCode = phaseCode;
            state.phase = phaseLabel(phaseCode);
        end
        return
    end

    % Above the critical pressure, classify by temperature relative to the
    % critical-temperature row, then use A-7 or A-6 when covered.
    if T < tables.Tcrit
        phaseCode = "CL";
        try
            [props, meta] = regionAtTP(tables.compressed, T, P);
            state = regionState(T, P, props, phaseCode, ...
                "A-7 compressed-liquid table; " + meta.method);
        catch ME
            state.notes(end+1,1) = string(ME.message);
            state.phaseCode = phaseCode;
            state.phase = phaseLabel(phaseCode);
        end
    else
        phaseCode = "SC";
        try
            [props, meta] = regionAtTP(tables.superheated, T, P);
            state = regionState(T, P, props, phaseCode, ...
                "A-6 high-temperature table; " + meta.method);
        catch ME
            state.notes(end+1,1) = string(ME.message);
            state.phaseCode = phaseCode;
            state.phase = phaseLabel(phaseCode);
        end
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

    if P >= tables.minSaturationP && P <= tables.Pcrit
        sat = saturationAtP(P, tables);
        eTol = opts.EnergyTolerance_kJ_kg;

        if isCriticalSaturation(sat) && abs(u - sat.uf) <= eTol
            state = criticalState(sat);
            return
        elseif u >= sat.uf - eTol && u <= sat.ug + eTol
            x = (u - sat.uf) / sat.ufg;
            x = min(max(x, 0), 1);
            state = saturatedState(sat, x);
            return
        elseif u < sat.uf
            if P <= opts.MaxIncompressibleApproximation_kPa
                T = inverseMonotonic(tables.satT.u_f_kJ_kg, ...
                                     tables.satT.T_C, u);
                if isfinite(T)
                    satT = saturationAtT(T, tables);
                    if P > satT.P_kPa
                        state = compressedLiquidApproximation(T, P, satT);
                        state.notes(end+1,1) = ...
                            "Temperature was obtained by inverting u_f(T); pressure dependence of u was neglected in the incompressible approximation.";
                        return
                    end
                end
            end

            candidates = candidatesAtP(tables.compressed, P, u, ...
                                       "CL", "A-7 compressed-liquid table", opts);
            state = chooseCandidates(candidates, state, ...
                "No unique compressed-liquid state was found inside the A-7 range.");
            return
        else
            candidates = candidatesAtP(tables.superheated, P, u, ...
                                       "SHV", "A-6 superheated-water table", opts);
            state = chooseCandidates(candidates, state, ...
                "No unique superheated state was found inside the A-6 range.");
            return
        end
    end

    % Outside the saturation-pressure range, search each applicable table.
    candidates = emptyCandidateTable();
    candidates = [candidates; candidatesAtP(tables.compressed, P, u, ...
                   "CL", "A-7 compressed-liquid table", opts)]; %#ok<AGROW>
    candidates = [candidates; candidatesAtP(tables.superheated, P, u, ...
                   "SC", "A-6 high-pressure/high-temperature table", opts)]; %#ok<AGROW>
    state = chooseCandidates(candidates, state, ...
        "The requested P-u state is outside the supported table ranges or is not unique.");
end

function state = solveTU(T, u, tables, opts)
    state = emptyState();
    state.T_C = T;
    state.u_kJ_kg = u;

    if T < tables.minSaturationT
        candidates = candidatesAtT(tables.compressed, T, u, ...
                                   "CL", "A-7 compressed-liquid table", opts);
        state = chooseCandidates(candidates, state, ...
            "This T-u state is below the A-4 range and is not uniquely covered by A-7. It requires the A-8 ice-water-vapor model for other phases.");
        return
    end

    if T <= tables.Tcrit
        sat = saturationAtT(T, tables);
        eTol = opts.EnergyTolerance_kJ_kg;

        if isCriticalSaturation(sat) && abs(u - sat.uf) <= eTol
            state = criticalState(sat);
            return
        elseif u >= sat.uf - eTol && u <= sat.ug + eTol
            x = (u - sat.uf) / sat.ufg;
            x = min(max(x, 0), 1);
            state = saturatedState(sat, x);
            return
        elseif u < sat.uf
            candidates = candidatesAtT(tables.compressed, T, u, ...
                                       "CL", "A-7 compressed-liquid table", opts);
            state = chooseCandidates(candidates, state, ...
                "At low pressure, the incompressible approximation makes u approximately a function of T only, so T and u do not uniquely determine pressure. A unique result is returned only when A-7 contains a single pressure solution.");
            return
        else
            candidates = candidatesAtT(tables.superheated, T, u, ...
                                       "SHV", "A-6 superheated-water table", opts);
            state = chooseCandidates(candidates, state, ...
                "No unique superheated state was found inside the A-6 range.");
            return
        end
    end

    candidates = emptyCandidateTable();
    candidates = [candidates; candidatesAtT(tables.compressed, T, u, ...
                   "CL", "A-7 compressed-liquid table", opts)]; %#ok<AGROW>
    candidates = [candidates; candidatesAtT(tables.superheated, T, u, ...
                   "SC", "A-6 high-temperature table", opts)]; %#ok<AGROW>
    state = chooseCandidates(candidates, state, ...
        "The requested T-u state is outside the supported table ranges or is not unique.");
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
        "The pair u-x did not produce a unique saturation state. This can occur because u_g and some mixture-energy curves are not monotonic near the critical region.");
end

function state = solvePhasePair(otherName, otherValue, phaseValue, tables, opts)
    [phaseCode, phaseText] = normalizePhase(phaseValue);
    state = emptyState();
    state.phaseCode = phaseCode;
    state.phase = phaseText;

    if phaseCode == "CRIT"
        satCrit = saturationAtT(tables.Tcrit, tables);
        switch otherName
            case "T"
                if abs(otherValue - tables.Tcrit) <= opts.SaturationTolerance_C
                    state = criticalState(satCrit);
                else
                    state.T_C = otherValue;
                    state.notes(end+1,1) = "The declared temperature does not match the critical-point row in A-4.";
                end
            case "P"
                pTol = max(opts.SaturationTolerance_kPa, ...
                    opts.SaturationRelativeTolerance * tables.Pcrit);
                if abs(otherValue - tables.Pcrit) <= pTol
                    state = criticalState(satCrit);
                else
                    state.P_kPa = otherValue;
                    state.notes(end+1,1) = "The declared pressure does not match the critical-point row in A-5.";
                end
            case "u"
                if abs(otherValue - satCrit.uf) <= opts.EnergyTolerance_kJ_kg
                    state = criticalState(satCrit);
                else
                    state.u_kJ_kg = otherValue;
                    state.notes(end+1,1) = "The declared internal energy does not match the critical-point row.";
                end
            otherwise
                state.notes(end+1,1) = "Quality is not defined at the critical point.";
        end
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
                    "Phase plus one intensive property is not enough to fix a compressed-liquid, superheated-vapor, or supercritical state. Supply P or another independent property.";
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
                    "Phase plus one intensive property is not enough to fix a compressed-liquid, superheated-vapor, or supercritical state. Supply T or another independent property.";
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
            code = phaseCode;
            if phaseCode == "SC" && P < 22064
                code = "SHV";
            end
            s = regionState(rootsT(k), P, props, code, ...
                source + "; inverse interpolation in u followed by " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
            % A root at an unsupported boundary is simply not a valid candidate.
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
            code = phaseCode;
            if phaseCode == "SC" && rootsP(k) < 22064
                code = "SHV";
            end
            s = regionState(T, rootsP(k), props, code, ...
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
        error('waterState:OutOfTableRange', ...
            'T = %.6g deg C and P = %.6g kPa are outside the usable region of this table. No extrapolation was performed.', T, P);
    end

    exactIdx = find(abs(pValid - P) <= max(1e-9, 1e-12*abs(P)), 1);
    if ~isempty(exactIdx)
        result = values(exactIdx,:);
        method = "linear interpolation in temperature at a tabulated pressure";
    else
        lowerIdx = find(pValid < P, 1, 'last');
        upperIdx = find(pValid > P, 1, 'first');
        if isempty(lowerIdx) || isempty(upperIdx)
            error('waterState:OutOfTableRange', ...
                'The requested pressure is not bracketed by usable table blocks at T = %.6g deg C.', T);
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

    % Permit a rounded endpoint only when no interpolated crossing exists.
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
    [x, order] = sort(x);
    y = y(order);
    [x, ia] = unique(x, 'stable');
    y = y(ia);
    if target < min(x) || target > max(x)
        value = NaN;
    else
        value = interp1(x, y, target, 'linear');
    end
end

function sat = saturationAtT(T, tables)
    tab = tables.satT;
    if T < min(tab.T_C) || T > max(tab.T_C)
        error('waterState:SaturationRange', ...
            'T = %.6g deg C is outside the A-4 saturation range [%.6g, %.6g] deg C.', ...
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
    sat.source = "A-4 saturation table; linear interpolation in temperature";
end

function sat = saturationAtP(P, tables)
    tab = tables.satP;
    if P < min(tab.P_kPa) || P > max(tab.P_kPa)
        error('waterState:SaturationRange', ...
            'P = %.6g kPa is outside the A-5 saturation range [%.6g, %.6g] kPa.', ...
            P, min(tab.P_kPa), max(tab.P_kPa));
    end

    sat = struct();
    sat.P_kPa = P;
    sat.T_C = interp1(tab.P_kPa, tab.T_sat_C, P, 'linear');
    sat.vf = interp1(tab.P_kPa, tab.v_f_m3_kg, P, 'linear');
    sat.vg = interp1(tab.P_kPa, tab.v_g_m3_kg, P, 'linear');
    sat.uf = interp1(tab.P_kPa, tab.u_f_kJ_kg, P, 'linear');
    sat.ufg = interp1(tab.P_kPa, tab.u_fg_kJ_kg, P, 'linear');
    sat.ug = interp1(tab.P_kPa, tab.u_g_kJ_kg, P, 'linear');
    sat.hf = interp1(tab.P_kPa, tab.h_f_kJ_kg, P, 'linear');
    sat.hfg = interp1(tab.P_kPa, tab.h_fg_kJ_kg, P, 'linear');
    sat.hg = interp1(tab.P_kPa, tab.h_g_kJ_kg, P, 'linear');
    sat.sf = interp1(tab.P_kPa, tab.s_f_kJ_kg_K, P, 'linear');
    sat.sfg = interp1(tab.P_kPa, tab.s_fg_kJ_kg_K, P, 'linear');
    sat.sg = interp1(tab.P_kPa, tab.s_g_kJ_kg_K, P, 'linear');
    sat.source = "A-5 saturation table; linear interpolation in pressure";
end

function tf = isCriticalSaturation(sat)
    tf = abs(sat.vg - sat.vf) < 1e-10 || ...
         (abs(sat.ufg) < 1e-8 && abs(sat.hfg) < 1e-8);
end

function state = saturatedState(sat, x)
    if isCriticalSaturation(sat)
        state = criticalState(sat);
        state.notes(end+1,1) = ...
            "Quality is not meaningful at the critical point because saturated-liquid and saturated-vapor properties coincide.";
        return
    end

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
end

function state = criticalState(sat)
    state = emptyState();
    state.isComplete = true;
    state.phaseCode = "CRIT";
    state.phase = phaseLabel("CRIT");
    state.T_C = sat.T_C;
    state.P_kPa = sat.P_kPa;
    state.v_m3_kg = sat.vf;
    state.u_kJ_kg = sat.uf;
    state.h_kJ_kg = sat.hf;
    state.s_kJ_kg_K = sat.sf;
    state.x = NaN;
    state.bounds = saturationBounds(sat);
    state.source = sat.source;
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
    state.source = "A-4 saturated-liquid values at T plus the incompressible compressed-liquid approximation";
    state.notes(end+1,1) = ...
        "Approximation used: v ~= v_f(T), u ~= u_f(T), s ~= s_f(T), and h ~= h_f(T) + v_f(T)[P-P_sat(T)].";
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
    if ~isfinite(props.s)
        state.notes(end+1,1) = ...
            "Entropy is not reported because the interpolation touches a source cell flagged as malformed; no replacement value was inferred.";
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
    token = regexprep(lower(strtrim(string(rawPhase))), '[^a-z0-9]', ''); %switched code sequence to respond to "S" being truncated at SHV
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
        case {"sat", "saturated", "saturatedstate", "saturatedstatequalityrequired"}
            code = "SAT";
        case {"critical", "criticalpoint", "crit"}
            code = "CRIT";
        otherwise
            error('waterState:UnknownPhase', ...
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
        case "CRIT"
            label = "Critical point";
        otherwise
            label = "Undetermined";
    end
end

function state = emptyState()
    state = struct();
    state.fluid = "Water";
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
                if ~isfinite(state.x) && state.phaseCode ~= "CRIT"
                    state.x = values{k};
                end
            case "phase"
                if state.phaseCode == "UNDET"
                    [state.phaseCode, state.phase] = normalizePhase(values{k});
                end
        end
    end
end

function tables = loadWaterTables(dataFolder)
    persistent cachedFolder cachedTables
    folderText = string(dataFolder);
    if ~isempty(cachedFolder) && cachedFolder == folderText
        tables = cachedTables;
        return
    end

    required = { ...
        'a4_saturated_water_temperature.csv', ...
        'a5_saturated_water_pressure.csv', ...
        'a6_superheated_water.csv', ...
        'a7_compressed_liquid_water.csv'};
    for k = 1:numel(required)
        path = fullfile(dataFolder, required{k});
        if ~isfile(path)
            error('waterState:MissingDataFile', ...
                'Required data file not found: %s', path);
        end
    end

    satT = readtable(fullfile(dataFolder, required{1}));
    satP = readtable(fullfile(dataFolder, required{2}));
    rawSH = readtable(fullfile(dataFolder, required{3}), 'TextType', 'string');
    rawCL = readtable(fullfile(dataFolder, required{4}), 'TextType', 'string');

    superheated = canonicalRegionTable(rawSH, satP, 1000);
    compressed = canonicalRegionTable(rawCL, satP, 1000);

    % The source A-7 CSV contains s = 20.0010 kJ/(kg K) at 50 MPa, 0 C.
    % This is retained in the raw CSV but suppressed in the working table;
    % no replacement value is inferred.
    flagged = abs(compressed.P_kPa - 50000) < 1e-9 & ...
              abs(compressed.T_C) < 1e-9 & ...
              compressed.s_kJ_kg_K > 10;
    compressed.s_kJ_kg_K(flagged) = NaN;

    tables = struct();
    tables.satT = sortrows(satT, 'T_C');
    tables.satP = sortrows(satP, 'P_kPa');
    tables.superheated = sortrows(superheated, {'P_kPa','T_C'});
    tables.compressed = sortrows(compressed, {'P_kPa','T_C'});
    tables.minSaturationT = min(satT.T_C);
    tables.minSaturationP = min(satP.P_kPa);
    tables.Tcrit = max(satT.T_C);
    tables.Pcrit = max(satP.P_kPa);
    tables.minCompressedP = min(compressed.P_kPa);
    tables.maxCompressedP = max(compressed.P_kPa);

    cachedFolder = folderText;
    cachedTables = tables;
end

function region = canonicalRegionTable(raw, satP, pressureMultiplier)
    p = raw.pressure_MPa * pressureMultiplier;
    t = str2double(string(raw.T_C));
    rowType = lower(string(raw.row_type));
    isReference = rowType == "saturated_reference";

    for k = find(isReference(:))'
        if p(k) >= min(satP.P_kPa) && p(k) <= max(satP.P_kPa)
            t(k) = interp1(satP.P_kPa, satP.T_sat_C, p(k), 'linear');
        end
    end

    keep = isfinite(t);
    P_kPa = p(keep);
    T_C = t(keep);
    v_m3_kg = raw.v_m3_kg(keep);
    u_kJ_kg = raw.u_kJ_kg(keep);
    h_kJ_kg = raw.h_kJ_kg(keep);
    s_kJ_kg_K = raw.s_kJ_kg_K(keep);
    region = table(P_kPa, T_C, v_m3_kg, u_kJ_kg, h_kJ_kg, s_kJ_kg_K);
end
