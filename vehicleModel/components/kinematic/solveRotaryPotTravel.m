function vehicle = solveRotaryPotTravel(vehicle, varargin)
% SOLVEROTARYPOTTRAVEL  Computes the rotary pot angle sweep as the lower
%                       A-arm rotates through its travel range.
%
% The rotary pot is mounted such that its shaft rotates with the rocker /
% bellcrank about the lower A-arm axis.  Unlike a linear pot (which tracks
% the extension length between two pickup points), a rotary pot outputs an
% angle — the angle swept by the arm from its ride-height datum.
%
% The angle is computed by:
%   1. Rotating the pot arm pickup (vehicle.ford.kinematics.(axle).Pot.armPickup)
%      about the lower A-arm axis using Rodrigues' formula — same as
%      solveLinearPotTravel / solveDamperTravel.
%   2. Computing the subtended angle at the pot pivot between the rotated
%      arm and its ride-height position.
%
% Outputs stored in vehicle.(manufacturer).kinematics.(axle).Pot:
%   .angle      - pot angle relative to ride height [deg]  [n x 1]
%   .thetaL     - lower A-arm angle parameter [rad]        [n x 1]  (zeroed at RH)
%   .thetaL_0Index - index of ride height in the array
%
% Voltage conversion:
%   Once you have angle vs damper displacement (via potToDamperLUT), apply:
%       pot_angle_deg = (volts - V_rideHeight) * degsPerVolt
%   where degsPerVolt comes from your DAQ calibration sheet.
%   Then look up damper displacement from the LUT:
%       damperDisp = interp1(Pot.angle, potToDamperLUT.damperDisp, pot_angle_deg)
%
% Required vehicle struct fields:
%   vehicle.(mfr).kinematics.(axle).Pot.pivotPoint   [1x3]  mm  - rot. pot pivot
%   vehicle.(mfr).kinematics.(axle).Pot.armPickup    [1x3]  mm  - end of pot arm
%   vehicle.(mfr).kinematics.(axle).lowerAArm.fore   [1x3]  mm
%   vehicle.(mfr).kinematics.(axle).lowerAArm.aft    [1x3]  mm
%   vehicle.(mfr).kinematics.(axle).camberSweep.thetaL

    p = inputParser;
    addRequired(p,  'vehicle', @isstruct);
    addParameter(p, 'axle',         'rear',  @ischar);
    addParameter(p, 'manufacturer', 'ford',  @ischar);
    addParameter(p, 'sweepRange',   1.0,     @isnumeric);
    addParameter(p, 'numPoints',    1001,    @isnumeric);
    addParameter(p, 'debug',        0,       @isnumeric);
    addParameter(p, 'Plotting',     false,   @islogical);
    parse(p, vehicle, varargin{:});

    mfr       = p.Results.manufacturer;
    axle      = p.Results.axle;
    sweepRange = p.Results.sweepRange;
    numPoints  = p.Results.numPoints;
    debug      = p.Results.debug;
    doPlot     = p.Results.Plotting;

    kin = vehicle.(mfr).kinematics.(axle);

    % ------------------------------------------------------------------ %
    % Validate required fields
    % ------------------------------------------------------------------ %
    if ~isfield(kin, 'Pot') || ~isfield(kin.Pot, 'pivotPoint') || ~isfield(kin.Pot, 'armPickup')
        error(['solveRotaryPotTravel: vehicle.%s.kinematics.%s.Pot must contain\n', ...
               '  .pivotPoint  [1x3] mm  — rotary pot body pivot (fixed to chassis)\n', ...
               '  .armPickup   [1x3] mm  — end of the rotating arm (fixed to rocker)\n'], ...
               mfr, axle);
    end

    if ~isfield(kin, 'camberSweep') || ~isfield(kin.camberSweep, 'thetaL')
        error('solveRotaryPotTravel: run solveWheelCamber / solveDamperTravel first.');
    end

    % ------------------------------------------------------------------ %
    % Rotation axis = lower A-arm axis (unit vector)
    % ------------------------------------------------------------------ %
    lowerFore = kin.lowerAArm.fore(:)';
    lowerAft  = kin.lowerAArm.aft(:)';
    rotAxis   = lowerAft - lowerFore;
    rotAxis   = rotAxis / norm(rotAxis);        % unit vector [1x3]

    % ------------------------------------------------------------------ %
    % Pot geometry
    % ------------------------------------------------------------------ %
    pivotPoint = kin.Pot.pivotPoint(:)';        % fixed chassis pivot  [1x3]
    armPickup  = kin.Pot.armPickup(:)';         % ride-height arm tip  [1x3]

    % Arm vector from pivot to arm tip (ride height)
    armVec0 = armPickup - pivotPoint;           % [1x3]
    armLen  = norm(armVec0);

    if armLen < eps
        error('solveRotaryPotTravel: pivotPoint and armPickup are coincident.');
    end

    % ------------------------------------------------------------------ %
    % Build thetaL sweep — same datum logic as solveDamperTravel
    % ------------------------------------------------------------------ %
    datumIndex    = ceil(length(kin.camberSweep.thetaL) / 2);
    datumPosition = kin.camberSweep.thetaL(datumIndex);

    thetaSweep = linspace(datumPosition - sweepRange, ...
                          datumPosition + sweepRange, numPoints);

    % ------------------------------------------------------------------ %
    % Rotate arm tip about lower A-arm axis at each theta
    % ------------------------------------------------------------------ %
    % The arm pickup is attached to the rocker which rotates with the A-arm.
    % We rotate armVec0 (relative to lowerFore origin) by theta.

    vectorToRotate = armPickup - lowerFore;     % [1x3]
    k = rotAxis;                                % [1x3]

    potAngleDeg = zeros(numPoints, 1);
    rotatedTips = zeros(numPoints, 3);

    for i = 1:numPoints
        theta    = thetaSweep(i) - datumPosition;
        cosT     = cos(theta);  sinT = sin(theta);

        % Rodrigues
        rotVec = vectorToRotate * cosT + ...
                 cross(k, vectorToRotate) * sinT + ...
                 k * dot(k, vectorToRotate) * (1 - cosT);

        armTip_i = lowerFore + rotVec;          % world position of arm tip
        rotatedTips(i, :) = armTip_i;

        % Angle subtended at pivot between ride-height arm and current arm
        v0 = armVec0;                           % ride-height arm vec
        vi = armTip_i - pivotPoint;             % current arm vec

        % Project both onto the plane perpendicular to the A-arm axis
        % (the pot only senses rotation about its own shaft, which is
        %  nominally parallel to the A-arm axis)
        v0_perp = v0 - dot(v0, k) * k;
        vi_perp = vi - dot(vi, k) * k;

        if norm(v0_perp) < eps || norm(vi_perp) < eps
            potAngleDeg(i) = 0;
            continue;
        end

        v0_hat = v0_perp / norm(v0_perp);
        vi_hat = vi_perp / norm(vi_perp);

        cosAngle = max(-1, min(1, dot(v0_hat, vi_hat)));
        angle    = acosd(cosAngle);

        % Sign: use cross product against A-arm axis to determine direction
        crossVec = cross(v0_hat, vi_hat);
        if dot(crossVec, k) < 0
            angle = -angle;
        end

        potAngleDeg(i) = angle;
    end

    % ------------------------------------------------------------------ %
    % Trim to valid range (same approach as solveDamperTravel)
    % Here "valid" = any finite result; adjust if your pot has hard limits
    % ------------------------------------------------------------------ %
    validIdx = find(isfinite(potAngleDeg));

    if isempty(validIdx)
        error('solveRotaryPotTravel: no valid pot angles computed.');
    end

    idxMin = validIdx(1);
    idxMax = validIdx(end);

    thetaOut    = (thetaSweep(idxMin:idxMax) - datumPosition)';
    potAngleOut = potAngleDeg(idxMin:idxMax);

    [~, rh0] = min(abs(thetaOut));

    % ------------------------------------------------------------------ %
    % Store results
    % ------------------------------------------------------------------ %
    vehicle.(mfr).kinematics.(axle).Pot.angle          = potAngleOut;
    vehicle.(mfr).kinematics.(axle).Pot.thetaL         = thetaOut;
    vehicle.(mfr).kinematics.(axle).Pot.thetaL_0Index  = rh0;
    vehicle.(mfr).kinematics.(axle).Pot.pivotPoint     = pivotPoint;
    vehicle.(mfr).kinematics.(axle).Pot.armPickup      = armPickup;
    vehicle.(mfr).kinematics.(axle).Pot.rotatedTips    = rotatedTips(idxMin:idxMax, :);

    if debug >= 1
        fprintf('\n=== Rotary Pot Summary [%s %s] ===\n', upper(mfr), upper(axle));
        fprintf('Arm length:         %.2f mm\n', armLen);
        fprintf('Angle range:        %.2f to %.2f deg\n', min(potAngleOut), max(potAngleOut));
        fprintf('thetaL range:       %.4f to %.4f rad\n', thetaOut(1), thetaOut(end));
        fprintf('Ride-height index:  %d\n', rh0);
        fprintf('====================================\n\n');
    end

    % ------------------------------------------------------------------ %
    % Voltage conversion helper — printed to console
    % ------------------------------------------------------------------ %
    fprintf('[%s %s] Rotary pot solved. Voltage -> damper workflow:\n', upper(mfr), upper(axle));
    fprintf('  1. Calibrate: angle_deg = (V - V_rh) * degs_per_volt\n');
    fprintf('  2. Look up:   damperDisp = interp1(Pot.angle, potToDamperLUT.damperDisp, angle_deg)\n');
    fprintf('  Pot.angle zeroed at ride height (index %d).\n\n', rh0);

    % ------------------------------------------------------------------ %
    % Optional plot
    % ------------------------------------------------------------------ %
    if doPlot
        wt = vehicle.(mfr).kinematics.(axle).camberSweep.wheelTravel(:, 3);
        tL = vehicle.(mfr).kinematics.(axle).camberSweep.thetaL;

        potOnWt = interp1(thetaOut, potAngleOut, tL, 'linear', NaN);

        figure('Name', sprintf('Rotary Pot — %s %s', upper(mfr), upper(axle)), ...
               'Position', [100 100 900 380]);

        subplot(1, 2, 1);
        plot(wt, potOnWt, 'b-', 'LineWidth', 2);
        hold on;
        xline(0, '--k');
        [~, wRH] = min(abs(wt));
        plot(wt(wRH), potOnWt(wRH), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
        hold off;
        xlabel('Wheel Travel [mm]');
        ylabel('Pot Angle [deg]');
        title(sprintf('%s Rotary Pot Angle vs Wheel Travel', upper(axle)));
        grid on;

        subplot(1, 2, 2);
        potGain = gradient(potOnWt, wt);
        plot(wt, potGain, 'r-', 'LineWidth', 2);
        hold on; xline(0, '--k'); hold off;
        xlabel('Wheel Travel [mm]');
        ylabel('Pot Gain [deg/mm]');
        title('Pot Gain vs Wheel Travel');
        grid on;
    end
end