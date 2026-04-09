function vehicle = calculateAntiGeometry( vehicle, varargin)
    % As the suspension compressed the angle from the contact patch to the
    % anti dive location gets smaller.
    % The chassis hard points are not moving, so their values stay the same
    % it is the contact path to lower wish bone (side view) that gets
    % smaller
    %
    % Inputs:
    %   wheel_travel - Wheel travel values [n x 1] (mm)
    %   vehicle - Vehicle struct containing kinematics data
    %
    % Optional Parameters:
    %   'axle' - 'front' or 'rear' (default: 'rear')
    %   'vehicle_name' - Vehicle name in struct (default: 'ford')
    %
    % Outputs:
    %   RC_height_array - Roll center height at each wheel travel point [n x 1] (mm)
    %   dRC_dz_nominal - Rate of change of RC height with wheel travel at nominal (dimensionless)
    
    % Parse inputs
    p = inputParser;
    addRequired(p, 'vehicle');
    addParameter(p, 'rideHeight', [0, 0, 0], @isnumeric)
    addParameter(p, 'manufacturer', 'ford');
    addParameter(p, 'axle', 'rear');
    
    parse(p, vehicle, varargin{:});
    
    axle = p.Results.axle;
    manufacturer = p.Results.manufacturer;
    vehicleContactPathTravel = p.Results.rideHeight;
    % Extract wheel travel data
    wheel_travel = vehicle.ford.kinematics.(axle).camberSweep.wheelTravel;
    % Extract kinematics data
    kin = vehicle.(manufacturer).kinematics.(axle);
    
    % Lower A-arm pivot points
    lower_fore = kin.lowerAArm.fore;
    lower_aft = kin.lowerAArm.aft;
    
    % Upper A-arm pivot points
    upper_fore = kin.upperAArm.fore;
    upper_aft = kin.upperAArm.aft;
    n_points = length(wheel_travel);
    % Number of points
    antiDive_array = zeros(n_points, 1);
    
    % Calculate RC at each wheel travel point
    
    
    
    mUpper = (kin.upperAArm.fore(3) - kin.upperAArm.aft(3)) / (kin.upperAArm.fore(1) - kin.upperAArm.aft(1));
    bL = kin.upperAArm.fore(3) - mUpper * kin.upperAArm.fore(1);

    mLower = (kin.lowerAArm.fore(3) - kin.lowerAArm.aft(3)) / (kin.lowerAArm.fore(1) - kin.lowerAArm.aft(1));
    bU = kin.lowerAArm.fore(3) - mLower * kin.lowerAArm.fore(1);

    IC_x = (bL - bU) / (mLower - mUpper);
    IC_z = mLower * IC_x + bU;
    AntiDiveLocation = [IC_x, 0, IC_z];
    %% lower a arm used to find anti dive angle
    
   
    for i = 1:n_points
        % Wheel center location (350mm below LBJ)
        wheel_centre = vehicleContactPathTravel + [0, 0, -350];
        
        mAD = (wheel_centre(3) - AntiDiveLocation(3)) / (wheel_centre(1) - AntiDiveLocation(1));
        bAD = wheel_centre(3) - mAD * wheel_centre(1);
        
        antiDive_array(i) = atan((mLower - mAD) / (1 + mAD *mLower));
            
        % Find Roll Center (IC to wheel center, intersect at centerline)
    end
    
    % Calculate derivative at nominal position (where wheel_travel = 0)
    [~, nominal_idx] = min(abs(wheel_travel));
    nominal_idx = nominal_idx(3);
    if nominal_idx == 1
        % Forward difference
        dRC_dz_nominal = (antiDive_array(2) - antiDive_array(1)) / ...
                         (wheel_travel(2) - wheel_travel(1));
    elseif nominal_idx == n_points
        % Backward difference
        dRC_dz_nominal = (antiDive_array(end) - antiDive_array(end-1)) / ...
                         (wheel_travel(end) - wheel_travel(end-1));
    else
        % Central difference
        dRC_dz_nominal = (antiDive_array(nominal_idx+1) - antiDive_array(nominal_idx-1)) / ...
                         (wheel_travel(nominal_idx+1) - wheel_travel(nominal_idx-1));
    end
    vehicle.(manufacturer).kinematics.(axle).antiDive_array = antiDive_array;
    vehicle.(manufacturer).kinematics.(axle).dRC_dz_nominal = dRC_dz_nominal;
end