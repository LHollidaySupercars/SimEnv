%% initiation script for kinematic analysis
%% Current kinematic logic requires the execution of the GEN3_KinematicParameters file
% % Not doing so will result in continuous offsets, if excecuting scripts multiple times
clear all; close all
manufacturer = 'ford'
axle = 'rear'
fprintf('Loading Kinematic properties...\n');


GEN3_KinematicParameters
POS = containers.Map();
vehicle.ford.kinematics.rear.upperAArm.uprightBalljointAdjust
axle = 'front'
%% Shim Enquiry
%% ============================== FRONT ==================================
% Upright Positions
POS('FRONT_UBJ_UPRIGHT_POS') = 3;


POS('FLF_POS') = 3;
Clevis = 'ford.kinematics.front.lowerAArm.fore';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FLA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.lowerAArm.aft';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FUF_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.upperAArm.fore';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FUA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.upperAArm.aft';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
%% ============================== REAR ==================================
POS('REAR_UBJ_UPRIGHT_POS') = 3;


axle = 'rear'
original = vehicle.ford.kinematics.rear.upperAArm.fore;
POS('RLF_POS') = 3;
Clevis = 'ford.kinematics.rear.lowerAArm.fore';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RLA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.lowerAArm.aft';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RUF_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.upperAArm.fore';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RUA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.upperAArm.aft';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle);
%%

vehicle = clevisPOSOffset(vehicle, manufacturer, POS, axle);

assumedLinearRackDisplacement = [-pi, pi] * vehicle.ford.steering.ratio;
vehicle.ford.kinematics.rear.upperAArm.fore - original
%% Ford initialization

fprintf('Initializing Rear Kinematic sweep...\n');
fprintf('Initializing Rear Camber...\nApplying Correction to Starting Point');
shims = [1, 1, 0];


%% Rear Compensation Section
%% Upper A-Arm Compensation
fprintf('Initializing A-Arm Compensation...\n');
radiiOffset = rearAArmCompensation(vehicle, manufacturer, axle, shims, 'CAD_ERROR', true); % in plane radius increase

[vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJoint, ~] = threeSphereUpperAArm(vehicle, 'ford', 'newRadii', radiiOffset, 'plotResults', true)
fprintf('Completed A-Arm Compensation...\n');
%% UBJ Compensation ( requires writing )
fprintf('Initializing UBJ to LBJ Length Compensation...\n');
radiiOffset = getOffset(vehicle, manufacturer, POS, axle)
[vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJoint, ~] = threeSphereUpperAArm(vehicle, 'ford', 'newRadii', radiiOffset, 'plotResults', true, 'geometrySystem', 'extendUBJ');
fprintf('Completed UBJ to LBJ Length Correction...\n');
%% Static Camber Compensation
fprintf('Initializing Rear Camber sweep...\n');
vehicle.(manufacturer).kinematics.(axle).camberSweep = solveWheelCamber(vehicle, 'manufacturer', 'ford', 'axle', axle);
fprintf('Completed rear camber sweep...\n');
%% Toe Sweep
fprintf('Initializing toe sweep...\n');
vehicle.(manufacturer).kinematics.(axle).toeSweep = solveWheelToe(vehicle, 'manufacturer', 'ford', 'axle', axle);
fprintf('Completed toe sweep...\n');

%% Roll Centre Calculation
fprintf('Initializing Roll Centre Sweep...\n');
[vehicle.(manufacturer).kinematics.(axle).RC_height_array, vehicle.ford.kinematics.dRC_dz_nominal] =  calculateRollCenter(vehicle, 'manufacturer', 'ford', 'Plotting', true)
fprintf('Initializing Roll Centre Sweep...\n');

fprintf('Initializing Anti Geometry Sweep...\n');
vehicle.(manufacturer).kinematics.(axle).antiDive = calculateAntiGeometry(vehicle);
fprintf('Initializing Anti Geometry Sweep...\n');

%% Front section
manufacturer = 'ford';
axle = 'front';
fprintf('Loading front Kinematic properties...\n');
assumedLinearRackDisplacement = [-pi, pi] * vehicle.ford.steering.ratio;

fprintf('Loading front Kinematic properties...\n');
assumedLinearRackDisplacement = [-pi, pi] * vehicle.ford.steering.ratio;
%%

fprintf('Initializing front Kinematic sweep...\n');
fprintf('Initializing front camber sweep...\n');
vehicle.(manufacturer).kinematics.(axle).camberSweep = solveWheelCamber(vehicle, 'manufacturer', 'ford', 'axle', axle);
fprintf('Completed front Camber sweep...\n');
%%

fprintf('Initializing camber sweep...\n');
vehicle.kinematics.front.camberShims_5219 = [0, 1.016, 0]; % CAD reference
vehicle.kinematics.front.camberShims_5220 = [0, 1.600, 0]; % CAD reference
vehicle.kinematics.front.camberShims_5221 = [0, 2.540, 0]; % CAD reference
vehicle.kinematics.front.camberShims_5222 = [0, 5.000, 0]; % CAD reference
% shims 1.016mm, 1.600mm 2.540mm 5.000mm
shims = [1, 1, 1, 0]; 


vehicle = camberOffset(vehicle, shims, manufacturer, axle);
fprintf('Completed Camber sweep...\n');
%% 
fprintf('Initializing toe sweep...\n');
vehicle.(manufacturer).kinematics.(axle).toeSweep = solveWheelToe(vehicle, 'manufacturer', 'ford', 'axle', axle, 'isSteeringAngle', true);
fprintf('Completed toe sweep...\n');

%%
fprintf('Initializing roll centre sweep...\n');
[vehicle.(manufacturer).kinematics.(axle).RC_height_array, vehicle.ford.kinematics.dRC_dz_nominal] =  calculateRollCenter(vehicle, 'manufacturer', 'ford')
fprintf('Initializing roll centre sweep...\n');
vehicle.(manufacturer).kinematics.(axle).antiDive = calculateAntiGeometry(vehicle);
% 
%%
%% Plotting Script for Suspension Kinematics
% This script creates a 2x3 grid of plots showing various suspension characteristics

% plotting the toe position

%% Plotting Script for Suspension Kinematics

% --- Extract All Data ---
frontToeSweep      = vehicle.ford.kinematics.front.toeSweep;
frontCamberResults = vehicle.ford.kinematics.front.camberSweep;
rearCamberResults  = vehicle.ford.kinematics.rear.camberSweep;
rearToeResults     = solveWheelToe(vehicle, 'axle', 'rear', 'manufacturer', 'ford', 'isSteeringAngle', false);

frontWheelTravel    = vehicle.ford.kinematics.front.camberSweep.wheelTravel;
rearWheelTravel     = vehicle.ford.kinematics.rear.camberSweep.wheelTravel;
frontSteeringDisp   = frontToeSweep.steeringRackDisplacement;
frontToeMatrix      = frontToeSweep.toe;  % 101x100 [wheelTravel x steeringSteps]

[~, zeroSteerIndex]   = min(abs(frontSteeringDisp));
[~, zeroTravelIndex]  = min(abs(frontWheelTravel));

% --- Colors ---
frontColor = [0.0, 0.4470, 0.7410];
rearColor  = [0.8500, 0.3250, 0.0980];

%% Create Figure
figure('Position', [100, 100, 1400, 800]);

% Subplot 1: Toe vs Wheel Travel - Front Surface Plot
subplot(2, 3, 1);
surf(frontWheelTravel, frontSteeringDisp, frontToeMatrix', 'EdgeColor', 'none');
xlabel('Wheel Travel [mm]');
ylabel('Steering Rack Displacement [mm]');
zlabel('Toe Angle [deg]');
title('Front Toe vs Wheel Travel & Steering');
colorbar;
view(45, 30);
grid on;

% Subplot 2: Toe vs Wheel Travel at Zero Steering
subplot(2, 3, 2);
hold on;
plot(frontWheelTravel, frontToeMatrix(:, zeroSteerIndex), 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front');
plot(rearWheelTravel, rearToeResults.toe, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Toe Angle [deg]');
title('Toe vs Wheel Travel (Zero Steering)');
legend('Location', 'best');
grid on;
hold off;

% Subplot 3: Camber vs Wheel Travel
subplot(2, 3, 3);
hold on;
plot(frontCamberResults.wheelTravel, frontCamberResults.camber, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front');
plot(frontCamberResults.wheelTravel, frontCamberResults.camberCorrected, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front Corrected');
plot(rearCamberResults.wheelTravel, rearCamberResults.camber, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Camber Angle [deg]');
title('Camber vs Wheel Travel');
legend('Location', 'best');
grid on;
hold off;

% Subplot 4: Toe vs Steering Rack Travel at Zero Wheel Travel
subplot(2, 3, 4);
plot(frontSteeringDisp, frontToeMatrix(zeroTravelIndex, :), 'LineWidth', 2, 'Color', frontColor);
xlabel('Steering Rack Displacement [mm]');
ylabel('Toe Angle [deg]');
title('Front Toe vs Steering (at Ride Height)');
grid on;

% Subplot 5: Anti-Dive/Squat vs Wheel Travel
subplot(2, 3, 5);
hold on;
plot(frontWheelTravel, 50 * ones(size(frontWheelTravel)), '--', 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front Anti-Dive');
plot(rearWheelTravel, vehicle.(manufacturer).kinematics.rear.antiDive, '--', 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear Anti-Squat');
xlabel('Wheel Travel [mm]');
ylabel('Anti-Geometry [%]');
title('Anti-Dive/Squat vs Wheel Travel');
legend('Location', 'best');
grid on;
ylim([0, 100]);
hold off;

% Subplot 6: Roll Center Height vs Wheel Travel
subplot(2, 3, 6);
hold on;
plot(frontWheelTravel, 50 + 0.1 * frontWheelTravel, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front RC Height');
plot(rearWheelTravel, vehicle.(manufacturer).kinematics.rear.RC_height_array, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear RC Height');
xlabel('Wheel Travel [mm]');
ylabel('Roll Center Height [mm]');
title('Roll Center Height vs Wheel Travel');
legend('Location', 'best');
grid on;
hold off;
%%
%% Gains Plotting Script

% --- Extract Gain Data ---
frontToeGain    = vehicle.ford.kinematics.front.toeSweep.toeGain;
rearToeGain     = rearToeResults.toeGain;
frontCamberGain = frontCamberResults.camberGain;
rearCamberGain  = rearCamberResults.camberGain;

frontWheelTravel = vehicle.ford.kinematics.front.camberSweep.wheelTravel;
rearWheelTravel  = vehicle.ford.kinematics.rear.camberSweep.wheelTravel;

% --- Colors ---
frontColor = [0.0, 0.4470, 0.7410];
rearColor  = [0.8500, 0.3250, 0.0980];

%% Create Figure
figure('Position', [100, 100, 1000, 500]);

% Subplot 1: Toe Gain vs Wheel Travel
subplot(1, 2, 1);
hold on;
plot(frontWheelTravel, frontToeGain, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front');
plot(rearWheelTravel, rearToeGain, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Toe Gain [deg/mm]');
title('Toe Gain vs Wheel Travel');
legend('Location', 'best');
grid on;
hold off;

% Subplot 2: Camber Gain vs Wheel Travel
subplot(1, 2, 2);
hold on;
plot(frontWheelTravel, frontCamberGain, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front');
plot(rearWheelTravel, rearCamberGain, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Camber Gain [deg/mm]');
title('Camber Gain vs Wheel Travel');
legend('Location', 'best');
grid on;
hold off;
%% Overall title
function plotToeRodSweep(vehicle)

sweep = vehicle.ford.kinematics.front.toeSweep;
uprightPositions  = sweep.uprightToeRod_new;
rackDisplacements = sweep.steeringRackDisplacement;

chassisToeRod_old = vehicle.ford.kinematics.front.lowerAArm.toeRodChassis;
chassisPositions  = chassisToeRod_old + rackDisplacements * [0, 1, 0];

LBJ = vehicle.ford.kinematics.front.lowerAArm.ballJoint;
UBJ = vehicle.ford.kinematics.front.upperAArm.ballJoint;
uprightToeRod_old = vehicle.ford.kinematics.front.lowerAArm.toeRodUpright;

figure; hold on;

colours = jet(size(rackDisplacements, 1));

for i = 1:size(rackDisplacements, 1)
    plot3(uprightPositions(i,1), uprightPositions(i,2), uprightPositions(i,3), 'o', 'MarkerSize', 4, 'Color', colours(i,:));
    plot3(chassisPositions(i,1), chassisPositions(i,2), chassisPositions(i,3), 's', 'MarkerSize', 3, 'Color', colours(i,:));
end

plot3(uprightPositions(:,1), uprightPositions(:,2), uprightPositions(:,3), 'k-', 'LineWidth', 0.8);
plot3(chassisPositions(:,1), chassisPositions(:,2), chassisPositions(:,3), 'k-', 'LineWidth', 0.8);

plot3(LBJ(1), LBJ(2), LBJ(3), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k');
plot3(UBJ(1), UBJ(2), UBJ(3), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k');
text(LBJ(1), LBJ(2), LBJ(3), '  LBJ', 'FontSize', 10);
text(UBJ(1), UBJ(2), UBJ(3), '  UBJ', 'FontSize', 10);

plot3(uprightToeRod_old(1), uprightToeRod_old(2), uprightToeRod_old(3), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
plot3(chassisToeRod_old(1), chassisToeRod_old(2), chassisToeRod_old(3), 'bs', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
text(uprightToeRod_old(1), uprightToeRod_old(2), uprightToeRod_old(3), '  Upright (old)', 'FontSize', 9, 'Color', 'b');
text(chassisToeRod_old(1), chassisToeRod_old(2), chassisToeRod_old(3), '  Chassis (old)', 'FontSize', 9, 'Color', 'b');

plot3([LBJ(1), uprightToeRod_old(1)], [LBJ(2), uprightToeRod_old(2)], [LBJ(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);
plot3([UBJ(1), uprightToeRod_old(1)], [UBJ(2), uprightToeRod_old(2)], [UBJ(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);
plot3([chassisToeRod_old(1), uprightToeRod_old(1)], [chassisToeRod_old(2), uprightToeRod_old(2)], [chassisToeRod_old(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);

colormap(jet);
caxis([min(rackDisplacements), max(rackDisplacements)]);
colorbar('Label', 'Rack Displacement (mm)');

axis equal; grid on;
xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
title('Steering Geometry - Toe Rod Sweep');

end

