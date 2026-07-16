% ========================================================================
% Steering Geometry - Three Sphere Intersection
% ========================================================================

% --- Adjustable Parameters ---
steeringDisplacement = [0; 1; 0];  % mm
plotResults = true;

% --- Extract Points ---
LBJ                = vehicle.ford.kinematics.front.lowerAArm.ballJoint';
UBJ                = vehicle.ford.kinematics.front.upperAArm.ballJoint';
% uprightToeRod_old  = vehicle.ford.kinematics.rear.steeringRack.toeRodUpright';
% chassisToeRod_old  = vehicle.ford.kinematics.rear.steeringRack.ackermann';
uprightToeRod_old  = vehicle.ford.kinematics.front.lowerAArm.toeRodUpright';
chassisToeRod_old  = vehicle.ford.kinematics.front.lowerAArm.toeRodChassis';
chassisToeRod_new  = chassisToeRod_old + steeringDisplacement;

% --- Link Lengths ---
r1 = norm(uprightToeRod_old - LBJ);
r2 = norm(uprightToeRod_old - UBJ);
r3 = norm(uprightToeRod_old - chassisToeRod_old);

% --- Plane Normals and Constants ---
A1 = 2 * (LBJ - UBJ);
b1 = r2^2 - r1^2 - dot(UBJ, UBJ) + dot(LBJ, LBJ);

A2 = 2 * (LBJ - chassisToeRod_new);
b2 = r3^2 - r1^2 - dot(chassisToeRod_new, chassisToeRod_new) + dot(LBJ, LBJ);

% --- Line Direction ---
lineDir = cross(A1, A2);
lineDir = lineDir / norm(lineDir);

% --- Find P0 (point on line) ---
[~, idx] = max(abs(lineDir));
cols = setdiff(1:3, idx);

A_sys = [A1(cols); A2(cols)];  % 2x2
b_sys = [b1; b2];              % 2x1

P0 = zeros(1, 3);
P0(cols) = (A_sys \ b_sys)';   % Transpose result back to 1x3

% --- Intersect Line with Sphere 1 ---
D = P0 - LBJ;                          % 1x3
B_coeff = 2 * dot(D, lineDir);         % scalar
C_coeff = dot(D, D) - r1^2;            % scalar
discriminant = B_coeff^2 - 4 * C_coeff; % scalar

t1 = (-B_coeff + sqrt(discriminant)) / 2;
t2 = (-B_coeff - sqrt(discriminant)) / 2;

P1 = P0 + t1 * lineDir;  % 1x3
P2 = P0 + t2 * lineDir;  % 1x3

% --- Pick closest to old position ---
if norm(P1 - uprightToeRod_old) < norm(P2 - uprightToeRod_old)
    uprightToeRod_new = P1;
else
    uprightToeRod_new = P2;
end

% --- Print Results ---
fprintf('Old upright: [%.4f, %.4f, %.4f]\n', uprightToeRod_old);
fprintf('New upright: [%.4f, %.4f, %.4f]\n', uprightToeRod_new);
fprintf('Delta:       [%.4f, %.4f, %.4f]\n', uprightToeRod_new - uprightToeRod_old);


% ----checking vector length)
fprintf('Old length: %.4f\n', norm(LBJ - uprightToeRod_old));
fprintf('New length: %.4f\n', norm(LBJ - uprightToeRod_new));
fprintf('Length Delta: %.4f\n', norm(LBJ - uprightToeRod_old) - norm(LBJ - uprightToeRod_new))


% --- Plot ---
if plotResults
    figure; hold on;

    % Fixed points (black)
    plot3(LBJ(1), LBJ(2), LBJ(3), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k');
    plot3(UBJ(1), UBJ(2), UBJ(3), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k');
    text(LBJ(1), LBJ(2), LBJ(3), '  LBJ', 'FontSize', 10);
    text(UBJ(1), UBJ(2), UBJ(3), '  UBJ', 'FontSize', 10);

    % Old positions (blue)
    plot3(chassisToeRod_old(1), chassisToeRod_old(2), chassisToeRod_old(3), 'bs', 'MarkerSize', 8, 'MarkerFaceColor', 'b');
    plot3(uprightToeRod_old(1), uprightToeRod_old(2), uprightToeRod_old(3), 'bo', 'MarkerSize', 8, 'MarkerFaceColor', 'b');
    text(chassisToeRod_old(1), chassisToeRod_old(2), chassisToeRod_old(3), '  Chassis (old)', 'FontSize', 9, 'Color', 'b');
    text(uprightToeRod_old(1), uprightToeRod_old(2), uprightToeRod_old(3), '  Upright (old)', 'FontSize', 9, 'Color', 'b');

    % Old links (blue)
    plot3([LBJ(1), uprightToeRod_old(1)], [LBJ(2), uprightToeRod_old(2)], [LBJ(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);
    plot3([UBJ(1), uprightToeRod_old(1)], [UBJ(2), uprightToeRod_old(2)], [UBJ(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);
    plot3([chassisToeRod_old(1), uprightToeRod_old(1)], [chassisToeRod_old(2), uprightToeRod_old(2)], [chassisToeRod_old(3), uprightToeRod_old(3)], 'b-', 'LineWidth', 1.5);

    % New positions (red)
    plot3(chassisToeRod_new(1), chassisToeRod_new(2), chassisToeRod_new(3), 'rs', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    plot3(uprightToeRod_new(1), uprightToeRod_new(2), uprightToeRod_new(3), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    text(chassisToeRod_new(1), chassisToeRod_new(2), chassisToeRod_new(3), '  Chassis (new)', 'FontSize', 9, 'Color', 'r');
    text(uprightToeRod_new(1), uprightToeRod_new(2), uprightToeRod_new(3), '  Upright (new)', 'FontSize', 9, 'Color', 'r');

    % New links (red)
    plot3([LBJ(1), uprightToeRod_new(1)], [LBJ(2), uprightToeRod_new(2)], [LBJ(3), uprightToeRod_new(3)], 'r-', 'LineWidth', 1.5);
    plot3([UBJ(1), uprightToeRod_new(1)], [UBJ(2), uprightToeRod_new(2)], [UBJ(3), uprightToeRod_new(3)], 'r-', 'LineWidth', 1.5);
    plot3([chassisToeRod_new(1), uprightToeRod_new(1)], [chassisToeRod_new(2), uprightToeRod_new(2)], [chassisToeRod_new(3), uprightToeRod_new(3)], 'r-', 'LineWidth', 1.5);

    axis equal; grid on;
    xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
    title('Steering Geometry - Upright Toe Rod Solver');
end