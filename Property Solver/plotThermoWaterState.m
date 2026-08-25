function ax = plotThermoWaterState(state, varargin)
%PLOTWATERSTATE Plot a state on a P-v or T-v saturation diagram.
%
%   plotWaterState(state)
%   plotWaterState(state,"Diagram","Pv")
%   plotWaterState(state,"Diagram","Tv")
%
% Optional name-value arguments:
%   "Diagram"    "Pv" (default) or "Tv"
%   "DataFolder" folder containing a4_saturated_water_temperature.csv

    defaultFolder = fullfile(fileparts(mfilename('fullpath')), 'data');
    p = inputParser;
    addParameter(p, 'Diagram', "Pv", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'DataFolder', defaultFolder, ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, varargin{:});

    diagram = lower(string(p.Results.Diagram));
    dataFolder = char(p.Results.DataFolder);
    satPath = fullfile(dataFolder, 'a4_saturated_water_temperature.csv');
    if ~isfile(satPath)
        error('plotThermoWaterState:MissingDataFile', ...
            'Saturation table not found: %s', satPath);
    end
    sat = readtable(satPath);

    figure('Name', 'Water State Diagram');
    ax = axes();
    hold(ax, 'on');

    switch diagram
        case {"pv", "p-v"}

            %--------------------------------------------------------------
            % Display settings for a readable P-v diagram
            %--------------------------------------------------------------
            pMinDisplay = 5;   % kPa; clip the very low-pressure tail
                               % so the dome is visually meaningful

            % Keep only the part of the dome above the display threshold
            mask = isfinite(sat.P_sat_kPa) & ...
                   isfinite(sat.v_f_m3_kg) & ...
                   isfinite(sat.v_g_m3_kg) & ...
                   sat.P_sat_kPa >= pMinDisplay;

            satPlot = sat(mask, :);

            % Plot saturation dome
            liquidLine = loglog(ax, satPlot.v_f_m3_kg, satPlot.P_sat_kPa, ...
                'LineWidth', 1.5, 'DisplayName', 'Saturated liquid line');
            loglog(ax, satPlot.v_g_m3_kg, satPlot.P_sat_kPa, ...
                'LineWidth', 1.5, 'Color', liquidLine.Color, ...
                'DisplayName', 'Saturated vapor line');

            xlabel(ax, 'Specific volume, v (m^3/kg)');
            ylabel(ax, 'Absolute pressure, P (kPa)');
            title(ax, {'Water P-v Diagram', ...
                'Saturation dome shown as a 2-D projection of the P-v-T surface'});

            xValue = state.v_m3_kg;
            yValue = state.P_kPa;

            %--------------------------------------------------------------
            % Axis scaling: focus on the useful part of the dome while
            % keeping the full pressure range up to the critical region.
            % jss added this so the PV diagram scales with the dome=f(T)
            %--------------------------------------------------------------
            critP = max(sat.P_sat_kPa);

            % Saturated vapor volume at the state's pressure (if available)
            if isfinite(state.P_kPa) && ...
               state.P_kPa >= min(sat.P_sat_kPa) && ...
               state.P_kPa <= max(sat.P_sat_kPa)
                vgAtStateP = interp1(sat.P_sat_kPa, sat.v_g_m3_kg, ...
                    state.P_kPa, 'linear');
            else
                vgAtStateP = NaN;
            end

            % Reasonable x-axis window:
            % - keep left side near compressed-liquid region
            % - include the local dome region and the current state
            xMin = 1e-3;
            xMaxCandidates = [1, 4*xValue];
            if isfinite(vgAtStateP)
                xMaxCandidates(end+1) = 3*vgAtStateP;
            end
            xMax = max(xMaxCandidates);

            % Prevent xMax from becoming too tiny or too huge
            xMax = max(xMax, 1);
            xMax = min(xMax, max(satPlot.v_g_m3_kg));

            % Reasonable y-axis window:
            % - keep the full upper dome up to the critical point
            % - clip only the extreme low-pressure end
            yMin = pMinDisplay;
            yMax = 1.05 * critP;

            xlim(ax, [xMin, xMax]);
            ylim(ax, [yMin, yMax]);

            %--------------------------------------------------------------
            % Helpful annotations
            %--------------------------------------------------------------

            % Mark the critical point
            loglog(ax, sat.v_f_m3_kg(end), sat.P_sat_kPa(end), 'ks', ...
                'MarkerFaceColor', 'k', 'DisplayName', 'Critical point');

            % Label the dome itself so students know it is not a single T
            domeIdx = round(0.65 * height(satPlot));
            text(ax, satPlot.v_g_m3_kg(domeIdx), satPlot.P_sat_kPa(domeIdx), ...
                "  Saturation dome" + newline + ...
                "  (all saturated states)", ...
                'VerticalAlignment', 'middle');

            % Add a clearer state label that explicitly includes temperature
            % to reinforce the P-v-T slice interpretation.
            if state.isComplete && isfinite(xValue) && isfinite(yValue)
                plot(ax, xValue, yValue, 'o', 'MarkerSize', 8, ...
                    'LineWidth', 1.5, 'DisplayName', 'Calculated state');

                text(ax, xValue*1.10, yValue*1.10, ...
                    "Calculated state" + newline + ...
                    "T = " + string(state.T_C) + " °C", ...
                    'VerticalAlignment', 'bottom');
            end

        case {"tv", "t-v"}
            liquidLine = semilogx(ax, sat.v_f_m3_kg, sat.T_C, ...
                'LineWidth', 1.5, 'DisplayName', 'Saturated liquid line');
            semilogx(ax, sat.v_g_m3_kg, sat.T_C, ...
                'LineWidth', 1.5, 'Color', liquidLine.Color, ...
                'DisplayName', 'Saturated vapor line');
            xlabel(ax, 'Specific volume, v (m^3/kg)');
            ylabel(ax, 'Temperature, T (deg C)');
            title(ax, 'Water T-v Diagram');
            xValue = state.v_m3_kg;
            yValue = state.T_C;

        otherwise
            error('plotThermoWaterState:UnknownDiagram', ...
                'Diagram must be "Pv" or "Tv".');
    end

    grid(ax, 'on');

    if state.isComplete && isfinite(xValue) && isfinite(yValue)
        plot(ax, xValue, yValue, 'o', 'MarkerSize', 8, ...
            'LineWidth', 1.5, 'DisplayName', 'Calculated state');
        text(ax, xValue, yValue, "  " + string(state.phase), ...
            'VerticalAlignment', 'bottom');
        plotTieLineIfApplicable(ax, state, sat, diagram);

    elseif ~isempty(state.candidates)
        switch diagram
            case {"pv", "p-v"}
                xCandidates = state.candidates.v_m3_kg;
                yCandidates = state.candidates.P_kPa;
            otherwise
                xCandidates = state.candidates.v_m3_kg;
                yCandidates = state.candidates.T_C;
        end
        plot(ax, xCandidates, yCandidates, 'o', 'MarkerSize', 7, ...
            'LineWidth', 1.2, 'DisplayName', 'Candidate states');

    elseif ~isempty(state.bounds) && isfinite(state.P_kPa) && isfinite(state.T_C)
        if diagram == "pv" || diagram == "p-v"
            yBounds = [state.P_kPa; state.P_kPa];
        else
            yBounds = [state.T_C; state.T_C];
        end
        plot(ax, state.bounds.v_m3_kg, yBounds, 'o--', ...
            'LineWidth', 1.2, 'DisplayName', 'Possible saturation interval');
    end

    legend(ax, 'Location', 'best');
    hold(ax, 'off');
end

function plotTieLineIfApplicable(ax, state, sat, diagram)
    if ~(isfinite(state.x) && state.x > 0 && state.x < 1)
        return
    end

    vf = interp1(sat.P_sat_kPa, sat.v_f_m3_kg, state.P_kPa, 'linear');
    vg = interp1(sat.P_sat_kPa, sat.v_g_m3_kg, state.P_kPa, 'linear');
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
