function Fy = MF_lateral_camber(alpha, B, D, y_a, gamma, pHy3, pDy3, varargin)
    % MF_LATERAL_CAMBER Magic Formula with camber effects for lateral force
    %
    % Inputs:
    %   alpha  - slip angle range (vector)
    %   B      - stiffness factor
    %   D      - peak force (N)
    %   y_a    - slip angle at peak force (deg or rad depending on 'degrees' parameter)
    %   gamma  - camber angle(s) - scalar or vector (deg or rad)
    %   pHy3   - camber thrust coefficient (horizontal shift)
    %   pDy3   - camber effect on peak force reduction
    %
    % Optional Parameters:
    %   'degrees' - true (default) if angles in degrees, false for radians
    %
    % Outputs:
    %   Fy - Lateral force (N x M matrix where N = length(alpha), M = length(gamma))
    %
    % Usage in tyreDataViewer:
    %   gamma can be entered as: 0, -2, -4, -6
    %   Each gamma value produces a separate curve
    
    p = inputParser;
    addRequired(p, 'alpha');
    addRequired(p, 'B');
    addRequired(p, 'D');
    addRequired(p, 'y_a');
    addRequired(p, 'gamma');
    addRequired(p, 'pHy3');
    addRequired(p, 'pDy3');
    addParameter(p, 'degrees', true);
    
    parse(p, alpha, B, D, y_a, gamma, pHy3, pDy3, varargin{:});
    degrees = p.Results.degrees;
    
    % Convert to radians if needed
    if degrees
        alpha_rad = deg2rad(alpha);
        gamma_rad = deg2rad(gamma);
        y_a_rad = deg2rad(y_a);
    else
        alpha_rad = alpha;
        gamma_rad = gamma;
        y_a_rad = y_a;
    end
    
    % Make sure dimensions work for multiple camber angles
    % alpha should be column vector, gamma should be row vector
    alpha_rad = alpha_rad(:);      % Force column [N x 1]
    gamma_rad = gamma_rad(:)';     % Force row [1 x M]
    
    % Calculate C and E from y_a (same for all camber angles)
    C = 1 + (1 - 2/pi * asin(y_a_rad / D));
    E = (B * y_a_rad - tan(pi / (2*C))) / (B * y_a_rad - atan(B * y_a_rad));
    
    % Modify peak force for camber (broadcasts across gammas)
    D_camber = D * (1 - pDy3 * gamma_rad.^2);  % [1 x M]
    
    % Camber thrust (horizontal shift)
    SHy = pHy3 * gamma_rad;  % [1 x M]
    
    % Shifted slip angle (broadcasts: each column is a different gamma)
    alpha_y = alpha_rad + SHy;  % [N x M]
    
    % Base Magic Formula with modified D and shifted alpha
    Fy = D_camber .* sin(C * atan(B * alpha_y - E * (B * alpha_y - atan(B * alpha_y))));
    % Output: [N x M] matrix
end