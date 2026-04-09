clear; clc; close all;

%% Define pickup points (using your naming convention)

% Shim offsets
clevisOriginOffset = [0, 0, 0];
nominalCamberShim = [0, 6.6, 0];
clevisShimOffsetUFA = [0, 9, 0];
clevisShimOffsetUAA = [0, 9, 0];
clevisShimOffsetLFA = [0, 9, 0];
clevisShimOffsetLAA = [0, 9, 0];
uprightConnector = [0, 82.5, 0];
GEN3_KinematicParameters

% Upper A-Arm
params.upperAArm.fore = vehicle.ford.kinematics.rear.upperAArm.fore;
params.upperAArm.aft = vehicle.ford.kinematics.rear.upperAArm.aft;
params.upperAArm.ballJoint = vehicle.ford.kinematics.rear.upperAArm.ballJoint;

% Lower A-Arm
params.lowerAArm.fore = vehicle.ford.kinematics.rear.lowerAArm.fore + clevisOriginOffset;
params.lowerAArm.aft = vehicle.ford.kinematics.rear.lowerAArm.aft + clevisOriginOffset;
params.lowerAArm.ballJoint = vehicle.ford.kinematics.rear.lowerAArm.ballJoint;

% Toe Rod
toeRodParams.chassis = vehicle.ford.kinematics.rear.lowerAArm.toeRodUpright;
toeRodParams.upright = vehicle.ford.kinematics.rear.lowerAArm.toeRodChassis;

% Wheel Center (adjust to your actual value)
% This should be on the spindle axis, at known offset from ball joints
params.wheelCenter = vehicle.ford.kinematics.rear.upright.rotationAxis;  % <-- UPDATE THIS

%% Step 1: Solve camber
fprintf('Solving camber...\n');
camberResults = solveWheelCamber(params, []);

%% Step 2: Solve toe
fprintf('Solving toe...\n');
toeResults = solveWheelToe(camberResults, toeRodParams);

%% Step 3: Apply toe offset correction for upright geometry
fprintf('Applying toe offset correction...\n');

% Find ride height index
[~, idx_ride] = min(abs(camberResults.wheelTravel));

% Define upright geometry for correction
uprightGeometry.pickupPlaneOrigin = params.lowerAArm.ballJoint(:);  % LBJ at ride height
uprightGeometry.wheelCenter = params.wheelCenter(:);                % Actual wheel center
uprightGeometry.KPI_axis = camberResults.KPI_axis(idx_ride, :)';   % KPI axis at ride height

% Calculate the geometric toe offset
toe_offset = calculateInitialToeOffset_inline(uprightGeometry);

% Apply correction - create new field with corrected values
toeResults.correctedToe = toeResults.toe + toe_offset;
toeResults.toeOffsetApplied = toe_offset;

fprintf('  Toe offset applied: %+.4f deg\n', toe_offset);

%% Display results
fprintf('\n============================================\n');
fprintf('         KINEMATICS RESULTS                \n');
fprintf('============================================\n\n');

fprintf('--- At Ride Height ---\n');
fprintf('  Wheel Travel: %.2f mm\n', camberResults.wheelTravel(idx_ride));
fprintf('  Camber:       %+.3f deg\n', camberResults.camber(idx_ride));
fprintf('  Camber Gain:  %+.4f deg/mm\n', camberResults.camberGain(idx_ride));
fprintf('  Toe (uncorrected):  %+.3f deg\n', toeResults.toe(idx_ride));
fprintf('  Toe (corrected):    %+.3f deg\n', toeResults.correctedToe(idx_ride));
fprintf('  Toe Gain:           %+.4f deg/mm\n', toeResults.toeGain(idx_ride));

fprintf('\n--- Link Lengths ---\n');
fprintf('  Upright:  %.2f mm\n', camberResults.L_upright);
fprintf('  Toe Rod:  %.2f mm\n', toeResults.toeRodLength);

%% Plot camber results
figure('Name', 'Camber Kinematics', 'Position', [100, 100, 1000, 400]);

subplot(1, 2, 1);
plot(camberResults.wheelTravel, camberResults.camber, 'b-', 'LineWidth', 2);
hold on;
plot(camberResults.wheelTravel(idx_ride), camberResults.camber(idx_ride), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
grid on;
xlabel('Wheel Travel [mm]');
ylabel('Camber [deg]');
title('Camber vs Wheel Travel');
xline(0, '--k');

subplot(1, 2, 2);
plot(camberResults.wheelTravel, camberResults.camberGain, 'b-', 'LineWidth', 2);
hold on;
plot(camberResults.wheelTravel(idx_ride), camberResults.camberGain(idx_ride), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
grid on;
xlabel('Wheel Travel [mm]');
ylabel('Camber Gain [deg/mm]');
title('Camber Gain vs Wheel Travel');
xline(0, '--k');

sgtitle('Camber Analysis');

%% Plot toe results (if valid)
if ~all(isnan(toeResults.toe))
    figure('Name', 'Toe Kinematics', 'Position', [150, 150, 1000, 800]);
    
    % Corrected toe
    subplot(2, 2, 1);
    plot(camberResults.wheelTravel, toeResults.correctedToe, 'r-', 'LineWidth', 2);
    hold on;
    plot(camberResults.wheelTravel(idx_ride), toeResults.correctedToe(idx_ride), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
    grid on;
    xlabel('Wheel Travel [mm]');
    ylabel('Toe [deg]');
    title('Toe vs Wheel Travel (Corrected)');
    xline(0, '--k');
    
    % Toe gain (unchanged)
    subplot(2, 2, 2);
    plot(camberResults.wheelTravel, toeResults.toeGain, 'r-', 'LineWidth', 2);
    hold on;
    plot(camberResults.wheelTravel(idx_ride), toeResults.toeGain(idx_ride), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
    grid on;
    xlabel('Wheel Travel [mm]');
    ylabel('Toe Gain [deg/mm]');
    title('Toe Gain vs Wheel Travel');
    xline(0, '--k');
    
    % Comparison: uncorrected vs corrected
    subplot(2, 2, 3);
    plot(camberResults.wheelTravel, toeResults.toe, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Uncorrected');
    hold on;
    plot(camberResults.wheelTravel, toeResults.correctedToe, 'r-', 'LineWidth', 2, 'DisplayName', 'Corrected');
    plot(camberResults.wheelTravel(idx_ride), toeResults.correctedToe(idx_ride), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
    grid on;
    xlabel('Wheel Travel [mm]');
    ylabel('Toe [deg]');
    title('Comparison: Uncorrected vs Corrected');
    legend('Location', 'best');
    xline(0, '--k');
    
    % Offset applied (constant)
    subplot(2, 2, 4);
    plot(camberResults.wheelTravel, ones(size(camberResults.wheelTravel)) * toe_offset, 'k-', 'LineWidth', 2);
    hold on;
    plot(camberResults.wheelTravel(idx_ride), toe_offset, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    grid on;
    xlabel('Wheel Travel [mm]');
    ylabel('Offset Applied [deg]');
    title(sprintf('Toe Offset = %+.4f deg (constant)', toe_offset));
    xline(0, '--k');
    ylim([toe_offset - 0.5, toe_offset + 0.5]);
    
    sgtitle('Toe Analysis with Upright Geometry Correction');
else
    warning('Toe solution invalid - check toe rod geometry');
end

%% 3D Visualization
figure('Name', '3D Geometry', 'Position', [200, 200, 900, 700]);
hold on; grid on; axis equal;
view(135, 25);


%% ========================================================================
%  HELPER FUNCTION - Inline version of calculateInitialToeOffset
%  ========================================================================

function [initial_toe_offset] = calculateInitialToeOffset_inline(uprightGeometry)
% Calculates the toe offset due to upright geometry
% Inline version to avoid external dependencies

%% Extract inputs
P_pickup = uprightGeometry.pickupPlaneOrigin(:);  % Origin of pickup plane
P_wheel = uprightGeometry.wheelCenter(:);         % Wheel center
w_hat = uprightGeometry.KPI_axis(:);              % KPI axis (unit vector)

% Ensure unit vector
w_hat = w_hat / norm(w_hat);

%% Calculate offset vector
offset = P_wheel - P_pickup;

%% Decompose offset relative to KPI axis
offset_parallel = dot(offset, w_hat) * w_hat;
offset_perp = offset - offset_parallel;

%% Project perpendicular offset onto vehicle axes
% Vehicle longitudinal axis (forward direction)
x_vehicle = [1; 0; 0];

% Make perpendicular to KPI
x_vehicle_perp = x_vehicle - dot(x_vehicle, w_hat) * w_hat;
if norm(x_vehicle_perp) < 1e-6
    % KPI is nearly vertical, use different reference
    x_vehicle_perp = [0; 1; 0] - dot([0; 1; 0], w_hat) * w_hat;
end
x_vehicle_perp = x_vehicle_perp / norm(x_vehicle_perp);

% Vehicle lateral axis (perpendicular to both KPI and longitudinal)
y_vehicle_perp = cross(w_hat, x_vehicle_perp);
y_vehicle_perp = y_vehicle_perp / norm(y_vehicle_perp);

% Project offset onto these axes
offset_longitudinal = dot(offset_perp, x_vehicle_perp);
offset_lateral = dot(offset_perp, y_vehicle_perp);

%% Calculate the angular offset
initial_toe_offset = atan2d(offset_lateral, offset_longitudinal);

%% Display information
fprintf('\n');
fprintf('--- Toe Offset Calculation ---\n');
fprintf('  Pickup origin:      [%.2f, %.2f, %.2f] mm\n', P_pickup);
fprintf('  Wheel center:       [%.2f, %.2f, %.2f] mm\n', P_wheel);
fprintf('  Offset vector:      [%.2f, %.2f, %.2f] mm\n', offset);
fprintf('  Perpendicular:      [%.2f, %.2f, %.2f] mm\n', offset_perp);
fprintf('  Longitudinal comp:  %.2f mm\n', offset_longitudinal);
fprintf('  Lateral comp:       %.2f mm\n', offset_lateral);
fprintf('  Toe offset:         %+.4f deg\n', initial_toe_offset);
fprintf('\n');

end
