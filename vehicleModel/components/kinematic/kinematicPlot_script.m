frontToeSweep      = vehicle.ford.kinematics.front.toeSweep;
frontCamberResults = vehicle.ford.kinematics.front.camberSweep;
rearCamberResults  = vehicle.ford.kinematics.rear.camberSweep;
rearToeResults     = solveWheelToe(vehicle, 'axle', 'rear', 'manufacturer', 'ford', 'isSteeringAngle', false);

frontWheelTravel    = vehicle.ford.kinematics.front.camberSweep.wheelTravel;
rearWheelTravel     = vehicle.ford.kinematics.rear.camberSweep.wheelTravel;
frontSteeringDisp   = frontToeSweep.steeringRackDisplacement;
frontToeMatrix      = frontToeSweep.toe;  % 101x100 [wheelTravel x steeringSteps]

[~, zeroSteerIndex]   = min(abs(frontSteeringDisp));
[~, zeroTravelIndex]  = min(abs(frontWheelTravel(:,3)));

% --- Colors ---
frontColor = [0.0, 0.4470, 0.7410];
rearColor  = [0.8500, 0.3250, 0.0980];

%% Create Figure
figure('Position', [100, 100, 1400, 800]);

% Subplot 1: Toe vs Wheel Travel - Front Surface Plot
subplot(2, 3, 1);
surf(frontWheelTravel(:,3), frontSteeringDisp, frontToeMatrix', 'EdgeColor', 'none');
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
plot(frontWheelTravel(:,3), frontToeMatrix(:, zeroSteerIndex), 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front');
plot(rearWheelTravel(:,3), rearToeResults.toe, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Toe Angle [deg]');
title('Toe vs Wheel Travel (Zero Steering)');
legend('Location', 'best');
grid on;
hold off;

% Subplot 3: Camber vs Wheel Travel
subplot(2, 3, 3);
hold on;
plot(frontCamberResults.wheelTravel(:,3), frontCamberResults.camber, 'LineWidth', 0.5, 'Color', frontColor, 'DisplayName', 'Front');
plot(frontCamberResults.wheelTravel(:,3), frontCamberResults.camberCorrected, 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front Corrected');
plot(rearCamberResults.wheelTravel(:,3),  rearCamberResults.camber, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear');
xlabel('Wheel Travel [mm]');
ylabel('Camber Angle [deg]');
title('Camber vs Wheel Travel');
legend('Location', 'best');
grid on;
hold off;

% Subplot 4: Toe vs Steering Rack Travel at Zero Wheel Travel
subplot(2, 3, 4);
plot(frontSteeringDisp, frontToeMatrix(:, zeroTravelIndex), 'LineWidth', 2, 'Color', frontColor);
xlabel('Steering Rack Displacement [mm]');
ylabel('Toe Angle [deg]');
ylim([-5,5])
title('Front Toe vs Steering (at Ride Height)');
grid on;

% Subplot 5: Anti-Dive/Squat vs Wheel Travel
subplot(2, 3, 5);
hold on;
plot(frontWheelTravel(:,3), 50 * ones(size(frontWheelTravel)), '--', 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front Anti-Dive');
plot(rearWheelTravel(:,3), vehicle.(manufacturer).kinematics.rear.antiDive, '--', 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear Anti-Squat');
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
plot(frontWheelTravel(:,3), 50 + 0.1 * frontWheelTravel(:,3), 'LineWidth', 2, 'Color', frontColor, 'DisplayName', 'Front RC Height');
plot(rearWheelTravel(:,3), vehicle.(manufacturer).kinematics.rear.RC_height_array, 'LineWidth', 2, 'Color', rearColor, 'DisplayName', 'Rear RC Height');
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

plotToeRodSweep(vehicle)
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