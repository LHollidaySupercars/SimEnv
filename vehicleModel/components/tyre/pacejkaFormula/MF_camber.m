function Fy = MF_camber(xRange, B, D, x_m, r_Vy1, r_Vy2, r_Vy3, r_Vy4, r_Vy5 , r_Vy6, gamma, u_y, df_z, r_Hyl, r_Hy2, k,  varargin)

    % fill in information
    p = inputParser;
    addRequired(p, 'xRange');
    addRequired(p, 'B');
    addRequired(p, 'D');
    addRequired(p, 'x_m');
    addRequired(p, 'r_Vy1');
    addRequired(p, 'r_Vy2');
    addRequired(p, 'r_Vy3');
    addRequired(p, 'r_Vy4');
    addRequired(p, 'r_Vy5');
    addRequired(p, 'r_Vy6');
    addRequired(p, 'gamma');
    addRequired(p, 'u_y');
    addRequired(p, 'df_z');
    addRequired(p, 'r_Hyl');
    addRequired(p, 'r_Hy2');
    addRequired(p, 'k');
    addOptional(p, 'IA', [0, -2, -4, -6, -8])
    addOptional(p, 'slipRange', [0, 12]);  % default = 0 - 12 degrees
    addOptional(p, 'fidelity', 100);  % default = 100
    addParameter(p, 'degrees', true);
    
    parse(p,xRange, B, D, x_m, r_Vy1, r_Vy2, r_Vy3, r_Vy4, r_Vy5, r_Vy6, gamma, u_y, df_z, r_Hyl, r_Hy2, k, varargin{:});
    
    
    % Access parsed values
    slipRange = p.Results.slipRange;
    degrees = p.Results.degrees;
    fidelity = p.Results.fidelity;
    IA = p.Results.IA;
    if degrees
        x_m = deg2rad(x_m);
        slipAngleRange = deg2rad(xRange);
    end
    y_a = x_m;
    C = 1 + (1 - 2/ pi * asin(y_a / D)); % Shape Factor, the + is indicate an initial positive growth
    E = (B * x_m - tan(pi / (2*C))) / ...
     ( B*x_m - atan(B*x_m));
    % y = D * sin( C * atan(B*x - E * (B * x - atan(B*x))));


    Fy = D * sin( C * atan(B*slipAngleRange - E * ( B * slipAngleRange - atan(B*slipAngleRange))));

    % additional contributions
%     df_z = (F_z - F_zo) / F_zo;
    df_z = df_z
    F_z = D;
    S_Hyk = r_Hyl+r_Hy2 .* df_z;
    D_Vyk = u_y .* F_z .* (r_Vy1 + r_Vy2 .* df_z + r_Vy3 .* IA') .* cos(atan(r_Vy4 .*tan(slipAngleRange)));
    S_Vyk = D_Vyk.*sin(r_Vy5 .* atan(r_Vy6 .* k));
%     S_Hyk = r_Hyl + r_H2 * df_z
    k_s = k + S_Hyk;
    Fy = Fy + S_Vyk
   
    
    %% Attempt two equations 4.E19 ->
    C_y = p_Cy1 * lamda_Cy
    D_y = u_u * F_z * zeta_2
    u_y = (p_Dy1 + p_Dy2 * df_z) *( 1 + p_py3 * dp_i ^2) * 1 - pDy3 * gamma_ ^2 ) * lamda_uy
    E_y = ( p_Ey1 + p_Ey2  df_z) * ( 1 + p_Ey5 * gamma_^2 - (p_Ey3 + p_Ey4 * gamma_) * sgn(a_y)) * lamda_Ey
    K_
    a_y = slipAngleRange + S_Hy
    Fy = D * sin( C * atan(B*slipAngleRange - E * ( B * slipAngleRange - atan(B*slipAngleRange)))) + S_vy;
    
end

% explanation
% What Each Parameter Does and Where to See It
% pHy3 (Camber Thrust)
% 
% Look at: Fy when slip angle = 0° across different camber angles
% You'll see: A linear offset in lateral force even with no slip angle
% Sign: Positive values mean negative camber produces force toward the inside of the turn
% Physical meaning: The tire generates lateral force just from being tilted
% 
% pKy6 (Camber Stiffness Effect)
% 
% Look at: The initial slope (Fy vs slip angle) at small slip angles across different cambers
% You'll see: The slope either gets steeper or shallower as you add camber
% Sign: Usually negative - camber typically reduces cornering stiffness
% Physical meaning: How camber changes the tire's sensitivity to slip angle in the linear region
% 
% pVy3 (Camber Peak Force Effect)
% 
% Look at: Maximum Fy achieved at each camber angle
% You'll see: Peak force changes as camber increases
% Typical behavior: Peak increases from 0° to ~3-4° negative camber, then decreases
% Physical meaning: How camber affects the maximum grip available
% 
% pVy4 (Load Dependency of Camber Peak)
% 
% Look at: How the camber effect on peak force changes with vertical load
% You'll see: At high loads, camber might help more/less than at low loads
% Physical meaning: Interaction between load and camber effects
% 
% pKy7 (Higher Order Camber-Stiffness)
% 
% Look at: Non-linear camber effects on stiffness (if pKy6 alone doesn't capture it)
% You'll see: Camber effects that don't scale linearly with camber^2
% Usually: Leave this at zero initially unless you see strong non-linearity
% 
% Practical Workflow
% 
% Plot Fy vs slip angle curves for each camber angle (all on one plot)
% Check the y-intercept (slip = 0) → that's your camber thrust
% Check the initial slope → that's your stiffness effect
% Check the peak value → that's your peak force effect
% Repeat at different loads → that tells you the load-dependent terms (pVy4, pHy4)