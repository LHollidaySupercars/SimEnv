function plotKinematicsDebug(vehicle, varargin)
% PLOTKINEMATICSDEBUG  Debug visualisation of all kinematic channels.
%
% Produces four figures covering every channel that exportKinematicsToExcel
% writes out, so you can sanity-check the data before committing to Excel.
%
%   Figure 1 — Kinematics overview  (2x3 grid)
%       Camber | Camber Gain | Toe @ zero steer
%       Toe Gain | Roll Centre Height | Anti Geometry %
%
%   Figure 2 — Damper & Pot  (2x2 grid)
%       Damper Displacement | Pot Angle (or Displacement)
%       Motion Ratio | Pot vs Damper (LUT curve)
%
%   Figure 3 — Front Toe surface  (steering x wheel travel)
%
%   Figure 4 — Bounds: rear lower chassis clevis POS slots
%       Y/Z offset scatter per slot with ride-height kinematics annotated
%
% Usage:
%   plotKinematicsDebug(vehicle)
%   plotKinematicsDebug(vehicle, 'manufacturer', 'ford')
%   plotKinematicsDebug(vehicle, 'Figures', [1 2])   % only figs 1 and 2

    p = inputParser;
    addRequired(p,  'vehicle');
    addParameter(p, 'manufacturer', 'ford', @ischar);
    addParameter(p, 'Figures',      [1 2 3 4], @isnumeric);
    parse(p, vehicle, varargin{:});

    mfr     = p.Results.manufacturer;
    figs    = p.Results.Figures;

    % Colour conventions matching your existing scripts
    frontColor = [0.0,  0.4470, 0.7410];   % blue
    rearColor  = [0.8500, 0.3250, 0.0980]; % orange
    rhColor    = [0.1,  0.7,  0.1];        % green — ride height marker

    axles = {'front', 'rear'};
    colors = {frontColor, rearColor};

    % ------------------------------------------------------------------ %
    % Pre-extract ride-height indices and common data for both axles
    % ------------------------------------------------------------------ %
    data = struct();
    for a = 1:2
        axle = axles{a};
        kin  = vehicle.(mfr).kinematics.(axle);

        wt   = kin.camberSweep.wheelTravel(:, 3);
        n    = length(wt);
        [~, rhIdx] = min(abs(wt));

        % Use damper.thetaL as the interpolation axis — it is zeroed at
        % ride height and consistent with the damper/pot sweep grids.
        % camberSweep.thetaL uses absolute circle angles (not zeroed).
        if isfield(kin, 'damper') && isfield(kin.damper, 'thetaL') && ...
                length(kin.damper.thetaL) == n
            tL = kin.damper.thetaL;
        else
            tL = wt;   % fallback — use wheel travel as proxy
        end

        data.(axle).wt    = wt;
        data.(axle).tL    = tL;
        data.(axle).rhIdx = rhIdx;

        % Camber
        data.(axle).camber     = kin.camberSweep.camber;
        data.(axle).camberCorr = getFieldSafe(kin.camberSweep, 'camberCorrected', kin.camberSweep.camber);
        data.(axle).camberGain = kin.camberSweep.camberGain;

        % Toe @ zero steer
        if isfield(kin, 'toeSweep')
            [~, zIdx] = min(abs(kin.toeSweep.steeringRackDisplacement));
            data.(axle).toe     = kin.toeSweep.toe(:, zIdx);
            data.(axle).toeGain = kin.toeSweep.toeGain;
        else
            data.(axle).toe     = NaN(length(wt), 1);
            data.(axle).toeGain = NaN(length(wt), 1);
        end

        % Roll centre
        data.(axle).RC = getFieldSafe(kin, 'RC_height_array', NaN(length(wt),1));

        % Anti geometry
        if isfield(kin, 'antiGeometry') && isfield(kin.antiGeometry, 'percent')
            data.(axle).anti = kin.antiGeometry.percent;
        elseif isfield(kin, 'antiDive')
            data.(axle).anti = kin.antiDive;
        else
            data.(axle).anti = NaN(length(wt), 1);
        end

        % Damper — interpolate damper.thetaL onto the consistent tL grid
        if isfield(kin, 'damper') && isfield(kin.damper, 'thetaL')
            dTh = kin.damper.thetaL;
            dD  = kin.damper.length;
            [~, rh] = min(abs(dTh));
            dDz = dD - dD(rh);
            if length(dTh) == n
                % Same length — direct assignment, no interp needed
                data.(axle).damperDisp = dDz;
            else
                [dThS, si] = sort(dTh);
                data.(axle).damperDisp = interp1(dThS, dDz(si), tL, 'linear', NaN);
            end
            data.(axle).damperTh   = dTh;
            data.(axle).damperD    = dDz;
        else
            data.(axle).damperDisp = NaN(n, 1);
            data.(axle).damperTh   = [];
            data.(axle).damperD    = [];
        end

        % Pot (rotary angle preferred, linear displacement fallback)
        data.(axle).potLabel = 'Pot [mm]';
        if isfield(kin, 'Pot')
            if isfield(kin.Pot, 'angle')
                pTh = kin.Pot.thetaL;
                pV  = kin.Pot.angle;
                [~, rh] = min(abs(pTh));
                data.(axle).potDisp  = interp1(pTh, pV - pV(rh), tL, 'linear', NaN);
                data.(axle).potTh    = pTh;
                data.(axle).potV     = pV - pV(rh);
                data.(axle).potLabel = 'Pot Angle [deg]';
            elseif isfield(kin.Pot, 'thetaL')
                pTh = kin.Pot.thetaL;
                pV  = kin.Pot.length;
                [~, rh] = min(abs(pTh));
                data.(axle).potDisp  = interp1(pTh, pV - pV(rh), tL, 'linear', NaN);
                data.(axle).potTh    = pTh;
                data.(axle).potV     = pV - pV(rh);
            else
                data.(axle).potDisp = NaN(length(wt),1);
                data.(axle).potTh   = []; data.(axle).potV = [];
            end
        else
            data.(axle).potDisp = NaN(length(wt),1);
            data.(axle).potTh   = []; data.(axle).potV = [];
        end

        % Motion ratio
        if isfield(kin, 'potToDamperLUT') && ~isempty(data.(axle).potTh)
            lut    = kin.potToDamperLUT;
            potMid = (lut.potDisp(1:end-1) + lut.potDisp(2:end)) / 2;

            % Sort ascending — pot may sweep in negative direction (rotary pot)
            [potMidSorted, sortIdx] = sort(potMid);
            gradSorted = lut.gradient(sortIdx);

            [potThSorted, sortIdx2] = sort(data.(axle).potTh);
            potVSorted = data.(axle).potV(sortIdx2);

            potOnWt           = interp1(potThSorted, potVSorted, tL, 'linear', NaN);
            data.(axle).MR    = interp1(potMidSorted, gradSorted, potOnWt, 'linear', NaN);
            data.(axle).lutPot    = lut.potDisp;
            data.(axle).lutDamper = lut.damperDisp;
        else
            data.(axle).MR        = NaN(length(wt), 1);
            data.(axle).lutPot    = [];
            data.(axle).lutDamper = [];
        end
    end

    % ================================================================== %
    % FIGURE 1 — Kinematics overview
    % ================================================================== %
    if ismember(1, figs)
        fig1 = figure('Name', 'Kinematics Debug — Overview', ...
                      'Position', [50, 50, 1400, 800]);
        sgtitle('Kinematic Sweep — Debug Overview', 'FontSize', 14, 'FontWeight', 'bold');

        % --- Subplot 1: Camber ---
        ax1 = subplot(2, 3, 1); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).camberCorr, '-',  'Color', colors{a}, 'LineWidth', 2,   'DisplayName', sprintf('%s corrected', upper(axle)));
            plot(data.(axle).wt, data.(axle).camber,     '--', 'Color', colors{a}, 'LineWidth', 0.8, 'DisplayName', sprintf('%s raw', upper(axle)));
            plotRHMarker(data.(axle).wt, data.(axle).camberCorr, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Camber [deg]');
        title('Camber vs Wheel Travel');
        legend('Location', 'best', 'FontSize', 7); hold off;

        % --- Subplot 2: Camber Gain ---
        subplot(2, 3, 2); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).camberGain, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).camberGain, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Camber Gain [deg/mm]');
        title('Camber Gain vs Wheel Travel');
        legend('Location', 'best'); hold off;

        % --- Subplot 3: Toe @ zero steer ---
        subplot(2, 3, 3); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).toe, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).toe, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Toe [deg]');
        title('Toe vs Wheel Travel (Zero Steer)');
        legend('Location', 'best'); hold off;

        % --- Subplot 4: Toe Gain ---
        subplot(2, 3, 4); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).toeGain, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).toeGain, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Toe Gain [deg/mm]');
        title('Toe Gain vs Wheel Travel');
        legend('Location', 'best'); hold off;

        % --- Subplot 5: Roll Centre Height ---
        subplot(2, 3, 5); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).RC, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).RC, data.(axle).rhIdx, colors{a});
        end
        yline(0, '--k', 'Ground', 'LineWidth', 0.5);
        xline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('RC Height [mm]');
        title('Roll Centre Height vs Wheel Travel');
        legend('Location', 'best'); hold off;

        % --- Subplot 6: Anti Geometry ---
        subplot(2, 3, 6); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).anti, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).anti, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        yline(100, ':k', '100%', 'LineWidth', 0.5);
        yline(0,   ':k', '0%',   'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Anti [%]');
        title('Anti Geometry % vs Wheel Travel');
        legend('Location', 'best');
        ylim([-20, 120]); hold off;

        printRHTable(data, axles, 1);
    end

    % ================================================================== %
    % FIGURE 2 — Damper, Pot & Motion Ratio
    % ================================================================== %
    if ismember(2, figs)
        figure('Name', 'Kinematics Debug — Damper & Pot', ...
               'Position', [100, 100, 1300, 700]);
        sgtitle('Damper / Pot / Motion Ratio — Debug', 'FontSize', 14, 'FontWeight', 'bold');

        % --- Subplot 1: Damper Displacement ---
        subplot(2, 2, 1); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).damperDisp, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).damperDisp, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        yline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel('Damper Disp [mm]');
        title('Damper Displacement vs Wheel Travel');
        legend('Location', 'best'); hold off;

        % --- Subplot 2: Pot ---
        subplot(2, 2, 2); hold on; grid on;
        potLabelUsed = 'Pot';
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).potDisp, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).potDisp, data.(axle).rhIdx, colors{a});
            potLabelUsed = data.(axle).potLabel;
        end
        xline(0, '--k', 'LineWidth', 0.5);
        yline(0, '--k', 'LineWidth', 0.5);
        xlabel('Wheel Travel [mm]'); ylabel(potLabelUsed);
        title(sprintf('%s vs Wheel Travel', potLabelUsed));
        legend('Location', 'best'); hold off;

        % --- Subplot 3: Motion Ratio ---
        subplot(2, 2, 3); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            plot(data.(axle).wt, data.(axle).MR, '-', 'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
            plotRHMarker(data.(axle).wt, data.(axle).MR, data.(axle).rhIdx, colors{a});
        end
        xline(0, '--k', 'LineWidth', 0.5);
        yline(1, '--k', '1:1', 'LineWidth', 0.8);
        xlabel('Wheel Travel [mm]'); ylabel('Motion Ratio [-]');
        title('Motion Ratio vs Wheel Travel');
        legend('Location', 'best'); hold off;

        % --- Subplot 4: Pot vs Damper LUT curve ---
        subplot(2, 2, 4); hold on; grid on;
        for a = 1:2
            axle = axles{a};
            if ~isempty(data.(axle).lutPot)
                plot(data.(axle).lutPot, data.(axle).lutDamper, '-', ...
                     'Color', colors{a}, 'LineWidth', 2, 'DisplayName', upper(axle));
                plot(0, 0, 'o', 'Color', colors{a}, 'MarkerFaceColor', colors{a}, ...
                     'MarkerSize', 8, 'HandleVisibility', 'off');
            end
        end
        plot([min(xlim), max(xlim)], [min(ylim), max(ylim)], ':k', 'LineWidth', 0.8, ...
             'DisplayName', '1:1 reference');
        xlabel('Pot Displacement / Angle'); ylabel('Damper Displacement [mm]');
        title('Pot \rightarrow Damper LUT');
        legend('Location', 'best'); hold off;
    end

    % ================================================================== %
    % FIGURE 3 — Front Toe surface (steering x wheel travel)
    % ================================================================== %
    if ismember(3, figs)
        frontKin = vehicle.(mfr).kinematics.front;
        if isfield(frontKin, 'toeSweep') && size(frontKin.toeSweep.toe, 2) > 1

            figure('Name', 'Kinematics Debug — Front Toe Surface', ...
                   'Position', [150, 150, 1100, 500]);
            sgtitle('Front Toe Surface (Wheel Travel x Steering)', ...
                    'FontSize', 14, 'FontWeight', 'bold');

            wt_front    = frontKin.camberSweep.wheelTravel(:, 3);
            steerDisp   = frontKin.toeSweep.steeringRackDisplacement;
            toeMatrix   = frontKin.toeSweep.toe;   % [nTravel x nSteer]

            [~, zSteer]  = min(abs(steerDisp));
            [~, zTravel] = min(abs(wt_front));

            % Surface
            subplot(1, 2, 1);
            surf(wt_front, steerDisp, toeMatrix', 'EdgeColor', 'none');
            xlabel('Wheel Travel [mm]'); ylabel('Rack Disp [mm]'); zlabel('Toe [deg]');
            title('Toe Surface'); colorbar; view(45, 30); grid on;

            % Zero-steer slice + zero-travel slice
            subplot(1, 2, 2); hold on; grid on;
            plot(wt_front, toeMatrix(:, zSteer), '-', 'Color', frontColor, ...
                 'LineWidth', 2, 'DisplayName', 'Toe vs Travel (zero steer)');
            plot(steerDisp, toeMatrix(zTravel, :), '--', 'Color', frontColor, ...
                 'LineWidth', 2, 'DisplayName', 'Toe vs Steer (ride height)');
            xline(0, '--k', 'LineWidth', 0.5);
            yline(0, '--k', 'LineWidth', 0.5);
            xlabel('Travel [mm] / Rack Disp [mm]'); ylabel('Toe [deg]');
            title('Toe Slices'); legend('Location', 'best'); hold off;
        else
            fprintf('[Fig 3] Front toe surface not available (rear axle or single steer point).\n');
        end
    end

    % ================================================================== %
    % FIGURE 4 — Bounds: clevis POS slot Y/Z scatter
    % ================================================================== %
    if ismember(4, figs)
        axle = 'rear';
        kin  = vehicle.(mfr).kinematics.(axle);

        if ~isfield(kin, 'clevis')
            fprintf('[Fig 4] No clevis field — bounds plot skipped.\n');
        else
            fnames    = fieldnames(kin.clevis);
            posFields = fnames(startsWith(fnames, 'POS'));
            nPos      = length(posFields);

            if nPos == 0
                fprintf('[Fig 4] No POS slots found — bounds plot skipped.\n');
            else
                figure('Name', 'Kinematics Debug — Clevis POS Bounds', ...
                       'Position', [200, 200, 1100, 500]);
                sgtitle('Rear Lower Chassis Wishbone — Clevis POS Y/Z Envelope', ...
                        'FontSize', 13, 'FontWeight', 'bold');

                baseFore = kin.lowerAArm.fore(:)';
                baseAft  = kin.lowerAArm.aft(:)';
                wt       = kin.camberSweep.wheelTravel(:, 3);
                [~, rhIdx] = min(abs(wt));

                yFore = zeros(nPos, 1);  zFore = zeros(nPos, 1);
                yAft  = zeros(nPos, 1);  zAft  = zeros(nPos, 1);
                labels = cell(nPos, 1);

                for k = 1:nPos
                    slot   = posFields{k};
                    offset = kin.clevis.(slot)(:)';
                    yFore(k) = baseFore(2) + offset(2);
                    zFore(k) = baseFore(3) + offset(3);
                    yAft(k)  = baseAft(2)  + offset(2);
                    zAft(k)  = baseAft(3)  + offset(3);
                    labels{k} = slot;
                end

                % --- Left: Y/Z pickup scatter ---
                subplot(1, 2, 1); hold on; grid on; axis equal;
                scatter(yFore, zFore, 80, rearColor, 'filled', 'DisplayName', 'Lower Fore');
                scatter(yAft,  zAft,  80, frontColor, 'filled', 'DisplayName', 'Lower Aft');

                % Label each point
                for k = 1:nPos
                    text(yFore(k)+0.3, zFore(k)+0.3, labels{k}, 'FontSize', 7, 'Color', rearColor);
                    text(yAft(k)+0.3,  zAft(k)+0.3,  labels{k}, 'FontSize', 7, 'Color', frontColor);
                end

                % Convex hull envelope
                if nPos >= 3
                    try
                        kF = convhull(yFore, zFore);
                        plot(yFore(kF), zFore(kF), '--', 'Color', rearColor,  'LineWidth', 1);
                        kA = convhull(yAft, zAft);
                        plot(yAft(kA),  zAft(kA),  '--', 'Color', frontColor, 'LineWidth', 1);
                    catch; end
                end

                xlabel('Y [mm] (lateral)'); ylabel('Z [mm] (vertical)');
                title('Clevis POS Slot Positions (Y-Z plane)');
                legend('Location', 'best'); hold off;

                % --- Right: ride-height kinematics bar chart per slot ---
                subplot(1, 2, 2); hold on; grid on;

                % Extract a scalar per slot for one representative channel
                antiRH = NaN(nPos, 1);
                camberRH = NaN(nPos, 1);
                toeRH = NaN(nPos, 1);

                for k = 1:nPos
                    if isfield(kin, 'antiGeometry') && isfield(kin.antiGeometry, 'percent')
                        antiRH(k) = safeIdx(kin.antiGeometry.percent, rhIdx);
                    elseif isfield(kin, 'antiDive')
                        antiRH(k) = safeIdx(kin.antiDive, rhIdx);
                    end
                    camberRH(k) = safeIdx(kin.camberSweep.camber, rhIdx);
                    if isfield(kin, 'toeSweep')
                        [~, zIdx] = min(abs(kin.toeSweep.steeringRackDisplacement));
                        toeRH(k) = safeIdx(kin.toeSweep.toe(:, zIdx), rhIdx);
                    end
                end

                x = 1:nPos;
                bar(x - 0.25, camberRH, 0.2, 'FaceColor', frontColor, 'DisplayName', 'Camber [deg]');
                bar(x,        toeRH,    0.2, 'FaceColor', rearColor,  'DisplayName', 'Toe [deg]');
                bar(x + 0.25, antiRH/10, 0.2, 'FaceColor', [0.4 0.2 0.6], 'DisplayName', 'Anti/10 [%]');

                xticks(x); xticklabels(labels); xtickangle(30);
                xlabel('POS Slot'); ylabel('Value');
                title('Ride-Height Kinematics per POS Slot');
                legend('Location', 'best'); hold off;
            end
        end
    end

    fprintf('\n[plotKinematicsDebug] Done. Figures generated: %s\n', num2str(figs));
end


% =========================================================================
%  HELPERS
% =========================================================================

function plotRHMarker(wt, y, rhIdx, col)
% Plots a filled circle at the ride-height index
    if isempty(y) || all(isnan(y)); return; end
    val = y(rhIdx);
    if ~isnan(val)
        plot(wt(rhIdx), val, 'o', 'Color', col, 'MarkerFaceColor', col, ...
             'MarkerSize', 6, 'HandleVisibility', 'off');
    end
end

function printRHTable(data, axles, figNum)
% Prints a ride-height summary table to the console after fig 1
    fprintf('\n--- Ride-Height Values (Fig %d) ---\n', figNum);
    fprintf('%-10s  %8s  %10s  %8s  %8s  %8s  %8s\n', ...
            'Axle', 'Camber', 'CamberGain', 'Toe', 'ToeGain', 'RC [mm]', 'Anti [%]');
    fprintf('%s\n', repmat('-', 1, 72));
    for a = 1:length(axles)
        axle = axles{a};
        i    = data.(axle).rhIdx;
        fprintf('%-10s  %+8.3f  %+10.4f  %+8.3f  %+8.4f  %8.1f  %8.1f\n', ...
                upper(axle), ...
                safeIdx(data.(axle).camberCorr, i), ...
                safeIdx(data.(axle).camberGain, i), ...
                safeIdx(data.(axle).toe, i), ...
                safeIdx(data.(axle).toeGain, i), ...
                safeIdx(data.(axle).RC, i), ...
                safeIdx(data.(axle).anti, i));
    end
    fprintf('%s\n\n', repmat('-', 1, 72));
end

function val = getFieldSafe(s, field, default)
    if isfield(s, field); val = s.(field); else; val = default; end
end

function val = safeIdx(arr, idx)
    arr = arr(:);
    if isempty(arr) || idx > length(arr) || all(isnan(arr))
        val = NaN;
    else
        val = arr(idx);
    end
end