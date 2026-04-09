function Fy = MF_basic(xRange, B, D, x_m, varargin)


    p = inputParser;
    addRequired(p, 'xRange');
    addRequired(p, 'B');
    addRequired(p, 'D');
    addRequired(p, 'x_m');
    addOptional(p, 'slipRange', [0, 12]);  % default = 0 - 12 degrees
    addOptional(p, 'fidelity', 100);  % default = 100
    addParameter(p, 'degrees', true);
    
    parse(p,xRange, B, D, x_m, varargin{:});
    
    % Access parsed values
    slipRange = p.Results.slipRange;
    degrees = p.Results.degrees;
    fidelity = p.Results.fidelity;
    if degrees
        x_m = deg2rad(x_m);
        slipAngleRange = deg2rad(xRange);
    end
    y_a = x_m;
    C = 1 + (1 - 2/ pi * asin(y_a / D)); % Shape Factor, the + is indicate an initial positive growth
    E = (B * x_m - tan(pi / (2*C))) / ...
     ( B*x_m - atan(B*x_m));
%     y = D * sin( C * atan(B*x - E * (B * x - atan(B*x))));

    Fy = D * sin( C * atan(B*slipAngleRange - E * ( B * slipAngleRange - atan(B*slipAngleRange))));

end
