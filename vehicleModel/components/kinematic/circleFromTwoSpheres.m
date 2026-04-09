function [P_c, r, u, v] = circleFromTwoSpheres(P1, P2, L1, L2)
% CIRCLEFROMTWOSPHERES Calculate circle of intersection between two spheres
%
% Sphere 1: center P1, radius L1
% Sphere 2: center P2, radius L2
%
% The intersection is a circle lying in a plane perpendicular to P1-P2.
%
% Returns:
%   P_c - circle center
%   r   - circle radius
%   u,v - orthonormal basis vectors spanning the circle plane

d_vec = P2 - P1;
d = norm(d_vec);
d_hat = d_vec / d;

% Distance from P1 to circle center along d_hat
a = (L1^2 - L2^2 + d^2) / (2 * d);

% Circle center
P_c = P1 + a * d_hat;

% Circle radius
r = sqrt(L1^2 - a^2);

% Basis vectors perpendicular to d_hat
k = [0; 0; 1];
if abs(dot(d_hat, k)) > 0.99
    k = [1; 0; 0];
end

u = cross(d_hat, k);
u = u / norm(u);
v = cross(d_hat, u);

end