    function vehicle = camberOffset(vehicle, shims, manufacturer, axle, varargin)
    p = inputParser;
    addRequired(p, 'vehicle');
    addRequired(p, 'shims');
    addRequired(p, 'manufacturer');
    addRequired(p, 'axle');
    addParameter(p, 'thetaL_range', []);
    
    parse(p, vehicle, shims, manufacturer, axle, varargin{:});
    
    thetaL_range = p.Results.thetaL_range;
    %% handle shim stack
    shimStack = sum([vehicle.kinematics.front.camberShims_5219;
    vehicle.kinematics.front.camberShims_5220;
    vehicle.kinematics.front.camberShims_5221;
    vehicle.kinematics.front.camberShims_5222]  .*shims') + vehicle.ford.kinematics.front.upperAArm.pivotPart;

    params = vehicle.(manufacturer).kinematics.(axle);
    
    UBJ = params.upperAArm.ballJoint;
    LBJ = params.lowerAArm.ballJoint;
    
    d_vec = norm((UBJ - LBJ) .* [0, 1, 1]);
    
    adjustedCamber = atan2((shimStack + vehicle.ford.kinematics.front.upperAArm.pivotPart), norm((UBJ - LBJ) .* [0, 1, 1]));
    
    %% add camber angle
    vehicle.(manufacturer).kinematics.(axle).camberSweep.camberCorrected = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber + rad2deg(adjustedCamber(2));
    % angle contribution from the shim and mating piece


end