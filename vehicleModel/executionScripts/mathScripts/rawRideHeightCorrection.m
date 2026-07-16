function [RH_corr, x_hit, y_hit] = rawRideHeightCorrection(data, vehicle, axle, channelNameFront, channelNameRear)
    %% Ride Height Laser Correction — Roll/Pitch Lever Arm + Beam Tilt (vectorized)

    % frontRaw = data.L180_Laser_Ride_Height_Front_Ra.data;  % units mm
    % rearRaw  = data.L180_Laser_Ride_Height_Rear_Raw.data;  % units mm
    frontRaw = data.(channelNameFront).data;  % units mm
    rearRaw  = data.(channelNameRear).data;  % units mm

    theta = atan((frontRaw - rearRaw) ./ 3015);   % pitch angle (rad), Nx1
    theta = theta(:);                              % ensure column vector

    % select the correct raw range channel for the axle being corrected
    switch lower(axle)
        case 'front'
            RH_raw = frontRaw;
        case 'rear'
            RH_raw = rearRaw;
        otherwise
            error('axle must be ''front'' or ''rear''');
    end
    RH_raw = RH_raw(:);

    r = vehicle.ford.kinematics.(axle).CentreLineLaser ...
        - vehicle.ford.kinematics.(axle).RideHeightReferenceLocationLeft .* [1, 0, 1];
    r = r(:);   % [r1; r2; r3] — fixed lever-arm offset, body frame
    r1 = r(1); r2 = r(2); r3 = r(3);

    % roll unmeasured — assumed zero for all samples, so R = Ry (Rx = eye(3))
    % d = [0;0;1] is the nominal (unit) pointing vector, so:
    %   d_ground = Ry * d = [sin(theta); 0; cos(theta)]
    %   r_ground = Ry * r = [r1*cos(theta)+r3*sin(theta); r2; -r1*sin(theta)+r3*cos(theta)]
    % Since d is unit norm and Ry is orthogonal, norm(d_ground) = 1,
    % so alpha = acos(cos(theta)) = |theta|, and cos(alpha) = cos(theta).

    z_ground = -r1 .* sin(theta) + r3 .* cos(theta);
    cos_alpha = cos(theta);

    RH_corr = z_ground + RH_raw .* cos_alpha;

    % ground hit point (x,y), t = RH_raw along d_ground
    x_hit = (r1 .* cos(theta) + r3 .* sin(theta)) + RH_raw .* sin(theta);
    y_hit = r2 .* ones(size(theta));   % constant — no roll/lateral rotation applied
end