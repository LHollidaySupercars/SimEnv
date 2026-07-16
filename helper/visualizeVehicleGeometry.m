function visualizeVehicleGeometry(vehicle, manufacturer, varargin)
    % VISUALIZEVEHICLEGEOMETRY - Visualize suspension geometry with lines connecting pickup points
    %
    % Syntax:
    %   visualizeVehicleGeometry(vehicle, manufacturer)
    %   visualizeVehicleGeometry(vehicle, manufacturer, 'Heave', heave_value)
    %
    % Inputs:
    %   vehicle - Vehicle structure with all kinematics data
    %   manufacturer - Manufacturer name (e.g., 'ford')
    %
    % Optional Parameters:
    %   'Heave' - Wheel displacement from ride height [mm] (default: 0)
    %   'Steer' - Steering angle [deg] for front axle (default: 0)
    %   'Side' - 'left', 'right', or 'both' (default: 'both')
    
    % Parse inputs
    p = inputParser;
    addRequired(p, 'vehicle');
    addRequired(p, 'manufacturer');
    addParameter(p, 'Heave', 0);
    addParameter(p, 'Steer', 0);
    addParameter(p, 'Side', 'both');
    parse(p, vehicle, manufacturer, varargin{:});
    
    heave = p.Results.Heave;
    steer = p.Results.Steer;
    side = p.Results.Side;
    
    % Get pickup points - FRONT AXLE
    % Lower A-arm points (aft, ball joint, fore)
    front_lowerArm_aft_left = vehicle.(manufacturer).kinematics.front.lowerAArm.aft;
    front_lowerArm_ballJoint_left = vehicle.(manufacturer).kinematics.front.lowerAArm.ballJoint;
    front_lowerArm_fore_left = vehicle.(manufacturer).kinematics.front.lowerAArm.fore;
    front_lowerArm_aft_right = front_lowerArm_aft_left .* [1, -1, 1];
    front_lowerArm_ballJoint_right = front_lowerArm_ballJoint_left.* [1, -1, 1];
    front_lowerArm_fore_right = front_lowerArm_fore_left.* [1, -1, 1];
    
    % Upper A-arm points (aft, ball joint, fore)
    front_upperArm_aft_left = vehicle.(manufacturer).kinematics.front.upperAArm.aft;
    front_upperArm_ballJoint_left = vehicle.(manufacturer).kinematics.front.upperAArm.ballJoint;
    front_upperArm_fore_left = vehicle.(manufacturer).kinematics.front.upperAArm.fore;
    front_upperArm_aft_right = front_upperArm_aft_left.* [1, -1, 1];
    front_upperArm_ballJoint_right = front_upperArm_ballJoint_left.* [1, -1, 1];
    front_upperArm_fore_right = front_upperArm_fore_left.* [1, -1, 1];
    
    % Tie rod points
    front_tieRod_inboard_left = vehicle.(manufacturer).kinematics.front.steeringRack.toeRodChassis;
    front_tieRod_outboard_left = vehicle.(manufacturer).kinematics.front.steeringRack.toeRodUpright;
    front_tieRod_inboard_right = front_tieRod_inboard_left.* [1, -1, 1];
    front_tieRod_outboard_right = front_tieRod_outboard_left.* [1, -1, 1];
    
    % Damper points
    front_damper_lower_left = vehicle.(manufacturer).kinematics.front.rocker.damperPickup;
    front_damper_upper_left = vehicle.(manufacturer).kinematics.front.damper.chassisPickup;
    front_damper_lower_right = front_damper_lower_left.* [1, -1, 1];
    front_damper_upper_right = front_damper_upper_left.* [1, -1, 1];
    
    % Wheel/contact patch points
    front_contactPatch_left = [0,0,0];
    front_contactPatch_right = [0,0,0];
    
    % Get pickup points - REAR AXLE
    % Lower A-arm points (aft, ball joint, fore)
    rear_lowerArm_aft_left = vehicle.(manufacturer).kinematics.rear.lowerAArm.aft;
    rear_lowerArm_ballJoint_left = vehicle.(manufacturer).kinematics.rear.lowerAArm.ballJoint;
    rear_lowerArm_fore_left = vehicle.(manufacturer).kinematics.rear.lowerAArm.fore;
    rear_lowerArm_aft_right = rear_lowerArm_aft_left.* [1, -1, 1];
    rear_lowerArm_ballJoint_right = rear_lowerArm_ballJoint_left.* [1, -1, 1];
    rear_lowerArm_fore_right = rear_lowerArm_fore_left.* [1, -1, 1];
    
    % Upper A-arm points (aft, ball joint, fore)
    rear_upperArm_aft_left = vehicle.(manufacturer).kinematics.rear.upperAArm.aft;
    rear_upperArm_ballJoint_left = vehicle.(manufacturer).kinematics.rear.upperAArm.ballJoint;
    rear_upperArm_fore_left = vehicle.(manufacturer).kinematics.rear.upperAArm.fore;
    rear_upperArm_aft_right = rear_upperArm_aft_left.* [1, -1, 1];
    rear_upperArm_ballJoint_right = rear_upperArm_ballJoint_left.* [1, -1, 1];
    rear_upperArm_fore_right = rear_upperArm_fore_left.* [1, -1, 1];
    
    % Toe rod points
    rear_toeRod_inboard_left = vehicle.(manufacturer).kinematics.rear.lowerAArm.toeRodChassis;
    rear_toeRod_outboard_left = vehicle.(manufacturer).kinematics.rear.lowerAArm.toeRodUpright;
    rear_toeRod_inboard_right = rear_toeRod_inboard_left.* [1, -1, 1];
    rear_toeRod_outboard_right = rear_toeRod_outboard_left.* [1, -1, 1];
    
    % Damper points
    rear_damper_lower_left = vehicle.(manufacturer).kinematics.rear.rocker.damperPickup;
    rear_damper_upper_left = vehicle.(manufacturer).kinematics.rear.damper.chassisPickup;
    rear_damper_lower_right = rear_damper_lower_left.* [1, -1, 1];
    rear_damper_upper_right = rear_damper_upper_left.* [1, -1, 1];
    
    % Wheel/contact patch points
    rear_contactPatch_left = vehicle.(manufacturer).kinematics.rear.correctedContactPatch(10,:);
    rear_contactPatch_right = rear_contactPatch_left.* [1, -1, 1];
    
    %% Calculate Vector Angles
    % Helper function to calculate projection angles onto each plane
    function angles = calcInclinationAngles(inboard, outboard)
        vec = outboard - inboard;
        X = vec(1);
        Y = vec(2);
        Z = vec(3);
        
        % Projection angles onto each plane (degrees)
        angle_from_XY = atan2d(X, Y);  % Angle in XZ plane (elevation in X direction)
        angle_from_XZ = atan2d(X, Z);  % Angle in XY plane (lateral in X direction)
        angle_from_YZ = atan2d(Y, Z);  % Angle in YX plane (longitudinal in Y direction)

        angles = [angle_from_XY, angle_from_XZ, angle_from_YZ];
    end
    
    % Initialize table data
    vectorNames = {};
    angleData = [];
    complementAngles = [];
    referenceAngle = 90;
    % Front Lower A-arm segments (aft->ball, fore->ball)
    vectorNames{end+1} = 'Front Lower Aft-Ball Left';
    angles = calcInclinationAngles(front_lowerArm_aft_left, front_lowerArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Lower Fore-Ball Left';
    angles = calcInclinationAngles(front_lowerArm_fore_left, front_lowerArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Lower Aft-Ball Right';
    angles = calcInclinationAngles(front_lowerArm_aft_right, front_lowerArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Lower Fore-Ball Right';
    angles = calcInclinationAngles(front_lowerArm_fore_right, front_lowerArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Front Upper A-arm segments (aft->ball, fore->ball)
    vectorNames{end+1} = 'Front Upper Aft-Ball Left';
    angles = calcInclinationAngles(front_upperArm_aft_left, front_upperArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Upper Fore-Ball Left';
    angles = calcInclinationAngles(front_upperArm_fore_left, front_upperArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Upper Aft-Ball Right';
    angles = calcInclinationAngles(front_upperArm_aft_right, front_upperArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Upper Fore-Ball Right';
    angles = calcInclinationAngles(front_upperArm_fore_right, front_upperArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Front Tie Rods (inboard to outboard)
    vectorNames{end+1} = 'Front Tie Rod Left';
    angles = calcInclinationAngles(front_tieRod_inboard_left, front_tieRod_outboard_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Tie Rod Right';
    angles = calcInclinationAngles(front_tieRod_inboard_right, front_tieRod_outboard_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Front Dampers (lower to upper)
    vectorNames{end+1} = 'Front Damper Left';
    angles = calcInclinationAngles(front_damper_lower_left, front_damper_upper_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Front Damper Right';
    angles = calcInclinationAngles(front_damper_lower_right, front_damper_upper_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Rear Lower A-arm segments (aft->ball, fore->ball)
    vectorNames{end+1} = 'Rear Lower Aft-Ball Left';
    angles = calcInclinationAngles(rear_lowerArm_aft_left, rear_lowerArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Lower Fore-Ball Left';
    angles = calcInclinationAngles(rear_lowerArm_fore_left, rear_lowerArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Lower Aft-Ball Right';
    angles = calcInclinationAngles(rear_lowerArm_aft_right, rear_lowerArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Lower Fore-Ball Right';
    angles = calcInclinationAngles(rear_lowerArm_fore_right, rear_lowerArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Rear Upper A-arm segments (aft->ball, fore->ball)
    vectorNames{end+1} = 'Rear Upper Aft-Ball Left';
    angles = calcInclinationAngles(rear_upperArm_aft_left, rear_upperArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Upper Fore-Ball Left';
    angles = calcInclinationAngles(rear_upperArm_fore_left, rear_upperArm_ballJoint_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Upper Aft-Ball Right';
    angles = calcInclinationAngles(rear_upperArm_aft_right, rear_upperArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Upper Fore-Ball Right';
    angles = calcInclinationAngles(rear_upperArm_fore_right, rear_upperArm_ballJoint_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Rear Toe Rods (inboard to outboard)
    vectorNames{end+1} = 'Rear Toe Rod Left';
    angles = calcInclinationAngles(rear_toeRod_inboard_left, rear_toeRod_outboard_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Toe Rod Right';
    angles = calcInclinationAngles(rear_toeRod_inboard_right, rear_toeRod_outboard_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    % Rear Dampers (lower to upper)
    vectorNames{end+1} = 'Rear Damper Left';
    angles = calcInclinationAngles(rear_damper_lower_left, rear_damper_upper_left);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    vectorNames{end+1} = 'Rear Damper Right';
    angles = calcInclinationAngles(rear_damper_lower_right, rear_damper_upper_right);
    angleData(end+1,:) = angles;
    complementAngles(end+1,:) = referenceAngle - abs(angles);
    
    %% Create Angle Table Figure
    tableFig = figure('Name', sprintf('%s Suspension Vector Angles', manufacturer), ...
                      'Position', [100, 100, 1200, 600]);
    
    % Create table with complement angles
    columnNames = {'Vector Name', ...
                   'XY Angle (deg)', 'XY Complement (deg)', ...
                   'XZ Angle (deg)', 'XZ Complement (deg)', ...
                   'YZ Angle (deg)', 'YZ Complement (deg)'};
    tableData = [vectorNames', ...
                 num2cell(angleData(:,1)), num2cell(complementAngles(:,1)), ...
                 num2cell(angleData(:,2)), num2cell(complementAngles(:,2)), ...
                 num2cell(angleData(:,3)), num2cell(complementAngles(:,3))];
    
    uit = uitable(tableFig, 'Data', tableData, ...
                  'ColumnName', columnNames, ...
                  'ColumnWidth', {200, 100, 120, 100, 120, 100, 120}, ...
                  'Units', 'normalized', ...
                  'Position', [0.05, 0.05, 0.9, 0.9], ...
                  'RowName', []);
    
    %% Create 3D Geometry Figure
    figure('Name', sprintf('%s Vehicle Suspension Geometry', manufacturer));
    hold on;
    grid on;
    axis equal;
    
    %% PLOT FRONT AXLE - LEFT SIDE
    if strcmp(side, 'both') || strcmp(side, 'left')
        % Lower A-arm (aft -> ball joint -> fore)
        plot3([front_lowerArm_aft_left(1), front_lowerArm_ballJoint_left(1), front_lowerArm_fore_left(1)], ...
              [front_lowerArm_aft_left(2), front_lowerArm_ballJoint_left(2), front_lowerArm_fore_left(2)], ...
              [front_lowerArm_aft_left(3), front_lowerArm_ballJoint_left(3), front_lowerArm_fore_left(3)], ...
              'b-', 'LineWidth', 2, 'DisplayName', 'Front Lower A-arm Left');
        
        % Upper A-arm (aft -> ball joint -> fore)
        plot3([front_upperArm_aft_left(1), front_upperArm_ballJoint_left(1), front_upperArm_fore_left(1)], ...
              [front_upperArm_aft_left(2), front_upperArm_ballJoint_left(2), front_upperArm_fore_left(2)], ...
              [front_upperArm_aft_left(3), front_upperArm_ballJoint_left(3), front_upperArm_fore_left(3)], ...
              'r-', 'LineWidth', 2, 'DisplayName', 'Front Upper A-arm Left');
        
        % Tie rod
        plot3([front_tieRod_inboard_left(1), front_tieRod_outboard_left(1)], ...
              [front_tieRod_inboard_left(2), front_tieRod_outboard_left(2)], ...
              [front_tieRod_inboard_left(3), front_tieRod_outboard_left(3)], ...
              'g-', 'LineWidth', 2, 'DisplayName', 'Front Tie Rod Left');
        
        % Damper
        plot3([front_damper_lower_left(1), front_damper_upper_left(1)], ...
              [front_damper_lower_left(2), front_damper_upper_left(2)], ...
              [front_damper_lower_left(3), front_damper_upper_left(3)], ...
              'k-', 'LineWidth', 3, 'DisplayName', 'Front Damper Left');
        
        % Contact patch
        plot3(front_contactPatch_left(1), front_contactPatch_left(2), front_contactPatch_left(3), ...
              'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'DisplayName', 'Front Contact Patch Left');
    end
    
    %% PLOT FRONT AXLE - RIGHT SIDE
    if strcmp(side, 'both') || strcmp(side, 'right')
        % Lower A-arm (aft -> ball joint -> fore)
        plot3([front_lowerArm_aft_right(1), front_lowerArm_ballJoint_right(1), front_lowerArm_fore_right(1)], ...
              [front_lowerArm_aft_right(2), front_lowerArm_ballJoint_right(2), front_lowerArm_fore_right(2)], ...
              [front_lowerArm_aft_right(3), front_lowerArm_ballJoint_right(3), front_lowerArm_fore_right(3)], ...
              'b--', 'LineWidth', 2, 'DisplayName', 'Front Lower A-arm Right');
        
        % Upper A-arm (aft -> ball joint -> fore)
        plot3([front_upperArm_aft_right(1), front_upperArm_ballJoint_right(1), front_upperArm_fore_right(1)], ...
              [front_upperArm_aft_right(2), front_upperArm_ballJoint_right(2), front_upperArm_fore_right(2)], ...
              [front_upperArm_aft_right(3), front_upperArm_ballJoint_right(3), front_upperArm_fore_right(3)], ...
              'r--', 'LineWidth', 2, 'DisplayName', 'Front Upper A-arm Right');
        
        % Tie rod
        plot3([front_tieRod_inboard_right(1), front_tieRod_outboard_right(1)], ...
              [front_tieRod_inboard_right(2), front_tieRod_outboard_right(2)], ...
              [front_tieRod_inboard_right(3), front_tieRod_outboard_right(3)], ...
              'g--', 'LineWidth', 2, 'DisplayName', 'Front Tie Rod Right');
        
        % Damper
        plot3([front_damper_lower_right(1), front_damper_upper_right(1)], ...
              [front_damper_lower_right(2), front_damper_upper_right(2)], ...
              [front_damper_lower_right(3), front_damper_upper_right(3)], ...
              'k--', 'LineWidth', 3, 'DisplayName', 'Front Damper Right');
        
        % Contact patch
        plot3(front_contactPatch_right(1), front_contactPatch_right(2), front_contactPatch_right(3), ...
              'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'DisplayName', 'Front Contact Patch Right');
    end
    
    %% PLOT REAR AXLE - LEFT SIDE
    if strcmp(side, 'both') || strcmp(side, 'left')
        % Lower A-arm (aft -> ball joint -> fore)
        plot3([rear_lowerArm_aft_left(1), rear_lowerArm_ballJoint_left(1), rear_lowerArm_fore_left(1)], ...
              [rear_lowerArm_aft_left(2), rear_lowerArm_ballJoint_left(2), rear_lowerArm_fore_left(2)], ...
              [rear_lowerArm_aft_left(3), rear_lowerArm_ballJoint_left(3), rear_lowerArm_fore_left(3)], ...
              'c-', 'LineWidth', 2, 'DisplayName', 'Rear Lower A-arm Left');
        
        % Upper A-arm (aft -> ball joint -> fore)
        plot3([rear_upperArm_aft_left(1), rear_upperArm_ballJoint_left(1), rear_upperArm_fore_left(1)], ...
              [rear_upperArm_aft_left(2), rear_upperArm_ballJoint_left(2), rear_upperArm_fore_left(2)], ...
              [rear_upperArm_aft_left(3), rear_upperArm_ballJoint_left(3), rear_upperArm_fore_left(3)], ...
              'm-', 'LineWidth', 2, 'DisplayName', 'Rear Upper A-arm Left');
        
        % Toe rod
        plot3([rear_toeRod_inboard_left(1), rear_toeRod_outboard_left(1)], ...
              [rear_toeRod_inboard_left(2), rear_toeRod_outboard_left(2)], ...
              [rear_toeRod_inboard_left(3), rear_toeRod_outboard_left(3)], ...
              'y-', 'LineWidth', 2, 'DisplayName', 'Rear Toe Rod Left');
        
        % Damper
        plot3([rear_damper_lower_left(1), rear_damper_upper_left(1)], ...
              [rear_damper_lower_left(2), rear_damper_upper_left(2)], ...
              [rear_damper_lower_left(3), rear_damper_upper_left(3)], ...
              'k-', 'LineWidth', 3, 'DisplayName', 'Rear Damper Left');
        
        % Contact patch
        plot3(rear_contactPatch_left(1), rear_contactPatch_left(2), rear_contactPatch_left(3), ...
              'ks', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'DisplayName', 'Rear Contact Patch Left');
    end
    
    %% PLOT REAR AXLE - RIGHT SIDE
    if strcmp(side, 'both') || strcmp(side, 'right')
        % Lower A-arm (aft -> ball joint -> fore)
        plot3([rear_lowerArm_aft_right(1), rear_lowerArm_ballJoint_right(1), rear_lowerArm_fore_right(1)], ...
              [rear_lowerArm_aft_right(2), rear_lowerArm_ballJoint_right(2), rear_lowerArm_fore_right(2)], ...
              [rear_lowerArm_aft_right(3), rear_lowerArm_ballJoint_right(3), rear_lowerArm_fore_right(3)], ...
              'c--', 'LineWidth', 2, 'DisplayName', 'Rear Lower A-arm Right');
        
        % Upper A-arm (aft -> ball joint -> fore)
        plot3([rear_upperArm_aft_right(1), rear_upperArm_ballJoint_right(1), rear_upperArm_fore_right(1)], ...
              [rear_upperArm_aft_right(2), rear_upperArm_ballJoint_right(2), rear_upperArm_fore_right(2)], ...
              [rear_upperArm_aft_right(3), rear_upperArm_ballJoint_right(3), rear_upperArm_fore_right(3)], ...
              'm--', 'LineWidth', 2, 'DisplayName', 'Rear Upper A-arm Right');
        
        % Toe rod
        plot3([rear_toeRod_inboard_right(1), rear_toeRod_outboard_right(1)], ...
              [rear_toeRod_inboard_right(2), rear_toeRod_outboard_right(2)], ...
              [rear_toeRod_inboard_right(3), rear_toeRod_outboard_right(3)], ...
              'y--', 'LineWidth', 2, 'DisplayName', 'Rear Toe Rod Right');
        
        % Damper
        plot3([rear_damper_lower_right(1), rear_damper_upper_right(1)], ...
              [rear_damper_lower_right(2), rear_damper_upper_right(2)], ...
              [rear_damper_lower_right(3), rear_damper_upper_right(3)], ...
              'k--', 'LineWidth', 3, 'DisplayName', 'Rear Damper Right');
        
        % Contact patch
        plot3(rear_contactPatch_right(1), rear_contactPatch_right(2), rear_contactPatch_right(3), ...
              'ks', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'DisplayName', 'Rear Contact Patch Right');
    end
    
    % Labels and formatting
    xlabel('X [mm] - Longitudinal');
    ylabel('Y [mm] - Lateral');
    zlabel('Z [mm] - Vertical');
    title(sprintf('%s Full Vehicle Suspension (Heave: %.1f mm, Steer: %.1f deg)', ...
                  manufacturer, heave, steer));
    legend('Location', 'best');
    view(3);  % 3D view
    
    hold off;
end