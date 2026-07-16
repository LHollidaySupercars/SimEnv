%% skidpad_init.m
% Initialisation script for skid pad bicycle model simulation.
% Run this before opening or simulating the Simulink model.
% All parameters are stored in a struct 'veh' and passed to the model
% via base workspace.

clear; clc;

%% -------------------------------------------------------------------------
% VEHICLE PARAMETERS
% -------------------------------------------------------------------------

veh.m    = 1300;        % Total mass [kg]
veh.L    = 2.750;       % Wheelbase [m]
veh.a    = 1.468;       % CG to front axle [m]
veh.b    = veh.L - veh.a; % CG to rear axle [m]
veh.Iz   = 1850;        % Yaw moment of inertia [kg.m^2]
veh.h_cg = 0.45;        % CG height [m]
veh.mu   = 1.0;         % Road friction coefficient [-]
veh.g    = 9.81;        % Gravitational acceleration [m/s^2]

% Static normal loads (no longitudinal load transfer)
veh.Fzf  = veh.m * veh.g * veh.b / veh.L;  % Front axle normal load [N]
veh.Fzr  = veh.m * veh.g * veh.a / veh.L;  % Rear axle normal load [N]

%% -------------------------------------------------------------------------
% PACEJKA MAGIC FORMULA TYRE PARAMETERS
% Pure lateral force, steady state: Fy = D*sin(C*atan(B*alpha - E*(B*alpha - atan(B*alpha))))
% D is computed inside the plant from mu*Fz so it scales with normal load.
% Front and rear are identical to start — update when real coefficients available.
% -------------------------------------------------------------------------

% Front tyre
tyre.f.B = 10.0;        % Stiffness factor [-]
tyre.f.C = 1.9;         % Shape factor [-]
tyre.f.E = 0.97;        % Curvature factor [-]

% Rear tyre
tyre.r.B = 10.0;
tyre.r.C = 1.9;
tyre.r.E = 0.97;

%% -------------------------------------------------------------------------
% SKID PAD GEOMETRY
% -------------------------------------------------------------------------

skidpad.R           = 15.25;    % Circle radius [m]
skidpad.L_straight  = 10.0;    % Entry straight length [m]
skidpad.n_laps      = 2;       % Number of laps on circle

%% -------------------------------------------------------------------------
% CONTROLLER PARAMETERS
% -------------------------------------------------------------------------

% Stanley path tracker (outer loop)
ctrl.stanley_k      = 1.0;     % Cross-track gain [tunable]

% Pure Pursuit configuration 
ctrl.e_ct_max       = 5;

% Yaw rate PID (mid loop)
ctrl.yr_Kp          = 2.0;
ctrl.yr_Ki          = 0.5;
ctrl.yr_Kd          = 0.1;

% Body slip limiter (inner loop)
ctrl.beta_max       = 6 * (pi/180);  % Max allowable body slip [rad] (~9 deg)
ctrl.beta_Kp        = 1.0;             % Proportional gain on beta error [tunable]

% Longitudinal speed PID
ctrl.spd_Kp         = 800;
ctrl.spd_Ki         = 200;
ctrl.spd_Kd         = 10;
ctrl.Fx_max         = 4000;    % Max drive force, rear axle [N]
ctrl.Fx_min         = -8000;   % Max brake force [N]

%% -------------------------------------------------------------------------
% LOAD PATH WAYPOINTS FROM EXCEL
% -------------------------------------------------------------------------

path_file = 'skidpad_path.xlsx';

if ~isfile(path_file)
    error('skidpad_init: path file ''%s'' not found. Generate and place in working directory.', path_file);
end

path_data  = readtable(path_file);
waypoints  = [path_data.x_norm, path_data.y_norm, path_data.psi];  % [N x 3] array

fprintf('Loaded %d waypoints from %s\n', size(waypoints,1), path_file);

%% -------------------------------------------------------------------------
% DESIRED SPEED
% Conservative starting value — increase toward grip limit iteratively.
% At grip limit: Fy_total = m*u^2/R, so u_lim = sqrt(mu*g*R) is the
% kinematic upper bound; true limit from Pacejka will be lower.
% -------------------------------------------------------------------------

u_lim       = sqrt(veh.mu * veh.g * skidpad.R);   % Kinematic upper bound [m/s]
ctrl.u_des  = 5;                        % Start at 80% — tune upward
ctrl.u_des  = 15;      
fprintf('Kinematic speed limit: %.2f m/s (%.1f km/h)\n', u_lim, u_lim*3.6);
fprintf('Initial u_des:         %.2f m/s (%.1f km/h)\n', ctrl.u_des, ctrl.u_des*3.6);

%% -------------------------------------------------------------------------
% SIMULATION SETTINGS
% -------------------------------------------------------------------------

sim_t_end   = 120;      % Simulation duration [s] — enough for entry + 2 laps + settling
sim_dt      = 0.01;     % Fixed time step [s]

%% -------------------------------------------------------------------------
% INITIAL CONDITIONS
% -------------------------------------------------------------------------

% Vehicle starts at origin, pointing along the straight (east, psi = 0)
ic.X    = waypoints(1,1);
ic.Y    = waypoints(1,2);
ic.psi  = waypoints(1,3);
ic.u    = 1.0;     % Small initial forward speed to avoid division by zero [m/s]
ic.v    = 0;
ic.r    = 0;

fprintf('\nskidpad_init complete. Ready to simulate.\n');