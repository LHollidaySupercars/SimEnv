function vehicle = calculateAntiGeometry(vehicle, varargin)
    % CALCULATEANTIGEOMETRY  Computes anti-dive (front) and anti-squat (rear) percentage
    %                        swept across the full wheel travel range.
    %
    % Method (side-view, X-Z plane):
    %   1. Find the side-view Instant Centre (IC) by intersecting the upper and lower
    %      A-arm pivot lines projected into the X-Z plane. Chassis pivots are static.
    %   2. At each travel point, take the wheel centre from correctedContactPatch
    %      (populated by offsetInPerpendicularPlane with 'tyreCentre'). The rigid-tyre
    %      ground contact point sits directly below: same X, Z = 0.
    %   3. Anti% = [IC_z / (IC_x - contactPatch_x)] / [CoG_z / wheelbase] * 100
    %      Wheelbase derived from front/rear LBJ X positions at ride height.
    %
    % Inputs:
    %   vehicle       - vehicle struct (correctedContactPatch must be populated)
    %
    % Optional Parameters:
    %   'manufacturer' - default 'ford'
    %   'axle'         - 'front' | 'rear' | 'both'  (default 'both')
    %   'CoGHeight'    - Centre of gravity height [mm]  (default 300)
    %   'Plotting'     - true/false  (default false)

    p = inputParser;
    addRequired(p,  'vehicle');
    addParameter(p, 'manufacturer', 'ford');
    addParameter(p, 'axle',        'both');
    addParameter(p, 'CoGHeight',   300,   @isnumeric);
    addParameter(p, 'Plotting',    false, @islogical);
    parse(p, vehicle, varargin{:});

    mfr     = p.Results.manufacturer;
    axleArg = p.Results.axle;
    CoG_z   = p.Results.CoGHeight;
    doPlot  = p.Results.Plotting;

    % --- Derive wheelbase from ride-height LBJ X positions ---
    frontLBJ_x = vehicle.(mfr).kinematics.front.lowerAArm.ballJoint(1);
    rearLBJ_x  = vehicle.(mfr).kinematics.rear.lowerAArm.ballJoint(1);
    wheelbase  = abs(frontLBJ_x - rearLBJ_x);
    fprintf('Wheelbase derived from LBJ X positions: %.1f mm\n', wheelbase);

    % --- Process requested axles ---
    if strcmp(axleArg, 'both')
        axles = {'front', 'rear'};
    else
        axles = {axleArg};
    end

    for a = 1:length(axles)
        vehicle = processAxle(vehicle, mfr, axles{a}, CoG_z, wheelbase, doPlot);
    end
end


% =========================================================================
function vehicle = processAxle(vehicle, mfr, axle, CoG_z, wheelbase, doPlot)
% =========================================================================

    kin = vehicle.(mfr).kinematics.(axle);

    % --- Side-view IC: intersect upper and lower A-arm lines in X-Z ---
    % Each A-arm defines a line through its two chassis pivot points.
    % Slopes in the X-Z (side view) plane.
    mUpper = (kin.upperAArm.fore(3) - kin.upperAArm.aft(3)) / ...
             (kin.upperAArm.fore(1) - kin.upperAArm.aft(1));
    bUpper =  kin.upperAArm.fore(3) - mUpper * kin.upperAArm.fore(1);

    mLower = (kin.lowerAArm.fore(3) - kin.lowerAArm.aft(3)) / ...
             (kin.lowerAArm.fore(1) - kin.lowerAArm.aft(1));
    bLower =  kin.lowerAArm.fore(3) - mLower * kin.lowerAArm.fore(1);

    % --- Check for parallel A-arms (IC at infinity = 0% anti) ---
    parallelThreshold = 1e-6;
    armsParallel = abs(mLower - mUpper) < parallelThreshold;

    if armsParallel
        fprintf('[%s] A-arms parallel in side view — IC at infinity — 0%% anti geometry\n', upper(axle));
        IC_x = Inf;
        IC_z = 0;
    else
        IC_x = (bUpper - bLower) / (mLower - mUpper);
        IC_z = mLower * IC_x + bLower;
        fprintf('[%s] Side-view IC:  X = %.1f mm,  Z = %.1f mm\n', upper(axle), IC_x, IC_z);
    end

    % --- Wheel centre X sweep from correctedContactPatch ---
    contactPatch   = kin.correctedContactPatch(:, 1:3);
    contactPatch_x = contactPatch(:, 1);

    wheelTravel = kin.camberSweep.wheelTravel(:, 3);
    n_points    = length(wheelTravel);

    % --- Anti % across sweep ---
    % Rigid tyre: contact patch at (wheelCentre_x, Z=0).
    % Anti% = (IC_z / (IC_x - cp_x)) / (CoG_z / wheelbase) * 100
    % Special case: parallel arms -> IC at infinity -> 0%

    antiPercent  = zeros(n_points, 1);
    weight_slope = CoG_z / wheelbase;

    if armsParallel
        fprintf('[%s] Anti %% at ride height: 0.0%% (parallel arms)\n', upper(axle));
        vehicle.(mfr).kinematics.(axle).antiGeometry.percent     = antiPercent;
        vehicle.(mfr).kinematics.(axle).antiGeometry.IC_x        = IC_x;
        vehicle.(mfr).kinematics.(axle).antiGeometry.IC_z        = IC_z;
        vehicle.(mfr).kinematics.(axle).antiGeometry.wheelTravel = wheelTravel;
        vehicle.(mfr).kinematics.(axle).antiGeometry.CoG_z       = CoG_z;
        vehicle.(mfr).kinematics.(axle).antiGeometry.wheelbase   = wheelbase;
        vehicle.(mfr).kinematics.(axle).antiDive                 = antiPercent;
        vehicle.(mfr).kinematics.(axle).antiDive_array           = antiPercent;
        return;
    end

    for i = 1:n_points
        dx = IC_x - contactPatch_x(i);
        if abs(dx) < 1e-6
            antiPercent(i) = NaN;
            continue;
        end
        IC_slope       = IC_z / dx;
        antiPercent(i) = (IC_slope / weight_slope) * 100;
    end

    % --- Store results ---
    vehicle.(mfr).kinematics.(axle).antiGeometry.percent     = antiPercent;
    vehicle.(mfr).kinematics.(axle).antiGeometry.IC_x        = IC_x;
    vehicle.(mfr).kinematics.(axle).antiGeometry.IC_z        = IC_z;
    vehicle.(mfr).kinematics.(axle).antiGeometry.wheelTravel = wheelTravel;
    vehicle.(mfr).kinematics.(axle).antiGeometry.CoG_z       = CoG_z;
    vehicle.(mfr).kinematics.(axle).antiGeometry.wheelbase   = wheelbase;

    % Legacy field names — existing plot code uses these
    vehicle.(mfr).kinematics.(axle).antiDive       = antiPercent;
    vehicle.(mfr).kinematics.(axle).antiDive_array = antiPercent;

    [~, rh_idx] = min(abs(wheelTravel));
    fprintf('[%s] Anti %% at ride height: %.1f%%\n', upper(axle), antiPercent(rh_idx));

    % --- Optional plot ---
    if doPlot
        figure('Name', sprintf('Anti Geometry - %s %s', upper(mfr), upper(axle)), ...
               'Position', [100 100 1000 420]);

        % Left: anti% vs wheel travel
        subplot(1, 2, 1);
        plot(wheelTravel, antiPercent, 'LineWidth', 2);
        hold on;
        yline(antiPercent(rh_idx), '--r', sprintf('RH: %.1f%%', antiPercent(rh_idx)), ...
              'LabelHorizontalAlignment', 'left');
        xline(0, '--k');
        hold off;
        xlabel('Wheel Travel [mm]');
        ylabel('Anti [%]');
        title(sprintf('%s Anti Geometry %%', upper(axle)));
        grid on;

        % Right: side-view geometry diagram at ride height
        subplot(1, 2, 2);
        LBJ_rh = kin.camberSweep.LBJ(rh_idx, :);
        UBJ_rh = kin.camberSweep.UBJ(rh_idx, :);
        cp_x_rh = contactPatch_x(rh_idx);

        hold on; grid on;
        % Ground line
        x_range = [min([kin.lowerAArm.fore(1), kin.upperAArm.fore(1), cp_x_rh, IC_x]) - 50, ...
                   max([kin.lowerAArm.fore(1), kin.upperAArm.fore(1), cp_x_rh, IC_x]) + 50];
        plot(x_range, [0 0], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');

        % A-arm lines extended to IC
        plot([kin.lowerAArm.fore(1), IC_x], [kin.lowerAArm.fore(3), IC_z], 'b--', 'LineWidth', 1);
        plot([kin.lowerAArm.aft(1),  IC_x], [kin.lowerAArm.aft(3),  IC_z], 'b--', 'LineWidth', 1, 'HandleVisibility', 'off');
        plot([kin.upperAArm.fore(1), IC_x], [kin.upperAArm.fore(3), IC_z], 'r--', 'LineWidth', 1);
        plot([kin.upperAArm.aft(1),  IC_x], [kin.upperAArm.aft(3),  IC_z], 'r--', 'LineWidth', 1, 'HandleVisibility', 'off');

        % Upright
        plot([LBJ_rh(1), UBJ_rh(1)], [LBJ_rh(3), UBJ_rh(3)], 'k-', 'LineWidth', 2.5);

        % Anti line: contact patch → IC
        plot([cp_x_rh, IC_x], [0, IC_z], 'm-', 'LineWidth', 2);

        % Key points
        plot(IC_x,    IC_z, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
        plot(cp_x_rh, 0,    'gs', 'MarkerFaceColor', 'g', 'MarkerSize', 8);

        xlabel('X [mm]'); ylabel('Z [mm]');
        title(sprintf('%s Side-View at Ride Height', upper(axle)));
        legend('Lower arm (to IC)', 'Upper arm (to IC)', 'Upright', 'Anti line', ...
               'IC', 'Contact patch', 'Location', 'best');
        axis equal; hold off;
    end
end