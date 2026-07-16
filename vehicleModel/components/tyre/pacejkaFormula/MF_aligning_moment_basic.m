function Mz = MF_aligning_moment_basic(xRange, B, D, x_m, varargin)
    % MF_ALIGNING_MOMENT_BASIC Magic Formula for aligning moment (self-aligning torque)
    %
    % Inputs:
    %   xRange - slip angle range (vector or scalar)
    %   B      - stiffness factor
    %   D      - peak moment
    %   x_m    - slip angle at peak moment
    %
    % Optional Parameters (varargin):
    %   'slipRange' - [min, max] slip angle range (default: [0, 12])
    %   'fidelity'  - number of points (default: 100)
    %   'degrees'   - true (default) if angles in degrees, false for radians
    %
    % Outputs:
    %   Mz - Aligning moment (N·m)
    %
    % Usage:
    %   Mz = MF_aligning_moment_basic(alpha, 10, 100, 5)
    %   Mz = MF_aligning_moment_basic(alpha, 10, 100, 5, 'degrees', false)
    %
    % Notes:
    %   - Aligning moment is the torque about the vertical axis (Z-axis)
    %   - Also called "self-aligning torque" - tends to straighten the tire
    %   - Provides steering feel/feedback
    %   - Typically peaks at lower slip angles than lateral force
    %   - Peak Mz usually occurs around 2-4 degrees slip angle
    %   - Mz goes to zero or becomes negative at high slip angles
    
    p = inputParser;
    addRequired(p, 'xRange');
    addRequired(p, 'B');
    addRequired(p, 'D');
    addRequired(p, 'x_m');
    addOptional(p, 'slipRange', [0, 12]);  % default = 0 - 12 degrees
    addOptional(p, 'fidelity', 100);       % default = 100
    addParameter(p, 'degrees', true);
    
    parse(p, xRange, B, D, x_m, varargin{:});
    
    % Access parsed values
    slipRange = p.Results.slipRange;
    degrees = p.Results.degrees;
    fidelity = p.Results.fidelity;
    
    % Convert to radians if needed
    if degrees
        x_m = deg2rad(x_m);
        slipAngleRange = deg2rad(xRange);
    else
        slipAngleRange = xRange;
    end
    
    % Calculate Magic Formula coefficients from x_m
    y_a = x_m;
    
    % Shape Factor
    C = 1 + (1 - 2/pi * asin(y_a / D));
    
    % Curvature factor
    E = (B * x_m - tan(pi / (2*C))) / ...
        (B * x_m - atan(B * x_m));
    
    % Basic Magic Formula
    Mz = D * sin(C * atan(B * slipAngleRange - E * (B * slipAngleRange - atan(B * slipAngleRange))));
    
end