function vehicle = solveWheelCamber(vehicle, varargin)
% SOLVEWHEELCAMBER Solves the camber kinematics for a double wishbone suspension
%
% The suspension is a 4-bar linkage:
%   - Lower A-arm constrains LBJ to a circle
%   - Upper A-arm constrains UBJ to a circle
%   - Upright connects LBJ to UBJ with fixed length
%
% We parameterize by theta_L (angle on LBJ circle) and solve for theta_U
% in closed form.
%
% INPUTS:
%   params - struct containing:
%       .upperAArm.fore       - [x,y,z] upper A-arm fore chassis pivot
%       .upperAArm.aft        - [x,y,z] upper A-arm aft chassis pivot
%       .upperAArm.ballJoint  - [x,y,z] upper ball joint at ride height
%       .lowerAArm.fore       - [x,y,z] lower A-arm fore chassis pivot
%       .lowerAArm.aft        - [x,y,z] lower A-arm aft chassis pivot
%       .lowerAArm.ballJoint  - [x,y,z] lower ball joint at ride height
%
%   thetaL_range - (optional) array of theta_L values [rad]
%                  If empty, auto-generates around ride height
%
% OUTPUTS:
%   camberResults - struct containing:
%       .thetaL           - parameter values [rad]
%       .thetaL_rideHeight- ride height theta_L value [rad]
%       .wheelTravel      - LBJ Z displacement [mm]
%       .camber           - camber angle [deg]
%       .camberGain       - d(camber)/d(wheelTravel) [deg/mm]
%       .LBJ              - lower ball joint positions [N x 3]
%       .UBJ              - upper ball joint positions [N x 3]
%       .KPI_axis         - unit vectors along KPI axis [N x 3]
%       .R_KPI            - rotation matrices from initial to current KPI {N x 1} cell
%       .w0_hat           - initial KPI axis direction [3 x 1]
%
% DERIVATION:
%
% Step 1: LBJ Circle
%   The LBJ is constrained by two links to P_LF and P_LA.
%   Two spheres intersect in a circle:
%       P_LBJ(theta_L) = P_cL + r_L * (cos(theta_L)*u_L + sin(theta_L)*v_L)
%
% Step 2: UBJ from Upright Constraint
%   Given LBJ, UBJ must lie on its circle AND at distance L_up from LBJ.
%   This gives: A*cos(theta_U) + B*sin(theta_U) = C
%   Solved as: theta_U = atan2(B,A) - acos(C/sqrt(A^2+B^2))
%
% Step 3: Camber
%   KPI axis: w_hat = (P_UBJ - P_LBJ) / L_up
%   Camber: gamma = arcsin(w_hat_y)
%
% Step 4: Camber Gain (Related Rates)
%   d(gamma)/d(z_LBJ) = [d(gamma)/d(theta_L)] / [d(z_LBJ)/d(theta_L)]
p = inputParser;
    addRequired(p, 'vehicle');
    addParameter(p, 'axle', 'rear');
    addParameter(p, 'thetaL_range', []);
    addParameter(p, 'manufacturer', 'ford');
    
    parse(p, vehicle, varargin{:});
    
    manufacturer = p.Results.manufacturer;
    thetaL_range = p.Results.thetaL_range;
    axle = p.Results.axle;
%% Extract inputs
params = vehicle.(manufacturer).kinematics.(axle);
P_UF = params.upperAArm.fore(:);
P_UA = params.upperAArm.aft(:);
P_UBJ0 = params.upperAArm.ballJoint(:);
P_LF = params.lowerAArm.fore(:);
P_LA = params.lowerAArm.aft(:);
P_LBJ0 = params.lowerAArm.ballJoint(:);

%% Calculate fixed link lengths
L_UF = norm(P_UBJ0 - P_UF);
L_UA = norm(P_UBJ0 - P_UA);
L_LF = norm(P_LBJ0 - P_LF);
L_LA = norm(P_LBJ0 - P_LA);
L_up = norm(P_UBJ0 - P_LBJ0);

%% Step 1: Lower ball joint circle
% Two spheres (centered at P_LF and P_LA) intersect in a circle
[P_cL, r_L, u_L, v_L] = circleFromTwoSpheres(P_LF, P_LA, L_LF, L_LA);

%% Upper ball joint circle
[P_cU, r_U, u_U, v_U] = circleFromTwoSpheres(P_UF, P_UA, L_UF, L_UA);



%% Find ride height theta_L
thetaL_0 = findAngleOnCircle(P_LBJ0, P_cL, r_L, u_L, v_L);

%% Generate theta_L range if not provided
if isempty(thetaL_range)
    thetaL_range = linspace(thetaL_0 - 0.3, thetaL_0 + 0.3, 149);
else
    thetaL_range = thetaL_0 - thetaL_range;
end
nPoints = length(thetaL_range);

%% Initial KPI axis
w0 = P_UBJ0 - P_LBJ0;
w0_hat = w0 / norm(w0);

%% Preallocate
LBJ = zeros(nPoints, 3);
UBJ = zeros(nPoints, 3);
KPI_axis = zeros(nPoints, 3);
R_KPI = cell(nPoints, 1);
camber = zeros(nPoints, 1);
dCamber_dThetaL = zeros(nPoints, 1);
dZlbj_dThetaL = zeros(nPoints, 1);

%% Main loop
for i = 1:nPoints
    thetaL = thetaL_range(i);
    
    %% LBJ position and derivative
    P_LBJ = P_cL + r_L * (cos(thetaL) * u_L + sin(thetaL) * v_L);
    dP_LBJ = r_L * (-sin(thetaL) * u_L + cos(thetaL) * v_L);
    
    %% Solve for UBJ (closed form)
    % Constraint: |P_UBJ - P_LBJ|^2 = L_up^2
    % P_UBJ = P_cU + r_U*(cos(thetaU)*u_U + sin(thetaU)*v_U)
    %
    % Let q = P_cU - P_LBJ
    % Expanding gives: A*cos(thetaU) + B*sin(thetaU) = C
    
    q = P_cU - P_LBJ;
    
    A = dot(q, u_U);
    B = dot(q, v_U);
    C = (L_up^2 - dot(q, q) - r_U^2) / (2 * r_U);
    
    R_AB = sqrt(A^2 + B^2);
    
    % Check if solution exists
    if abs(C / R_AB) > 1.5
        error('No solution at thetaL = %.4f rad. Upright constraint cannot be satisfied (C/R = %.4f)', thetaL, C/R_AB);
    end
    
    psi = atan2(B, A);
    alpha = acos(C / R_AB);
    thetaU = psi - alpha;  % Pick one branch (continuous with ride height)
    
    %% UBJ position and derivative
    P_UBJ = P_cU + r_U * (cos(thetaU) * u_U + sin(thetaU) * v_U);
    
    % Derivative of thetaU w.r.t. thetaL
    dq = -dP_LBJ;
    dA = dot(dq, u_U);
    dB = dot(dq, v_U);
    dC = -dot(q, dq) / r_U;
    
    dR_AB = (A * dA + B * dB) / R_AB;
    dPsi = (A * dB - B * dA) / (A^2 + B^2);
    dAlpha = (-1 / sqrt(1 - (C / R_AB)^2)) * (R_AB * dC - C * dR_AB) / R_AB^2;
    
    dThetaU_dThetaL = dPsi - dAlpha;
    
    dP_UBJ_dThetaU = r_U * (-sin(thetaU) * u_U + cos(thetaU) * v_U);
    dP_UBJ = dP_UBJ_dThetaU * dThetaU_dThetaL;
    
    %% KPI axis
    w = P_UBJ - P_LBJ;
    w_hat = w / L_up;
    
    dw = dP_UBJ - dP_LBJ;
    dw_hat = dw / L_up;
    
    %% Camber
    % gamma = arcsin(w_hat_y)
    camber(i) = asind(w_hat(2));
    dCamber_dThetaL(i) = (1 / sqrt(1 - w_hat(2)^2)) * dw_hat(2) * (180 / pi);
    
    %% Wheel travel derivative (using LBJ Z)
    dZlbj_dThetaL(i) = dP_LBJ(3);
    
    %% Rotation matrix R_KPI
    R_KPI{i} = rotationBetweenVectors(w0_hat, w_hat);
    
    %% Store
    LBJ(i, :) = P_LBJ';
    UBJ(i, :) = P_UBJ';
    KPI_axis(i, :) = w_hat';
end

%% Wheel travel (LBJ Z displacement from ride height)
wheelTravel = LBJ(:, 3) - P_LBJ0(3);

%% Camber gain via related rates
% d(camber)/d(z) = [d(camber)/d(thetaL)] / [d(z)/d(thetaL)]
camberGain = dCamber_dThetaL(:) ./ dZlbj_dThetaL(:);

%% Package results
camberResults.thetaL = thetaL_range(:);
camberResults.thetaL_rideHeight = thetaL_0;
camberResults.wheelTravel = [zeros(nPoints,1) ,zeros(nPoints,1) , wheelTravel];
camberResults.camber = camber;
camberResults.camberGain = camberGain;
camberResults.LBJ = LBJ;
camberResults.UBJ = UBJ;
camberResults.KPI_axis = KPI_axis;
camberResults.R_KPI = R_KPI;
camberResults.w0_hat = w0_hat;
camberResults.L_upright = L_up;

vehicle.(manufacturer).kinematics.(axle).camberSweep = camberResults;

end


%% ========================================================================
%  HELPER FUNCTIONS
%  ========================================================================

%%
% function [P_c, r, u, v] = circleFromTwoSpheres(P1, P2, L1, L2)
% % CIRCLEFROMTWOSPHERES Calculate circle of intersection between two spheres
% %
% % Sphere 1: center P1, radius L1
% % Sphere 2: center P2, radius L2
% %
% % The intersection is a circle lying in a plane perpendicular to P1-P2.
% %
% % Returns:
% %   P_c - circle center
% %   r   - circle radius
% %   u,v - orthonormal basis vectors spanning the circle plane
% 
% d_vec = P2 - P1;
% d = norm(d_vec);
% d_hat = d_vec / d;
% 
% % Distance from P1 to circle center along d_hat
% a = (L1^2 - L2^2 + d^2) / (2 * d);
% 
% % Circle center
% P_c = P1 + a * d_hat;
% 
% % Circle radius
% r = sqrt(L1^2 - a^2);
% 
% % Basis vectors perpendicular to d_hat
% k = [0; 0; 1];
% if abs(dot(d_hat, k)) > 0.99
%     k = [1; 0; 0];
% end
% 
% u = cross(d_hat, k);
% u = u / norm(u);
% v = cross(d_hat, u);
% 
% end


function theta = findAngleOnCircle(P, P_c, r, u, v)
% FINDANGLEONCIRCLE Find angle theta such that P lies on the circle
%
% P = P_c + r * (cos(theta)*u + sin(theta)*v)

offset = P - P_c;
cosTheta = dot(offset, u) / r;
sinTheta = dot(offset, v) / r;
theta = atan2(sinTheta, cosTheta);

end


function R = rotationBetweenVectors(a, b)
% ROTATIONBETWEENVECTORS Rotation matrix that rotates vector a to vector b
%
% Uses Rodrigues' formula

a = a / norm(a);
b = b / norm(b);

v = cross(a, b);
s = norm(v);
c = dot(a, b);

if s < 1e-10
    if c > 0
        R = eye(3);
    else
        % 180 degree rotation
        if abs(a(1)) < 0.9
            perp = cross(a, [1; 0; 0]);
        else
            perp = cross(a, [0; 1; 0]);
        end
        perp = perp / norm(perp);
        R = -eye(3) + 2 * (perp * perp');
    end
    return;
end

vx = [  0,    -v(3),  v(2);
       v(3),   0,    -v(1);
      -v(2),  v(1),   0   ];

R = eye(3) + vx + vx * vx * (1 - c) / (s^2);

end