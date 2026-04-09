function [initial_toe_offset] = calculateInitialToeOffset(uprightGeometry)
% CALCULATEINITIALTOEOFFSET Calculates the toe offset due to upright geometry
%
% The kinematic solver works in the pickup point plane (where UBJ, LBJ, and
% toe rod upright pickups are located). However, toe angle should be measured
% at the wheel plane, which is offset from the pickup plane by the upright
% geometry.
%
% INPUTS:
%   uprightGeometry - struct containing:
%       .pickupPlaneOrigin - [x,y,z] reference point in pickup plane (typically LBJ)
%       .wheelCenter       - [x,y,z] wheel center position
%       .KPI_axis          - [x,y,z] unit vector of KPI axis at ride height
%
% OUTPUTS:
%   initial_toe_offset - toe angle offset [deg] to add to kinematic results
%
% METHODOLOGY:
% The offset creates an effective steering angle because the wheel plane is
% displaced from where the kinematics think it is. This is a pure geometric
% effect - like how a front axle offset on a shopping cart makes it steer.

%% Extract inputs
P_pickup = uprightGeometry.pickupPlaneOrigin(:);  % Origin of pickup plane
P_wheel = uprightGeometry.wheelCenter(:);         % Wheel center
w_hat = uprightGeometry.KPI_axis(:);              % KPI axis (unit vector)

%% Calculate offset vector
% Vector from pickup plane reference to wheel center
offset = P_wheel - P_pickup;

%% Decompose offset relative to KPI axis
% Offset parallel to KPI (doesn't affect toe)
offset_parallel = dot(offset, w_hat) * w_hat;

% Offset perpendicular to KPI (this creates the toe effect)
offset_perp = offset - offset_parallel;

%% Calculate toe offset
% The perpendicular offset creates an angular offset when viewed along the
% KPI axis. This is the geometric toe offset.
%
% For small offsets, toe_offset ≈ atan2(lateral_offset, longitudinal_distance)
% But we'll calculate it exactly:

% Get the longitudinal (x) and lateral (y) components of the perpendicular offset
% We need to project offset_perp onto the vehicle longitudinal and lateral axes

% Vehicle longitudinal axis (forward direction)
x_vehicle = [1; 0; 0];

% Project perpendicular offset onto vehicle axes
% First, make sure x_vehicle is perpendicular to KPI
x_vehicle_perp = x_vehicle - dot(x_vehicle, w_hat) * w_hat;
x_vehicle_perp = x_vehicle_perp / norm(x_vehicle_perp);

% Vehicle lateral axis (perpendicular to both KPI and longitudinal)
y_vehicle_perp = cross(w_hat, x_vehicle_perp);
y_vehicle_perp = y_vehicle_perp / norm(y_vehicle_perp);

% Project offset onto these axes
offset_longitudinal = dot(offset_perp, x_vehicle_perp);
offset_lateral = dot(offset_perp, y_vehicle_perp);

%% Calculate the angular offset
% Toe is positive for toe-out (front of wheel points outward)
% atan2 gives the angle from the longitudinal axis
initial_toe_offset = atan2d(offset_lateral, offset_longitudinal);

%% Display information
fprintf('\n');
fprintf('=================================================\n');
fprintf('INITIAL TOE OFFSET CALCULATION\n');
fprintf('=================================================\n');
fprintf('Pickup plane origin:  [%.2f, %.2f, %.2f] mm\n', P_pickup);
fprintf('Wheel center:         [%.2f, %.2f, %.2f] mm\n', P_wheel);
fprintf('KPI axis:             [%.4f, %.4f, %.4f]\n', w_hat);
fprintf('\n');
fprintf('Offset vector:        [%.2f, %.2f, %.2f] mm\n', offset);
fprintf('  - Parallel to KPI:  [%.2f, %.2f, %.2f] mm\n', offset_parallel);
fprintf('  - Perpendicular:    [%.2f, %.2f, %.2f] mm\n', offset_perp);
fprintf('\n');
fprintf('Perpendicular offset components:\n');
fprintf('  - Longitudinal:     %.2f mm\n', offset_longitudinal);
fprintf('  - Lateral:          %.2f mm\n', offset_lateral);
fprintf('\n');
fprintf('RESULT:\n');
fprintf('  Initial toe offset: %+.4f deg\n', initial_toe_offset);
fprintf('=================================================\n');
fprintf('\n');

end
