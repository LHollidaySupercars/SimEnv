% function vehicle = buildPotToDamperLUT(vehicle, varargin)
% % BUILDPOTTODAMERLUT  Build a pot-displacement to damper-displacement lookup table.
% %
% % Both solveDamperTravel and solveLinearPotTravel parameterise their results
% % over the lower A-arm angle (thetaL).  This function eliminates that common
% % parameter to produce a direct pot -> damper mapping.
% %
% % Inputs:
% %   vehicle      - Vehicle struct (damper.thetaL / Pot.thetaL must exist)
% %
% % Optional parameters:
% %   'axle'         - 'front' | 'rear'  (default: 'rear')
% %   'manufacturer' - manufacturer key  (default: 'ford')
% %   'numPoints'    - LUT resolution    (default: 1001)
% %   'Plotting'     - true | false      (default: false)
% %
% % Outputs:
% %   vehicle.(manufacturer).kinematics.(axle).potToDamperLUT
% %       .thetaL      - common parameter grid [n x 1]
% %       .potDisp     - pot displacement zeroed at ride height [n x 1] mm
% %       .damperDisp  - damper displacement zeroed at ride height [n x 1] mm
% %       .gradient    - d(damper)/d(pot) at each point [n-1 x 1]
% 
%     p = inputParser;
%     addRequired(p, 'vehicle', @isstruct);
%     addParameter(p, 'axle',         'rear',  @ischar);
%     addParameter(p, 'manufacturer', 'ford',  @ischar);
%     addParameter(p, 'numPoints',    1001,    @(x) isnumeric(x) && isscalar(x) && x > 1);
%     addParameter(p, 'Plotting',     false,   @islogical);
%     parse(p, vehicle, varargin{:});
% 
%     axle         = p.Results.axle;
%     manufacturer = p.Results.manufacturer;
%     numPoints    = p.Results.numPoints;
%     doPlotting   = p.Results.Plotting;
% 
%     kin = vehicle.(manufacturer).kinematics.(axle);
% 
%     % ------------------------------------------------------------------ %
%     % 1. Validate prerequisite fields
%     % ------------------------------------------------------------------ %
%     if ~isfield(kin, 'damper') || ~isfield(kin.damper, 'thetaL')
%         error('buildPotToDamperLUT: damper.thetaL not found. Run solveDamperTravel first.');
%     end
%     if ~isfield(kin, 'Pot') || ~isfield(kin.Pot, 'thetaL')
%         error('buildPotToDamperLUT: Pot.thetaL not found. Run solveLinearPotTravel first.');
%     end
% 
%     damperThetaL = kin.damper.thetaL;   % column vector
%     potThetaL    = kin.Pot.thetaL;      % column vector
%     damperDisp   = kin.damper.length;   % zeroed at full-bump by solveDamperTravel
%     potDisp      = kin.Pot.length;      % zeroed at full-bump by solveLinearPotTravel
% 
%     % ------------------------------------------------------------------ %
%     % 2. Find shared thetaL overlap
%     % ------------------------------------------------------------------ %
%     thetaMin = max(min(damperThetaL), min(potThetaL));
%     thetaMax = min(max(damperThetaL), max(potThetaL));
% 
%     if thetaMin >= thetaMax
%         error('buildPotToDamperLUT: damper and pot thetaL ranges do not overlap.');
%     end
% 
%     commonTheta = linspace(thetaMin, thetaMax, numPoints)';
% 
%     % ------------------------------------------------------------------ %
%     % 3. Interpolate both onto common grid
%     % ------------------------------------------------------------------ %
%     damperOnCommon = interp1(damperThetaL, damperDisp, commonTheta, 'linear');
%     potOnCommon    = interp1(potThetaL,    potDisp,    commonTheta, 'linear');
% 
%     % ------------------------------------------------------------------ %
%     % 4. Zero both at ride height (thetaL = 0)
%     % ------------------------------------------------------------------ %
%     [~, idx0] = min(abs(commonTheta));
%     damperOnCommon = damperOnCommon - damperOnCommon(idx0);
%     potOnCommon    = potOnCommon    - potOnCommon(idx0);
% 
%     % ------------------------------------------------------------------ %
%     % 5. Instantaneous gradient d(damper)/d(pot)
%     % ------------------------------------------------------------------ %
%     dPot    = diff(potOnCommon);
%     dDamper = diff(damperOnCommon);
% 
%     gradient = zeros(size(dPot));
%     nonZero  = abs(dPot) > eps;
%     gradient(nonZero) = dDamper(nonZero) ./ dPot(nonZero);
%     % carry last valid value forward over any zero-pot-change region
%     for i = 1:length(gradient)
%         if ~nonZero(i) && i > 1
%             gradient(i) = gradient(i-1);
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     % 6. Store LUT
%     % ------------------------------------------------------------------ %
%     lut.thetaL     = commonTheta;
%     lut.potDisp    = potOnCommon;
%     lut.damperDisp = damperOnCommon;
%     lut.gradient   = gradient;
% 
%     vehicle.(manufacturer).kinematics.(axle).potToDamperLUT = lut;
% 
%     fprintf('buildPotToDamperLUT: %s %s LUT built over %.2f to %.2f rad (%d points)\n', ...
%             upper(manufacturer), upper(axle), thetaMin, thetaMax, numPoints);
% 
%     % ------------------------------------------------------------------ %
%     % 7. Optional plots
%     % ------------------------------------------------------------------ %
%     if doPlotting
%         figure('Name', sprintf('Pot-to-Damper LUT - %s %s', upper(manufacturer), upper(axle)), ...
%                'Position', [100, 100, 1200, 450]);
% 
%         subplot(1, 3, 1);
%         hold on; grid on;
%         plot(potOnCommon, damperOnCommon, 'b-', 'LineWidth', 2);
%         plot(0, 0, 'ko', 'MarkerSize', 8, 'DisplayName', 'Ride height');
%         xlabel('Pot Displacement [mm]');
%         ylabel('Damper Displacement [mm]');
%         title(sprintf('Pot \rightarrow Damper LUT (%s %s)', upper(manufacturer), upper(axle)));
%         legend('LUT', 'Ride height', 'Location', 'best');
%         hold off;
% 
%         subplot(1, 3, 2);
%         hold on; grid on;
%         potMidpts = (potOnCommon(1:end-1) + potOnCommon(2:end)) / 2;
%         plot(potMidpts, gradient, 'r-', 'LineWidth', 2);
%         plot([min(potMidpts), max(potMidpts)], [1, 1], 'k--', 'LineWidth', 1);
%         xlabel('Pot Displacement [mm]');
%         ylabel('d(Damper)/d(Pot) [mm/mm]');
%         title('Pot-to-Damper Gradient');
%         hold off;
% 
%         subplot(1, 3, 3);
%         hold on; grid on;
%         plot(commonTheta, potOnCommon,    'b-', 'LineWidth', 2, 'DisplayName', 'Pot');
%         plot(commonTheta, damperOnCommon, 'r-', 'LineWidth', 2, 'DisplayName', 'Damper');
%         xlabel('Lower A-Arm Angle \theta_L [rad]');
%         ylabel('Displacement [mm]');
%         title('Both vs Common Parameter');
%         legend('Location', 'best');
%         hold off;
%     end
% end
function vehicle = buildPotToDamperLUT(vehicle, varargin)
% BUILDPOTTODAMERLUT  Build a pot-displacement to damper-displacement lookup table.
%
% Both solveDamperTravel and solveLinearPotTravel parameterise their results
% over the lower A-arm angle (thetaL).  This function eliminates that common
% parameter to produce a direct pot -> damper mapping.
%
% Inputs:
%   vehicle      - Vehicle struct (damper.thetaL / Pot.thetaL must exist)
%
% Optional parameters:
%   'axle'         - 'front' | 'rear'  (default: 'rear')
%   'manufacturer' - manufacturer key  (default: 'ford')
%   'numPoints'    - LUT resolution    (default: 1001)
%   'Plotting'     - true | false      (default: false)
%
% Outputs:
%   vehicle.(manufacturer).kinematics.(axle).potToDamperLUT
%       .thetaL      - common parameter grid [n x 1]
%       .potDisp     - pot displacement zeroed at ride height [n x 1] mm
%       .damperDisp  - damper displacement zeroed at ride height [n x 1] mm
%       .gradient    - d(damper)/d(pot) at each point [n-1 x 1]

    p = inputParser;
    addRequired(p, 'vehicle', @isstruct);
    addParameter(p, 'axle',         'rear',  @ischar);
    addParameter(p, 'manufacturer', 'ford',  @ischar);
    addParameter(p, 'numPoints',    1001,    @(x) isnumeric(x) && isscalar(x) && x > 1);
    addParameter(p, 'Plotting',     false,   @islogical);
    parse(p, vehicle, varargin{:});

    axle         = p.Results.axle;
    manufacturer = p.Results.manufacturer;
    numPoints    = p.Results.numPoints;
    doPlotting   = p.Results.Plotting;

    kin = vehicle.(manufacturer).kinematics.(axle);

    % ------------------------------------------------------------------ %
    % 1. Validate prerequisite fields
    % ------------------------------------------------------------------ %
    if ~isfield(kin, 'damper') || ~isfield(kin.damper, 'thetaL')
        error('buildPotToDamperLUT: damper.thetaL not found. Run solveDamperTravel first.');
    end
    if ~isfield(kin, 'Pot') || ~isfield(kin.Pot, 'thetaL')
        error('buildPotToDamperLUT: Pot.thetaL not found. Run solveRotaryPotTravel or solveLinearPotTravel first.');
    end
    if ~isfield(kin.Pot, 'angle') && ~isfield(kin.Pot, 'length')
        error('buildPotToDamperLUT: Pot must contain either .angle (rotary) or .length (linear).');
    end

    damperThetaL = kin.damper.thetaL;   % column vector
    potThetaL    = kin.Pot.thetaL;      % column vector
    damperDisp   = kin.damper.length;   % zeroed at full-bump by solveDamperTravel

    % Rotary pot outputs angle [deg]; linear pot outputs displacement [mm]
    if isfield(kin.Pot, 'angle')
        potDisp   = kin.Pot.angle;
        potLabel  = 'Pot Angle [deg]';
        gradLabel = 'd(Damper)/d(Pot) [mm/deg]';
    else
        potDisp   = kin.Pot.length;
        potLabel  = 'Pot Displacement [mm]';
        gradLabel = 'd(Damper)/d(Pot) [mm/mm]';
    end

    % ------------------------------------------------------------------ %
    % 2. Find shared thetaL overlap
    % ------------------------------------------------------------------ %
    thetaMin = max(min(damperThetaL), min(potThetaL));
    thetaMax = min(max(damperThetaL), max(potThetaL));

    if thetaMin >= thetaMax
        error('buildPotToDamperLUT: damper and pot thetaL ranges do not overlap.');
    end

    commonTheta = linspace(thetaMin, thetaMax, numPoints)';

    % ------------------------------------------------------------------ %
    % 3. Interpolate both onto common grid
    % ------------------------------------------------------------------ %
    damperOnCommon = interp1(damperThetaL, damperDisp, commonTheta, 'linear');
    potOnCommon    = interp1(potThetaL,    potDisp,    commonTheta, 'linear');

    % ------------------------------------------------------------------ %
    % 4. Zero both at ride height (thetaL = 0)
    % ------------------------------------------------------------------ %
    [~, idx0] = min(abs(commonTheta));
    damperOnCommon = damperOnCommon - damperOnCommon(idx0);
    potOnCommon    = potOnCommon    - potOnCommon(idx0);

    % ------------------------------------------------------------------ %
    % 5. Instantaneous gradient d(damper)/d(pot)
    % ------------------------------------------------------------------ %
    dPot    = diff(potOnCommon);
    dDamper = diff(damperOnCommon);

    gradient = zeros(size(dPot));
    nonZero  = abs(dPot) > eps;
    gradient(nonZero) = dDamper(nonZero) ./ dPot(nonZero);
    % carry last valid value forward over any zero-pot-change region
    for i = 1:length(gradient)
        if ~nonZero(i) && i > 1
            gradient(i) = gradient(i-1);
        end
    end

    % ------------------------------------------------------------------ %
    % 6. Store LUT
    % ------------------------------------------------------------------ %
    lut.thetaL     = commonTheta;
    lut.potDisp    = potOnCommon;      % angle [deg] if rotary, displacement [mm] if linear
    lut.damperDisp = damperOnCommon;
    lut.gradient   = gradient;
    lut.potLabel   = potLabel;         % carry units through for downstream plots

    vehicle.(manufacturer).kinematics.(axle).potToDamperLUT = lut;

    fprintf('buildPotToDamperLUT: %s %s LUT built over %.2f to %.2f rad (%d points)\n', ...
            upper(manufacturer), upper(axle), thetaMin, thetaMax, numPoints);

    % ------------------------------------------------------------------ %
    % 7. Optional plots
    % ------------------------------------------------------------------ %
    if doPlotting
        figure('Name', sprintf('Pot-to-Damper LUT - %s %s', upper(manufacturer), upper(axle)), ...
               'Position', [100, 100, 1200, 450]);

        subplot(1, 3, 1);
        hold on; grid on;
        plot(potOnCommon, damperOnCommon, 'b-', 'LineWidth', 2);
        plot(0, 0, 'ko', 'MarkerSize', 8, 'DisplayName', 'Ride height');
        xlabel(potLabel);
        ylabel('Damper Displacement [mm]');
        title(sprintf('Pot \rightarrow Damper LUT (%s %s)', upper(manufacturer), upper(axle)));
        legend('LUT', 'Ride height', 'Location', 'best');
        hold off;

        subplot(1, 3, 2);
        hold on; grid on;
        potMidpts = (potOnCommon(1:end-1) + potOnCommon(2:end)) / 2;
        plot(potMidpts, gradient, 'r-', 'LineWidth', 2);
        plot([min(potMidpts), max(potMidpts)], [1, 1], 'k--', 'LineWidth', 1);
        xlabel(potLabel);
        ylabel(gradLabel);
        title('Pot-to-Damper Gradient');
        hold off;

        subplot(1, 3, 3);
        hold on; grid on;
        plot(commonTheta, potOnCommon,    'b-', 'LineWidth', 2, 'DisplayName', 'Pot');
        plot(commonTheta, damperOnCommon, 'r-', 'LineWidth', 2, 'DisplayName', 'Damper');
        xlabel('Lower A-Arm Angle \theta_L [rad]');
        ylabel('Value');
        title('Both vs Common Parameter');
        legend('Location', 'best');
        hold off;
    end
end