function vehicle = solveWheelToe(vehicle, varargin)
% SOLVEWHEELTOE Solves the toe kinematics given camber results
%
% Once the KPI axis is known (from solveWheelCamber), the toe rod constrains
% rotation about that axis. This function solves for that rotation angle phi.
%
% INPUTS:
%   vehicle - vehicle data structure
%
% OPTIONAL PARAMETERS:
%   'axle' - 'front' or 'rear' (default: 'rear')
%   'manufacturer' - vehicle manufacturer (default: 'ford')
%   'fidelity' - number of points for steering sweep (default: 100)
%   'isSteeringAngle' - boolean, enable steering displacement (default: false)
%
% OUTPUTS:
%   toeResults - struct containing:
%       .phi        - rotation about KPI axis [rad] (nTravel x nSteer)
%       .toe        - toe angle [deg] (nTravel x nSteer)
%       .toeGain    - d(toe)/d(wheelTravel) [deg/mm] (nTravel x nSteer)
%       .toeRodUprightPos - toe rod upright pickup positions (nTravel x 3 x nSteer)
%       .steeringRackDisplacement - steering rack displacement values [mm] (1 x nSteer)
%
% DERIVATION:
%
% The toe rod upright pickup is fixed on the upright. At ride height:
%   r_TU0 = P_TU0 - P_LBJ0
%
% As the suspension moves:
%   1. The KPI axis rotates (captured by R_KPI)
%   2. The upright can rotate by angle phi about the KPI axis
%
% The toe rod pickup position is:
%   P_TU = P_LBJ + R_toe(phi) * R_KPI * r_TU0
%
% The constraint is:
%   |P_TU - P_TC|^2 = L_TR^2
%
% This reduces to: A*cos(phi) + B*sin(phi) = C
% Solved as: phi = atan2(B,A) - acos(C/sqrt(A^2+B^2))
%% =========================== To do ========================
% apply the 3 sphere rule and proof
% |B' - P₁|² = r₁²
% |B' - P₂|² = r₂²
% |B' - P₃|² = r₃²
%% Parse inputs
p = inputParser;
addRequired(p, 'vehicle');
addParameter(p, 'axle', 'rear');
addParameter(p, 'manufacturer', 'ford');
addParameter(p, 'fidelity', 100, @isnumeric);
addParameter(p, 'isSteeringAngle', false, @islogical);
addParameter(p, 'use3Spheres', true, @islogical);

parse(p, vehicle, varargin{:});

manufacturer = p.Results.manufacturer;
axle = p.Results.axle;
isSteeringAngle = p.Results.isSteeringAngle;
fidelity = p.Results.fidelity;
use3Spheres = p.Results.use3Spheres;

params = vehicle.(manufacturer).kinematics.(axle);

%% Setup steering displacement range
if isSteeringAngle
    steeringRange = vehicle.(manufacturer).steering.ratio * [-pi, pi];
    steeringRackDisplacement = [zeros(fidelity, 1), linspace(steeringRange(1), steeringRange(2), fidelity)', zeros(fidelity, 1)];
    nSteer = length(steeringRackDisplacement);
else
    steeringRackDisplacement = [0,0,0];
    nSteer = size(steeringRackDisplacement);
    nSteer = nSteer(1)
end


%% Extract geometry
P_TC_base = params.lowerAArm.toeRodChassis(:);
P_TU0_base = params.lowerAArm.toeRodUpright(:);
camberResults = vehicle.(manufacturer).kinematics.(axle).camberSweep;
LBJ = camberResults.LBJ;
KPI_axis = camberResults.KPI_axis;
R_KPI = camberResults.R_KPI;
w0_hat = camberResults.w0_hat;
wheelTravel = camberResults.wheelTravel(:,3);

nPoints = size(LBJ, 1);

%% Initial configuration
P_LBJ0 = LBJ(abs(wheelTravel) == min(abs(wheelTravel)), :)';
P_LBJ0 = P_LBJ0(:, 1);  % Take first if multiple

% Initial wheel forward direction (perpendicular to KPI)
f0 = [1; 0; 0];
f0 = f0 - dot(f0, w0_hat) * w0_hat;
f0 = f0 / norm(f0);

%% Preallocate
phi = zeros(nPoints, nSteer);
toe = zeros(nPoints, nSteer);
toeRodUprightPos = zeros(nPoints, 3, nSteer);

%% Steering angle loop (outer loop)
for j = 1:nSteer
    % Apply steering displacement to both toe rod points
    if use3Spheres
        [uprightToeRod_new(j,:), ~] = threeSphereDisplacement(vehicle, manufacturer, steeringRackDisplacement(j, :), 'axle', axle);
       
        P_TC = P_TC_base + steeringRackDisplacement(j, :)';
        P_TU0 = P_TU0_base + uprightToeRod_new(j,:)';
    else
    
        P_TC = P_TC_base + steeringRackDisplacement(j, :)';
        P_TU0 = P_TU0_base + steeringRackDisplacement(j, :)';
    end
    % Toe rod offset from LBJ in initial frame
    r_TU0 = P_TU0 - P_LBJ0;
    
    % Toe rod length (constant for this steering position)
    L_TR = norm(P_TU0 - P_TC);
    %% Wheel travel loop (inner loop)
    for i = 1:nPoints
        P_LBJ = LBJ(i, :)';
        w_hat = KPI_axis(i, :)';
        R_kpi = R_KPI{i};
        
        %% Transform toe rod offset by KPI rotation
        r_TU_prime = R_kpi * r_TU0;
        
        %% Decompose into parallel and perpendicular to current KPI axis
        r_parallel = dot(w_hat, r_TU_prime) * w_hat;
        r_perp = r_TU_prime - r_parallel;
        r_cross = cross(w_hat, r_TU_prime);
        
        rho_sq = dot(r_perp, r_perp);  % |r_perp|^2 = |r_cross|^2
        
        %% Toe rod constraint
        % P_TU = P_LBJ + r_parallel + cos(phi)*r_perp + sin(phi)*r_cross
        % |P_TU - P_TC|^2 = L_TR^2
        
        p0 = P_LBJ + r_parallel - P_TC;
        
        A_phi = dot(p0, r_perp);
        B_phi = dot(p0, r_cross);
        C_phi = (L_TR^2 - dot(p0, p0) - rho_sq) / 2;
        
        R_phi = sqrt(A_phi^2 + B_phi^2);
        
        %% Check if solution exists
        if abs(C_phi / R_phi) > 1
            warning('No toe solution at wheelTravel = %.2f mm, steer = %.2f mm. C/R = %.4f', ...
                wheelTravel(i), steeringRackDisplacement(j), C_phi / R_phi);
            phi(i, j) = NaN;
            toe(i, j) = NaN;
            toeRodUprightPos(i, :, j) = NaN;
            continue;
        end
        
        %% Solve for phi
        psi_phi = atan2(B_phi, A_phi);
        alpha_phi = acos(C_phi / R_phi);
        if contains(axle, "front") && contains(manufacturer, ["ford", "GM", "toyota"])
            phi(i, j) = psi_phi + alpha_phi;
        elseif contains(axle, "rear") && contains(manufacturer, ["ford", "GM", "toyota"])
            phi(i, j) = psi_phi - alpha_phi;
        end
        
        %% Compute toe rod upright position
        P_TU = P_LBJ + r_parallel + cos(phi(i, j)) * r_perp + sin(phi(i, j)) * r_cross;
        toeRodUprightPos(i, :, j) = P_TU';
        
        %% Compute toe angle
        R_toe = axisAngleRotation(w_hat, phi(i, j));
        R_total = R_toe * R_kpi;
        
        f = R_total * f0;
        toe(i, j) = atan2d(f(2), f(1));
        
    end
end

%% Toe gain (numerical derivative with respect to wheel travel)
toeResults.steeringRackDisplacement = steeringRackDisplacement(:,2);
[~, zeroIndex] = min(abs(toeResults.steeringRackDisplacement));
toeGain = gradient(toe(:,zeroIndex), wheelTravel);

%% Package results
toeResults.phi = phi;
toeResults.toe = toe;
toeResults.uprightToeRod_new = uprightToeRod_new;
toeResults.toeGain = toeGain;
toeResults.toeRodUprightPos = toeRodUprightPos;
toeResults.wheelTravel = wheelTravel;

vehicle.(manufacturer).kinematics.(axle).toeSweep = toeResults; 
end


%% ========================================================================
%  HELPER FUNCTION
%  ========================================================================




%%
function R = axisAngleRotation(axis, angle)
% AXISANGLEROTATION Rotation matrix for rotation by angle about axis
%
% Uses Rodrigues' formula

axis = axis / norm(axis);

K = [  0,       -axis(3),  axis(2);
      axis(3),   0,       -axis(1);
     -axis(2),  axis(1),   0      ];

R = eye(3) + sin(angle) * K + (1 - cos(angle)) * K * K;

end