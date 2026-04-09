function vehicle = calculateRollCenter(vehicle, varargin)
    % calculateRollCenter - Compute roll center height at all wheel travel points and derivative at nominal
    %
    % Inputs:
    %   vehicle - Vehicle struct containing kinematics data
    %
    % Optional Parameters:
    %   'axle' - 'front' or 'rear' (default: 'rear')
    %   'manufacturer' - manufacturer name in struct (default: 'ford')
    %   'Plotting' - logical, whether to plot results (default: false)
    %
    % Outputs:
    %   RC_height_array - Roll center height at each wheel travel point [n x 1] (mm)
    %   dRC_dz_nominal - Rate of change of RC height with wheel travel at nominal (dimensionless)
    
    % Parse inputs
    p = inputParser;
    addRequired(p, 'vehicle');
    addParameter(p, 'axle', 'rear');
    addParameter(p, 'manufacturer', 'ford');
    addParameter(p, 'wheelCentre', 'simplified');
    addParameter(p, 'Plotting', false);
    
    parse(p, vehicle, varargin{:});
    manufacturer = p.Results.manufacturer;
    axle = p.Results.axle;
    doPlotting = p.Results.Plotting;
    wheelCentre = p.Results.wheelCentre;
    % extract results
    UBJ_array = vehicle.(manufacturer).kinematics.(axle).camberSweep.UBJ;
    if strcmp(wheelCentre, 'compensated')
        wheel_travel = vehicle.(manufacturer).kinematics.(axle).correctedContactPatch;
    elseif strcmp(wheelCentre, 'simplified')
        wheel_travel = vehicle.(manufacturer).kinematics.(axle).camberSweep.wheelTravel; 
    else
        wheel_travel = vehicle.(manufacturer).kinematics.(axle).camberSweep.wheelTravel; 
    end
        
    LBJ_array = vehicle.(manufacturer).kinematics.(axle).camberSweep.LBJ;
    
    % Extract kinematics data
    kin = vehicle.(manufacturer).kinematics.(axle);
    
    % Lower A-arm pivot points
    lower_fore = kin.lowerAArm.fore;
    lower_aft = kin.lowerAArm.aft;
    
    % Upper A-arm pivot points
    upper_fore = kin.upperAArm.fore;
    upper_aft = kin.upperAArm.aft;
    
    % Number of points
    n_points = size(UBJ_array, 1);
    RC_height_array = zeros(n_points, 1);
    
    % Storage for plotting data
    if doPlotting
        IC_array = zeros(n_points, 3);
        P_cl_array = zeros(n_points, 3);
        P_cu_array = zeros(n_points, 3);
        wheel_centre_array = zeros(n_points, 3);
        RC_array = zeros(n_points, 3);
    end
    
    % Calculate RC at each wheel travel point
    for i = 1:n_points
        LBJ = LBJ_array(i, :)';
        UBJ = UBJ_array(i, :)';
        
        % Lower A-arm swing axis center
        d_l_vec = lower_aft - lower_fore;
        d_l_mag = norm(d_l_vec);
        d_l_hat = d_l_vec / d_l_mag;
        
        L_lf = norm(lower_fore - LBJ);
        L_la = norm(lower_aft - LBJ);
        
        P_cl = lower_fore + (L_lf^2 - L_la^2 + d_l_mag^2) / (2 * d_l_mag) * d_l_hat;
        
        % Upper A-arm swing axis center
        d_u_vec = upper_aft - upper_fore;
        d_u_mag = norm(d_u_vec);
        d_u_hat = d_u_vec / d_u_mag;
        
        L_uf = norm(upper_fore - UBJ);
        L_ua = norm(upper_aft - UBJ);
        
        P_cu = upper_fore + (L_uf^2 - L_ua^2 + d_u_mag^2) / (2 * d_u_mag) * d_u_hat;
        
        % Find Instant Center (intersection of swing arm axes in Y-Z plane)
        mL = (LBJ(3) - P_cl(3)) / (LBJ(2) - P_cl(2));
        bL = LBJ(3) - mL * LBJ(2);
        
        mU = (UBJ(3) - P_cu(3)) / (UBJ(2) - P_cu(2));
        bU = UBJ(3) - mU * UBJ(2);
        
        IC_y = (bL - bU) / (mU - mL);
        IC_z = mU * IC_y + bU;
        
        % Wheel center location (350mm below LBJ)
        if strcmp(wheelCentre, 'compensated')
            wheel_centre = wheel_travel;
            wheel_centre = wheel_centre(i,:)';
        elseif strcmp(wheelCentre, 'simplified')
            wheel_centre = LBJ + [0; 0; -350];
        elseif strcmp(wheelCentre, 'underLBJ')
            wheel_centre = LBJ + [0; 0; -350];
        else
            wheel_centre = LBJ + [0; 0; -350];
        end
        % Find Roll Center (IC to wheel center, intersect at centerline)
        y_centerline = 0;
        t = (y_centerline - IC_y) / (wheel_centre(2) - IC_y);
        RC_z = IC_z + t * (wheel_centre(3) - IC_z);
        RC_height_array(i) = RC_z;
        
        % Store for plotting
        if doPlotting
            IC_array(i, :) = [0; IC_y; IC_z]';
            P_cl_array(i, :) = P_cl';
            P_cu_array(i, :) = P_cu';
            wheel_centre_array(i, :) = wheel_centre';
            RC_array(i, :) = [0; y_centerline; RC_z]';
        end
    end
    
    % Calculate derivative at nominal position (where wheel_travel = 0)
    [~, nominal_idx] = min(abs(wheel_travel(:,3)));
    
    if nominal_idx == 1
        % Forward difference
        dRC_dz_nominal = (RC_height_array(2) - RC_height_array(1)) / ...
                         (wheel_travel(2) - wheel_travel(1));
    elseif nominal_idx == n_points
        % Backward difference
        dRC_dz_nominal = (RC_height_array(end) - RC_height_array(end-1)) / ...
                         (wheel_travel(end) - wheel_travel(end-1));
    else
        % Central difference
        dRC_dz_nominal = (RC_height_array(nominal_idx+1) - RC_height_array(nominal_idx-1)) / ...
                         (wheel_travel(nominal_idx+1) - wheel_travel(nominal_idx-1));
    end
    vehicle.(manufacturer).kinematics.(axle).RC_height_array = RC_height_array;
    vehicle.(manufacturer).kinematics.(axle).dRC_dz_nominal = dRC_dz_nominal;
    % Plotting
    if doPlotting
        % Select 3 evenly spaced indices: start, middle, end
        plot_indices = round(linspace(1, n_points, 3));
        
        % Create color gradient (blue to red)
        colors = [0, 0, 1; 0.5, 0, 0.5; 1, 0, 0];
        
        % Create figure
        figure;
        hold on;
        grid on;
        axis equal;
        
        % Ground plane
        y_ground = linspace(min(wheel_centre_array(:, 2)) - 200, max(wheel_centre_array(:, 2)) + 200, 2);
        z_ground = wheel_centre_array(1, 3); % Ground level at contact patch
        plot(y_ground, [z_ground, z_ground], 'k-', 'LineWidth', 2, 'DisplayName', 'Ground');
        
        % Plot each position
        for idx = 1:3
            i = plot_indices(idx);
            color = colors(idx, :);
            
            % Get data for this position
            UBJ = UBJ_array(i, :);
            LBJ = LBJ_array(i, :);
            P_cl = P_cl_array(i, :);
            P_cu = P_cu_array(i, :);
            IC = IC_array(i, :);
%             if strcmp(wheelCentre, 'compensated')
%                 wheel_centre = vehicle.(manufacturer).kinematics.(axle).correctedContactPatch(i,:);
%             else
                wheel_centre = wheel_centre_array(i, :);
%             end
            RC = RC_array(i, :);
            
            % Solid lines - physical links
            % UBJ to LBJ (upright)
            plot([UBJ(2), LBJ(2)], [UBJ(3), LBJ(3)], '-', 'Color', color, 'LineWidth', 2.5, 'HandleVisibility', 'off');
            
            % LBJ to contact patch
            plot([LBJ(2), wheel_centre(2)], [LBJ(3), wheel_centre(3)], '-', 'Color', color, 'LineWidth', 2.5, 'HandleVisibility', 'off');
            
            % LBJ to P_cl (lower A-arm)
            plot([LBJ(2), P_cl(2)], [LBJ(3), P_cl(3)], '-', 'Color', color, 'LineWidth', 2.5, 'HandleVisibility', 'off');
            
            % UBJ to P_cu (upper A-arm)
            plot([UBJ(2), P_cu(2)], [UBJ(3), P_cu(3)], '-', 'Color', color, 'LineWidth', 2.5, 'HandleVisibility', 'off');
            
            % Dashed lines - projected swing arms
            % Upper swing arm axis (P_cu through UBJ to IC)
            plot([P_cu(2), IC(2)], [P_cu(3), IC(3)], '--', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            
            % Dashed lines - projected swing arms
            % Upper swing arm axis (P_cu through UBJ to IC)
            plot([wheel_centre(2), IC(2)], [wheel_centre(3), IC(3)], '--rs', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            
            % Lower swing arm axis (P_cl through LBJ to IC)
            plot([P_cl(2), IC(2)], [P_cl(3), IC(3)], '--', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            
            % Roll center cross
            plot(RC(2), RC(3), 'x', 'Color', color, 'MarkerSize', 14, 'LineWidth', 3, 'HandleVisibility', 'off');
            
            % Add to legend
            travel_str = sprintf('%.0f mm', wheel_travel(i));
            plot(NaN, NaN, 's', 'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 10, 'DisplayName', travel_str);
        end
        
        xlabel('Y Position (mm)');
        ylabel('Z Position (mm)');
        title(sprintf('Roll Center Analysis - %s %s', upper(manufacturer), upper(axle)));
        legend('Location', 'best');
        hold off;
    end
end