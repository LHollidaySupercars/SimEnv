function offset = getOffset(vehicle, manufacturer, POS, axle, varargin)
     p = inputParser;
        addRequired(p, 'vehicle');
        addRequired(p, 'manufacturer');
        addRequired(p, 'POS');
        addRequired(p, 'axle');
        addParameter(p, 'thetaL_range', [])
        
    parse(p, vehicle, manufacturer, POS, axle, varargin{:});
%     FRONT_UBJ_UPRIGHT_POS
%     REAR_UBJ_UPRIGHT_POS
% vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_1
    offset = ...
        vehicle.(manufacturer).kinematics.(axle).upperAArm.(sprintf("UBJ_UPRIGHT_POS_%d", POS(sprintf('%s_UBJ_UPRIGHT_POS',upper(axle)))));

end