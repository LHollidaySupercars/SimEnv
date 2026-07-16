function Fx = mf_fx(kappa, Fz, varargin)
% MF_FX  Pacejka Magic Formula longitudinal tyre force (pure slip)
%
%   Fx = mf_fx(kappa, Fz)
%   Fx = mf_fx(kappa, Fz, params)
%
%   Inputs:
%     kappa  - longitudinal slip ratio [-], scalar or vector, range [-1, 1]
%     Fz     - normal load [N], scalar or vector (must broadcast with kappa)
%     params - (optional) struct with fields B, C, D, E
%              If omitted, default values are used (see below)
%
%   Output:
%     Fx     - longitudinal tyre force [N], same size as kappa
%
%   Magic Formula:
%     Fx = D * sin( C * atan( B*kappa - E*(B*kappa - atan(B*kappa)) ) )
%
%   Default parameters (passenger car baseline, Fz0 = 4000 N):
%     B  = 10      stiffness factor          [-]
%     C  = 1.65    shape factor              [-]
%     D  = 1.20    peak friction coefficient [-]  (Fx_peak = D * Fz)
%     E  = 0.97    curvature factor          [-]  (must be <= 1)
%
%   Notes:
%     - D here is the peak friction coefficient mu_x, so peak force = D * Fz
%     - Slip stiffness (initial slope) BCD = B * C * D * Fz
%     - Approximate slip at peak: kappa_peak ≈ 1 / (B * C)
%
%   Example:
%     kappa = linspace(-1, 1, 201);
%     Fx    = mf_fx(kappa, 4000);
%     plot(kappa, Fx);
%     xlabel('Slip ratio \kappa [-]'); ylabel('Fx [N]');

% --- Default parameters ---
p.B = 10.00;    % stiffness factor
p.C =  1.65;    % shape factor
p.D =  1.20;    % peak friction coefficient (mu_x)
p.E =  0.97;    % curvature factor

% --- Override with user-supplied struct ---
if nargin == 3
    user = varargin{1};
    fields = fieldnames(user);
    for i = 1:numel(fields)
        p.(fields{i}) = user.(fields{i});
    end
end

% --- Validate E ---
if p.E > 1
    warning('mf_fx:invalidE', 'E > 1 is physically invalid; clamping to 1.');
    p.E = 1;
end

% --- Peak force (D as mu_x, scaled by Fz) ---
D_force = p.D .* Fz;

% --- Core Magic Formula ---
phi = p.B .* kappa;
Fx  = D_force .* sin( p.C .* atan( phi - p.E .* (phi - atan(phi)) ) );

end


% =========================================================================
%  Quick-plot demo (runs when script is executed directly, not as function)
% =========================================================================
% Remove or comment out the lines below if using as a pure function file.

% if false  % set to true to run the demo
%     kappa  = linspace(-1, 1, 401);
%     Fz_nom = 4000;                        % nominal load [N]
% 
%     Fx_nom  = mf_fx(kappa, Fz_nom);
%     Fx_high = mf_fx(kappa, 6000);         % higher load example
%     Fx_low  = mf_fx(kappa, 2000);         % lower load example
% 
%     figure('Name', 'Magic Formula – Fx vs slip ratio');
%     plot(kappa, Fx_nom,  'b-',  'LineWidth', 1.8, 'DisplayName', 'Fz = 4000 N'); hold on;
%     plot(kappa, Fx_high, 'r--', 'LineWidth', 1.4, 'DisplayName', 'Fz = 6000 N');
%     plot(kappa, Fx_low,  'k:',  'LineWidth', 1.4, 'DisplayName', 'Fz = 2000 N');
%     xline(0, 'Color', [0.5 0.5 0.5], 'LineStyle', ':');
%     yline(0, 'Color', [0.5 0.5 0.5], 'LineStyle', ':');
%     xlabel('Slip ratio \kappa [-]');
%     ylabel('F_x [N]');
%     legend('Location', 'southeast');
%     grid on;
%     title('Pacejka Magic Formula – longitudinal force');
% 
%     fprintf('\n--- Derived quantities at Fz = 4000 N ---\n');
%     p_def = struct('B', 10, 'C', 1.65, 'D', 1.20, 'E', 0.97);
%     fprintf('  Peak Fx         : %.0f N\n',  p_def.D * Fz_nom);
%     fprintf('  Slip stiffness  : %.0f N\n',  p_def.B * p_def.C * p_def.D * Fz_nom);
%     fprintf('  Approx kappa_pk : %.3f\n',    1 / (p_def.B * p_def.C));
% end