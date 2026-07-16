function point3D = offsetInPerpendicularPlane(basePoint, axisDirection, rotationAngle, offset_u, offset_v)
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
    
    % Normalize axis
    axisDir = axisDirection ./ vecnorm(axisDirection, 2, 2);
    
    % Create basis vectors in perpendicular plane
    vehicleX = [1, 0, 0];
    temp = vehicleX - dot(vehicleX, axisDir, 2) .* axisDir;
    forwardInPlane = temp ./ vecnorm(temp, 2, 2);
    
    lateralInPlane = cross(axisDir, forwardInPlane, 2);
    
    % Rotate by angle to get U and V axes
    u_hat = cos(rotationAngle) .* forwardInPlane + sin(rotationAngle) .* lateralInPlane;
    v_hat = -sin(rotationAngle) .* forwardInPlane + cos(rotationAngle) .* lateralInPlane;
    
    % Apply offsets
    point3D = basePoint + offset_u * u_hat + offset_v * v_hat;
end