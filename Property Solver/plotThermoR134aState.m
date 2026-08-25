function ax = plotThermoR134aState(state, varargin)
%PLOTTHERMOR134ASTATE Plot an R-134a state on a P-v or T-v diagram.
%
%   plotThermoR134aState(state)
%   plotThermoR134aState(state,"Diagram","Pv")
%   plotThermoR134aState(state,"Diagram","Tv")
%
% Optional name-value arguments:
%   "Diagram"    "Pv" (default) or "Tv"
%   "DataFolder" folder containing a11_saturated_r134a_temperature.csv
%
% Uses only base MATLAB plotting functions.

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    p = inputParser;
    p.FunctionName = 'plotThermoR134aState';
    addParameter(p, 'Diagram', "Pv", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, varargin{:});

    diagram = lower(string(p.Results.Diagram));
    dataFolder = char(p.Results.DataFolder);
    satPath = fullfile(dataFolder, ...
        'a11_saturated_r134a_temperature.csv');
    if ~isfile(satPath)
        error('plotThermoR134aState:MissingDataFile', ...
            'Saturation table not found: %s', satPath);
    end

    sat = readtable(satPath);
    required = {'T_C','P_sat_kPa','v_f_m3_kg','v_g_m3_kg'};
    missing = setdiff(string(required), ...
        string(sat.Properties.VariableNames));
    if ~isempty(missing)
        error('plotThermoR134aState:InvalidDataSchema', ...
            'A-11 is missing required column(s): %s', ...
            strjoin(missing, ', '));
    end

    mask = isfinite(sat.T_C) & isfinite(sat.P_sat_kPa) & ...
           isfinite(sat.v_f_m3_kg) & isfinite(sat.v_g_m3_kg) & ...
           sat.P_sat_kPa > 0 & sat.v_f_m3_kg > 0 & sat.v_g_m3_kg > 0;
    sat = sortrows(sat(mask,:), 'T_C');

    figure('Name', 'R-134a State Diagram');
    ax = axes();
    hold(ax, 'on');

    switch diagram
        case {"pv", "p-v"}
            liquidLine = loglog(ax, sat.v_f_m3_kg, sat.P_sat_kPa, ...
                'LineWidth', 1.6, ...
                'DisplayName', 'Saturated liquid line');
            loglog(ax, sat.v_g_m3_kg, sat.P_sat_kPa, ...
                'LineWidth', 1.6, 'Color', liquidLine.Color, ...
                'DisplayName', 'Saturated vapor line');

            xlabel(ax, 'Specific volume, v (m^3/kg)');
            ylabel(ax, 'Absolute pressure, P (kPa)');
            title(ax, {'R-134a P-v Diagram', ...
                'Saturation dome is a 2-D projection of the P-v-T surface'});
            xValue = state.v_m3_kg;
            yValue = state.P_kPa;

            xMin = 0.75 * min(sat.v_f_m3_kg);
            xMax = 1.20 * max(sat.v_g_m3_kg);
            yMin = 0.80 * min(sat.P_sat_kPa);
            yMax = 1.10 * max(sat.P_sat_kPa);

            if isfinite(xValue) && xValue > 0
                xMin = min(xMin, 0.70*xValue);
                xMax = max(xMax, 1.80*xValue);
            end
            if isfinite(yValue) && yValue > 0
                yMin = min(yMin, 0.70*yValue);
                yMax = max(yMax, 1.50*yValue);
            end

            xlim(ax, [xMin, xMax]);
            ylim(ax, [yMin, yMax]);
            set(ax, 'XScale', 'log', 'YScale', 'log');

            domeIdx = max(1, min(height(sat), round(0.58*height(sat))));
            text(ax, 1.10*sat.v_g_m3_kg(domeIdx), ...
                sat.P_sat_kPa(domeIdx), ...
                "Saturation dome" + newline + ...
                "(all tabulated saturation temperatures)", ...
                'VerticalAlignment', 'middle');

            text(ax, sat.v_f_m3_kg(end), sat.P_sat_kPa(end), ...
                "  Upper end of supplied A-11 table" + newline + ...
                "  T = " + string(sat.T_C(end)) + " deg C", ...
                'VerticalAlignment', 'top');

        case {"tv", "t-v"}
            liquidLine = semilogx(ax, sat.v_f_m3_kg, sat.T_C, ...
                'LineWidth', 1.6, ...
                'DisplayName', 'Saturated liquid line');
            semilogx(ax, sat.v_g_m3_kg, sat.T_C, ...
                'LineWidth', 1.6, 'Color', liquidLine.Color, ...
                'DisplayName', 'Saturated vapor line');

            xlabel(ax, 'Specific volume, v (m^3/kg)');
            ylabel(ax, 'Temperature, T (deg C)');
            title(ax, 'R-134a T-v Diagram');
            xValue = state.v_m3_kg;
            yValue = state.T_C;

            xMin = 0.75 * min(sat.v_f_m3_kg);
            xMax = 1.20 * max(sat.v_g_m3_kg);
            ySpan = max(sat.T_C) - min(sat.T_C);
            yMin = min(sat.T_C) - 0.08*ySpan;
            yMax = max(sat.T_C) + 0.08*ySpan;

            if isfinite(xValue) && xValue > 0
                xMin = min(xMin, 0.70*xValue);
                xMax = max(xMax, 1.80*xValue);
            end
            if isfinite(yValue)
                yMin = min(yMin, yValue - 0.10*ySpan);
                yMax = max(yMax, yValue + 0.10*ySpan);
            end

            xlim(ax, [xMin, xMax]);
            ylim(ax, [yMin, yMax]);
            set(ax, 'XScale', 'log');

        otherwise
            error('plotThermoR134aState:UnknownDiagram', ...
                'Diagram must be "Pv" or "Tv".');
    end

    grid(ax, 'on');
    ax.Layer = 'top';

    if state.isComplete && isfinite(xValue) && isfinite(yValue) && xValue > 0
        plot(ax, xValue, yValue, 'o', 'MarkerSize', 8, ...
            'LineWidth', 1.5, 'DisplayName', 'Calculated state');

        label = "Calculated state" + newline + ...
                string(state.phase) + newline + ...
                "T = " + compose('%.3g', state.T_C) + " deg C" + newline + ...
                "P = " + compose('%.4g', state.P_kPa) + " kPa";
        text(ax, 1.06*xValue, 1.04*yValue, label, ...
            'VerticalAlignment', 'bottom');

        plotTieLineIfApplicable(ax, state, sat, diagram);

        if diagram == "pv" || diagram == "p-v"
            annotationText = ...
                "The marked point lies on the T = " + ...
                compose('%.3g', state.T_C) + ...
                " deg C isotherm of the underlying P-v-T surface.";
            text(ax, 0.03, 0.04, annotationText, ...
                'Units', 'normalized', ...
                'VerticalAlignment', 'bottom', ...
                'BackgroundColor', 'white', ...
                'Margin', 4);
        end

    elseif ~isempty(state.candidates)
        switch diagram
            case {"pv", "p-v"}
                xCandidates = state.candidates.v_m3_kg;
                yCandidates = state.candidates.P_kPa;
            otherwise
                xCandidates = state.candidates.v_m3_kg;
                yCandidates = state.candidates.T_C;
        end
        valid = isfinite(xCandidates) & isfinite(yCandidates) & ...
                xCandidates > 0;
        plot(ax, xCandidates(valid), yCandidates(valid), 'o', ...
            'MarkerSize', 7, 'LineWidth', 1.2, ...
            'DisplayName', 'Candidate states');

    elseif ~isempty(state.bounds) && ...
            isfinite(state.P_kPa) && isfinite(state.T_C)
        if diagram == "pv" || diagram == "p-v"
            yBounds = [state.P_kPa; state.P_kPa];
        else
            yBounds = [state.T_C; state.T_C];
        end
        plot(ax, state.bounds.v_m3_kg, yBounds, 'o--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Possible saturation interval');
    end

    legend(ax, 'Location', 'best');
    hold(ax, 'off');
end

function plotTieLineIfApplicable(ax, state, sat, diagram)
    if ~(isfinite(state.x) && state.x > 0 && state.x < 1)
        return
    end

    vf = interp1(sat.P_sat_kPa, sat.v_f_m3_kg, ...
        state.P_kPa, 'linear');
    vg = interp1(sat.P_sat_kPa, sat.v_g_m3_kg, ...
        state.P_kPa, 'linear');
    if ~(isfinite(vf) && isfinite(vg))
        return
    end

    if diagram == "pv" || diagram == "p-v"
        y = [state.P_kPa, state.P_kPa];
    else
        y = [state.T_C, state.T_C];
    end
    plot(ax, [vf, vg], y, '--', 'HandleVisibility', 'off');
end
