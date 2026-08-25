function state = airState(name1, value1, name2, value2, varargin)
%AIRSTATE Determine an ideal-gas air state from two declared quantities.
%
%   state = airState("T",26.85,"P",100)
%   state = airState("T_K",300,"P",100)
%   state = airState("P",500,"u",214.07)
%   state = airState("P",100,"v",0.861)
%   state = airState("u",214.07,"s",1.70203)
%
% Supported declared quantities (SI interface):
%   T, T_C   temperature in deg C
%   T_K      absolute temperature in K
%   P        absolute pressure in kPa
%   v        specific volume in m^3/kg
%   rho      density in kg/m^3
%   u        specific internal energy in kJ/kg
%   h        specific enthalpy in kJ/kg
%   s        reference-based specific entropy in kJ/(kg K)
%   s0       tabulated standard-state entropy function in kJ/(kg K)
%
% A complete ideal-gas state requires one temperature-defining quantity
% and one independent mechanical or entropy quantity. Because u, h, and
% s0 are functions of temperature alone for ideal-gas air, pairs such as
% T+u or u+h are checked for consistency but remain underdetermined.
%
% Data sources:
%   A-21  ideal-gas properties of air: h, u, relative pressure,
%         relative specific volume, and s0 as functions of temperature.
%   A-22  air properties at 1 atm: cp, thermal conductivity, dynamic
%         viscosity, and Prandtl number as functions of temperature.
%
% A-22 density, thermal diffusivity, and kinematic viscosity are not copied
% directly at arbitrary pressure. The solver instead evaluates density from
% Pv = RT and then calculates alpha = k/(rho*cp) and nu = mu/rho.
%
% Optional name-value arguments:
%   "DataFolder"              folder containing the air CSV files
%   "GasConstant_kJ_kg_K"     default 0.2870 kJ/(kg K)
%   "ReferencePressure_kPa"   default 100 kPa for the reported s value
%   "TemperatureTolerance_K"  default 0.5 K for redundant-input checks
%
% Output fields retain the naming pattern used by waterState and
% r134aState, while adding ideal-gas and transport properties.

    narginchk(4, 20);

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    opts = parseOptions(defaultFolder, varargin{:});

    in1 = normalizeInput(name1, value1);
    in2 = normalizeInput(name2, value2);
    if in1.name == in2.name
        error('airState:DuplicateInput', ...
            'Specify two independent quantities; %s and %s represent the same property.', ...
            string(name1), string(name2));
    end

    tables = loadAirTables(opts.DataFolder);
    inputs = [in1, in2];

    state = emptyState(opts);
    state.inputPair = in1.label + " + " + in2.label;
    state = preserveDeclaredInputs(state, inputs);

    try
        [T_K, temperatureNotes] = determineTemperature(inputs, tables, opts);
    catch ME
        if startsWith(string(ME.identifier), "airState:OutOfTableRange") || ...
           startsWith(string(ME.identifier), "airState:Underdetermined")
            state.notes(end+1,1) = string(ME.message);
            return
        end
        rethrow(ME)
    end

    state.T_K = T_K;
    state.T_C = T_K - 273.15;
    state.notes = appendStrings(state.notes, temperatureNotes);

    try
        [thermo, thermoNotes] = idealGasPropertiesAtT(T_K, tables);
    catch ME
        if startsWith(string(ME.identifier), "airState:OutOfTableRange")
            state.notes(end+1,1) = string(ME.message);
            return
        end
        rethrow(ME)
    end

    state.u_kJ_kg = thermo.u;
    state.h_kJ_kg = thermo.h;
    state.s0_kJ_kg_K = thermo.s0;
    state.Pr_relative = thermo.PrRelative;
    state.vr_relative = thermo.vrRelative;
    state.notes = appendStrings(state.notes, thermoNotes);

    [P_kPa, v_m3_kg, mechanicalNote] = determineMechanicalState( ...
        inputs, T_K, thermo.s0, opts);
    state.notes = appendStrings(state.notes, mechanicalNote);

    if ~(isfinite(P_kPa) && isfinite(v_m3_kg))
        state = addTransportProperties(state, tables, opts);
        state.notes(end+1,1) = ...
            "The supplied pair determines temperature-dependent air properties but not both P and v. Supply P, v, rho, or the reference-based entropy s as an independent second quantity.";
        return
    end

    state.P_kPa = P_kPa;
    state.v_m3_kg = v_m3_kg;
    state.rho_kg_m3 = 1 / v_m3_kg;
    state.s_kJ_kg_K = thermo.s0 - opts.GasConstant_kJ_kg_K * ...
        log(P_kPa / opts.ReferencePressure_kPa);

    checkDeclaredConsistency(state, inputs, opts);

    state.phaseCode = "IG";
    state.phase = "Ideal gas";
    state.model = "Ideal-gas air";
    state.isComplete = all(isfinite([state.T_K, state.P_kPa, ...
        state.v_m3_kg, state.u_kJ_kg, state.h_kJ_kg]));

    state = addTransportProperties(state, tables, opts);
    state.source = ...
        "A-21 air ideal-gas table with linear interpolation in temperature; " + ...
        "Pv = RT for pressure, specific volume, and density; A-22 air-at-1-atm table for cp, k, mu, and Prandtl number.";
end

function opts = parseOptions(defaultFolder, varargin)
    p = inputParser;
    p.FunctionName = 'airState';
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'GasConstant_kJ_kg_K', 0.2870, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'ReferencePressure_kPa', 100, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'TemperatureTolerance_K', 0.5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'RelativeConsistencyTolerance', 5e-4, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'EntropyConsistencyTolerance_kJ_kg_K', 5e-5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    parse(p, varargin{:});

    opts = p.Results;
    opts.DataFolder = char(opts.DataFolder);
end

function input = normalizeInput(rawName, rawValue)
    if ~(isnumeric(rawValue) && isscalar(rawValue) && isfinite(rawValue))
        error('airState:InvalidInput', ...
            'The value associated with %s must be a finite numeric scalar.', ...
            string(rawName));
    end

    token = regexprep(lower(strtrim(string(rawName))), '[^a-z0-9]', '');
    input = struct('name', "", 'value', NaN, 'label', "");

    switch token
        case {"t", "tc", "temperature", "temperaturec", "degc"}
            input.name = "T";
            input.value = rawValue + 273.15;
            input.label = "T";
            if input.value <= 0
                error('airState:InvalidTemperature', ...
                    'Temperature must be greater than absolute zero.');
            end

        case {"tk", "temperaturek", "kelvin"}
            input.name = "T";
            input.value = rawValue;
            input.label = "T_K";
            if input.value <= 0
                error('airState:InvalidTemperature', ...
                    'Absolute temperature must be greater than zero kelvin.');
            end

        case {"p", "pressure", "pkpa", "pressurekpa"}
            input.name = "P";
            input.value = rawValue;
            input.label = "P";
            if input.value <= 0
                error('airState:InvalidPressure', ...
                    'Pressure must be absolute and greater than zero.');
            end

        case {"v", "specificvolume", "vm3kg", "specificvolumem3kg"}
            input.name = "v";
            input.value = rawValue;
            input.label = "v";
            if input.value <= 0
                error('airState:InvalidSpecificVolume', ...
                    'Specific volume must be greater than zero.');
            end

        case {"rho", "density", "rhokgm3", "densitykgm3"}
            if rawValue <= 0
                error('airState:InvalidDensity', ...
                    'Density must be greater than zero.');
            end
            input.name = "v";
            input.value = 1 / rawValue;
            input.label = "rho";

        case {"u", "internalenergy", "specificinternalenergy", "ukjkg"}
            input.name = "u";
            input.value = rawValue;
            input.label = "u";

        case {"h", "enthalpy", "specificenthalpy", "hkjkg"}
            input.name = "h";
            input.value = rawValue;
            input.label = "h";

        case {"s", "entropy", "specificentropy", "skjkgk"}
            input.name = "s";
            input.value = rawValue;
            input.label = "s";

        case {"s0", "standardentropy", "standardstateentropy", "s0kjkgk"}
            input.name = "s0";
            input.value = rawValue;
            input.label = "s0";

        otherwise
            error('airState:UnknownProperty', ...
                ['Unknown quantity "%s". Use T, T_K, P, v, rho, u, ' ...
                 'h, s, or s0.'], string(rawName));
    end
end

function [T_K, notes] = determineTemperature(inputs, tables, opts)
    temperatures = zeros(0,1);
    labels = strings(0,1);
    notes = strings(0,1);

    for k = 1:numel(inputs)
        switch inputs(k).name
            case "T"
                temperatures(end+1,1) = inputs(k).value; %#ok<AGROW>
                labels(end+1,1) = inputs(k).label; %#ok<AGROW>
            case "u"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K, tables.a21.u_kJ_kg, ...
                    inputs(k).value, "u"); %#ok<AGROW>
                labels(end+1,1) = "u"; %#ok<AGROW>
            case "h"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K, tables.a21.h_kJ_kg, ...
                    inputs(k).value, "h"); %#ok<AGROW>
                labels(end+1,1) = "h"; %#ok<AGROW>
            case "s0"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K, tables.a21.s0_kJ_kg_K, ...
                    inputs(k).value, "s0"); %#ok<AGROW>
                labels(end+1,1) = "s0"; %#ok<AGROW>
        end
    end

    if hasInput(inputs, "P") && hasInput(inputs, "v")
        P = getInput(inputs, "P");
        v = getInput(inputs, "v");
        temperatures(end+1,1) = P * v / opts.GasConstant_kJ_kg_K;
        labels(end+1,1) = "Pv = RT";
    elseif hasInput(inputs, "P") && hasInput(inputs, "s")
        P = getInput(inputs, "P");
        sTarget = getInput(inputs, "s");
        entropyGrid = tables.a21.s0_kJ_kg_K - ...
            opts.GasConstant_kJ_kg_K * log(P / opts.ReferencePressure_kPa);
        temperatures(end+1,1) = inverseTableProperty( ...
            tables.a21.T_K, entropyGrid, sTarget, "s at declared P");
        labels(end+1,1) = "P+s";
    elseif hasInput(inputs, "v") && hasInput(inputs, "s")
        v = getInput(inputs, "v");
        sTarget = getInput(inputs, "s");
        pressureGrid = opts.GasConstant_kJ_kg_K .* tables.a21.T_K ./ v;
        entropyGrid = tables.a21.s0_kJ_kg_K - ...
            opts.GasConstant_kJ_kg_K .* ...
            log(pressureGrid ./ opts.ReferencePressure_kPa);
        temperatures(end+1,1) = inverseTableProperty( ...
            tables.a21.T_K, entropyGrid, sTarget, "s at declared v");
        labels(end+1,1) = "v+s";
    end

    if isempty(temperatures)
        error('airState:Underdetermined', ...
            ['This pair does not determine temperature. Supply T, u, h, ' ...
             'or s0; alternatively use P+v, P+s, or v+s.']);
    end

    T_K = temperatures(1);
    if numel(temperatures) > 1
        mismatch = max(abs(temperatures - T_K));
        if mismatch > opts.TemperatureTolerance_K
            detail = strjoin(labels + " -> " + compose("%.6g K", temperatures), "; ");
            error('airState:InconsistentInputs', ...
                'The declared quantities imply inconsistent temperatures: %s.', detail);
        end
        T_K = mean(temperatures);
        notes(end+1,1) = ...
            "Both declared quantities depend on temperature alone and were checked for consistency.";
    end

    if T_K <= 0
        error('airState:InvalidTemperature', ...
            'The declared pair implies a nonphysical absolute temperature.');
    end
end

function [P_kPa, v_m3_kg, note] = determineMechanicalState(inputs, T_K, s0, opts)
    P_kPa = NaN;
    v_m3_kg = NaN;
    note = strings(0,1);

    haveP = hasInput(inputs, "P");
    haveV = hasInput(inputs, "v");
    haveS = hasInput(inputs, "s");

    if haveP
        P_kPa = getInput(inputs, "P");
        v_m3_kg = opts.GasConstant_kJ_kg_K * T_K / P_kPa;
    elseif haveV
        v_m3_kg = getInput(inputs, "v");
        P_kPa = opts.GasConstant_kJ_kg_K * T_K / v_m3_kg;
    elseif haveS
        s = getInput(inputs, "s");
        P_kPa = opts.ReferencePressure_kPa * ...
            exp((s0 - s) / opts.GasConstant_kJ_kg_K);
        v_m3_kg = opts.GasConstant_kJ_kg_K * T_K / P_kPa;
        note(end+1,1) = ...
            "Pressure was obtained from s = s0(T) - R ln(P/Pref) using the configured reference pressure.";
    end
end

function checkDeclaredConsistency(state, inputs, opts)
    for k = 1:numel(inputs)
        declared = inputs(k).value;
        switch inputs(k).name
            case "T"
                calculated = state.T_K;
                tolerance = opts.TemperatureTolerance_K;
            case "P"
                calculated = state.P_kPa;
                tolerance = opts.RelativeConsistencyTolerance * max(abs(declared), 1);
            case "v"
                calculated = state.v_m3_kg;
                tolerance = opts.RelativeConsistencyTolerance * max(abs(declared), 1e-12);
            case "u"
                calculated = state.u_kJ_kg;
                tolerance = opts.RelativeConsistencyTolerance * max(abs(declared), 1);
            case "h"
                calculated = state.h_kJ_kg;
                tolerance = opts.RelativeConsistencyTolerance * max(abs(declared), 1);
            case "s"
                calculated = state.s_kJ_kg_K;
                tolerance = opts.EntropyConsistencyTolerance_kJ_kg_K;
            case "s0"
                calculated = state.s0_kJ_kg_K;
                tolerance = opts.EntropyConsistencyTolerance_kJ_kg_K;
            otherwise
                continue
        end

        if isfinite(calculated) && abs(calculated - declared) > tolerance
            error('airState:InconsistentInputs', ...
                ['The calculated %s value (%.9g) is inconsistent with the ' ...
                 'declared value (%.9g).'], inputs(k).label, calculated, declared);
        end
    end
end

function [props, notes] = idealGasPropertiesAtT(T_K, tables)
    if T_K < tables.minT_K || T_K > tables.maxT_K
        error('airState:OutOfTableRange', ...
            ['T = %.6g K is outside the supplied A-21 range of %.6g to ' ...
             '%.6g K. No extrapolation was performed.'], ...
             T_K, tables.minT_K, tables.maxT_K);
    end

    props = struct();
    props.h = interpolateFinite(tables.a21.T_K, ...
        tables.a21.h_kJ_kg, T_K);
    props.u = interpolateFinite(tables.a21.T_K, ...
        tables.a21.u_kJ_kg, T_K);
    props.PrRelative = interpolateFinite(tables.a21.T_K, ...
        tables.a21.Pr, T_K);
    props.vrRelative = interpolateFinite(tables.a21.T_K, ...
        tables.a21.v_r, T_K);
    props.s0 = interpolateFinite(tables.a21.T_K, ...
        tables.a21.s0_kJ_kg_K, T_K);

    notes = strings(0,1);
    for k = 1:numel(tables.excludedH_T_K)
        badT = tables.excludedH_T_K(k);
        finiteMask = isfinite(tables.a21.h_kJ_kg);
        lowerT = max(tables.a21.T_K(finiteMask & tables.a21.T_K < badT));
        upperT = min(tables.a21.T_K(finiteMask & tables.a21.T_K > badT));
        if ~isempty(lowerT) && ~isempty(upperT) && T_K >= lowerT && T_K <= upperT
            notes(end+1,1) = ...
                "The supplied A-21 h value at 550 K was excluded because it conflicts with h-u = RT and the neighboring trend; h was linearly interpolated across the adjacent valid rows.";
        end
    end
end

function state = addTransportProperties(state, tables, opts)
    if ~isfinite(state.T_C)
        return
    end

    T_C = state.T_C;
    if T_C < tables.minTransportT_C || T_C > tables.maxTransportT_C
        state.notes(end+1,1) = ...
            "Temperature is outside the supplied A-22 transport-property range; cp, k, mu, and Prandtl number were not extrapolated.";
        return
    end

    cp_J_kg_K = interpolateFinite(tables.a22.T_C, ...
        tables.a22.cp_J_kg_K, T_C);
    state.cp_kJ_kg_K = cp_J_kg_K / 1000;
    state.cv_kJ_kg_K = state.cp_kJ_kg_K - opts.GasConstant_kJ_kg_K;
    if state.cv_kJ_kg_K > 0
        state.k_ratio = state.cp_kJ_kg_K / state.cv_kJ_kg_K;
    end

    state.k_W_m_K = interpolateFinite(tables.a22.T_C, ...
        tables.a22.k_W_m_K, T_C);
    state.mu_Pa_s = interpolateFinite(tables.a22.T_C, ...
        tables.a22.mu_kg_m_s, T_C);
    state.Prandtl = interpolateFinite(tables.a22.T_C, ...
        tables.a22.Pr, T_C);

    if isfinite(state.rho_kg_m3) && state.rho_kg_m3 > 0
        state.nu_m2_s = state.mu_Pa_s / state.rho_kg_m3;
        state.alpha_m2_s = state.k_W_m_K / ...
            (state.rho_kg_m3 * cp_J_kg_K);
    end

    state.transportSource = ...
        "A-22 values for cp, k, mu, and Prandtl at 1 atm, interpolated in temperature. Density is from Pv=RT; alpha and nu are recomputed at the solved pressure.";
end

function value = inverseTableProperty(T, property, target, label)
    mask = isfinite(T) & isfinite(property);
    T = T(mask);
    property = property(mask);

    [T, order] = sort(T);
    property = property(order);

    increasing = all(diff(property) > 0);
    decreasing = all(diff(property) < 0);
    if ~(increasing || decreasing)
        error('airState:NonMonotonicTable', ...
            'The usable %s table values are not monotonic and cannot be inverted safely.', label);
    end

    low = min(property);
    high = max(property);
    if target < low || target > high
        error('airState:OutOfTableRange', ...
            ['%s = %.9g is outside the supplied A-21 range of %.9g to ' ...
             '%.9g. No extrapolation was performed.'], label, target, low, high);
    end

    if decreasing
        property = flipud(property);
        T = flipud(T);
    end
    value = interp1(property, T, target, 'linear');
end

function value = interpolateFinite(x, y, query)
    mask = isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    [x, order] = sort(x);
    y = y(order);
    [x, uniqueIndex] = unique(x, 'stable');
    y = y(uniqueIndex);

    if query < min(x) || query > max(x)
        value = NaN;
        return
    end
    value = interp1(x, y, query, 'linear');
end

function tf = hasInput(inputs, target)
    tf = any([inputs.name] == target);
end

function value = getInput(inputs, target)
    idx = find([inputs.name] == target, 1, 'first');
    if isempty(idx)
        error('airState:InternalInputError', ...
            'The requested input %s was not supplied.', target);
    end
    value = inputs(idx).value;
end

function state = preserveDeclaredInputs(state, inputs)
    for k = 1:numel(inputs)
        switch inputs(k).name
            case "T"
                state.T_K = inputs(k).value;
                state.T_C = inputs(k).value - 273.15;
            case "P"
                state.P_kPa = inputs(k).value;
            case "v"
                state.v_m3_kg = inputs(k).value;
                state.rho_kg_m3 = 1 / inputs(k).value;
            case "u"
                state.u_kJ_kg = inputs(k).value;
            case "h"
                state.h_kJ_kg = inputs(k).value;
            case "s"
                state.s_kJ_kg_K = inputs(k).value;
            case "s0"
                state.s0_kJ_kg_K = inputs(k).value;
        end
    end
end

function state = emptyState(opts)
    state = struct( ...
        'fluid', "Air", ...
        'units', "SI", ...
        'model', "Ideal-gas air", ...
        'isComplete', false, ...
        'phaseCode', "IG", ...
        'phase', "Ideal gas", ...
        'T_C', NaN, ...
        'T_K', NaN, ...
        'P_kPa', NaN, ...
        'v_m3_kg', NaN, ...
        'rho_kg_m3', NaN, ...
        'u_kJ_kg', NaN, ...
        'h_kJ_kg', NaN, ...
        's_kJ_kg_K', NaN, ...
        's0_kJ_kg_K', NaN, ...
        'Pr_relative', NaN, ...
        'vr_relative', NaN, ...
        'cp_kJ_kg_K', NaN, ...
        'cv_kJ_kg_K', NaN, ...
        'k_ratio', NaN, ...
        'k_W_m_K', NaN, ...
        'alpha_m2_s', NaN, ...
        'mu_Pa_s', NaN, ...
        'nu_m2_s', NaN, ...
        'Prandtl', NaN, ...
        'x', NaN, ...
        'R_kJ_kg_K', opts.GasConstant_kJ_kg_K, ...
        'referencePressure_kPa', opts.ReferencePressure_kPa, ...
        'entropyReference', ...
            "s = s0(T) - R ln(P/Pref); Pref is configurable and defaults to 100 kPa.", ...
        'transportSource', "", ...
        'source', "", ...
        'inputPair', "", ...
        'notes', strings(0,1), ...
        'bounds', table(), ...
        'candidates', table());
end

function out = appendStrings(current, additions)
    out = current;
    if isempty(additions)
        return
    end
    additions = string(additions(:));
    additions = additions(strlength(additions) > 0);
    out = [out; additions];
end

function tables = loadAirTables(dataFolder)
    a21Path = findDataFile(dataFolder, { ...
        'a21_air_ideal_gas_properties.csv', ...
        'a21_air_ideal_gas_properties - Copy.csv'});
    a22Path = findDataFile(dataFolder, { ...
        'a22_air_1atm_properties.csv', ...
        'a22_air_1atm_properties - Copy.csv'});

    a21 = readtable(a21Path);
    a22 = readtable(a22Path);

    assertRequiredColumns(a21, { ...
        'T_K','h_kJ_kg','Pr','u_kJ_kg','v_r','s0_kJ_kg_K'}, a21Path);
    assertRequiredColumns(a22, { ...
        'T_C','rho_kg_m3','cp_J_kg_K','k_W_m_K', ...
        'alpha_m2_s','mu_kg_m_s','nu_m2_s','Pr'}, a22Path);

    a21 = sortrows(a21, 'T_K');
    a22 = sortrows(a22, 'T_C');

    if numel(unique(a21.T_K)) ~= height(a21)
        error('airState:DuplicateTemperature', ...
            'The A-21 table contains duplicate temperature rows.');
    end
    if numel(unique(a22.T_C)) ~= height(a22)
        error('airState:DuplicateTemperature', ...
            'The A-22 table contains duplicate temperature rows.');
    end

    % One supplied A-21 cell is inconsistent with both h-u=RT and the
    % neighboring h trend. Preserve the CSV, but exclude only that h cell
    % from interpolation rather than silently replacing it.
    impliedR = (a21.h_kJ_kg - a21.u_kJ_kg) ./ a21.T_K;
    baselineR = median(impliedR(isfinite(impliedR)));
    badH = abs(impliedR - baselineR) > 1e-3;
    excludedH_T_K = a21.T_K(badH);
    a21.h_kJ_kg(badH) = NaN;

    if ~all(diff(a21.u_kJ_kg) > 0) || ...
       ~all(diff(a21.s0_kJ_kg_K) > 0) || ...
       ~all(diff(a21.Pr) > 0) || ...
       ~all(diff(a21.v_r) < 0)
        error('airState:InvalidA21Table', ...
            'The sorted A-21 table is not monotonic in one or more required properties.');
    end

    finiteH = a21.h_kJ_kg(isfinite(a21.h_kJ_kg));
    if ~all(diff(finiteH) > 0)
        error('airState:InvalidA21Table', ...
            'The usable A-21 enthalpy values are not monotonic.');
    end

    tables = struct();
    tables.a21 = a21;
    tables.a22 = a22;
    tables.a21Path = string(a21Path);
    tables.a22Path = string(a22Path);
    tables.minT_K = min(a21.T_K);
    tables.maxT_K = max(a21.T_K);
    tables.minTransportT_C = min(a22.T_C);
    tables.maxTransportT_C = max(a22.T_C);
    tables.excludedH_T_K = excludedH_T_K;
end

function path = findDataFile(dataFolder, candidates)
    path = '';
    for k = 1:numel(candidates)
        candidatePath = fullfile(dataFolder, candidates{k});
        if isfile(candidatePath)
            path = candidatePath;
            return
        end
    end

    error('airState:MissingDataFile', ...
        'None of the expected files were found in %s: %s', ...
        dataFolder, strjoin(string(candidates), ', '));
end

function assertRequiredColumns(T, required, fileName)
    actual = string(T.Properties.VariableNames);
    missing = string(required(~ismember(required, cellstr(actual))));
    if ~isempty(missing)
        error('airState:MissingColumns', ...
            'File %s is missing required columns: %s', ...
            fileName, strjoin(missing, ', '));
    end
end
