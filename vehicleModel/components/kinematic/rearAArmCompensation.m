function radiiOffset = rearAArmCompensation(vehicle, manufacturer, axle, shims, varargin)
    p = inputParser;
    addRequired(p, 'vehicle');
    addRequired(p, 'manufacturer');
    addRequired(p, 'axle');
    addRequired(p, 'shims');
    addParameter(p, 'CAD_ERROR', false, @islogical);

    parse(p, vehicle,  manufacturer, axle, shims, varargin{:});
    CAD_ERROR = p.Results.CAD_ERROR;

    
    P_UF =  vehicle.(manufacturer).kinematics.(axle).upperAArm.fore ;
    P_UA =  vehicle.(manufacturer).kinematics.(axle).upperAArm.aft ;
    P_UBJ = vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJoint;
    P_LBJ = vehicle.(manufacturer).kinematics.(axle).lowerAArm.ballJoint;


    vec_UBJ_UA = P_UBJ - P_UA ;
    vec_UBJ_UF = P_UBJ - P_UF;

    projectionPlane = cross(vec_UBJ_UF, vec_UBJ_UA);
    [P_cU, ~, ~, ~] = circleFromTwoSpheres(P_UF, P_UA, norm(P_UBJ - P_UF), norm(P_UBJ - P_UA))
    % defined P_CU from function 
    P_cU =[680.5000, 455.0000, 296.0000];

    v1 = P_UBJ - P_UF 
    v2 = P_UBJ - P_UA 
    va = P_UBJ - P_cU 


    % normal plane
    normal_plane = cross(v1, v2) / norm(cross(v1, v2))

    % basis vectors
    u_vec = va / norm(va);
    v_vec = cross(normal_plane, u_vec);
    %% section with shim addition



    vehicle.kinematics.(axle).camberShims_5219 = [0, 1.016, 0]; % CAD reference
    vehicle.kinematics.(axle).camberShims_5220 = [0, 1.600, 0]; % CAD reference
    vehicle.kinematics.(axle).camberShims_5221 = [0, 2.540, 0]; % CAD reference
    vehicle.kinematics.(axle).camberShims_5222 = [0, 5.000, 0]; % CAD reference
    if CAD_ERROR
        shimStack = sum([vehicle.kinematics.rear.camberShims_3127;
                         vehicle.kinematics.rear.camberShims_3140;
                         vehicle.kinematics.rear.camberShims_3141
                         vehicle.kinematics.rear.camberShims_CAD_ERROR]  .*[0,0,1,1]') + vehicle.ford.kinematics.rear.upperAArm.uprightConnector;
    elseif ~CAD_ERROR
        shimStack = sum([vehicle.kinematics.rear.camberShims_3127;
                         vehicle.kinematics.rear.camberShims_3140;
                         vehicle.kinematics.rear.camberShims_3141]  .*shims') + vehicle.ford.kinematics.rear.upperAArm.uprightConnector;
    end
    v1_new = [dot(v1, u_vec) + shimStack(2), dot(v1, v_vec)]
    v2_new = [dot(v2, u_vec) + shimStack(2), dot(v2, v_vec)]
    va_new = [dot(va, u_vec) + shimStack(2), dot(va, v_vec)]

    v1_3D = P_UF + v1_new(1) * u_vec + v1_new(2) * v_vec;
    v1_3D - P_UBJ

    v2_3D = P_UA + v2_new(1) * u_vec + v2_new(2) * v_vec;
    v2_3D - P_UBJ

    va_3D = P_cU + va_new(1) * u_vec + va_new(2) * v_vec;
    radiiOffset = va_3D - P_UBJ;

end