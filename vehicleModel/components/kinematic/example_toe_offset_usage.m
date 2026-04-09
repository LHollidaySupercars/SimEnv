% EXAMPLE: How to use the toe offset correction
%
% This example shows how to integrate the toe offset correction into your
% existing workflow with solveWheelCamber and solveWheelToe.

clear; clc;

%% Step 1: Run your existing kinematic solvers
% (This is your existing workflow - just showing structure)

% Define your suspension geometry
% camberParams = struct(...);
% toeRodParams = struct(...);

% Solve camber
% camberResults = solveWheelCamber(camberParams);

% Solve toe (using existing method)
% toeResults = solveWheelToe(camberResults, toeRodParams);

% At this point, toeResults.toe has the correct GRADIENT but wrong ABSOLUTE value

%% Step 2: Define the upright geometry offset
% This is the NEW information you need to provide

uprightGeometry = struct();

% Origin point in the pickup plane (typically the LBJ at ride height)
% This should match what you use as reference in your kinematic solver
uprightGeometry.pickupPlaneOrigin = [0; 730; 80];  % [x, y, z] in mm

% Actual wheel center position
% This is offset from the pickup plane by the upright geometry
uprightGeometry.wheelCenter = [0; 750; 200];  % [x, y, z] in mm

% KPI axis at ride height (from your camber results)
% This is the unit vector along the kingpin axis
% You can get this from: camberResults.KPI_axis(ride_height_index, :)
uprightGeometry.KPI_axis = [-0.0342; -0.0872; 0.9957];  % Example values

% NOTE: If you don't have the exact KPI axis, you can approximate it as:
% KPI_axis = (UBJ - LBJ) / norm(UBJ - LBJ)
% using the positions at ride height

%% Step 3: Apply the correction
% This is a simple one-liner that adds the offset

% toeResults_corrected = applyToeOffsetCorrection(toeResults, uprightGeometry);

%% Example with dummy data to show the concept
fprintf('========================================\n');
fprintf('EXAMPLE DEMONSTRATION\n');
fprintf('========================================\n\n');

% Create dummy toe results (like what solveWheelToe would give you)
wheelTravel = -50:5:50;  % mm
nPoints = length(wheelTravel);

toeResults_dummy = struct();
toeResults_dummy.toe = 122.2 + (-0.1226) * wheelTravel;  % Your actual values from image
toeResults_dummy.toeGain = -0.1226 * ones(nPoints, 1);
toeResults_dummy.phi = zeros(nPoints, 1);  % Dummy
toeResults_dummy.toeRodUprightPos = zeros(nPoints, 3);  % Dummy

fprintf('BEFORE CORRECTION:\n');
fprintf('  Toe at ride height: %.3f deg\n', toeResults_dummy.toe(wheelTravel == 0));
fprintf('  Toe gain:           %.4f deg/mm\n', toeResults_dummy.toeGain(1));
fprintf('\n');

% Apply correction
toeResults_corrected = applyToeOffsetCorrection(toeResults_dummy, uprightGeometry);

fprintf('AFTER CORRECTION:\n');
fprintf('  Toe at ride height: %.3f deg\n', toeResults_corrected.toe(wheelTravel == 0));
fprintf('  Toe gain:           %.4f deg/mm (unchanged)\n', toeResults_corrected.toeGain(1));
fprintf('\n');

%% Visualization
figure('Position', [100 100 1200 500]);

% Plot uncorrected vs corrected
subplot(1,2,1);
plot(wheelTravel, toeResults_dummy.toe, 'r--', 'LineWidth', 2, 'DisplayName', 'Uncorrected');
hold on;
plot(wheelTravel, toeResults_corrected.toe, 'b-', 'LineWidth', 2, 'DisplayName', 'Corrected');
plot(0, toeResults_corrected.toe(wheelTravel == 0), 'ko', 'MarkerSize', 10, ...
    'MarkerFaceColor', 'g', 'DisplayName', 'Ride Height');
grid on;
xlabel('Wheel Travel [mm]');
ylabel('Toe Angle [deg]');
title('Toe vs Wheel Travel');
legend('Location', 'best');
set(gca, 'FontSize', 11);

% Plot toe gain (unchanged)
subplot(1,2,2);
plot(wheelTravel, toeResults_dummy.toeGain, 'b-', 'LineWidth', 2);
grid on;
xlabel('Wheel Travel [mm]');
ylabel('Toe Gain [deg/mm]');
title('Toe Gain (Unchanged by Correction)');
set(gca, 'FontSize', 11);
ylim([min(toeResults_dummy.toeGain)*1.2, max(toeResults_dummy.toeGain)*1.2]);

%% How to integrate into your workflow

fprintf('\n========================================\n');
fprintf('INTEGRATION INTO YOUR WORKFLOW:\n');
fprintf('========================================\n\n');

fprintf('1. Run your existing solvers:\n');
fprintf('   camberResults = solveWheelCamber(camberParams);\n');
fprintf('   toeResults = solveWheelToe(camberResults, toeRodParams);\n\n');

fprintf('2. Define upright geometry (ONCE, as part of your car setup):\n');
fprintf('   uprightGeometry.pickupPlaneOrigin = [x_LBJ, y_LBJ, z_LBJ];\n');
fprintf('   uprightGeometry.wheelCenter = [x_wheel, y_wheel, z_wheel];\n');
fprintf('   uprightGeometry.KPI_axis = camberResults.KPI_axis(ride_idx, :);\n\n');

fprintf('3. Apply correction:\n');
fprintf('   toeResults = applyToeOffsetCorrection(toeResults, uprightGeometry);\n\n');

fprintf('4. Use corrected results:\n');
fprintf('   - toeResults.toe now has correct absolute values\n');
fprintf('   - toeResults.toeGain is unchanged (was already correct)\n\n');

%% What you need to measure/provide

fprintf('========================================\n');
fprintf('WHAT YOU NEED TO PROVIDE:\n');
fprintf('========================================\n\n');

fprintf('For the uprightGeometry struct, you need:\n\n');

fprintf('1. pickupPlaneOrigin (reference point):\n');
fprintf('   - Typically use LBJ position at ride height\n');
fprintf('   - Should match what your kinematic solver uses as reference\n');
fprintf('   - Get from: camberResults.LBJ(ride_height_index, :)\n\n');

fprintf('2. wheelCenter (actual wheel center):\n');
fprintf('   - [x, y, z] position of wheel center at ride height\n');
fprintf('   - This is the "true" wheel position in vehicle coordinates\n');
fprintf('   - Offset from pickup plane by upright geometry\n\n');

fprintf('3. KPI_axis (kingpin axis direction):\n');
fprintf('   - Unit vector from LBJ to UBJ at ride height\n');
fprintf('   - Get from: camberResults.KPI_axis(ride_height_index, :)\n');
fprintf('   - Or calculate: (UBJ - LBJ) / norm(UBJ - LBJ)\n\n');

%% Physical interpretation

fprintf('========================================\n');
fprintf('PHYSICAL INTERPRETATION:\n');
fprintf('========================================\n\n');

fprintf('The offset exists because:\n');
fprintf('  - Your kinematic solver tracks the UBJ, LBJ, toe rod pickups\n');
fprintf('  - These are on the upright structure\n');
fprintf('  - The wheel center is offset from these pickup points\n');
fprintf('  - When measuring "toe", we care about wheel orientation, not pickup orientation\n\n');

fprintf('Example:\n');
fprintf('  If wheel center is 20mm outboard of the pickup plane,\n');
fprintf('  and 100mm behind the KPI axis, then there''s an effective\n');
fprintf('  toe angle even when the upright is "straight" in the pickup plane.\n\n');

fprintf('This correction accounts for that geometric offset.\n');
fprintf('The RATE of change (bump steer gradient) is still correct\n');
fprintf('because it depends on link geometry, not absolute position.\n\n');
