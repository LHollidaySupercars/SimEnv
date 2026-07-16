% MF_FullSet
function Fy = MF_camber_Inclusion()

% fill in information
    p = inputParser;
    addRequired(p, 'xRange');
    addRequired(p, 'B');
    addRequired(p, 'D');
    addRequired(p, 'x_m');
    addOptional(p, 'slipRange', [0, 12]);  % default = 0 - 12 degrees
    addOptional(p, 'fidelity', 100);  % default = 100
    addParameter(p, 'degrees', true);
    
    parse(p,xRange, B, D, x_m, varargin{:});



    

end