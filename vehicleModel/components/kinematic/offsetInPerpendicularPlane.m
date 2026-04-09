function vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, varargin)
    % OFFSETINPERPENDICULARPLANE Apply 2D offsets in a plane perpendicular to an axis
    %
    % Inputs:
    %   basePoint (n,3)      - Starting points in 3D
    %   axisDirection (n,3)  - Axis vectors (will be normalized)
    %   rotationAngle (n,1)  - Rotation angle in plane (radians)
    %   offset_u (scalar)    - Offset along rotated U direction
    %   offset_v (scalar)    - Offset along V direction (90° to U)
    %
    % Output:
    %   point3D (n,3)        - Resulting 3D points
    p = inputParser;
    addRequired(p, 'vehicle');
    addRequired(p, 'manufacturer');
    addRequired(p, 'axle');
    addParameter(p, 'contactChoice', 'inside');
    addParameter(p, 'toeIndex', 1);
    parse(p, vehicle, manufacturer, axle, varargin{:});

    contactChoice = p.Results.contactChoice;  
    toeIndex = p.Results.toeIndex;  
    % Normalize axis
    
    basePoint = vehicle.(manufacturer).kinematics.(axle).camberSweep.LBJ;
%     axisDirection = vehicle.(manufacturer).kinematics.(axle).camberSweep.UBJ - vehicle.(manufacturer).kinematics.(axle).camberSweep.LBJ;
    axisDirection = vehicle.(manufacturer).kinematics.(axle).camberSweep.LBJ - vehicle.(manufacturer).kinematics.(axle).camberSweep.UBJ;
    rotationAngle = vehicle.(manufacturer).kinematics.(axle).toeSweep.toe(:,toeIndex);
    axisDir = axisDirection ./ vecnorm(axisDirection, 2, 2);
    offset_u = vehicle.(manufacturer).kinematics.(axle).upright.wheelCenterDelta2KPI(1);
    offset_v = vehicle.(manufacturer).kinematics.(axle).upright.wheelCenterDelta2KPI(2);
    basePoint = axisDir * 149 + basePoint;
    % Create basis vectors in perpendicular plane
    axisDirSize = size(axisDir);
    
    vehicleX = zeros(axisDirSize(1), axisDirSize(2)) + [1, 0, 0];
    temp = vehicleX - dot(vehicleX, axisDir, 2) .* axisDir;
    forwardInPlane = temp ./ vecnorm(temp, 2, 2);
    
    lateralInPlane = cross(axisDir, forwardInPlane, 2);
    
    % Rotate by angle to get U and V axes
    % 149 x 1,                      149 x 3         149 x 1  % 149 x 3
    if toeIndex == 1
        u_hat = cosd(rotationAngle) .* forwardInPlane + sind(rotationAngle) .* lateralInPlane;
        v_hat = -sind(rotationAngle) .* forwardInPlane + cosd(rotationAngle) .* lateralInPlane;
    else
        u_hat = cosd(rotationAngle) .* forwardInPlane + sind(rotationAngle) .* lateralInPlane;
        v_hat = -sind(rotationAngle) .* forwardInPlane + cosd(rotationAngle) .* lateralInPlane;
    end
    % Apply offsets
%     vehicle.(manufacturer).kinematics.(axle).correctedContactPatch = basePoint + offset_u * u_hat + offset_v * v_hat;
    
    vehicle.(manufacturer).kinematics.(axle).spindleAxisPoint = basePoint + offset_u * u_hat + (offset_v - 1) * v_hat;
    vehicle.(manufacturer).kinematics.(axle).spindleAxis = basePoint + offset_u * u_hat + offset_v * v_hat - vehicle.(manufacturer).kinematics.(axle).spindleAxisPoint;
    
    if strcmp(contactChoice, 'inside')
        
        axisDirection =  vehicle.(manufacturer).kinematics.(axle).spindleAxis;
        rotationAngle = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber;
        axisDir = axisDirection ./ vecnorm(axisDirection, 2, 2);
        offset_u = vehicle.(manufacturer).kinematics.(axle).tyreGeometryInside(2)*-1;
        offset_v = vehicle.(manufacturer).kinematics.(axle).tyrecenterPoint(3);
        
        axisDirSize = size(axisDir);

        vehicleX = zeros(axisDirSize(1), axisDirSize(2)) + [1, 0, 0];
        temp = vehicleX - dot(vehicleX, axisDir, 2) .* axisDir;
        forwardInPlane = temp ./ vecnorm(temp, 2, 2);

        lateralInPlane = cross(axisDir, forwardInPlane, 2);

    elseif strcmp(contactChoice,'tyreCentre')
        basePoint =  vehicle.(manufacturer).kinematics.(axle).spindleAxisPoint;
        axisDirection =  vehicle.(manufacturer).kinematics.(axle).spindleAxis;
        rotationAngle = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber;
        axisDir = axisDirection ./ vecnorm(axisDirection, 2, 2);
        offset_u = (-vehicle.(manufacturer).kinematics.(axle).tyrecenterPoint(2));
        offset_v = vehicle.(manufacturer).kinematics.(axle).tyrecenterPoint(3);
        
        axisDirSize = size(axisDir);

        vehicleX = zeros(axisDirSize(1), axisDirSize(2)) + [1, 0, 0];
        temp = vehicleX - dot(vehicleX, axisDir, 2) .* axisDir;
        forwardInPlane = temp ./ vecnorm(temp, 2, 2);

        lateralInPlane = cross(axisDir, forwardInPlane, 2);

        % Rotate by angle to get U and V axes
    elseif strcmp(contactChoice,'tyreContactPatch')
        warning('Work In Progress');
        fprintf('\nNo exact way to determine the starting contact patch yet\n');
        fprintf('No toe correction for contact patch\n\tSmall contributing factor\n');
        basePoint =  vehicle.(manufacturer).kinematics.(axle).spindleAxisPoint;
        axisDirection =  vehicle.(manufacturer).kinematics.(axle).spindleAxis;
        rotationAngle = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber;
        axisDir = axisDirection ./ vecnorm(axisDirection, 2, 2);
        offset_u = (-vehicle.(manufacturer).kinematics.(axle).tyrecenterPoint(2));
        offset_v = vehicle.(manufacturer).kinematics.(axle).tyrecenterPoint(3);
        
        axisDirSize = size(axisDir);

        vehicleX = zeros(axisDirSize(1), axisDirSize(2)) + [1, 0, 0];
        temp = vehicleX - dot(vehicleX, axisDir, 2) .* axisDir;
        forwardInPlane = temp ./ vecnorm(temp, 2, 2);

        lateralInPlane = cross(axisDir, forwardInPlane, 2);
    end
        % Rotate by angle to get U and V axes
        u_hat = cosd(rotationAngle) .* forwardInPlane + sind(rotationAngle) .* lateralInPlane;
        v_hat = -sind(rotationAngle) .* forwardInPlane + cosd(rotationAngle) .* lateralInPlane;
%         basePoint =  vehicle.(manufacturer).kinematics.(axle).spindleAxisPoint 
        % Apply offsets
        % toe Index Span
        toeIndexSpan = [(toeIndex*3) - 2, toeIndex*3];
        vehicle.(manufacturer).kinematics.(axle).correctedContactPatch(:, (toeIndexSpan(1) : toeIndexSpan(2))) = ...
            basePoint + offset_u * u_hat + offset_v * v_hat;
end