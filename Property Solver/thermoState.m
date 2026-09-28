function state = thermoState(fluid, varargin)
%THERMOSTATE Unified table-driven thermodynamic state solver.
%
% FINAL STUDENT-FACING API
%   state = thermoState(fluid, units, prop1, value1, prop2, value2)
%   state = thermoState(..., 'DataFolder', folder)
%
% Examples
%   state = thermoState("water","SI","P",500,"h",2800)
%   state = thermoState("R134a","EN","P",60,"T",140)
%   state = thermoState("air","SI","P",500,"s",7.0)
%
% Supported fluids
%   water / H2O / steam
%   R134 / R134a / R-134a
%   air / dry air
%
% Unit systems
%   "SI" : T [deg C], P [kPa abs], v [m^3/kg], rho [kg/m^3],
%          u,h [kJ/kg], s [kJ/(kg K)]
%   "EN" : T [deg F], P [psia], v [ft^3/lbm], rho [lbm/ft^3],
%          u,h [Btu/lbm], s [Btu/(lbm R)]
%
% Common input properties
%   T, P, v, rho, u, h, s
%   SI also accepts T_K; EN also accepts T_R.
%   Water/R-134a also accept x and phase.
%   Air also accepts s0.
%
% Canonical calculations are performed internally in SI units. The selected
% unit system controls public input interpretation and the generic outputs:
%   state.T, state.P, state.v, state.rho, state.u, state.h, state.s
%
% Unit-explicit fields are also returned in BOTH unit systems so prior SI
% code remains usable and conversions remain visible.
%
% Machine-readable status values
%   "OK", "UNDERDETERMINED", "AMBIGUOUS", "OUT_OF_RANGE", "INVALID_PAIR"
%
% The solver uses linear interpolation only and does not extrapolate beyond
% the usable source-table ranges. Device equations, efficiencies, cycle
% balances, and iterative solution logic belong outside thermoState.
%
% Backward compatibility
%   Legacy calls of the form thermoState(fluid,prop1,val1,prop2,val2) are
%   still accepted and interpreted as SI. New student work should use the
%   explicit unit-system argument.

    if nargin < 5
        error('thermoState:NotEnoughInputs', ...
            ['Use thermoState(fluid,units,prop1,value1,prop2,value2). ' ...
             'Legacy five-argument SI calls are also accepted.']);
    end

    [unitsCode, name1, value1, name2, value2, publicOpts, legacyCall] = ...
        parsePublicCall(varargin{:});

    fluidCode = normalizeFluid(fluid);
    [coreName1, coreValue1] = convertPublicInputToSI(unitsCode, name1, value1);
    [coreName2, coreValue2] = convertPublicInputToSI(unitsCode, name2, value2);

    try
        stateSI = thermoStateCoreSI(fluid, coreName1, coreValue1, ...
            coreName2, coreValue2, 'DataFolder', publicOpts.DataFolder);
    catch ME
        if isRecoverableRangeError(ME)
            if string(ME.identifier) == "thermoState:AirNonUnique"
                failStatus = "AMBIGUOUS";
            else
                failStatus = "OUT_OF_RANGE";
            end
            stateSI = publicFailureState(fluidCode, publicOpts.DataFolder, ...
                failStatus, string(ME.message));
        else
            rethrow(ME)
        end
    end

    stateSI.inputPair = string(name1) + " + " + string(name2);
    state = decoratePublicState(stateSI, unitsCode);
    if legacyCall
        state.notes = appendStrings(state.notes, ...
            "Legacy thermoState call detected; interpreted as SI. New work should include the explicit SI/EN argument.");
    end
end

function [unitsCode, name1, value1, name2, value2, opts, legacyCall] = parsePublicCall(varargin)
    legacyCall = false;
    first = string(varargin{1});
    if isUnitToken(first)
        if numel(varargin) < 5
            error('thermoState:NotEnoughInputs', ...
                'After units, specify property1, value1, property2, and value2.');
        end
        unitsCode = normalizeUnits(first);
        name1 = varargin{2}; value1 = varargin{3};
        name2 = varargin{4}; value2 = varargin{5};
        extra = varargin(6:end);
    else
        % Backward-compatible SI call: thermoState(fluid,prop1,val1,prop2,val2,...)
        if numel(varargin) < 4
            error('thermoState:NotEnoughInputs', ...
                'Legacy SI syntax requires property1, value1, property2, and value2.');
        end
        unitsCode = "SI";
        legacyCall = true;
        name1 = varargin{1}; value1 = varargin{2};
        name2 = varargin{3}; value2 = varargin{4};
        extra = varargin(5:end);
    end

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    p = inputParser;
    p.FunctionName = 'thermoState';
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, extra{:});
    opts = p.Results;
    opts.DataFolder = char(opts.DataFolder);
end

function tf = isUnitToken(raw)
    token = regexprep(lower(strtrim(string(raw))), '[^a-z0-9]', '');
    tf = any(token == ["si","metric","en","english","uscs","imperial"]);
end

function code = normalizeUnits(raw)
    token = regexprep(lower(strtrim(string(raw))), '[^a-z0-9]', '');
    switch token
        case {"si","metric"}
            code = "SI";
        case {"en","english","uscs","imperial"}
            code = "EN";
        otherwise
            error('thermoState:UnknownUnits', ...
                'Unknown unit system "%s". Use SI or EN.', string(raw));
    end
end

function [coreName, coreValue] = convertPublicInputToSI(unitsCode, rawName, rawValue)
    token = regexprep(lower(strtrim(string(rawName))), '[^a-z0-9]', '');
    C = unitConstants();

    % Inputs with no dimensional conversion.
    if any(token == ["x","quality","vaporquality","vapourquality", ...
                     "phase","region"])
        coreName = rawName;
        coreValue = rawValue;
        return
    end

    if unitsCode == "SI"
        switch token
            case {"t","tc","temperature","temperaturec","degc"}
                coreName = "T"; coreValue = rawValue;
            case {"tk","temperaturek","kelvin"}
                coreName = "T_K"; coreValue = rawValue;
            case {"tf","temperaturef","fahrenheit","tr","temperaturer","rankine"}
                error('thermoState:UnitMismatch', ...
                    'With SI selected, use T/T_C [deg C] or T_K [K].');
            case {"p","pressure","pkpa","pressurekpa"}
                coreName = "P"; coreValue = rawValue;
            case {"ppsia","pressurepsia","psia"}
                error('thermoState:UnitMismatch', ...
                    'With SI selected, pressure input is kPa absolute.');
            case {"v","specificvolume","vm3kg","specificvolumem3kg"}
                coreName = "v"; coreValue = rawValue;
            case {"rho","density","rhokgm3","densitykgm3"}
                coreName = "rho"; coreValue = rawValue;
            case {"u","internalenergy","specificinternalenergy","ukjkg"}
                coreName = "u"; coreValue = rawValue;
            case {"h","enthalpy","specificenthalpy","hkjkg"}
                coreName = "h"; coreValue = rawValue;
            case {"s","entropy","specificentropy","skjkgk"}
                coreName = "s"; coreValue = rawValue;
            case {"s0","standardentropy","standardstateentropy","s0kjkgk"}
                coreName = "s0"; coreValue = rawValue;
            otherwise
                error('thermoState:UnknownProperty', ...
                    'Unknown property name "%s".', string(rawName));
        end
    else
        % English inputs are converted once here; the numerical solver remains SI.
        switch token
            case {"t","tf","temperature","temperaturef","degf","fahrenheit"}
                validateNumericScalar(rawValue, 'temperature');
                coreName = "T";
                coreValue = (double(rawValue)-32)*5/9;
            case {"tr","temperaturer","rankine"}
                validateNumericScalar(rawValue, 'absolute temperature');
                coreName = "T_K";
                coreValue = double(rawValue)*5/9;
            case {"tc","temperaturec","degc","tk","temperaturek","kelvin"}
                error('thermoState:UnitMismatch', ...
                    'With EN selected, use T/T_F [deg F] or T_R [deg R].');
            case {"p","pressure","ppsia","pressurepsia","psia"}
                validateNumericScalar(rawValue, 'pressure');
                coreName = "P";
                coreValue = double(rawValue)*C.kPa_per_psia;
            case {"pkpa","pressurekpa"}
                error('thermoState:UnitMismatch', ...
                    'With EN selected, pressure input is psia.');
            case {"v","specificvolume","vft3lbm","specificvolumeft3lbm"}
                validateNumericScalar(rawValue, 'specific volume');
                coreName = "v";
                coreValue = double(rawValue)*C.m3kg_per_ft3lbm;
            case {"rho","density","rholbmft3","densitylbmft3"}
                validateNumericScalar(rawValue, 'density');
                coreName = "rho";
                coreValue = double(rawValue)*C.kgm3_per_lbmft3;
            case {"u","internalenergy","specificinternalenergy","ubtulbm"}
                validateNumericScalar(rawValue, 'specific internal energy');
                coreName = "u";
                coreValue = double(rawValue)*C.kJkg_per_Btulbm;
            case {"h","enthalpy","specificenthalpy","hbtulbm"}
                validateNumericScalar(rawValue, 'specific enthalpy');
                coreName = "h";
                coreValue = double(rawValue)*C.kJkg_per_Btulbm;
            case {"s","entropy","specificentropy","sbtulbmr"}
                validateNumericScalar(rawValue, 'specific entropy');
                coreName = "s";
                coreValue = double(rawValue)*C.kJkgK_per_BtulbmR;
            case {"s0","standardentropy","standardstateentropy","s0btulbmr"}
                validateNumericScalar(rawValue, 'standard-state entropy');
                coreName = "s0";
                coreValue = double(rawValue)*C.kJkgK_per_BtulbmR;
            otherwise
                error('thermoState:UnknownProperty', ...
                    'Unknown property name "%s".', string(rawName));
        end
    end
end

function state = decoratePublicState(state, unitsCode)
    C = unitConstants();

    % Always retain the canonical SI explicit fields from the core solver.
    state.T_F = convertFinite(state.T_C, @(x) x*9/5+32);
    state.T_R = convertFinite(state.T_K, @(x) x*9/5);
    state.P_psia = convertFinite(state.P_kPa, @(x) x/C.kPa_per_psia);
    state.v_ft3_lbm = convertFinite(state.v_m3_kg, @(x) x/C.m3kg_per_ft3lbm);
    state.rho_lbm_ft3 = convertFinite(state.rho_kg_m3, @(x) x/C.kgm3_per_lbmft3);
    state.u_Btu_lbm = convertFinite(state.u_kJ_kg, @(x) x/C.kJkg_per_Btulbm);
    state.h_Btu_lbm = convertFinite(state.h_kJ_kg, @(x) x/C.kJkg_per_Btulbm);
    state.s_Btu_lbm_R = convertFinite(state.s_kJ_kg_K, @(x) x/C.kJkgK_per_BtulbmR);
    state.s0_Btu_lbm_R = convertFinite(state.s0_kJ_kg_K, @(x) x/C.kJkgK_per_BtulbmR);
    state.R_Btu_lbm_R = convertFinite(state.R_kJ_kg_K, @(x) x/C.kJkgK_per_BtulbmR);
    state.referencePressure_psia = convertFinite(state.referencePressure_kPa, @(x) x/C.kPa_per_psia);

    % Air transport/specific-heat conversions. NaN stays NaN for other fluids.
    state.cp_Btu_lbm_R = convertFinite(state.cp_kJ_kg_K, @(x) x/C.kJkgK_per_BtulbmR);
    state.cv_Btu_lbm_R = convertFinite(state.cv_kJ_kg_K, @(x) x/C.kJkgK_per_BtulbmR);
    state.k_Btu_h_ft_R = convertFinite(state.k_W_m_K, @(x) x*C.BtuhftR_per_WmK);
    state.mu_lbm_ft_s = convertFinite(state.mu_Pa_s, @(x) x*C.lbmfts_per_Pas);
    state.nu_ft2_s = convertFinite(state.nu_m2_s, @(x) x*C.ft2_per_m2);
    state.alpha_ft2_s = convertFinite(state.alpha_m2_s, @(x) x*C.ft2_per_m2);

    % Generic computational aliases follow the selected public unit system.
    state.units = unitsCode;
    if unitsCode == "SI"
        state.T = state.T_C;
        state.T_abs = state.T_K;
        state.P = state.P_kPa;
        state.v = state.v_m3_kg;
        state.rho = state.rho_kg_m3;
        state.u = state.u_kJ_kg;
        state.h = state.h_kJ_kg;
        state.s = state.s_kJ_kg_K;
        state.s0 = state.s0_kJ_kg_K;
    else
        state.T = state.T_F;
        state.T_abs = state.T_R;
        state.P = state.P_psia;
        state.v = state.v_ft3_lbm;
        state.rho = state.rho_lbm_ft3;
        state.u = state.u_Btu_lbm;
        state.h = state.h_Btu_lbm;
        state.s = state.s_Btu_lbm_R;
        state.s0 = state.s0_Btu_lbm_R;
    end

    if ~(isfield(state,'status') && strlength(string(state.status)) > 0)
        state.status = inferPublicStatus(state);
    end
    state.bounds = decorateBoundsTable(state.bounds, unitsCode);
    state.candidates = decorateCandidateTable(state.candidates, unitsCode);
end

function status = inferPublicStatus(state)
    if state.isComplete
        status = "OK";
        return
    end
    if istable(state.candidates) && height(state.candidates) > 0
        status = "AMBIGUOUS";
        return
    end
    noteText = lower(strjoin(string(state.notes), " "));
    if contains(noteText,"outside") || contains(noteText,"out of range") || ...
            contains(noteText,"no extrapolation")
        status = "OUT_OF_RANGE";
    elseif contains(noteText,"not implemented") || contains(noteText,"not inputs") || ...
            contains(noteText,"must be paired")
        status = "INVALID_PAIR";
    else
        status = "UNDERDETERMINED";
    end
end

function T = decorateCandidateTable(T, unitsCode)
    if ~istable(T) || isempty(T)
        return
    end
    C = unitConstants();
    T.T_F = T.T_C*9/5+32;
    T.P_psia = T.P_kPa/C.kPa_per_psia;
    T.v_ft3_lbm = T.v_m3_kg/C.m3kg_per_ft3lbm;
    T.u_Btu_lbm = T.u_kJ_kg/C.kJkg_per_Btulbm;
    T.h_Btu_lbm = T.h_kJ_kg/C.kJkg_per_Btulbm;
    T.s_Btu_lbm_R = T.s_kJ_kg_K/C.kJkgK_per_BtulbmR;
    if unitsCode == "SI"
        T.T = T.T_C; T.P = T.P_kPa; T.v = T.v_m3_kg;
        T.u = T.u_kJ_kg; T.h = T.h_kJ_kg; T.s = T.s_kJ_kg_K;
    else
        T.T = T.T_F; T.P = T.P_psia; T.v = T.v_ft3_lbm;
        T.u = T.u_Btu_lbm; T.h = T.h_Btu_lbm; T.s = T.s_Btu_lbm_R;
    end
end

function T = decorateBoundsTable(T, unitsCode)
    if ~istable(T) || isempty(T)
        return
    end
    C = unitConstants();
    names = string(T.Properties.VariableNames);
    if any(names == "v_m3_kg")
        T.v_ft3_lbm = T.v_m3_kg/C.m3kg_per_ft3lbm;
    end
    if any(names == "u_kJ_kg")
        T.u_Btu_lbm = T.u_kJ_kg/C.kJkg_per_Btulbm;
    end
    if any(names == "h_kJ_kg")
        T.h_Btu_lbm = T.h_kJ_kg/C.kJkg_per_Btulbm;
    end
    if any(names == "s_kJ_kg_K")
        T.s_Btu_lbm_R = T.s_kJ_kg_K/C.kJkgK_per_BtulbmR;
    end
    if unitsCode == "SI"
        if any(names == "v_m3_kg"), T.v = T.v_m3_kg; end
        if any(names == "u_kJ_kg"), T.u = T.u_kJ_kg; end
        if any(names == "h_kJ_kg"), T.h = T.h_kJ_kg; end
        if any(names == "s_kJ_kg_K"), T.s = T.s_kJ_kg_K; end
    else
        if any(string(T.Properties.VariableNames) == "v_ft3_lbm"), T.v = T.v_ft3_lbm; end
        if any(string(T.Properties.VariableNames) == "u_Btu_lbm"), T.u = T.u_Btu_lbm; end
        if any(string(T.Properties.VariableNames) == "h_Btu_lbm"), T.h = T.h_Btu_lbm; end
        if any(string(T.Properties.VariableNames) == "s_Btu_lbm_R"), T.s = T.s_Btu_lbm_R; end
    end
end

function y = convertFinite(x, f)
    if isnumeric(x) && isscalar(x) && isfinite(x)
        y = f(x);
    else
        y = NaN;
    end
end

function C = unitConstants()
    C.kPa_per_psia = 6.894757293168361;
    C.m3kg_per_ft3lbm = 0.06242796057614461;
    C.kgm3_per_lbmft3 = 16.01846337396014;
    C.kJkg_per_Btulbm = 2.326000324917282;
    C.kJkgK_per_BtulbmR = 4.186800584851108;
    C.BtuhftR_per_WmK = 0.577789318;
    C.lbmfts_per_Pas = 0.671968975;
    C.ft2_per_m2 = 10.76391041670972;
end

function tf = isRecoverableRangeError(ME)
    id = string(ME.identifier);
    tf = any(id == ["thermoState:OutOfTableRange", ...
                    "thermoState:SaturationRange", ...
                    "thermoState:AirOutOfRange", ...
                    "thermoState:AirNonUnique"]);
end

function state = publicFailureState(fluidCode, dataFolder, status, message)
    opts = internalDefaultOptions(dataFolder);
    switch fluidCode
        case "WATER"
            state = emptyState("Water", "Table-based pure substance", opts);
        case "R134A"
            state = emptyState("R-134a", "Table-based pure substance", opts);
        case "AIR"
            state = emptyState("Air", "Ideal-gas air", opts);
            state.phaseCode = "IG";
            state.phase = "Ideal gas";
        otherwise
            state = emptyState(string(fluidCode), "Unknown", opts);
    end
    state.notes(end+1,1) = string(message);
    state.status = string(status);
end

function state = thermoStateCoreSI(fluid, name1, value1, name2, value2, varargin)
    narginchk(5, 30);

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    opts = parseOptions(defaultFolder, varargin{:});
    fluidCode = normalizeFluid(fluid);

    in1 = normalizeDeclaredInput(name1, value1);
    in2 = normalizeDeclaredInput(name2, value2);
    if in1.name == in2.name
        error('thermoState:DuplicateInput', ...
            'Specify two different thermodynamic quantities; %s and %s represent the same property.', ...
            string(name1), string(name2));
    end
    inputs = [in1, in2];

    switch fluidCode
        case {"WATER", "R134A"}
            model = loadPureFluidModel(fluidCode, opts.DataFolder, opts);
            state = solvePureState(model, inputs, opts);
        case "AIR"
            tables = loadAirTables(opts.DataFolder);
            state = solveAirState(inputs, tables, opts);
        otherwise
            error('thermoState:InternalFluidError', 'Unhandled fluid code %s.', fluidCode);
    end

    state.inputPair = in1.label + " + " + in2.label;
    state = preserveDeclaredInputs(state, inputs);
    state = finalizeCommonState(state);
end

%% ------------------------------------------------------------------------
%  INPUTS, OPTIONS, AND COMMON STRUCTURE
%  ------------------------------------------------------------------------
function opts = parseOptions(defaultFolder, varargin)
    % Public tolerance controls were intentionally removed in the final API.
    % The table quality does not justify presenting these numerical thresholds
    % as meaningful user-adjustable precision settings. They remain fixed
    % implementation safeguards documented in THERMOSTATE_DATA_CAVEATS.md.
    p = inputParser;
    p.FunctionName = 'thermoState';
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, varargin{:});
    opts = internalDefaultOptions(char(p.Results.DataFolder));
end

function opts = internalDefaultOptions(dataFolder)
    opts = struct();
    opts.DataFolder = char(dataFolder);
    opts.SaturationTolerance_C = 0.05;
    opts.SaturationTolerance_kPa = 0.05;
    opts.SaturationRelativeTolerance = 2e-4;
    opts.EnergyTolerance_kJ_kg = 0.10;
    opts.EntropyTolerance_kJ_kg_K = 1e-4;
    opts.SpecificVolumeRelativeTolerance = 1e-4;
    opts.MaxWaterIncompressibleApproximation_kPa = 2500;
    opts.GasConstant_kJ_kg_K = 0.2870;
    opts.ReferencePressure_kPa = 100;
    opts.TemperatureTolerance_K = 0.5;
    opts.RelativeConsistencyTolerance = 5e-4;
end

function code = normalizeFluid(rawFluid)
    token = regexprep(lower(strtrim(string(rawFluid))), '[^a-z0-9]', '');
    switch token
        case {"water", "h2o", "steam"}
            code = "WATER";
        case {"r134", "r134a", "refrigerant134a", "refrigerant134"}
            code = "R134A";
        case {"air", "dryair"}
            code = "AIR";
        otherwise
            error('thermoState:UnknownFluid', ...
                'Unknown fluid "%s". Use water, R134/R134a, or air.', string(rawFluid));
    end
end

function input = normalizeDeclaredInput(rawName, rawValue)
    token = regexprep(lower(strtrim(string(rawName))), '[^a-z0-9]', '');
    input = struct('name', "", 'value', [], 'label', "");

    switch token
        case {"t", "tc", "temperature", "temperaturec", "degc"}
            validateNumericScalar(rawValue, 'temperature');
            if rawValue <= -273.15
                error('thermoState:InvalidTemperature', ...
                    'Temperature must be greater than absolute zero.');
            end
            input.name = "T";
            input.value = double(rawValue);
            input.label = "T";

        case {"tk", "temperaturek", "kelvin"}
            validateNumericScalar(rawValue, 'absolute temperature');
            if rawValue <= 0
                error('thermoState:InvalidTemperature', ...
                    'Absolute temperature must be greater than zero kelvin.');
            end
            input.name = "T";
            input.value = double(rawValue) - 273.15;
            input.label = "T_K";

        case {"p", "pressure", "pkpa", "pressurekpa"}
            validateNumericScalar(rawValue, 'pressure');
            if rawValue <= 0
                error('thermoState:InvalidPressure', ...
                    'Pressure must be absolute and greater than zero.');
            end
            input.name = "P";
            input.value = double(rawValue);
            input.label = "P";

        case {"v", "specificvolume", "vm3kg", "specificvolumem3kg"}
            validateNumericScalar(rawValue, 'specific volume');
            if rawValue <= 0
                error('thermoState:InvalidSpecificVolume', ...
                    'Specific volume must be greater than zero.');
            end
            input.name = "v";
            input.value = double(rawValue);
            input.label = "v";

        case {"rho", "density", "rhokgm3", "densitykgm3"}
            validateNumericScalar(rawValue, 'density');
            if rawValue <= 0
                error('thermoState:InvalidDensity', ...
                    'Density must be greater than zero.');
            end
            input.name = "v";
            input.value = 1 / double(rawValue);
            input.label = "rho";

        case {"u", "internalenergy", "specificinternalenergy", "ukjkg"}
            validateNumericScalar(rawValue, 'specific internal energy');
            input.name = "u";
            input.value = double(rawValue);
            input.label = "u";

        case {"h", "enthalpy", "specificenthalpy", "hkjkg"}
            validateNumericScalar(rawValue, 'specific enthalpy');
            input.name = "h";
            input.value = double(rawValue);
            input.label = "h";

        case {"s", "entropy", "specificentropy", "skjkgk"}
            validateNumericScalar(rawValue, 'specific entropy');
            input.name = "s";
            input.value = double(rawValue);
            input.label = "s";

        case {"s0", "standardentropy", "standardstateentropy", "s0kjkgk"}
            validateNumericScalar(rawValue, 'standard-state entropy');
            input.name = "s0";
            input.value = double(rawValue);
            input.label = "s0";

        case {"x", "quality", "vaporquality", "vapourquality"}
            validateNumericScalar(rawValue, 'quality');
            if rawValue < 0 || rawValue > 1
                error('thermoState:InvalidQuality', ...
                    'Quality x must satisfy 0 <= x <= 1.');
            end
            input.name = "x";
            input.value = double(rawValue);
            input.label = "x";

        case {"phase", "region"}
            if ~(ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue)))
                error('thermoState:InvalidPhase', ...
                    'Phase must be text such as "SHV" or "saturated liquid".');
            end
            normalizePhase(rawValue); % validates spelling now
            input.name = "phase";
            input.value = string(rawValue);
            input.label = "phase";

        otherwise
            error('thermoState:UnknownProperty', ...
                ['Unknown quantity "%s". Use T, T_K, P, v, rho, u, h, s, ' ...
                 'x, phase, or air-only s0.'], string(rawName));
    end
end

function validateNumericScalar(value, label)
    if ~(isnumeric(value) && isscalar(value) && isfinite(value))
        error('thermoState:InvalidNumericInput', ...
            '%s must be a finite numeric scalar.', label);
    end
end

function state = emptyState(fluidName, modelName, opts)
    state = struct( ...
        'fluid', string(fluidName), ...
        'units', "SI", ...
        'model', string(modelName), ...
        'isComplete', false, ...
        'phaseCode', "UNDET", ...
        'phase', "Undetermined", ...
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
        'R_kJ_kg_K', NaN, ...
        'referencePressure_kPa', NaN, ...
        'entropyReference', "", ...
        'transportSource', "", ...
        'source', "", ...
        'inputPair', "", ...
        'notes', strings(0,1), ...
        'bounds', table(), ...
        'candidates', emptyCandidateTable());

    if nargin >= 3 && isfield(opts, 'GasConstant_kJ_kg_K') && modelName == "Ideal-gas air"
        state.R_kJ_kg_K = opts.GasConstant_kJ_kg_K;
        state.referencePressure_kPa = opts.ReferencePressure_kPa;
        state.entropyReference = ...
            "s = s0(T) - R ln(P/Pref); the current implementation uses Pref = 100 kPa.";
    end
end

function state = finalizeCommonState(state)
    if isfinite(state.T_C)
        state.T_K = state.T_C + 273.15;
    elseif isfinite(state.T_K)
        state.T_C = state.T_K - 273.15;
    end

    if isfinite(state.v_m3_kg) && state.v_m3_kg > 0
        state.rho_kg_m3 = 1 / state.v_m3_kg;
    elseif isfinite(state.rho_kg_m3) && state.rho_kg_m3 > 0
        state.v_m3_kg = 1 / state.rho_kg_m3;
    end
end

function state = preserveDeclaredInputs(state, inputs)
    for k = 1:numel(inputs)
        switch inputs(k).name
            case "T"
                if ~isfinite(state.T_C)
                    state.T_C = inputs(k).value;
                    state.T_K = inputs(k).value + 273.15;
                end
            case "P"
                if ~isfinite(state.P_kPa), state.P_kPa = inputs(k).value; end
            case "v"
                if ~isfinite(state.v_m3_kg)
                    state.v_m3_kg = inputs(k).value;
                    state.rho_kg_m3 = 1 / inputs(k).value;
                end
            case "u"
                if ~isfinite(state.u_kJ_kg), state.u_kJ_kg = inputs(k).value; end
            case "h"
                if ~isfinite(state.h_kJ_kg), state.h_kJ_kg = inputs(k).value; end
            case "s"
                if ~isfinite(state.s_kJ_kg_K), state.s_kJ_kg_K = inputs(k).value; end
            case "s0"
                if ~isfinite(state.s0_kJ_kg_K), state.s0_kJ_kg_K = inputs(k).value; end
            case "x"
                if ~isfinite(state.x) && state.phaseCode ~= "CRIT"
                    state.x = inputs(k).value;
                end
            case "phase"
                if state.phaseCode == "UNDET"
                    [state.phaseCode, state.phase] = normalizePhase(inputs(k).value);
                end
        end
    end
end

function tf = hasInput(inputs, target)
    tf = any(string({inputs.name}) == string(target));
end

function value = getInput(inputs, target)
    names = string({inputs.name});
    idx = find(names == string(target), 1, 'first');
    if isempty(idx)
        error('thermoState:InternalInputError', ...
            'The requested input %s was not supplied.', string(target));
    end
    value = inputs(idx).value;
end

function input = getOtherInput(inputs, excludedName)
    names = string({inputs.name});
    idx = find(names ~= string(excludedName), 1, 'first');
    input = inputs(idx);
end

function tf = isPureProperty(name)
    tf = ismember(string(name), ["v","u","h","s"]);
end

%% ------------------------------------------------------------------------
%  PURE-SUBSTANCE SOLVER: WATER AND R-134A
%  ------------------------------------------------------------------------
function state = solvePureState(model, inputs, opts)
    names = string({inputs.name});

    if any(names == "s0")
        error('thermoState:UnsupportedPureInput', ...
            's0 is an air-only input. Use s for water or R-134a.');
    end

    if hasInput(inputs, "T") && hasInput(inputs, "P")
        state = solvePureTP(model, getInput(inputs,"T"), getInput(inputs,"P"), opts);
        return
    end

    if hasInput(inputs, "T") && hasInput(inputs, "x")
        state = saturatedState(model, saturationAtT(model, getInput(inputs,"T")), ...
            getInput(inputs,"x"));
        return
    end

    if hasInput(inputs, "P") && hasInput(inputs, "x")
        state = saturatedState(model, saturationAtP(model, getInput(inputs,"P")), ...
            getInput(inputs,"x"));
        return
    end

    if hasInput(inputs, "phase")
        other = getOtherInput(inputs, "phase");
        state = solvePurePhasePair(model, other, getInput(inputs,"phase"), opts);
        return
    end

    if hasInput(inputs, "x")
        other = getOtherInput(inputs, "x");
        if isPureProperty(other.name)
            state = solvePurePropertyX(model, other.name, other.value, ...
                getInput(inputs,"x"), opts);
        else
            state = emptyState(model.fluidName, model.modelName, opts);
            state.notes(end+1,1) = ...
                "Quality must be paired with T, P, v, u, h, or s.";
        end
        return
    end

    if hasInput(inputs, "T")
        other = getOtherInput(inputs, "T");
        if isPureProperty(other.name)
            state = solvePureTProperty(model, getInput(inputs,"T"), ...
                other.name, other.value, opts);
        else
            state = unsupportedPurePairState(model, opts);
        end
        return
    end

    if hasInput(inputs, "P")
        other = getOtherInput(inputs, "P");
        if isPureProperty(other.name)
            state = solvePurePProperty(model, getInput(inputs,"P"), ...
                other.name, other.value, opts);
        else
            state = unsupportedPurePairState(model, opts);
        end
        return
    end

    if all(arrayfun(@(x) isPureProperty(x.name), inputs))
        state = solvePureTwoProperties(model, inputs(1), inputs(2), opts);
        return
    end

    state = unsupportedPurePairState(model, opts);
end

function state = unsupportedPurePairState(model, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.notes(end+1,1) = ...
        "This pure-substance input pair is not implemented. Supported locating inputs are T, P, x, and saturation-phase constraints, with v, u, h, or s as the second property.";
end

function state = solvePureTP(model, T, P, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.T_C = T;
    state.P_kPa = P;

    haveSatT = T >= model.minSaturationT && T <= model.maxSaturationT;
    haveSatP = P >= model.minSaturationP && P <= model.maxSaturationP;
    onSatByT = false;
    onSatByP = false;
    satT = struct();
    satP = struct();

    if haveSatT
        satT = saturationAtT(model, T);
        pTol = max(opts.SaturationTolerance_kPa, ...
            opts.SaturationRelativeTolerance * satT.P_kPa);
        onSatByT = abs(P - satT.P_kPa) <= pTol;
    else
        pTol = NaN;
    end

    if haveSatP
        satP = saturationAtP(model, P);
        onSatByP = abs(T - satP.T_C) <= opts.SaturationTolerance_C;
    end

    if onSatByT || onSatByP
        if onSatByP
            sat = satP;
        else
            sat = satT;
        end
        if isCriticalSaturation(sat)
            state = criticalState(model, sat);
        else
            state = partialSaturatedState(model, sat, ...
                "T and P identify the saturation line but do not determine quality x. Supply x, v, u, h, or s to locate the state inside the dome.");
        end
        return
    end

    if haveSatT && haveSatP
        compressed = T < satP.T_C - opts.SaturationTolerance_C && ...
                     P > satT.P_kPa + pTol;
        vapor = T > satP.T_C + opts.SaturationTolerance_C && ...
                P < satT.P_kPa - pTol;
        if compressed
            state = compressedStateAtTP(model, T, P, opts);
        elseif vapor
            state = vaporStateAtTP(model, T, P, opts);
        else
            state = partialSaturatedState(model, satP, ...
                "The rounded T-P pair lies in a narrow near-saturation band. Supply x or another specific property rather than forcing a phase classification.");
        end
        return
    end

    if haveSatT
        if P > satT.P_kPa + pTol
            state = compressedStateAtTP(model, T, P, opts);
        elseif P < satT.P_kPa - pTol
            state = vaporStateAtTP(model, T, P, opts);
        else
            state = partialSaturatedState(model, satT, ...
                "T and P identify the saturation line but not quality x.");
        end
        return
    end

    if haveSatP
        if T < satP.T_C - opts.SaturationTolerance_C
            state = compressedStateAtTP(model, T, P, opts);
        elseif T > satP.T_C + opts.SaturationTolerance_C
            state = vaporStateAtTP(model, T, P, opts);
        else
            state = partialSaturatedState(model, satP, ...
                "T and P identify the saturation line but not quality x.");
        end
        return
    end

    % Outside the saturation table's independent ranges, try the supplied
    % single-phase tables without extrapolation.
    candidates = emptyCandidateTable();
    if model.hasCompressedTable
        try
            [props, meta] = regionAtTP(model.compressed, T, P, model.fluidCode);
            s = regionState(model, T, P, props, "CL", ...
                model.compressedSource + "; " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
        end
    end
    try
        [props, meta] = regionAtTP(model.superheated, T, P, model.fluidCode);
        code = classifyVaporCode(model, T, P);
        s = regionState(model, T, P, props, code, ...
            model.superheatedSource + "; " + meta.method);
        candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
    catch
    end

    state = chooseCandidates(model, candidates, state, ...
        "The declared T-P pair is outside the usable source-table ranges. No extrapolation was performed.", opts);
end

function state = solvePureTProperty(model, T, propName, target, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.T_C = T;
    state = setStateProperty(state, propName, target);

    if T >= model.minSaturationT && T <= model.maxSaturationT
        sat = saturationAtT(model, T);
        [f, g] = saturationPropertyPair(sat, propName);
        tol = propertyTolerance(propName, target, opts);

        if isCriticalSaturation(sat) && abs(target - f) <= tol
            state = criticalState(model, sat);
            return
        elseif target >= f - tol && target <= g + tol
            if abs(g-f) <= tol
                state = criticalState(model, sat);
            else
                x = min(max((target-f)/(g-f), 0), 1);
                state = saturatedState(model, sat, x);
            end
            return
        elseif target < f
            candidates = compressedCandidatesAtT(model, T, propName, target, opts);
            state = chooseCandidates(model, candidates, state, ...
                "No unique compressed-liquid state was found for the declared T-property pair. The compressed-liquid approximation may make some properties effectively functions of T alone.", opts);
            return
        else
            candidates = candidatesAtT(model, model.superheated, T, ...
                propName, target, "SHV", model.superheatedSource, opts);
            state = chooseCandidates(model, candidates, state, ...
                "No unique superheated state was found inside the supplied table range.", opts);
            return
        end
    end

    candidates = emptyCandidateTable();
    if model.hasCompressedTable
        candidates = [candidates; candidatesAtT(model, model.compressed, T, ...
            propName, target, "CL", model.compressedSource, opts)]; %#ok<AGROW>
    end
    candidates = [candidates; candidatesAtT(model, model.superheated, T, ...
        propName, target, "SHV", model.superheatedSource, opts)]; %#ok<AGROW>
    state = chooseCandidates(model, candidates, state, ...
        "The requested T-property state is outside the supported table ranges or is not unique.", opts);
end

function state = solvePurePProperty(model, P, propName, target, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.P_kPa = P;
    state = setStateProperty(state, propName, target);

    if P >= model.minSaturationP && P <= model.maxSaturationP
        sat = saturationAtP(model, P);
        [f, g] = saturationPropertyPair(sat, propName);
        tol = propertyTolerance(propName, target, opts);

        if isCriticalSaturation(sat) && abs(target - f) <= tol
            state = criticalState(model, sat);
            return
        elseif target >= f - tol && target <= g + tol
            if abs(g-f) <= tol
                state = criticalState(model, sat);
            else
                x = min(max((target-f)/(g-f), 0), 1);
                state = saturatedState(model, sat, x);
            end
            return
        elseif target < f
            candidates = compressedCandidatesAtP(model, P, propName, target, opts);
            state = chooseCandidates(model, candidates, state, ...
                "No unique compressed-liquid state was found for the declared P-property pair.", opts);
            return
        else
            candidates = candidatesAtP(model, model.superheated, P, ...
                propName, target, "SHV", model.superheatedSource, opts);
            state = chooseCandidates(model, candidates, state, ...
                "No unique superheated state was found inside the supplied table range.", opts);
            return
        end
    end

    candidates = emptyCandidateTable();
    candidates = [candidates; compressedCandidatesAtP(model, P, ...
        propName, target, opts)]; %#ok<AGROW>
    candidates = [candidates; candidatesAtP(model, model.superheated, P, ...
        propName, target, "SHV", model.superheatedSource, opts)]; %#ok<AGROW>
    state = chooseCandidates(model, candidates, state, ...
        "The requested P-property state is outside the supported table ranges or is not unique.", opts);
end

function state = solvePurePropertyX(model, propName, target, x, opts)
    fVec = saturationVector(model.satT, propName, "f");
    gVec = saturationVector(model.satT, propName, "g");
    mixVec = fVec + x .* (gVec - fVec);
    rootsT = piecewiseLinearRoots(model.satT.T_C, mixVec, target, ...
        propertyTolerance(propName, target, opts));

    candidates = emptyCandidateTable();
    for k = 1:numel(rootsT)
        try
            sat = saturationAtT(model, rootsT(k));
            s = saturatedState(model, sat, x);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
        end
    end

    base = emptyState(model.fluidName, model.modelName, opts);
    base = setStateProperty(base, propName, target);
    base.x = x;
    state = chooseCandidates(model, candidates, base, ...
        "The property-quality pair did not produce a unique saturation state within the usable saturation table.", opts);
end

function state = solvePureTwoProperties(model, in1, in2, opts)
%SOLVEPURETWOPROPERTIES Invert two tabulated properties without T/P.
% The search is deliberately region-aware. Saturation candidates are solved
% on the T-x surface; single-phase candidates are solved cell-by-cell using
% the same bilinear interpolation implied by the source pressure blocks.

    base = emptyState(model.fluidName, model.modelName, opts);
    base = setStateProperty(base, in1.name, in1.value);
    base = setStateProperty(base, in2.name, in2.value);

    candidates = emptyCandidateTable();

    satCandidates = saturationTwoPropertyCandidates(model, ...
        in1.name, in1.value, in2.name, in2.value, opts);
    candidates = [candidates; satCandidates]; %#ok<AGROW>

    if model.hasCompressedTable
        clCandidates = twoPropertyCandidatesRegion(model, model.compressed, ...
            in1.name, in1.value, in2.name, in2.value, ...
            "CL", model.compressedSource, opts);
        candidates = [candidates; clCandidates]; %#ok<AGROW>
    end

    if model.allowCompressedApproximation
        approxCandidates = compressedApproxTwoPropertyCandidates(model, ...
            in1.name, in1.value, in2.name, in2.value, opts);
        candidates = [candidates; approxCandidates]; %#ok<AGROW>
    end

    shCandidates = twoPropertyCandidatesRegion(model, model.superheated, ...
        in1.name, in1.value, in2.name, in2.value, ...
        "SHV", model.superheatedSource, opts);
    candidates = [candidates; shCandidates]; %#ok<AGROW>

    candidates = deduplicateCandidates(candidates);
    state = chooseCandidates(model, candidates, base, ...
        "No table-interpolated state was found for the declared property pair. The pair may be outside the supplied data ranges or may require a region not represented by the available tables.", opts);
end

function candidates = saturationTwoPropertyCandidates(model, prop1, target1, prop2, target2, opts)
    candidates = emptyCandidateTable();
    Tnodes = model.satT.T_C;
    d = nan(size(Tnodes));
    x1nodes = nan(size(Tnodes));
    x2nodes = nan(size(Tnodes));

    for k = 1:numel(Tnodes)
        sat = saturationAtT(model, Tnodes(k));
        [f1,g1] = saturationPropertyPair(sat, prop1);
        [f2,g2] = saturationPropertyPair(sat, prop2);
        if abs(g1-f1) > propertyTolerance(prop1,target1,opts) && ...
                abs(g2-f2) > propertyTolerance(prop2,target2,opts)
            x1nodes(k) = (target1-f1)/(g1-f1);
            x2nodes(k) = (target2-f2)/(g2-f2);
            d(k) = x1nodes(k)-x2nodes(k);
        end
    end

    rootsT = zeros(0,1);
    dTol = 1e-8;
    for k = 1:numel(Tnodes)
        if isfinite(d(k)) && abs(d(k)) <= dTol && ...
                x1nodes(k) >= -1e-8 && x1nodes(k) <= 1+1e-8 && ...
                x2nodes(k) >= -1e-8 && x2nodes(k) <= 1+1e-8
            rootsT(end+1,1) = Tnodes(k); %#ok<AGROW>
        end
        if k == numel(Tnodes) || ~isfinite(d(k)) || ~isfinite(d(k+1))
            continue
        end
        if d(k)*d(k+1) < 0
            try
                root = fzero(@(T) saturationXDifference(model,T,prop1,target1,prop2,target2), ...
                    [Tnodes(k),Tnodes(k+1)]);
                rootsT(end+1,1) = root; %#ok<AGROW>
            catch
            end
        end
    end
    rootsT = uniqueWithTolerance(rootsT,1e-7);

    tol1 = propertyTolerance(prop1,target1,opts);
    tol2 = propertyTolerance(prop2,target2,opts);
    for k = 1:numel(rootsT)
        try
            sat = saturationAtT(model,rootsT(k));
            [f1,g1] = saturationPropertyPair(sat,prop1);
            [f2,g2] = saturationPropertyPair(sat,prop2);
            if abs(g1-f1) <= tol1 || abs(g2-f2) <= tol2
                continue
            end
            x1 = (target1-f1)/(g1-f1);
            x2 = (target2-f2)/(g2-f2);
            x = 0.5*(x1+x2);
            if x < -1e-7 || x > 1+1e-7
                continue
            end
            x = min(max(x,0),1);
            st = saturatedState(model,sat,x);
            if abs(getStateProperty(st,prop1)-target1) <= 5*tol1 && ...
                    abs(getStateProperty(st,prop2)-target2) <= 5*tol2
                candidates = [candidates; stateToCandidate(st)]; %#ok<AGROW>
            end
        catch
        end
    end
end

function d = saturationXDifference(model,T,prop1,target1,prop2,target2)
    sat = saturationAtT(model,T);
    [f1,g1] = saturationPropertyPair(sat,prop1);
    [f2,g2] = saturationPropertyPair(sat,prop2);
    if abs(g1-f1) < eps || abs(g2-f2) < eps
        d = NaN;
        return
    end
    d = (target1-f1)/(g1-f1) - (target2-f2)/(g2-f2);
end

function candidates = compressedApproxTwoPropertyCandidates(model, prop1, target1, prop2, target2, opts)
    candidates = emptyCandidateTable();

    % Under the incompressible approximation v, u, and s are functions of
    % T alone. A second independent pressure-sensitive relation is needed;
    % among the currently modeled properties that relation is h.
    if prop1 == "h" && prop2 ~= "h"
        hTarget = target1;
        tempProp = prop2;
        tempTarget = target2;
    elseif prop2 == "h" && prop1 ~= "h"
        hTarget = target2;
        tempProp = prop1;
        tempTarget = target1;
    else
        return
    end

    if ~ismember(tempProp,["v","u","s"])
        return
    end

    curve = saturationVector(model.satT,tempProp,"f");
    rootsT = piecewiseLinearRoots(model.satT.T_C,curve,tempTarget, ...
        propertyTolerance(tempProp,tempTarget,opts));
    tolH = propertyTolerance("h",hTarget,opts);
    tolOther = propertyTolerance(tempProp,tempTarget,opts);

    for k = 1:numel(rootsT)
        try
            sat = saturationAtT(model,rootsT(k));
            P = sat.P_kPa + (hTarget-sat.hf)/sat.vf;
            if ~(isfinite(P) && P > sat.P_kPa && compressedApproximationAllowed(model,P,opts))
                continue
            end
            st = compressedLiquidApproximation(model,rootsT(k),P,sat);
            if abs(st.h_kJ_kg-hTarget) <= 5*tolH && ...
                    abs(getStateProperty(st,tempProp)-tempTarget) <= 5*tolOther
                candidates = [candidates; stateToCandidate(st)]; %#ok<AGROW>
            end
        catch
        end
    end
end

function candidates = twoPropertyCandidatesRegion(model, regionTable, prop1, target1, prop2, target2, phaseCode, source, opts)
    candidates = emptyCandidateTable();
    if isempty(regionTable) || height(regionTable) < 4
        return
    end

    pressureLevels = unique(regionTable.P_kPa);
    pressureLevels = sort(pressureLevels);
    tol1 = propertyTolerance(prop1,target1,opts);
    tol2 = propertyTolerance(prop2,target2,opts);

    for ip = 1:numel(pressureLevels)-1
        P0 = pressureLevels(ip);
        P1 = pressureLevels(ip+1);
        block0 = sortrows(regionTable(regionTable.P_kPa == P0,:), 'T_C');
        block1 = sortrows(regionTable(regionTable.P_kPa == P1,:), 'T_C');
        [~,ia0] = unique(block0.T_C,'stable'); block0 = block0(ia0,:);
        [~,ia1] = unique(block1.T_C,'stable'); block1 = block1(ia1,:);
        if height(block0) < 2 || height(block1) < 2
            continue
        end

        Tmin = max(min(block0.T_C),min(block1.T_C));
        Tmax = min(max(block0.T_C),max(block1.T_C));
        if Tmax <= Tmin
            continue
        end
        breaks = unique([Tmin; Tmax; ...
            block0.T_C(block0.T_C > Tmin & block0.T_C < Tmax); ...
            block1.T_C(block1.T_C > Tmin & block1.T_C < Tmax)]);
        breaks = sort(breaks);

        for it = 1:numel(breaks)-1
            T0 = breaks(it);
            T1 = breaks(it+1);
            if T1 <= T0, continue, end

            p00 = propsAtBlockT(block0,T0);
            p10 = propsAtBlockT(block0,T1);
            p01 = propsAtBlockT(block1,T0);
            p11 = propsAtBlockT(block1,T1);
            y1corners = [propertyFromProps(p00,prop1), propertyFromProps(p10,prop1), ...
                         propertyFromProps(p01,prop1), propertyFromProps(p11,prop1)];
            y2corners = [propertyFromProps(p00,prop2), propertyFromProps(p10,prop2), ...
                         propertyFromProps(p01,prop2), propertyFromProps(p11,prop2)];
            if any(~isfinite(y1corners)) || any(~isfinite(y2corners))
                continue
            end

            solutions = solveBilinearInverse(y1corners,target1,y2corners,target2,tol1,tol2);
            for isol = 1:size(solutions,1)
                a = solutions(isol,1);
                b = solutions(isol,2);
                T = T0 + a*(T1-T0);
                P = P0 + b*(P1-P0);
                try
                    [props,meta] = regionAtTP(regionTable,T,P,model.fluidCode);
                    code = phaseCode;
                    if code == "SHV"
                        code = classifyVaporCode(model,T,P);
                    end
                    st = regionState(model,T,P,props,code, ...
                        source + "; inverse bilinear interpolation in " + prop1 + " and " + prop2 + "; " + meta.method);
                    if abs(getStateProperty(st,prop1)-target1) <= 5*tol1 && ...
                            abs(getStateProperty(st,prop2)-target2) <= 5*tol2
                        candidates = [candidates; stateToCandidate(st)]; %#ok<AGROW>
                    end
                catch
                end
            end
        end
    end
    candidates = deduplicateCandidates(candidates);
end

function props = propsAtBlockT(block,T)
    props = struct();
    props.v = interp1(block.T_C,block.v_m3_kg,T,'linear');
    props.u = interp1(block.T_C,block.u_kJ_kg,T,'linear');
    props.h = interp1(block.T_C,block.h_kJ_kg,T,'linear');
    props.s = interp1(block.T_C,block.s_kJ_kg_K,T,'linear');
end

function solutions = solveBilinearInverse(y1,target1,y2,target2,tol1,tol2)
% Corner order is [T0P0, T1P0, T0P1, T1P1].
    c1 = bilinearCoefficients(y1);
    c2 = bilinearCoefficients(y2);
    starts = [0.5 0.5; 0.1 0.1; 0.9 0.1; 0.1 0.9; 0.9 0.9];
    solutions = zeros(0,2);
    scale1 = max(tol1,1e-10);
    scale2 = max(tol2,1e-10);

    for k = 1:size(starts,1)
        z = starts(k,:)';
        converged = false;
        for iter = 1:30
            a = z(1); b = z(2);
            f1 = (bilinearValue(c1,a,b)-target1)/scale1;
            f2 = (bilinearValue(c2,a,b)-target2)/scale2;
            F = [f1;f2];
            if norm(F,inf) < 1e-5
                converged = true;
                break
            end
            J = [(c1(2)+c1(4)*b)/scale1, (c1(3)+c1(4)*a)/scale1; ...
                 (c2(2)+c2(4)*b)/scale2, (c2(3)+c2(4)*a)/scale2];
            if rcond(J) < 1e-12
                break
            end
            step = J\F;
            z = z-step;
            if any(~isfinite(z)) || any(z < -0.25) || any(z > 1.25)
                break
            end
        end
        if converged && all(z >= -1e-7) && all(z <= 1+1e-7)
            z = min(max(z,0),1);
            if isempty(solutions) || all(vecnorm(solutions-z',2,2) > 1e-6)
                solutions(end+1,:) = z'; %#ok<AGROW>
            end
        end
    end
end

function c = bilinearCoefficients(y)
    y00 = y(1); y10 = y(2); y01 = y(3); y11 = y(4);
    c = [y00, y10-y00, y01-y00, y11-y10-y01+y00];
end

function y = bilinearValue(c,a,b)
    y = c(1)+c(2)*a+c(3)*b+c(4)*a*b;
end

function value = getStateProperty(state,propName)
    switch propName
        case "v", value = state.v_m3_kg;
        case "u", value = state.u_kJ_kg;
        case "h", value = state.h_kJ_kg;
        case "s", value = state.s_kJ_kg_K;
        otherwise
            error('thermoState:InternalPropertyError','Unsupported state property %s.',propName);
    end
end

function candidates = deduplicateCandidates(candidates)
    if height(candidates) <= 1
        return
    end
    keep = true(height(candidates),1);
    for i = 1:height(candidates)
        if ~keep(i), continue, end
        for j = i+1:height(candidates)
            if ~keep(j), continue, end
            sameT = abs(candidates.T_C(i)-candidates.T_C(j)) <= 1e-5*max(abs(candidates.T_C(i)),1);
            sameP = abs(candidates.P_kPa(i)-candidates.P_kPa(j)) <= 1e-5*max(abs(candidates.P_kPa(i)),1);
            if sameT && sameP
                keep(j) = false;
            end
        end
    end
    candidates = candidates(keep,:);
end

function state = solvePurePhasePair(model, other, phaseValue, opts)
    [phaseCode, phaseText] = normalizePhase(phaseValue);
    state = emptyState(model.fluidName, model.modelName, opts);
    state.phaseCode = phaseCode;
    state.phase = phaseText;

    if phaseCode == "SC" && ~model.supportsSupercritical
        state.notes(end+1,1) = ...
            "The supplied files do not provide a supported supercritical region for this fluid.";
        return
    end

    if phaseCode == "CRIT"
        sat = saturationAtT(model, model.maxSaturationT);
        tol = propertyToleranceForCritical(other.name, other.value, opts);
        if other.name == "T"
            match = abs(other.value - sat.T_C) <= opts.SaturationTolerance_C;
        elseif other.name == "P"
            pTol = max(opts.SaturationTolerance_kPa, ...
                opts.SaturationRelativeTolerance * sat.P_kPa);
            match = abs(other.value - sat.P_kPa) <= pTol;
        elseif isPureProperty(other.name)
            [f, ~] = saturationPropertyPair(sat, other.name);
            match = abs(other.value - f) <= tol;
        else
            match = false;
        end
        if match && isCriticalSaturation(sat)
            state = criticalState(model, sat);
        else
            state.notes(end+1,1) = ...
                "The declared second quantity does not match the critical-point row available in the source table.";
        end
        return
    end

    switch other.name
        case "T"
            T = other.value;
            state.T_C = T;
            if ismember(phaseCode, ["SL","SV","SLVM","SAT"])
                sat = saturationAtT(model, T);
                if phaseCode == "SL"
                    state = saturatedState(model, sat, 0);
                elseif phaseCode == "SV"
                    state = saturatedState(model, sat, 1);
                else
                    state = partialSaturatedState(model, sat, ...
                        "A saturated-mixture phase and temperature determine saturation pressure, but quality x is still required for v, u, h, and s.");
                end
            else
                state.notes(end+1,1) = ...
                    "Phase plus temperature does not uniquely fix a compressed-liquid or superheated-vapor state. Supply P, v, u, h, or s.";
            end

        case "P"
            P = other.value;
            state.P_kPa = P;
            if ismember(phaseCode, ["SL","SV","SLVM","SAT"])
                sat = saturationAtP(model, P);
                if phaseCode == "SL"
                    state = saturatedState(model, sat, 0);
                elseif phaseCode == "SV"
                    state = saturatedState(model, sat, 1);
                else
                    state = partialSaturatedState(model, sat, ...
                        "A saturated-mixture phase and pressure determine saturation temperature, but quality x is still required for v, u, h, and s.");
                end
            else
                state.notes(end+1,1) = ...
                    "Phase plus pressure does not uniquely fix a compressed-liquid or superheated-vapor state. Supply T, v, u, h, or s.";
            end

        otherwise
            if isPureProperty(other.name) && ismember(phaseCode, ["SL","SV"])
                state = solveSaturationEndpointProperty(model, other.name, ...
                    other.value, phaseCode, opts);
            elseif other.name == "x"
                state.x = other.value;
                state.notes(end+1,1) = ...
                    "Quality plus a phase label does not identify the saturation temperature or pressure. Supply T or P.";
            else
                state = setStateProperty(state, other.name, other.value);
                state.notes(end+1,1) = ...
                    "A broad single-phase label plus one property generally does not fix a unique state. Saturated-liquid and saturated-vapor endpoint labels can be paired with v, u, h, or s; otherwise supply another independent locating property.";
            end
    end
end

function state = solveSaturationEndpointProperty(model, propName, target, phaseCode, opts)
    if phaseCode == "SL"
        curve = saturationVector(model.satT, propName, "f");
        x = 0;
    else
        curve = saturationVector(model.satT, propName, "g");
        x = 1;
    end
    rootsT = piecewiseLinearRoots(model.satT.T_C, curve, target, ...
        propertyTolerance(propName, target, opts));
    candidates = emptyCandidateTable();
    for k = 1:numel(rootsT)
        try
            s = saturatedState(model, saturationAtT(model, rootsT(k)), x);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
        end
    end
    base = emptyState(model.fluidName, model.modelName, opts);
    base = setStateProperty(base, propName, target);
    base.phaseCode = phaseCode;
    base.phase = phaseLabel(phaseCode);
    state = chooseCandidates(model, candidates, base, ...
        "The saturation endpoint property did not map to a unique state in the source table.", opts);
end

function state = compressedStateAtTP(model, T, P, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.T_C = T;
    state.P_kPa = P;
    state.phaseCode = "CL";
    state.phase = phaseLabel("CL");

    if model.hasCompressedTable
        try
            [props, meta] = regionAtTP(model.compressed, T, P, model.fluidCode);
            state = regionState(model, T, P, props, "CL", ...
                model.compressedSource + "; " + meta.method);
            return
        catch ME
            if ~(model.allowCompressedApproximation && ...
                    compressedApproximationAllowed(model, P, opts))
                state.notes(end+1,1) = string(ME.message);
                return
            end
        end
    end

    if model.allowCompressedApproximation && ...
            T >= model.minSaturationT && T <= model.maxSaturationT && ...
            compressedApproximationAllowed(model, P, opts)
        sat = saturationAtT(model, T);
        if P > sat.P_kPa
            state = compressedLiquidApproximation(model, T, P, sat);
            return
        end
    end

    state.notes(end+1,1) = ...
        "The compressed-liquid state is outside the supplied compressed-liquid table/approximation range.";
end

function state = vaporStateAtTP(model, T, P, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
    state.T_C = T;
    state.P_kPa = P;
    code = classifyVaporCode(model, T, P);
    state.phaseCode = code;
    state.phase = phaseLabel(code);
    try
        [props, meta] = regionAtTP(model.superheated, T, P, model.fluidCode);
        state = regionState(model, T, P, props, code, ...
            model.superheatedSource + "; " + meta.method);
    catch ME
        state.notes(end+1,1) = string(ME.message);
    end
end

function code = classifyVaporCode(model, T, P)
    if model.supportsSupercritical && T >= model.Tcrit && P >= model.Pcrit
        code = "SC";
    else
        code = "SHV";
    end
end

function candidates = compressedCandidatesAtP(model, P, propName, target, opts)
    candidates = emptyCandidateTable();
    if model.hasCompressedTable
        candidates = [candidates; candidatesAtP(model, model.compressed, P, ...
            propName, target, "CL", model.compressedSource, opts)]; %#ok<AGROW>
    end

    if isempty(candidates) && model.allowCompressedApproximation && ...
            compressedApproximationAllowed(model, P, opts)
        candidates = compressedApproxCandidatesAtP(model, P, propName, target, opts);
    end
end

function candidates = compressedCandidatesAtT(model, T, propName, target, opts)
    candidates = emptyCandidateTable();
    if model.hasCompressedTable
        candidates = [candidates; candidatesAtT(model, model.compressed, T, ...
            propName, target, "CL", model.compressedSource, opts)]; %#ok<AGROW>
    end

    if isempty(candidates) && model.allowCompressedApproximation && ...
            T >= model.minSaturationT && T <= model.maxSaturationT
        sat = saturationAtT(model, T);
        if propName == "h"
            P = sat.P_kPa + (target - sat.hf) / sat.vf;
            if isfinite(P) && P > sat.P_kPa && ...
                    compressedApproximationAllowed(model, P, opts)
                s = compressedLiquidApproximation(model, T, P, sat);
                candidates = stateToCandidate(s);
            end
        end
    end
end

function candidates = compressedApproxCandidatesAtP(model, P, propName, target, opts)
    candidates = emptyCandidateTable();
    Tgrid = model.satT.T_C;
    valid = P > model.satT.P_kPa;
    Tgrid = Tgrid(valid);
    if numel(Tgrid) < 2
        return
    end

    y = nan(size(Tgrid));
    for k = 1:numel(Tgrid)
        sat = saturationAtT(model, Tgrid(k));
        approx = compressedApproxProps(P, sat);
        y(k) = propertyFromProps(approx, propName);
    end

    rootsT = piecewiseLinearRoots(Tgrid, y, target, ...
        propertyTolerance(propName, target, opts));
    for k = 1:numel(rootsT)
        sat = saturationAtT(model, rootsT(k));
        if P > sat.P_kPa
            s = compressedLiquidApproximation(model, rootsT(k), P, sat);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        end
    end
end

function tf = compressedApproximationAllowed(model, P, opts)
    if model.fluidCode == "WATER"
        tf = P <= opts.MaxWaterIncompressibleApproximation_kPa;
    else
        tf = isfinite(P) && P > 0;
    end
end

function props = compressedApproxProps(P, sat)
    props = struct();
    props.v = sat.vf;
    props.u = sat.uf;
    props.h = sat.hf + sat.vf * (P - sat.P_kPa);
    props.s = sat.sf;
end

function candidates = candidatesAtP(model, regionTable, P, propName, target, phaseCode, source, opts)
    candidates = emptyCandidateTable();
    [Tgrid, Ygrid] = virtualSliceAtP(regionTable, P, propName, model.fluidCode);
    if numel(Tgrid) < 2
        return
    end

    rootsT = piecewiseLinearRoots(Tgrid, Ygrid, target, ...
        propertyTolerance(propName, target, opts));
    for k = 1:numel(rootsT)
        try
            [props, meta] = regionAtTP(regionTable, rootsT(k), P, model.fluidCode);
            code = phaseCode;
            if phaseCode == "SHV"
                code = classifyVaporCode(model, rootsT(k), P);
            end
            s = regionState(model, rootsT(k), P, props, code, ...
                source + "; inverse interpolation in " + propName + ...
                " followed by " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
        end
    end
end

function candidates = candidatesAtT(model, regionTable, T, propName, target, phaseCode, source, opts)
    candidates = emptyCandidateTable();
    [Pgrid, Ygrid] = virtualSliceAtT(regionTable, T, propName, model.fluidCode);
    if numel(Pgrid) < 2
        return
    end

    rootsP = piecewiseLinearRoots(Pgrid, Ygrid, target, ...
        propertyTolerance(propName, target, opts));
    for k = 1:numel(rootsP)
        try
            [props, meta] = regionAtTP(regionTable, T, rootsP(k), model.fluidCode);
            code = phaseCode;
            if phaseCode == "SHV"
                code = classifyVaporCode(model, T, rootsP(k));
            end
            s = regionState(model, T, rootsP(k), props, code, ...
                source + "; inverse interpolation in " + propName + ...
                " followed by " + meta.method);
            candidates = [candidates; stateToCandidate(s)]; %#ok<AGROW>
        catch
        end
    end
end

function [Tgrid, Ygrid] = virtualSliceAtP(regionTable, P, propName, fluidCode)
    candidateT = unique(regionTable.T_C);
    Tgrid = zeros(0,1);
    Ygrid = zeros(0,1);
    for k = 1:numel(candidateT)
        try
            [props, ~] = regionAtTP(regionTable, candidateT(k), P, fluidCode);
            y = propertyFromProps(props, propName);
            if isfinite(y)
                Tgrid(end+1,1) = candidateT(k); %#ok<AGROW>
                Ygrid(end+1,1) = y; %#ok<AGROW>
            end
        catch
        end
    end
    [Tgrid, order] = sort(Tgrid);
    Ygrid = Ygrid(order);
end

function [Pgrid, Ygrid] = virtualSliceAtT(regionTable, T, propName, fluidCode)
    candidateP = unique(regionTable.P_kPa);
    Pgrid = zeros(0,1);
    Ygrid = zeros(0,1);
    for k = 1:numel(candidateP)
        try
            [props, ~] = regionAtTP(regionTable, T, candidateP(k), fluidCode);
            y = propertyFromProps(props, propName);
            if isfinite(y)
                Pgrid(end+1,1) = candidateP(k); %#ok<AGROW>
                Ygrid(end+1,1) = y; %#ok<AGROW>
            end
        catch
        end
    end
    [Pgrid, order] = sort(Pgrid);
    Ygrid = Ygrid(order);
end

function [props, meta] = regionAtTP(regionTable, T, P, fluidCode)
%REGIONATTP Sequential linear interpolation: first in T, then in P.
    pressureLevels = unique(regionTable.P_kPa);
    values = nan(numel(pressureLevels), 4);
    valid = false(numel(pressureLevels), 1);

    for k = 1:numel(pressureLevels)
        block = regionTable(regionTable.P_kPa == pressureLevels(k), :);
        block = sortrows(block, 'T_C');
        [tUnique, ia] = unique(block.T_C, 'stable');
        block = block(ia,:);

        if numel(tUnique) == 1
            if abs(T - tUnique(1)) <= 1e-10
                values(k,:) = [block.v_m3_kg(1), block.u_kJ_kg(1), ...
                    block.h_kJ_kg(1), block.s_kJ_kg_K(1)];
                valid(k) = all(isfinite(values(k,1:3)));
            end
        elseif T >= min(tUnique)-1e-10 && T <= max(tUnique)+1e-10
            values(k,1) = interp1(tUnique, block.v_m3_kg, T, 'linear');
            values(k,2) = interp1(tUnique, block.u_kJ_kg, T, 'linear');
            values(k,3) = interp1(tUnique, block.h_kJ_kg, T, 'linear');
            values(k,4) = interp1(tUnique, block.s_kJ_kg_K, T, 'linear');
            valid(k) = all(isfinite(values(k,1:3)));
        end
    end

    pValid = pressureLevels(valid);
    values = values(valid,:);
    if isempty(pValid) || P < min(pValid)-1e-10 || P > max(pValid)+1e-10
        error('thermoState:OutOfTableRange', ...
            '%s: T = %.6g deg C and P = %.6g kPa are outside this table''s usable interpolation region. No extrapolation was performed.', ...
            fluidCode, T, P);
    end

    exactIdx = find(abs(pValid-P) <= max(1e-9,1e-12*abs(P)), 1);
    if ~isempty(exactIdx)
        result = values(exactIdx,:);
        method = "linear interpolation in temperature at a tabulated pressure";
    else
        lowerIdx = find(pValid < P, 1, 'last');
        upperIdx = find(pValid > P, 1, 'first');
        if isempty(lowerIdx) || isempty(upperIdx)
            error('thermoState:OutOfTableRange', ...
                '%s: requested pressure is not bracketed by usable table blocks at T = %.6g deg C.', ...
                fluidCode, T);
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

    props = struct('v',result(1),'u',result(2),'h',result(3),'s',result(4));
    meta = struct('method',method);
end

function sat = saturationAtT(model, T)
    tab = model.satT;
    if T < min(tab.T_C) || T > max(tab.T_C)
        error('thermoState:SaturationRange', ...
            '%s: T = %.6g deg C is outside the saturation range [%.6g, %.6g] deg C.', ...
            model.fluidName, T, min(tab.T_C), max(tab.T_C));
    end
    sat = interpolateSaturation(tab, 'T_C', T);
    sat.source = model.satTSource + "; linear interpolation in temperature";
end

function sat = saturationAtP(model, P)
    tab = model.satP;
    if P < min(tab.P_kPa) || P > max(tab.P_kPa)
        error('thermoState:SaturationRange', ...
            '%s: P = %.6g kPa is outside the saturation range [%.6g, %.6g] kPa.', ...
            model.fluidName, P, min(tab.P_kPa), max(tab.P_kPa));
    end
    sat = interpolateSaturation(tab, 'P_kPa', P);
    sat.source = model.satPSource + "; linear interpolation in pressure";
end

function sat = interpolateSaturation(tab, xName, query)
    x = tab.(xName);
    sat = struct();
    sat.T_C = interp1(x, tab.T_C, query, 'linear');
    sat.P_kPa = interp1(x, tab.P_kPa, query, 'linear');
    sat.vf = interp1(x, tab.vf, query, 'linear');
    sat.vg = interp1(x, tab.vg, query, 'linear');
    sat.uf = interp1(x, tab.uf, query, 'linear');
    sat.ug = interp1(x, tab.ug, query, 'linear');
    sat.hf = interp1(x, tab.hf, query, 'linear');
    sat.hg = interp1(x, tab.hg, query, 'linear');
    sat.sf = interp1(x, tab.sf, query, 'linear');
    sat.sg = interp1(x, tab.sg, query, 'linear');
end

function [f, g] = saturationPropertyPair(sat, propName)
    switch propName
        case "v"
            f = sat.vf; g = sat.vg;
        case "u"
            f = sat.uf; g = sat.ug;
        case "h"
            f = sat.hf; g = sat.hg;
        case "s"
            f = sat.sf; g = sat.sg;
        otherwise
            error('thermoState:InternalPropertyError', ...
                'Unsupported saturation property %s.', propName);
    end
end

function values = saturationVector(tab, propName, side)
    switch propName
        case "v"
            fName = 'vf'; gName = 'vg';
        case "u"
            fName = 'uf'; gName = 'ug';
        case "h"
            fName = 'hf'; gName = 'hg';
        case "s"
            fName = 'sf'; gName = 'sg';
        otherwise
            error('thermoState:InternalPropertyError', ...
                'Unsupported saturation property %s.', propName);
    end
    if side == "f"
        values = tab.(fName);
    else
        values = tab.(gName);
    end
end

function state = saturatedState(model, sat, x)
    if isCriticalSaturation(sat)
        state = criticalState(model, sat);
        state.notes(end+1,1) = ...
            "Quality is not meaningful at the critical point because saturated-liquid and saturated-vapor properties coincide.";
        return
    end

    state = emptyState(model.fluidName, model.modelName, struct());
    state.isComplete = true;
    state.T_C = sat.T_C;
    state.P_kPa = sat.P_kPa;
    state.v_m3_kg = sat.vf + x*(sat.vg-sat.vf);
    state.u_kJ_kg = sat.uf + x*(sat.ug-sat.uf);
    state.h_kJ_kg = sat.hf + x*(sat.hg-sat.hf);
    state.s_kJ_kg_K = sat.sf + x*(sat.sg-sat.sf);
    state.x = x;
    state.bounds = saturationBounds(sat);
    if x <= 1e-10
        state.phaseCode = "SL";
    elseif x >= 1-1e-10
        state.phaseCode = "SV";
    else
        state.phaseCode = "SLVM";
    end
    state.phase = phaseLabel(state.phaseCode);
    state.source = sat.source + "; quality relation y = y_f + x(y_g-y_f)";
end

function state = partialSaturatedState(model, sat, note)
    state = emptyState(model.fluidName, model.modelName, struct());
    state.T_C = sat.T_C;
    state.P_kPa = sat.P_kPa;
    state.phaseCode = "SAT";
    state.phase = phaseLabel("SAT");
    state.source = sat.source;
    state.bounds = saturationBounds(sat);
    state.notes(end+1,1) = string(note);
end

function state = criticalState(model, sat)
    state = emptyState(model.fluidName, model.modelName, struct());
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

function tf = isCriticalSaturation(sat)
    tf = abs(sat.vg-sat.vf) < 1e-10 && ...
         abs(sat.ug-sat.uf) < 1e-7 && ...
         abs(sat.hg-sat.hf) < 1e-7;
end

function state = compressedLiquidApproximation(model, T, P, sat)
    state = emptyState(model.fluidName, model.modelName, struct());
    props = compressedApproxProps(P, sat);
    state.isComplete = true;
    state.phaseCode = "CL";
    state.phase = phaseLabel("CL");
    state.T_C = T;
    state.P_kPa = P;
    state.v_m3_kg = props.v;
    state.u_kJ_kg = props.u;
    state.h_kJ_kg = props.h;
    state.s_kJ_kg_K = props.s;
    state.x = NaN;
    state.source = model.satTSource + ...
        "; saturated-liquid values at T plus incompressible compressed-liquid approximation";
    state.notes(end+1,1) = ...
        "Approximation used: v ~= v_f(T), u ~= u_f(T), s ~= s_f(T), and h ~= h_f(T) + v_f(T)[P-P_sat(T)].";
end

function state = regionState(model, T, P, props, phaseCode, source)
    state = emptyState(model.fluidName, model.modelName, struct());
    state.isComplete = all(isfinite([T,P,props.v,props.u,props.h]));
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
            "Entropy is unavailable because interpolation touches a source cell that was excluded/flagged; no replacement was inferred.";
    end
end

function state = setStateProperty(state, propName, value)
    switch propName
        case "v"
            state.v_m3_kg = value;
            if isfinite(value) && value > 0, state.rho_kg_m3 = 1/value; end
        case "u"
            state.u_kJ_kg = value;
        case "h"
            state.h_kJ_kg = value;
        case "s"
            state.s_kJ_kg_K = value;
        case "T"
            state.T_C = value;
        case "P"
            state.P_kPa = value;
        case "x"
            state.x = value;
    end
end

function y = propertyFromProps(props, propName)
    switch propName
        case "v", y = props.v;
        case "u", y = props.u;
        case "h", y = props.h;
        case "s", y = props.s;
        otherwise
            error('thermoState:InternalPropertyError', ...
                'Unsupported region property %s.', propName);
    end
end

function tol = propertyTolerance(propName, target, opts)
    switch propName
        case {"u","h"}
            tol = max(opts.EnergyTolerance_kJ_kg, 1e-6*max(abs(target),1));
        case "s"
            tol = max(opts.EntropyTolerance_kJ_kg_K, 1e-6*max(abs(target),1));
        case "v"
            tol = max(1e-10, opts.SpecificVolumeRelativeTolerance*max(abs(target),1e-8));
        otherwise
            tol = 1e-8;
    end
end

function tol = propertyToleranceForCritical(propName, target, opts)
    if isPureProperty(propName)
        tol = propertyTolerance(propName, target, opts);
    else
        tol = 1e-8;
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
        case {"sat", "saturated", "saturatedstate", "saturatedstatequalityrequired"}
            code = "SAT";
        case {"critical", "criticalpoint", "crit"}
            code = "CRIT";
        case {"ig", "idealgas"}
            code = "IG";
        otherwise
            error('thermoState:UnknownPhase', ...
                ['Unknown phase "%s". Use CL, SL, SLVM, SV, SHV, SC, ' ...
                 'saturated, critical, or a full phase name.'], string(rawPhase));
    end
    label = phaseLabel(code);
end

function label = phaseLabel(code)
    switch string(code)
        case "CL", label = "Compressed liquid";
        case "SL", label = "Saturated liquid";
        case "SLVM", label = "Saturated liquid-vapor mixture";
        case "SV", label = "Saturated vapor";
        case "SHV", label = "Superheated vapor";
        case "SC", label = "Supercritical fluid";
        case "SAT", label = "Saturated state; quality required";
        case "CRIT", label = "Critical point";
        case "IG", label = "Ideal gas";
        otherwise, label = "Undetermined";
    end
end

function candidates = emptyCandidateTable()
    candidates = table('Size',[0,9], ...
        'VariableTypes',{'double','double','double','double','double', ...
                         'double','double','string','string'}, ...
        'VariableNames',{'T_C','P_kPa','v_m3_kg','u_kJ_kg','h_kJ_kg', ...
                         's_kJ_kg_K','x','phase','source'});
end

function row = stateToCandidate(state)
    row = table(state.T_C, state.P_kPa, state.v_m3_kg, ...
        state.u_kJ_kg, state.h_kJ_kg, state.s_kJ_kg_K, state.x, ...
        string(state.phase), string(state.source), ...
        'VariableNames',{'T_C','P_kPa','v_m3_kg','u_kJ_kg','h_kJ_kg', ...
                         's_kJ_kg_K','x','phase','source'});
end

function state = candidateToState(model, row, opts)
    state = emptyState(model.fluidName, model.modelName, opts);
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

function state = chooseCandidates(model, candidates, baseState, noUniqueMessage, opts)
    state = baseState;
    if height(candidates) == 1
        state = candidateToState(model, candidates(1,:), opts);
    elseif height(candidates) > 1
        state.candidates = candidates;
        state.notes(end+1,1) = ...
            "More than one table-interpolated state satisfies the declared pair. Review state.candidates and add another independent property.";
    else
        state.notes(end+1,1) = string(noUniqueMessage);
    end
end

function roots = piecewiseLinearRoots(x, y, target, tolerance)
    mask = isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    [x, order] = sort(x);
    y = y(order);
    [x, ia] = unique(x, 'stable');
    y = y(ia);

    roots = zeros(0,1);
    exactTol = max(1e-10, 1e-10*max(abs(target),1));
    for k = 1:numel(x)
        if abs(y(k)-target) <= exactTol
            roots(end+1,1) = x(k); %#ok<AGROW>
        end
        if k == numel(x), continue, end
        y1 = y(k)-target;
        y2 = y(k+1)-target;
        if y1*y2 < 0
            root = x(k) + (target-y(k))*(x(k+1)-x(k))/(y(k+1)-y(k));
            roots(end+1,1) = root; %#ok<AGROW>
        elseif abs(y1) <= exactTol && abs(y2) <= exactTol && ...
                abs(y(k+1)-y(k)) <= exactTol
            roots(end+1,1) = x(k+1); %#ok<AGROW>
        end
    end

    if isempty(roots) && ~isempty(y)
        [nearestError, nearestIdx] = min(abs(y-target));
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
        if isempty(out) || abs(values(k)-out(end)) > tolerance
            out(end+1,1) = values(k); %#ok<AGROW>
        end
    end
end

%% ------------------------------------------------------------------------
%  PURE-FLUID DATA PATCHES / LOADERS
%  ------------------------------------------------------------------------
function model = loadPureFluidModel(fluidCode, dataFolder, opts)
    persistent cacheKeys cacheModels
    if isempty(cacheKeys)
        cacheKeys = strings(0,1);
        cacheModels = cell(0,1);
    end
    key = string(fluidCode) + "|" + string(dataFolder);
    idx = find(cacheKeys == key, 1);
    if ~isempty(idx)
        model = cacheModels{idx};
        return
    end

    switch fluidCode
        case "WATER"
            model = loadWaterModel(dataFolder, opts);
        case "R134A"
            model = loadR134aModel(dataFolder);
        otherwise
            error('thermoState:InternalFluidError', ...
                'No pure-fluid loader exists for %s.', fluidCode);
    end

    cacheKeys(end+1,1) = key;
    cacheModels{end+1,1} = model;
end

function model = loadWaterModel(dataFolder, opts)
    satTPath = findDataFile(dataFolder, {'a4_saturated_water_temperature.csv'});
    satPPath = findDataFile(dataFolder, {'a5_saturated_water_pressure.csv'});
    shPath = findDataFile(dataFolder, {'a6_superheated_water.csv'});
    clPath = findDataFile(dataFolder, {'a7_compressed_liquid_water.csv'});

    rawSatT = readtable(satTPath);
    rawSatP = readtable(satPPath);
    rawSH = readtable(shPath, 'TextType','string');
    rawCL = readtable(clPath, 'TextType','string');

    satT = canonicalSatT(rawSatT, satTPath);
    satP = canonicalSatP(rawSatP, satPPath);
    superheated = canonicalWaterRegion(rawSH, satP, shPath);
    compressed = canonicalWaterRegion(rawCL, satP, clPath);

    flagged = abs(compressed.P_kPa-50000) < 1e-9 & ...
              abs(compressed.T_C) < 1e-9 & ...
              compressed.s_kJ_kg_K > 10;
    compressed.s_kJ_kg_K(flagged) = NaN;

    model = struct();
    model.fluidCode = "WATER";
    model.fluidName = "Water";
    model.modelName = "Table-based pure substance";
    model.satT = sortrows(satT,'T_C');
    model.satP = sortrows(satP,'P_kPa');
    model.superheated = sortrows(superheated,{'P_kPa','T_C'});
    model.compressed = sortrows(compressed,{'P_kPa','T_C'});
    model.hasCompressedTable = true;
    model.allowCompressedApproximation = true;
    model.supportsSupercritical = true;
    model.satTSource = "A-4 saturated-water temperature table";
    model.satPSource = "A-5 saturated-water pressure table";
    model.superheatedSource = "A-6 superheated-water table";
    model.compressedSource = "A-7 compressed-liquid-water table";
    model.minSaturationT = min(model.satT.T_C);
    model.maxSaturationT = max(model.satT.T_C);
    model.minSaturationP = min(model.satP.P_kPa);
    model.maxSaturationP = max(model.satP.P_kPa);
    model.Tcrit = max(model.satT.T_C);
    model.Pcrit = max(model.satP.P_kPa);
    model.maxApproxP = opts.MaxWaterIncompressibleApproximation_kPa;
end

function model = loadR134aModel(dataFolder)
    satTPath = findDataFile(dataFolder, {'a11_saturated_r134a_temperature.csv'});
    shPath = findDataFile(dataFolder, {'a13e_superheated_r134a.csv'});

    rawSat = readtable(satTPath);
    rawSH = readtable(shPath, 'TextType','string');
    [satT, removedCount] = cleanR134aSaturation(rawSat, satTPath);
    [superheated, malformedCount] = canonicalR134aSuperheated(rawSH, satT, shPath);

    satP = sortrows(satT, 'P_kPa');

    model = struct();
    model.fluidCode = "R134A";
    model.fluidName = "R-134a";
    model.modelName = "Table-based pure substance";
    model.satT = sortrows(satT,'T_C');
    model.satP = satP;
    model.superheated = sortrows(superheated,{'P_kPa','T_C'});
    model.compressed = table();
    model.hasCompressedTable = false;
    model.allowCompressedApproximation = true;
    model.supportsSupercritical = false;
    if removedCount > 0
        model.satTSource = ...
            "A-11 saturated R-134a temperature table; malformed thermodynamic-identity row(s) excluded without replacement";
    else
        model.satTSource = "A-11 saturated R-134a temperature table";
    end
    model.satPSource = model.satTSource + "; pressure lookup obtained by inverting the cleaned A-11 saturation curve";
    if malformedCount > 0
        model.superheatedSource = ...
            "A-13E superheated R-134a table converted internally to SI; malformed duplicate -20 deg F rows following 200 deg F excluded without replacement";
    else
        model.superheatedSource = ...
            "A-13E superheated R-134a table converted internally to SI";
    end
    model.compressedSource = "Compressed-liquid approximation from A-11 saturated-liquid values";
    model.minSaturationT = min(model.satT.T_C);
    model.maxSaturationT = max(model.satT.T_C);
    model.minSaturationP = min(model.satP.P_kPa);
    model.maxSaturationP = max(model.satP.P_kPa);
    model.Tcrit = model.maxSaturationT;
    model.Pcrit = model.maxSaturationP;
    model.maxApproxP = Inf;
end

function sat = canonicalSatT(raw, fileName)
    required = {'T_C','P_sat_kPa','v_f_m3_kg','v_g_m3_kg', ...
        'u_f_kJ_kg','u_g_kJ_kg','h_f_kJ_kg','h_g_kJ_kg', ...
        's_f_kJ_kg_K','s_g_kJ_kg_K'};
    assertRequiredColumns(raw, required, fileName);
    sat = table(raw.T_C, raw.P_sat_kPa, raw.v_f_m3_kg, raw.v_g_m3_kg, ...
        raw.u_f_kJ_kg, raw.u_g_kJ_kg, raw.h_f_kJ_kg, raw.h_g_kJ_kg, ...
        raw.s_f_kJ_kg_K, raw.s_g_kJ_kg_K, ...
        'VariableNames',{'T_C','P_kPa','vf','vg','uf','ug','hf','hg','sf','sg'});
end

function sat = canonicalSatP(raw, fileName)
    required = {'P_kPa','T_sat_C','v_f_m3_kg','v_g_m3_kg', ...
        'u_f_kJ_kg','u_g_kJ_kg','h_f_kJ_kg','h_g_kJ_kg', ...
        's_f_kJ_kg_K','s_g_kJ_kg_K'};
    assertRequiredColumns(raw, required, fileName);
    sat = table(raw.T_sat_C, raw.P_kPa, raw.v_f_m3_kg, raw.v_g_m3_kg, ...
        raw.u_f_kJ_kg, raw.u_g_kJ_kg, raw.h_f_kJ_kg, raw.h_g_kJ_kg, ...
        raw.s_f_kJ_kg_K, raw.s_g_kJ_kg_K, ...
        'VariableNames',{'T_C','P_kPa','vf','vg','uf','ug','hf','hg','sf','sg'});
end

function region = canonicalWaterRegion(raw, satP, fileName)
    required = {'pressure_MPa','T_C','row_type','v_m3_kg','u_kJ_kg','h_kJ_kg','s_kJ_kg_K'};
    assertRequiredColumns(raw, required, fileName);
    P_kPa_all = str2double(string(raw.pressure_MPa))*1000;
    T_C_all = str2double(string(raw.T_C));
    rowType = lower(strtrim(string(raw.row_type)));
    isReference = rowType == "saturated_reference";

    for k = find(isReference(:))'
        if P_kPa_all(k) >= min(satP.P_kPa) && P_kPa_all(k) <= max(satP.P_kPa)
            T_C_all(k) = interp1(satP.P_kPa, satP.T_C, P_kPa_all(k), 'linear');
        end
    end

    v_all = str2double(string(raw.v_m3_kg));
    u_all = str2double(string(raw.u_kJ_kg));
    h_all = str2double(string(raw.h_kJ_kg));
    s_all = str2double(string(raw.s_kJ_kg_K));
    keep = isfinite(P_kPa_all) & isfinite(T_C_all) & ...
           isfinite(v_all) & isfinite(u_all) & isfinite(h_all);

    P_kPa = P_kPa_all(keep);
    T_C = T_C_all(keep);
    v_m3_kg = v_all(keep);
    u_kJ_kg = u_all(keep);
    h_kJ_kg = h_all(keep);
    s_kJ_kg_K = s_all(keep);
    region = table(P_kPa,T_C,v_m3_kg,u_kJ_kg,h_kJ_kg,s_kJ_kg_K);
    region = sortrows(region,{'P_kPa','T_C'});
    [~,ia] = unique([region.P_kPa,region.T_C],'rows','stable');
    region = region(ia,:);
end

function [sat, removedCount] = cleanR134aSaturation(raw, fileName)
    required = {'T_C','P_sat_kPa','v_f_m3_kg','v_g_m3_kg', ...
        'u_f_kJ_kg','u_fg_kJ_kg','u_g_kJ_kg','h_f_kJ_kg','h_fg_kJ_kg', ...
        'h_g_kJ_kg','s_f_kJ_kg_K','s_fg_kJ_kg_K','s_g_kJ_kg_K'};
    assertRequiredColumns(raw, required, fileName);

    uErr = abs(raw.u_g_kJ_kg-(raw.u_f_kJ_kg+raw.u_fg_kJ_kg));
    hErr = abs(raw.h_g_kJ_kg-(raw.h_f_kJ_kg+raw.h_fg_kJ_kg));
    sErr = abs(raw.s_g_kJ_kg_K-(raw.s_f_kJ_kg_K+raw.s_fg_kJ_kg_K));
    liquidHErr = abs(raw.h_f_kJ_kg-(raw.u_f_kJ_kg+raw.P_sat_kPa.*raw.v_f_m3_kg));
    malformed = uErr > 0.10 | hErr > 0.10 | sErr > 0.002 | liquidHErr > 0.10;
    removedCount = sum(malformed);
    raw = raw(~malformed,:);
    sat = canonicalSatT(raw, fileName);
    sat = sortrows(sat,'T_C');
    if any(diff(sat.T_C) <= 0) || any(diff(sat.P_kPa) <= 0)
        error('thermoState:InvalidR134aSaturationTable', ...
            'The cleaned R-134a saturation table is not strictly increasing in T and P.');
    end
end

function [region, malformedCount] = canonicalR134aSuperheated(raw, satT, fileName)
    required = {'pressure_psia','T_F','row_type','v_ft3_lbm', ...
        'u_Btu_lbm','h_Btu_lbm','s_Btu_lbm_R'};
    assertRequiredColumns(raw, required, fileName);

    pPsia = str2double(string(raw.pressure_psia));
    tF = str2double(string(raw.T_F));
    rowType = lower(strtrim(string(raw.row_type)));

    malformed = false(height(raw),1);
    levels = unique(pPsia(isfinite(pPsia)), 'stable');
    for k = 1:numel(levels)
        idx = find(pPsia == levels(k) & rowType == "superheated");
        for j = 2:numel(idx)
            if abs(tF(idx(j))+20) < 1e-10 && abs(tF(idx(j-1))-200) < 1e-10
                malformed(idx(j)) = true;
            end
        end
    end
    malformedCount = sum(malformed);

    kPaPerPsia = 6.894757293168361;
    m3kgPerFt3lbm = 0.0624279605761;
    kJkgPerBtuLbm = 2.326000324917;
    kJkgKPerBtuLbmR = 4.1868005848506;

    P_all = pPsia*kPaPerPsia;
    T_all = (tF-32)*(5/9);
    isReference = rowType == "saturated_reference";
    for k = find(isReference(:))'
        if P_all(k) >= min(satT.P_kPa) && P_all(k) <= max(satT.P_kPa)
            T_all(k) = interp1(satT.P_kPa, satT.T_C, P_all(k), 'linear');
        else
            T_all(k) = NaN;
        end
    end

    v_all = str2double(string(raw.v_ft3_lbm))*m3kgPerFt3lbm;
    u_all = str2double(string(raw.u_Btu_lbm))*kJkgPerBtuLbm;
    h_all = str2double(string(raw.h_Btu_lbm))*kJkgPerBtuLbm;
    s_all = str2double(string(raw.s_Btu_lbm_R))*kJkgKPerBtuLbmR;

    keep = ~malformed & isfinite(P_all) & isfinite(T_all) & ...
        isfinite(v_all) & isfinite(u_all) & isfinite(h_all) & isfinite(s_all) & ...
        (rowType == "superheated" | isReference);

    P_kPa = P_all(keep);
    T_C = T_all(keep);
    v_m3_kg = v_all(keep);
    u_kJ_kg = u_all(keep);
    h_kJ_kg = h_all(keep);
    s_kJ_kg_K = s_all(keep);
    retainedType = rowType(keep);

    Tsat = interp1(satT.P_kPa, satT.T_C, P_kPa, 'linear', NaN);
    physical = retainedType == "saturated_reference" | ...
        ~isfinite(Tsat) | T_C >= Tsat-1e-8;

    region = table(P_kPa(physical),T_C(physical),v_m3_kg(physical), ...
        u_kJ_kg(physical),h_kJ_kg(physical),s_kJ_kg_K(physical), ...
        'VariableNames',{'P_kPa','T_C','v_m3_kg','u_kJ_kg','h_kJ_kg','s_kJ_kg_K'});
    region = sortrows(region,{'P_kPa','T_C'});
    [~,ia] = unique([region.P_kPa,region.T_C],'rows','stable');
    region = region(ia,:);
end

%% ------------------------------------------------------------------------
%  IDEAL-GAS AIR SOLVER
%  ------------------------------------------------------------------------
function state = solveAirState(inputs, tables, opts)
    names = string({inputs.name});
    if any(ismember(names,["x","phase"]))
        error('thermoState:UnsupportedAirInput', ...
            'Quality and liquid-vapor phase labels are not inputs for ideal-gas air.');
    end

    state = emptyState("Air", "Ideal-gas air", opts);
    state.phaseCode = "IG";
    state.phase = "Ideal gas";

    try
        [T_K, temperatureNotes] = determineAirTemperature(inputs, tables, opts);
    catch ME
        if startsWith(string(ME.identifier),"thermoState:AirOutOfRange") || ...
                startsWith(string(ME.identifier),"thermoState:AirUnderdetermined")
            state.notes(end+1,1) = string(ME.message);
            return
        end
        rethrow(ME)
    end

    state.T_K = T_K;
    state.T_C = T_K-273.15;
    state.notes = appendStrings(state.notes, temperatureNotes);

    [thermo, thermoNotes] = airPropertiesAtT(T_K, tables);
    state.u_kJ_kg = thermo.u;
    state.h_kJ_kg = thermo.h;
    state.s0_kJ_kg_K = thermo.s0;
    state.Pr_relative = thermo.PrRelative;
    state.vr_relative = thermo.vrRelative;
    state.notes = appendStrings(state.notes, thermoNotes);

    [P, v, mechNotes] = determineAirMechanicalState(inputs, T_K, thermo.s0, opts);
    state.notes = appendStrings(state.notes, mechNotes);
    if ~(isfinite(P) && isfinite(v))
        state = addAirTransportProperties(state, tables, opts);
        state.notes(end+1,1) = ...
            "The declared pair determines temperature-dependent air properties but not both P and v. Supply P, v/rho, or reference-based entropy s as an independent second quantity.";
        return
    end

    state.P_kPa = P;
    state.v_m3_kg = v;
    state.rho_kg_m3 = 1/v;
    state.s_kJ_kg_K = thermo.s0 - opts.GasConstant_kJ_kg_K* ...
        log(P/opts.ReferencePressure_kPa);
    checkAirDeclaredConsistency(state, inputs, opts);

    state.isComplete = all(isfinite([state.T_K,state.P_kPa,state.v_m3_kg, ...
        state.u_kJ_kg,state.h_kJ_kg,state.s_kJ_kg_K]));
    state = addAirTransportProperties(state, tables, opts);
    state.source = ...
        "A-21 ideal-gas air table with linear interpolation in temperature; Pv = RT for P-v-rho; A-22 air-at-1-atm table for temperature-dependent transport properties.";
end

function [T_K, notes] = determineAirTemperature(inputs, tables, opts)
    temperatures = zeros(0,1);
    labels = strings(0,1);
    notes = strings(0,1);

    for k = 1:numel(inputs)
        switch inputs(k).name
            case "T"
                temperatures(end+1,1) = inputs(k).value+273.15; %#ok<AGROW>
                labels(end+1,1) = inputs(k).label; %#ok<AGROW>
            case "u"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K,tables.a21.u_kJ_kg,inputs(k).value,"u"); %#ok<AGROW>
                labels(end+1,1) = "u"; %#ok<AGROW>
            case "h"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K,tables.a21.h_kJ_kg,inputs(k).value,"h"); %#ok<AGROW>
                labels(end+1,1) = "h"; %#ok<AGROW>
            case "s0"
                temperatures(end+1,1) = inverseTableProperty( ...
                    tables.a21.T_K,tables.a21.s0_kJ_kg_K,inputs(k).value,"s0"); %#ok<AGROW>
                labels(end+1,1) = "s0"; %#ok<AGROW>
        end
    end

    if hasInput(inputs,"P") && hasInput(inputs,"v")
        P = getInput(inputs,"P");
        v = getInput(inputs,"v");
        temperatures(end+1,1) = P*v/opts.GasConstant_kJ_kg_K; %#ok<AGROW>
        labels(end+1,1) = "Pv = RT"; %#ok<AGROW>
    elseif hasInput(inputs,"P") && hasInput(inputs,"s")
        P = getInput(inputs,"P");
        sTarget = getInput(inputs,"s");
        entropyGrid = tables.a21.s0_kJ_kg_K - opts.GasConstant_kJ_kg_K* ...
            log(P/opts.ReferencePressure_kPa);
        temperatures(end+1,1) = inverseTableProperty( ...
            tables.a21.T_K,entropyGrid,sTarget,"s at declared P"); %#ok<AGROW>
        labels(end+1,1) = "P+s"; %#ok<AGROW>
    elseif hasInput(inputs,"v") && hasInput(inputs,"s")
        v = getInput(inputs,"v");
        sTarget = getInput(inputs,"s");
        pressureGrid = opts.GasConstant_kJ_kg_K.*tables.a21.T_K./v;
        entropyGrid = tables.a21.s0_kJ_kg_K - opts.GasConstant_kJ_kg_K.* ...
            log(pressureGrid./opts.ReferencePressure_kPa);
        temperatures(end+1,1) = inverseTableProperty( ...
            tables.a21.T_K,entropyGrid,sTarget,"s at declared v"); %#ok<AGROW>
        labels(end+1,1) = "v+s"; %#ok<AGROW>
    end

    if isempty(temperatures)
        error('thermoState:AirUnderdetermined', ...
            ['This air input pair does not determine temperature. Supply T, u, h, or s0; ' ...
             'alternatively use P+v, P+s, or v+s.']);
    end

    T_K = temperatures(1);
    if numel(temperatures) > 1
        mismatch = max(abs(temperatures-T_K));
        if mismatch > opts.TemperatureTolerance_K
            detail = strjoin(labels + " -> " + compose("%.6g K",temperatures), "; ");
            error('thermoState:AirInconsistentInputs', ...
                'The declared quantities imply inconsistent temperatures: %s.', detail);
        end
        T_K = mean(temperatures);
        notes(end+1,1) = ...
            "Both declared quantities independently constrained temperature and were checked for consistency.";
    end

    if T_K <= 0
        error('thermoState:InvalidTemperature', ...
            'The declared pair implies a nonphysical absolute temperature.');
    end
end

function [P, v, notes] = determineAirMechanicalState(inputs, T_K, s0, opts)
    P = NaN;
    v = NaN;
    notes = strings(0,1);
    if hasInput(inputs,"P")
        P = getInput(inputs,"P");
        v = opts.GasConstant_kJ_kg_K*T_K/P;
    elseif hasInput(inputs,"v")
        v = getInput(inputs,"v");
        P = opts.GasConstant_kJ_kg_K*T_K/v;
    elseif hasInput(inputs,"s")
        s = getInput(inputs,"s");
        P = opts.ReferencePressure_kPa*exp((s0-s)/opts.GasConstant_kJ_kg_K);
        v = opts.GasConstant_kJ_kg_K*T_K/P;
        notes(end+1,1) = ...
            "Pressure was obtained from s = s0(T) - R ln(P/Pref) using the internal 100 kPa reference pressure.";
    end
end

function checkAirDeclaredConsistency(state, inputs, opts)
    for k = 1:numel(inputs)
        declared = inputs(k).value;
        switch inputs(k).name
            case "T"
                calculated = state.T_C;
                tolerance = opts.TemperatureTolerance_K;
            case "P"
                calculated = state.P_kPa;
                tolerance = opts.RelativeConsistencyTolerance*max(abs(declared),1);
            case "v"
                calculated = state.v_m3_kg;
                tolerance = opts.RelativeConsistencyTolerance*max(abs(declared),1e-12);
            case "u"
                calculated = state.u_kJ_kg;
                tolerance = opts.RelativeConsistencyTolerance*max(abs(declared),1);
            case "h"
                calculated = state.h_kJ_kg;
                tolerance = opts.RelativeConsistencyTolerance*max(abs(declared),1);
            case "s"
                calculated = state.s_kJ_kg_K;
                tolerance = opts.EntropyTolerance_kJ_kg_K;
            case "s0"
                calculated = state.s0_kJ_kg_K;
                tolerance = opts.EntropyTolerance_kJ_kg_K;
            otherwise
                continue
        end
        if isfinite(calculated) && abs(calculated-declared) > tolerance
            error('thermoState:AirInconsistentInputs', ...
                'The calculated %s value (%.9g) is inconsistent with the declared value (%.9g).', ...
                inputs(k).label, calculated, declared);
        end
    end
end

function [props, notes] = airPropertiesAtT(T_K, tables)
    if T_K < tables.minT_K || T_K > tables.maxT_K
        error('thermoState:AirOutOfRange', ...
            'T = %.6g K is outside the supplied A-21 range [%.6g, %.6g] K. No extrapolation was performed.', ...
            T_K,tables.minT_K,tables.maxT_K);
    end
    props = struct();
    props.h = interpolateFinite(tables.a21.T_K,tables.a21.h_kJ_kg,T_K);
    props.u = interpolateFinite(tables.a21.T_K,tables.a21.u_kJ_kg,T_K);
    props.PrRelative = interpolateFinite(tables.a21.T_K,tables.a21.Pr,T_K);
    props.vrRelative = interpolateFinite(tables.a21.T_K,tables.a21.v_r,T_K);
    props.s0 = interpolateFinite(tables.a21.T_K,tables.a21.s0_kJ_kg_K,T_K);

    notes = strings(0,1);
    for k = 1:numel(tables.excludedH_T_K)
        badT = tables.excludedH_T_K(k);
        finiteMask = isfinite(tables.a21.h_kJ_kg);
        lower = tables.a21.T_K(finiteMask & tables.a21.T_K < badT);
        upper = tables.a21.T_K(finiteMask & tables.a21.T_K > badT);
        if ~isempty(lower) && ~isempty(upper) && T_K >= max(lower) && T_K <= min(upper)
            notes(end+1,1) = ...
                "A supplied A-21 enthalpy cell inconsistent with h-u = RT and the neighboring trend was excluded; h was linearly interpolated across adjacent valid rows.";
        end
    end
end

function state = addAirTransportProperties(state, tables, opts)
    if ~isfinite(state.T_C), return, end
    T_C = state.T_C;
    if T_C < tables.minTransportT_C || T_C > tables.maxTransportT_C
        state.notes(end+1,1) = ...
            "Temperature is outside the supplied A-22 transport-property range; cp, k, mu, and Prandtl number were not extrapolated.";
        return
    end

    cp_J = interpolateFinite(tables.a22.T_C,tables.a22.cp_J_kg_K,T_C);
    state.cp_kJ_kg_K = cp_J/1000;
    state.cv_kJ_kg_K = state.cp_kJ_kg_K-opts.GasConstant_kJ_kg_K;
    state.k_ratio = state.cp_kJ_kg_K/state.cv_kJ_kg_K;
    state.k_W_m_K = interpolateFinite(tables.a22.T_C,tables.a22.k_W_m_K,T_C);
    state.mu_Pa_s = interpolateFinite(tables.a22.T_C,tables.a22.mu_kg_m_s,T_C);
    state.Prandtl = interpolateFinite(tables.a22.T_C,tables.a22.Pr,T_C);
    if isfinite(state.rho_kg_m3) && state.rho_kg_m3 > 0
        state.nu_m2_s = state.mu_Pa_s/state.rho_kg_m3;
        state.alpha_m2_s = state.k_W_m_K/(state.rho_kg_m3*cp_J);
    end
    state.transportSource = ...
        "A-22 air-at-1-atm table: cp, k, mu, and Prandtl interpolated in temperature; nu and alpha recomputed at the solved density.";
end

function value = inverseTableProperty(T, property, target, label)
    mask = isfinite(T) & isfinite(property);
    T = T(mask);
    property = property(mask);
    [T,order] = sort(T);
    property = property(order);
    roots = piecewiseLinearRoots(T,property,target,1e-8);
    if isempty(roots)
        error('thermoState:AirOutOfRange', ...
            'The declared %s value %.9g is outside the usable A-21 range. No extrapolation was performed.', ...
            label,target);
    elseif numel(roots) > 1
        error('thermoState:AirNonUnique', ...
            'The declared %s value %.9g maps to more than one table temperature.',label,target);
    end
    value = roots(1);
end

function value = interpolateFinite(x, y, query)
    mask = isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    [x,order] = sort(x);
    y = y(order);
    [x,ia] = unique(x,'stable');
    y = y(ia);
    if query < min(x) || query > max(x)
        value = NaN;
    else
        value = interp1(x,y,query,'linear');
    end
end

function tables = loadAirTables(dataFolder)
    persistent cachedFolder cachedTables
    if ~isempty(cachedFolder) && cachedFolder == string(dataFolder)
        tables = cachedTables;
        return
    end

    a21Path = findDataFile(dataFolder, { ...
        'a21_air_ideal_gas_properties.csv', ...
        'a21_air_ideal_gas_properties - Copy.csv'});
    a22Path = findDataFile(dataFolder, { ...
        'a22_air_1atm_properties.csv', ...
        'a22_air_1atm_properties - Copy.csv'});
    a21 = readtable(a21Path);
    a22 = readtable(a22Path);

    assertRequiredColumns(a21,{'T_K','h_kJ_kg','Pr','u_kJ_kg','v_r','s0_kJ_kg_K'},a21Path);
    assertRequiredColumns(a22,{'T_C','rho_kg_m3','cp_J_kg_K','k_W_m_K', ...
        'alpha_m2_s','mu_kg_m_s','nu_m2_s','Pr'},a22Path);
    a21 = sortrows(a21,'T_K');
    a22 = sortrows(a22,'T_C');

    if numel(unique(a21.T_K)) ~= height(a21)
        error('thermoState:DuplicateTemperature','A-21 contains duplicate temperature rows.');
    end
    if numel(unique(a22.T_C)) ~= height(a22)
        error('thermoState:DuplicateTemperature','A-22 contains duplicate temperature rows.');
    end

    impliedR = (a21.h_kJ_kg-a21.u_kJ_kg)./a21.T_K;
    baselineR = median(impliedR(isfinite(impliedR)));
    badH = abs(impliedR-baselineR) > 1e-3;
    excludedH_T_K = a21.T_K(badH);
    a21.h_kJ_kg(badH) = NaN;

    tables = struct();
    tables.a21 = a21;
    tables.a22 = a22;
    tables.minT_K = min(a21.T_K);
    tables.maxT_K = max(a21.T_K);
    tables.minTransportT_C = min(a22.T_C);
    tables.maxTransportT_C = max(a22.T_C);
    tables.excludedH_T_K = excludedH_T_K;
    cachedFolder = string(dataFolder);
    cachedTables = tables;
end

%% ------------------------------------------------------------------------
%  SHARED FILE / TABLE HELPERS
%  ------------------------------------------------------------------------
function path = findDataFile(dataFolder, candidates)
    path = '';
    searchFolders = {char(dataFolder), fileparts(mfilename('fullpath'))};
    for f = 1:numel(searchFolders)
        for k = 1:numel(candidates)
            candidatePath = fullfile(searchFolders{f}, candidates{k});
            if isfile(candidatePath)
                path = candidatePath;
                return
            end
        end
    end
    error('thermoState:MissingDataFile', ...
        'None of the expected files were found. Data folder: %s. Expected one of: %s', ...
        char(dataFolder), strjoin(string(candidates), ', '));
end

function assertRequiredColumns(T, required, fileName)
    actual = string(T.Properties.VariableNames);
    required = string(required);
    missing = required(~ismember(required,actual));
    if ~isempty(missing)
        error('thermoState:MissingColumns', ...
            'File %s is missing required columns: %s', ...
            string(fileName), strjoin(missing, ', '));
    end
end

function out = appendStrings(current, additions)
    out = current;
    if isempty(additions), return, end
    additions = string(additions(:));
    additions = additions(strlength(additions) > 0);
    out = [out; additions];
end
