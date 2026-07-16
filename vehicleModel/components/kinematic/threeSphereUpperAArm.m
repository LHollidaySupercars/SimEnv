function vehicle = threeSphereUpperAArm(vehicle, manufacturer, varargin)

    p = inputParser;
    addRequired(p, 'vehicle');
    addRequired(p, 'manufacturer');
    addParameter(p, 'geometrySystem', 'extendAArm');
    addParameter(p, 'axle', 'rear');
    addParameter(p, 'newRadii', [0, 0], @isnumeric);
    addParameter(p, 'plotResults', false, @islogical);
    
    parse(p, vehicle, manufacturer, varargin{:});
    
    axle = p.Results.axle;
    plotResults = p.Results.plotResults;
    newRadii = p.Results.newRadii;
    geometrySystem = p.Results.geometrySystem;
    % ========================================================================
    % Upper A-Arm Geometry - Three Sphere Intersection
    % ========================================================================
    
    % --- Extract Points ---
    if strcmp(geometrySystem, 'extendAArm')
        LBJ          = vehicle.(manufacturer).kinematics.(axle).lowerAArm.ballJoint;
        UBJ          = vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJointCAD;
        chassisFore  = vehicle.(manufacturer).kinematics.(axle).upperAArm.fore;
        chassisAft   = vehicle.(manufacturer).kinematics.(axle).upperAArm.aft;
            % --- Link Lengths (Sphere Radii) ---
        r1 = norm(LBJ - UBJ);           % Distance from LBJ to UBJ
        r2 = norm(chassisFore - UBJ - newRadii);   % Distance from fore pivot to UBJ
        r3 = norm(chassisAft - UBJ - newRadii);    % Distance from aft pivot to UBJ
    elseif strcmp(geometrySystem, 'extendUBJ')
        LBJ          = vehicle.(manufacturer).kinematics.(axle).lowerAArm.ballJoint;
        UBJ          = vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJointCAD;
        chassisFore  = vehicle.(manufacturer).kinematics.(axle).upperAArm.fore;
        chassisAft   = vehicle.(manufacturer).kinematics.(axle).upperAArm.aft;
        % --- Link Lengths (Sphere Radii) ---
        r1 = norm(LBJ - UBJ - newRadii );           % Distance from LBJ to UBJ
        r2 = norm(chassisFore - UBJ);   % Distance from fore pivot to UBJ
        r3 = norm(chassisAft - UBJ);    % Distance from aft pivot to UBJ
    end

    % --- Plane 1: Subtract sphere 1 from sphere 2 ---
    % Sphere 1: ||P - LBJ||² = r1²
    % Sphere 2: ||P - chassisFore||² = r2²
    A1 = 2 * (LBJ - chassisFore);
    b1 = r2^2 - r1^2 + dot(LBJ, LBJ) - dot(chassisFore, chassisFore);
    
    % --- Plane 2: Subtract sphere 1 from sphere 3 ---
    % Sphere 3: ||P - chassisAft||² = r3²
    A2 = 2 * (LBJ - chassisAft);
    b2 = r3^2 - r1^2 + dot(LBJ, LBJ) - dot(chassisAft, chassisAft);
    
    % --- Line Direction (intersection of two planes) ---
    lineDir = cross(A1, A2);
    lineDir = lineDir / norm(lineDir);
    
    % --- Find P0 (point on line) ---
    % Select two coordinates where lineDir is smallest (non-zero for third coord)
    [~, idx] = max(abs(lineDir));
    cols = setdiff(1:3, idx);
    
    A_sys = [A1(cols); A2(cols)];  % 2x2
    b_sys = [b1; b2];              % 2x1
    
    P0 = zeros(1, 3);
    P0(cols) = (A_sys \ b_sys)';   % Transpose result back to 1x3
    
    % --- Intersect Line with Sphere 1 (centered at LBJ, radius r1) ---
    D = P0 - LBJ;                          % 1x3
    B_coeff = 2 * dot(D, lineDir);         % scalar
    C_coeff = dot(D, D) - r1^2;            % scalar
    discriminant = B_coeff^2 - 4 * C_coeff; % scalar
    
    if discriminant < 0
        error('No intersection found - spheres do not intersect');
    end
    
    t1 = (-B_coeff + sqrt(discriminant)) / 2;
    t2 = (-B_coeff - sqrt(discriminant)) / 2;
    
    P1 = P0 + t1 * lineDir;  % 1x3
    P2 = P0 + t2 * lineDir;  % 1x3
    
    % --- Pick closest to old UBJ position ---
    if norm(P1 - UBJ) < norm(P2 - UBJ)
        newUBJ_Location = P1;
    else
        newUBJ_Location = P2;
    end
    
    if strcmp(geometrySystem, 'extendAArm')
        vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJoint = newUBJ_Location;
    elseif strcmp(geometrySystem, 'extendUBJ')
        vehicle.(manufacturer).kinematics.(axle).upperAArm.ballJoint = newUBJ_Location;
    end
    % --- Print Results ---
    fprintf('\n=== Upper A-Arm Ball Joint Solution ===\n');
    fprintf('Old UBJ: [%.4f, %.4f, %.4f]\n', UBJ);
    fprintf('New UBJ: [%.4f, %.4f, %.4f]\n', newUBJ_Location);
    fprintf('Delta:   [%.4f, %.4f, %.4f]\n', newUBJ_Location - UBJ);
    
    % --- Verify Link Lengths ---
    fprintf('\n--- Link Length Verification ---\n');
    fprintf('LBJ to UBJ:        Old = %.4f, New = %.4f, Error = %.6f\n', ...
        norm(LBJ - UBJ), norm(LBJ - newUBJ_Location), ...
        abs(r1 - norm(LBJ - newUBJ_Location)));
    
    fprintf('Fore pivot to UBJ: Old = %.4f, New = %.4f, Error = %.6f\n', ...
        norm(chassisFore - UBJ), norm(chassisFore - newUBJ_Location), ...
        abs(r2 - norm(chassisFore - newUBJ_Location)));
    
    fprintf('Aft pivot to UBJ:  Old = %.4f, New = %.4f, Error = %.6f\n', ...
        norm(chassisAft - UBJ), norm(chassisAft - newUBJ_Location), ...
        abs(r3 - norm(chassisAft - newUBJ_Location)));
    
    % --- Store results in output structure ---
    upperAArm.oldUBJ = UBJ;
    upperAArm.newUBJ = newUBJ_Location;
    upperAArm.delta = newUBJ_Location - UBJ;
    upperAArm.linkLengthErrors = [
        abs(r1 - norm(LBJ - newUBJ_Location));
        abs(r2 - norm(chassisFore - newUBJ_Location));
        abs(r3 - norm(chassisAft - newUBJ_Location))
    ];
    upperAArm.maxError = max(upperAArm.linkLengthErrors);
    
    vehicle.(manufacturer).kinematics.(axle).upperAArm.adjustmentInfo = upperAArm;
    
    % --- Plot ---
    if plotResults
        figure; hold on;
        
        % Fixed points (black)
        plot3(LBJ(1), LBJ(2), LBJ(3), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'k');
        plot3(chassisFore(1), chassisFore(2), chassisFore(3), 'ks', ...
            'MarkerSize', 10, 'MarkerFaceColor', 'k');
        plot3(chassisAft(1), chassisAft(2), chassisAft(3), 'ks', ...
            'MarkerSize', 10, 'MarkerFaceColor', 'k');
        text(LBJ(1), LBJ(2), LBJ(3), '  LBJ', 'FontSize', 10);
        text(chassisFore(1), chassisFore(2), chassisFore(3), '  Fore Pivot', ...
            'FontSize', 10);
        text(chassisAft(1), chassisAft(2), chassisAft(3), '  Aft Pivot', ...
            'FontSize', 10);
        
        % Old UBJ position (blue)
        plot3(UBJ(1), UBJ(2), UBJ(3), 'bo', 'MarkerSize', 8, 'MarkerFaceColor', 'b');
        text(UBJ(1), UBJ(2), UBJ(3), '  UBJ (old)', 'FontSize', 9, 'Color', 'b');
        
        % Old links (blue)
        plot3([LBJ(1), UBJ(1)], [LBJ(2), UBJ(2)], [LBJ(3), UBJ(3)], ...
            'b-', 'LineWidth', 1.5);
        plot3([chassisFore(1), UBJ(1)], [chassisFore(2), UBJ(2)], ...
            [chassisFore(3), UBJ(3)], 'b-', 'LineWidth', 1.5);
        plot3([chassisAft(1), UBJ(1)], [chassisAft(2), UBJ(2)], ...
            [chassisAft(3), UBJ(3)], 'b-', 'LineWidth', 1.5);
        
        % New UBJ position (red)
        plot3(newUBJ_Location(1), newUBJ_Location(2), newUBJ_Location(3), ...
            'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
        text(newUBJ_Location(1), newUBJ_Location(2), newUBJ_Location(3), ...
            '  UBJ (new)', 'FontSize', 9, 'Color', 'r');
        
        % New links (red)
        plot3([LBJ(1), newUBJ_Location(1)], [LBJ(2), newUBJ_Location(2)], ...
            [LBJ(3), newUBJ_Location(3)], 'r-', 'LineWidth', 1.5);
        plot3([chassisFore(1), newUBJ_Location(1)], [chassisFore(2), newUBJ_Location(2)], ...
            [chassisFore(3), newUBJ_Location(3)], 'r-', 'LineWidth', 1.5);
        plot3([chassisAft(1), newUBJ_Location(1)], [chassisAft(2), newUBJ_Location(2)], ...
            [chassisAft(3), newUBJ_Location(3)], 'r-', 'LineWidth', 1.5);
        
        axis equal; grid on;
        xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
        title('Upper A-Arm Geometry - Three Sphere Ball Joint Solver');
        legend('Fixed Points', '', '', 'Old UBJ', 'New UBJ', 'Location', 'best');
    end
end