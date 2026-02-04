function vehicle = clevisPOSOffset(vehicle, manufacturer, POS, axle, varargin)
     p = inputParser;
        addRequired(p, 'vehicle');
        addRequired(p, 'manufacturer');
        addRequired(p, 'POS');
        addRequired(p, 'axle');
        addParameter(p, 'thetaL_range', [])
        
    parse(p, vehicle, manufacturer, POS, axle, varargin{:});
    
    vehicle.(manufacturer).kinematics.(axle).upperAArm.fore = ...
        vehicle.(manufacturer).kinematics.(axle).upperAArm.fore + vehicle.(manufacturer).kinematics.(axle).clevis.(sprintf("POS%d", POS(sprintf('%sUF_POS',upper(axle(1))))));
    vehicle.(manufacturer).kinematics.(axle).upperAArm.aft = ...
        vehicle.(manufacturer).kinematics.(axle).upperAArm.aft + vehicle.(manufacturer).kinematics.(axle).clevis.(sprintf("POS%d", POS(sprintf('%sUA_POS',upper(axle(1))))));
    vehicle.(manufacturer).kinematics.(axle).lowerAArm.fore = ...
        vehicle.(manufacturer).kinematics.(axle).upperAArm.fore + vehicle.(manufacturer).kinematics.(axle).clevis.(sprintf("POS%d", POS(sprintf('%sLF_POS',upper(axle(1))))));
    vehicle.(manufacturer).kinematics.(axle).lowerAArm.aft = ...
        vehicle.(manufacturer).kinematics.(axle).lowerAArm.aft + vehicle.(manufacturer).kinematics.(axle).clevis.(sprintf("POS%d", POS(sprintf('%sLA_POS',upper(axle(1))))));
    
    
    
end