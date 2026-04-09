function vehicle = solveDamperTravel(vehicle, varargin)
% SOLVEDAMPERTRAVEL Calculate damper displacement by rotating damper pickup point
% around lower A-arm axis
%
% Inputs:
%   vehicle - Vehicle structure containing kinematics data
%
% Optional Parameters:
%   'axle'              - Axle to analyze ('front' or 'rear'), default: 'rear'
%   'manufacturer'      - Manufacturer name in vehicle struct, default: 'ford'
%   'wheelCentre'       - Wheel center calculation method, default: 'simplified'
%                         'simplified'  - uses camberSweep.wheelTravel
%                         'compensated' - uses correctedContactPatch
%   'maxDamperLength'   - Maximum damper length [mm], default: 560
%   'minDamperLength'   - Minimum damper length [mm], default: 440
%   'sweepRange'        - Rotation sweep range [rad], default: 1.0
%   'numPoints'         - Number of points in sweep, default: 1001
%   'debug'             - Debug level (0=off, 1=verbose), default: 0
%   'Plotting'          - Enable plotting, default: false
%
% Outputs:
%   vehicle - Updated vehicle structure with damper travel data

    % Parse and validate inputs
    p = inputParser;
    addRequired(p, 'vehicle', @isstruct);
    addParameter(p, 'axle', 'rear', @ischar);
    addParameter(p, 'manufacturer', 'ford', @ischar);
    addParameter(p, 'wheelCentre', 'simplified', @(x) ismember(x, {'simplified', 'compensated','zeroedSimplified', 'zeroedCompensated' }));
    addParameter(p, 'maxDamperLength', 560, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'minDamperLength', 440, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'sweepRange', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'numPoints', 1001, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'debug', 0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'Plotting', false, @islogical);
    
    parse(p, vehicle, varargin{:});
    
    % Extract parameters
    manufacturer = p.Results.manufacturer;
    axle = p.Results.axle;
    wheelCentre = p.Results.wheelCentre;
    maxDamperLength = p.Results.maxDamperLength;
    minDamperLength = p.Results.minDamperLength;
    sweepRange = p.Results.sweepRange;
    numPoints = p.Results.numPoints;
    debug = p.Results.debug;
    doPlotting = p.Results.Plotting;
    
    % Validate damper length parameters
    if minDamperLength >= maxDamperLength
        error('minDamperLength must be less than maxDamperLength');
    end
    
    % Validate vehicle structure has required fields
    validateVehicleStructure(vehicle, manufacturer, axle);
    
    % Extract kinematics data (shorthand for readability)
    kin = vehicle.(manufacturer).kinematics.(axle);
    
    % Get datum position (center of original sweep)
    if ~isfield(kin, 'camberSweep') || ~isfield(kin.camberSweep, 'thetaL')
        error('Vehicle structure missing camberSweep.thetaL field');
    end
    
    datumIndex = ceil(length(kin.camberSweep.thetaL) / 2);
    datumPosition = kin.camberSweep.thetaL(datumIndex);
    
    % Create new sweep range centered on datum
    % sets baseline +- 0.3 rad, operates about this point
    
    thetaSweep = linspace(datumPosition - sweepRange, datumPosition + sweepRange, numPoints);
    
    % Define rotation axis (lower A-arm axis) as unit vector (1×3)
    lowerArmFore = kin.lowerAArm.fore(:)';  % Ensure row vector (1×3)
    lowerArmAft = kin.lowerAArm.aft(:)';    % Ensure row vector (1×3)
    rotationAxis = lowerArmAft - lowerArmFore;
    axisLength = norm(rotationAxis);
    
    if axisLength < eps
        error('Lower A-arm fore and aft points are coincident - cannot define rotation axis');
    end
    
    rotationAxis = rotationAxis / axisLength;  % Normalize to unit vector (1×3)
    
    % Vector to be rotated: from lower A-arm fore point to damper pickup on rocker
    % Translate to origin (lower A-arm fore point becomes origin)
    rockerDamperPickup = kin.rocker.damperPickup(:)';  % Row vector (1×3)
    vectorToRotate = rockerDamperPickup - lowerArmFore;  % (1×3)
    
    % Chassis damper pickup point (translated to same origin)
    chassisDamperPickup = kin.damper.chassisPickup(:)';  % Row vector (1×3)
    chassisPickupFromOrigin = chassisDamperPickup - lowerArmFore;  % (1×3)
    
    % Pre-allocate output arrays
    rotatedPositions = zeros(numPoints, 3);  % (n×3)
    damperLength = zeros(numPoints, 1);       % (n×1)
    rotationError = zeros(numPoints, 1);      % (n×1)
    
    % Initialize debug figure if needed
    if debug >= 1
        debugFig = figure('Name', 'Damper Travel Debug');
        hold on; grid on; axis equal;
        xlabel('X [mm]'); ylabel('Y [mm]'); zlabel('Z [mm]');
        title(sprintf('%s %s Damper Rotation Debug', upper(manufacturer), upper(axle)));
        view(3);
    end
    
    % Loop through rotation angles and calculate damper positions
    for i = 1:numPoints
        % Rotation angle relative to datum
        theta = thetaSweep(i) - datumPosition;
        
        % Apply Rodrigues' rotation formula
        % v_rot = v*cos(θ) + (k×v)*sin(θ) + k*(k·v)*(1-cos(θ))
        % where k is rotation axis unit vector, v is vector to rotate
        k = rotationAxis;  % (1×3)
        v = vectorToRotate;  % (1×3)
        
        cosTheta = cos(theta);
        sinTheta = sin(theta);
        
        % Calculate rotated vector (1×3)
        rotatedVec = v * cosTheta + ...
                     cross(k, v) * sinTheta + ...
                     k * dot(k, v) * (1 - cosTheta);
        
        rotatedPositions(i, :) = rotatedVec;  % Store as row
        
        % Calculate damper length (distance from rotated pickup to chassis pickup)
        damperVector = rotatedVec - chassisPickupFromOrigin;
        damperLength(i) = norm(damperVector);
        
        % Calculate rotation error (should preserve length)
        rotationError(i) = norm(rotatedVec) - norm(v);
        
        % Debug plotting (every 50th point)
        if debug >= 1 && mod(i, 50) == 0
            figure(debugFig);
            origin = [0, 0, 0];  % (1×3)
            
            % Plot lower A-arm axis
            lowerArmVector = lowerArmAft - lowerArmFore;
            plot3([0, lowerArmVector(1)], [0, lowerArmVector(2)], [0, lowerArmVector(3)], ...
                  'k-', 'LineWidth', 3);
            
            % Plot rotation axis direction
            quiver3(0, 0, 0, rotationAxis(1)*200, rotationAxis(2)*200, rotationAxis(3)*200, ...
                    'k--', 'LineWidth', 1.5, 'MaxHeadSize', 0.5);
            
            % Plot original vector
            quiver3(0, 0, 0, vectorToRotate(1), vectorToRotate(2), vectorToRotate(3), ...
                    'b', 'LineWidth', 2, 'MaxHeadSize', 0.5);
            
            % Plot rotated vector
            quiver3(0, 0, 0, rotatedVec(1), rotatedVec(2), rotatedVec(3), ...
                    'r', 'LineWidth', 2, 'MaxHeadSize', 0.5);
            
            % Print debug info
            if debug >= 2
                fprintf('Iteration %d: θ = %.2f°, Damper Length = %.2f mm, Error = %.6f mm\n', ...
                        i, rad2deg(theta), damperLength(i), rotationError(i));
            end
        end
    end
    
    if debug >= 1
        figure(debugFig);
        legend('Lower A-Arm', 'Rotation Axis', 'Original Position', 'Rotated Position', ...
               'Location', 'best');
        hold off;
    end
    
    % Find indices where damper length is within specified range
    validIndices = find(damperLength >= minDamperLength & damperLength <= maxDamperLength);
    
    if isempty(validIndices)
        warning('No damper positions found within specified length range [%.1f, %.1f] mm', ...
                minDamperLength, maxDamperLength);
        % Find closest approaches
        [~, idxMin] = min(abs(damperLength - minDamperLength));
        [~, idxMax] = min(abs(damperLength - maxDamperLength));
        validIndices = min(idxMin, idxMax):max(idxMin, idxMax);
    end
    
    % Extract valid range
    indexMin = validIndices(1);
    indexMax = validIndices(end);
    
    % Store results in vehicle structure
    vehicle.(manufacturer).kinematics.(axle).damper.chassisPickupRot = ...
        rotatedPositions(indexMin:indexMax, :);
    
    vehicle.(manufacturer).kinematics.(axle).damper.chassisPickupError = ...
        rotationError(indexMin:indexMax);
    
    vehicle.(manufacturer).kinematics.(axle).damper.displacement = ...
        damperLength(indexMin:indexMax);
    
    vehicle.(manufacturer).kinematics.(axle).damper.length = ...
        damperLength(indexMin:indexMax) - damperLength(indexMax);
    
    vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL = ...
        (thetaSweep(indexMin:indexMax) - datumPosition)';  % Column vector
    [~, indexOfMin] = min(abs(vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL));
    vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL_0Index = ...
        indexOfMin;
    % Optional plotting
    if doPlotting
        plotDamperTravel(thetaSweep, damperLength, rotationError, ...
                        indexMin, indexMax, minDamperLength, maxDamperLength, ...
                        manufacturer, axle, vehicle, wheelCentre, 'displacement');
                    
       damperLengthFrame = damperLength - damperLength(indexMax);
       minDamperLength = minDamperLength - damperLength(indexMax)
       maxDamperLength = maxDamperLength - damperLength(indexMax) 
       plotDamperTravel(thetaSweep, damperLengthFrame, rotationError, ...
                        indexMin, indexMax, minDamperLength, maxDamperLength, ...
                        manufacturer, axle, vehicle, wheelCentre, 'length');             
       plotDamperTravel(thetaSweep, damperLengthFrame, rotationError, ...
                        indexMin, indexMax, minDamperLength, maxDamperLength, ...
                        manufacturer, axle, vehicle, 'zeroedSimplified', 'length');                 
    end
    
    % Summary output
    if debug >= 1
        fprintf('\n=== Damper Travel Summary ===\n');
        fprintf('Valid range: indices %d to %d (out of %d)\n', indexMin, indexMax, numPoints);
        fprintf('Damper length range: %.2f to %.2f mm\n', ...
                min(damperLength(indexMin:indexMax)), max(damperLength(indexMin:indexMax)));
        fprintf('Rotation angle range: %.2f to %.2f deg\n', ...
                rad2deg(thetaSweep(indexMin) - datumPosition), ...
                rad2deg(thetaSweep(indexMax) - datumPosition));
        fprintf('Max rotation error: %.6f mm\n', max(abs(rotationError)));
        fprintf('=============================\n\n');
    end
end

function validateVehicleStructure(vehicle, manufacturer, axle)
    % Validate that vehicle structure contains required fields
    
    if ~isfield(vehicle, manufacturer)
        error('Vehicle structure does not contain manufacturer "%s"', manufacturer);
    end
    
    if ~isfield(vehicle.(manufacturer), 'kinematics')
        error('Vehicle.%s structure does not contain "kinematics" field', manufacturer);
    end
    
    if ~isfield(vehicle.(manufacturer).kinematics, axle)
        error('Vehicle.%s.kinematics does not contain axle "%s"', manufacturer, axle);
    end
    
    kin = vehicle.(manufacturer).kinematics.(axle);
    
    % Check for required geometry fields
    requiredFields = {'lowerAArm', 'rocker', 'damper'};
    for i = 1:length(requiredFields)
        if ~isfield(kin, requiredFields{i})
            error('Vehicle.%s.kinematics.%s missing required field "%s"', ...
                  manufacturer, axle, requiredFields{i});
        end
    end
    
    % Check lower A-arm points
    if ~isfield(kin.lowerAArm, 'fore') || ~isfield(kin.lowerAArm, 'aft')
        error('lowerAArm must contain "fore" and "aft" pickup points');
    end
    
    % Check damper points
    if ~isfield(kin.rocker, 'damperPickup')
        error('rocker must contain "damperPickup" point');
    end
    
    if ~isfield(kin.damper, 'chassisPickup')
        error('damper must contain "chassisPickup" point');
    end
end

function plotDamperTravel(thetaSweep, damperLength, rotationError, ...
                          indexMin, indexMax, minDamperLength, maxDamperLength, ...
                          manufacturer, axle, vehicle, wheelCentre, plotType)
    % Plot damper displacement and rotation error
    
    % Convert angles to degrees for plotting
    thetaDeg = rad2deg(thetaSweep - thetaSweep(ceil(length(thetaSweep)/2)));
    
    % Determine wheel travel data source based on wheelCentre parameter
    if strcmp(wheelCentre, 'simplified')
        % Use standard wheelTravel data
        wheelTravelFieldPath = 'camberSweep.wheelTravel';
        hasWheelTravel = isfield(vehicle.(manufacturer).kinematics.(axle), 'camberSweep') && ...
                         isfield(vehicle.(manufacturer).kinematics.(axle).camberSweep, 'wheelTravel');
        if hasWheelTravel
            wheelTravel = vehicle.(manufacturer).kinematics.(axle).camberSweep.wheelTravel;
        end
        dataSourceLabel = 'Simplified';
        
    elseif strcmp(wheelCentre, 'compensated')
        % Use corrected contact patch data
        wheelTravelFieldPath = 'correctedContactPatch';
        hasWheelTravel = isfield(vehicle.(manufacturer).kinematics.(axle), 'correctedContactPatch');
        
        if ~hasWheelTravel
            error('wheelCentre set to ''compensated'' but correctedContactPatch data not found in vehicle.%s.kinematics.%s', ...
                  manufacturer, axle);
        end
        
        wheelTravel = vehicle.(manufacturer).kinematics.(axle).correctedContactPatch;
        dataSourceLabel = 'Compensated';
        
        
        %%
    elseif strcmp(wheelCentre, 'zeroedSimplified')
        % Use standard wheelTravel data
        wheelTravelFieldPath = 'camberSweep.wheelTravel';
        hasWheelTravel = isfield(vehicle.(manufacturer).kinematics.(axle), 'camberSweep') && ...
                         isfield(vehicle.(manufacturer).kinematics.(axle).camberSweep, 'wheelTravel');
        if hasWheelTravel
            wheelTravel = flip(vehicle.(manufacturer).kinematics.(axle).camberSweep.wheelTravel -...
                vehicle.(manufacturer).kinematics.(axle).camberSweep.wheelTravel(vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL_0Index,:));
        end
        dataSourceLabel = 'Simplified';
        
    elseif strcmp(wheelCentre, 'zeroedCompensated')
        % Use corrected contact patch data
        wheelTravelFieldPath = 'correctedContactPatch';
        hasWheelTravel = isfield(vehicle.(manufacturer).kinematics.(axle), 'correctedContactPatch');
        
        if ~hasWheelTravel
            error('wheelCentre set to ''compensated'' but correctedContactPatch data not found in vehicle.%s.kinematics.%s', ...
                  manufacturer, axle);
        end
        
        wheelTravel = vehicle.(manufacturer).kinematics.(axle).correctedContactPatch;
        dataSourceLabel = 'Compensated';
        
    else
        error('Invalid wheelCentre option: %s. Must be ''simplified'' or ''compensated''', wheelCentre);
    end
    
    % Create figure based on whether wheelTravel data exists
    if hasWheelTravel
        % Create larger figure with 5 subplots for full analysis
        figure('Name', sprintf('Damper Travel & Motion Ratio Analysis (%s)', dataSourceLabel), ...
               'Position', [50, 50, 1400, 900]);
        numPlots = 5;
    else
        % Create smaller figure with 2 subplots (original plots only)
        figure('Name', 'Damper Travel Analysis', 'Position', [100, 100, 1200, 500]);
        numPlots = 2;
    end
    
    % Plot 1: Damper Length vs Rotation Angle
    subplot(ceil(numPlots/2), 2, 1);
    hold on; grid on;
    
    % Plot full sweep
    plot(thetaDeg, damperLength, 'b-', 'LineWidth', 1.5);
    
    % Highlight valid range
    plot(thetaDeg(indexMin:indexMax), damperLength(indexMin:indexMax), ...
         'r-', 'LineWidth', 2);
    
    % Plot damper length limits
    yLimits = ylim;
    plot([thetaDeg(1), thetaDeg(end)], [maxDamperLength, maxDamperLength], ...
         'k--', 'LineWidth', 1);
    plot([thetaDeg(1), thetaDeg(end)], [minDamperLength, minDamperLength], ...
         'k--', 'LineWidth', 1);
    
    xlabel('Rotation Angle [deg]');
    ylabel('Damper Length [mm]');
    title(sprintf('%s %s Damper Displacement', upper(manufacturer), upper(axle)));
    legend('Full Sweep', 'Valid Range', 'Length Limits', 'Location', 'best');
    hold off;
    
    % Plot 2: Rotation Error (zoomed to show detail, not square waves)
    subplot(ceil(numPlots/2), 2, 2);
    hold on; grid on;
    
    plot(thetaDeg, rotationError * 1e3, 'b-', 'LineWidth', 1.5);
    plot(thetaDeg(indexMin:indexMax), rotationError(indexMin:indexMax) * 1e3, ...
         'r-', 'LineWidth', 2);
    
    % Set y-axis limits to ±1 µm to avoid square wave appearance
    maxError = max(abs(rotationError)) * 1e3;
    if maxError < 1
        ylim([-1, 1]);
    else
        ylim([-maxError*1.1, maxError*1.1]);
    end
    
    xlabel('Rotation Angle [deg]');
    ylabel('Rotation Error [μm]');
    title('Rodrigues Formula Accuracy');
    legend('Full Sweep', 'Valid Range', 'Location', 'best');
    hold off;
    
    % If wheelTravel data exists, add motion ratio analysis
    if hasWheelTravel
        % Extract valid range data
        if strcmp(plotType, 'displacement')
            displacement = vehicle.(manufacturer).kinematics.(axle).damper.displacement;
        elseif strcmp(plotType, 'length')
            displacement = vehicle.(manufacturer).kinematics.(axle).damper.length;
        end
        % Calculate instantaneous motion ratio and displacement increments
        % Using VERTICAL (z-component) wheel travel only
        numPoints = length(displacement);
        MR = zeros(numPoints, 1);
        deltaDisplacement = zeros(numPoints, 1);
        deltaWheelTravel = zeros(numPoints, 1);
        verticalWheelTravel = zeros(numPoints, 1);
        
        for i = 1:numPoints
            % Extract vertical (z-component) wheel travel
            verticalWheelTravel(i) = wheelTravel(i, 3);
            
            if i > 1
                % Instantaneous changes (vertical only)
                deltaWheelTravel(i) = wheelTravel(i, 3) - wheelTravel(i-1, 3);
                deltaDisplacement(i) = displacement(i) - displacement(i-1);
                
                % Motion ratio: vertical wheel travel per unit damper displacement
                if abs(deltaDisplacement(i)) > eps
                    MR(i) = deltaWheelTravel(i) / deltaDisplacement(i);
                else
                    MR(i) = MR(i-1);  % Avoid division by zero
                end
            end
        end
        
        % Set first value to second value to avoid zero
        MR(1) = MR(2);
        
        % Plot 3: Motion Ratio vs Damper Displacement
        subplot(ceil(numPlots/2), 2, 3);
        hold on; grid on;
        
        plot(displacement, MR, 'b-', 'LineWidth', 1.5);
        
        xlabel('Damper Displacement [mm]');
        ylabel('Motion Ratio [mm/mm]');
        title(sprintf('Motion Ratio vs Damper Displacement - %s', dataSourceLabel));
        hold off;
        
        % Plot 4: Motion Ratio vs Vertical Wheel Travel
        subplot(ceil(numPlots/2), 2, 4);
        hold on; grid on;
        
        plot(verticalWheelTravel, MR, 'b-', 'LineWidth', 1.5);
        
        xlabel('Vertical Wheel Travel [mm]');
        ylabel('Motion Ratio [mm/mm]');
        title(sprintf('Motion Ratio vs Wheel Travel - %s', dataSourceLabel));
        hold off;
        
        % Plot 5: Damper Displacement vs Vertical Wheel Travel (Cumulative)
        subplot(ceil(numPlots/2), 2, 5);
        hold on; grid on;
        
        plot(displacement, verticalWheelTravel, 'b-', 'LineWidth', 1.5);
        
        xlabel('Damper Displacement [mm]');
        ylabel('Vertical Wheel Travel [mm]');
        title(sprintf('Damper vs Wheel Travel (Cumulative) - %s', dataSourceLabel));
        hold off;
    end
end