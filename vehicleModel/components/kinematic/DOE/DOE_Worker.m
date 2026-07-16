function DOE_Worker(workerID, tmpDir)
% DOE_WORKER  Runs kinematic sweep for one chunk of DOE combinations.
%
%   Standalone file — called by DOE_Experiment.m parallel launcher via:
%     matlab -batch "addpath(genpath('<path>')); DOE_Worker(<id>, '<tmp>')"
%
%   In serial mode, DOE_Experiment.m calls DOE_Experiment_worker (local
%   function) directly instead — this file is only needed for parallel.

    fprintf('========================================\n');
    fprintf('  DOE Worker %d  started  %s\n', workerID, datestr(now,'HH:MM:SS'));
    fprintf('========================================\n\n');

    % Load chunk and config
    S   = load(fullfile(tmpDir, sprintf('chunk_%d.mat', workerID)));
    cfg = load(fullfile(tmpDir, 'worker_cfg.mat'));

    workerChunk  = S.workerChunk;
    doeCfg       = cfg.doeCfg;
    nRuns        = size(workerChunk, 1);

    manufacturer = doeCfg.manufacturer;
    axle         = doeCfg.axle;
    CoGHeight    = doeCfg.CoGHeight;
    camberShims  = doeCfg.camberShims;
    shims        = doeCfg.shims;
    allClevisPosSlots = doeCfg.allClevisPosSlots;
    allUbjSlots       = doeCfg.allUbjSlots;
    % Field names are axle-prefixed: fufY_abs / rufY_abs etc.
    pfx = lower(axle(1));  % 'f' for front, 'r' for rear
    ufY_abs  = doeCfg.([pfx 'ufY_abs']);
    uaY_abs  = doeCfg.([pfx 'uaY_abs']);
    lfY_abs  = doeCfg.([pfx 'lfY_abs']);
    laY_abs  = doeCfg.([pfx 'laY_abs']);
    damperAxial_offsets = doeCfg.damperAxial_offsets;
    varNames = doeCfg.varNames;

    results = cell(nRuns, length(varNames));

    for run = 1:nRuns

        ufPOS = workerChunk(run,1);  ufY = ufY_abs(workerChunk(run,2));
        uaPOS = workerChunk(run,3);  uaY = uaY_abs(workerChunk(run,4));
        lfPOS = workerChunk(run,5);  lfY = lfY_abs(workerChunk(run,6));
        laPOS = workerChunk(run,7);  laY = laY_abs(workerChunk(run,8));
        ubjPOS_idx    = workerChunk(run,9);
        damperAxial_idx = workerChunk(run,10);

        ubjPOS       = allUbjSlots(ubjPOS_idx);
        damperAxial  = damperAxial_offsets(damperAxial_idx);

        ufSlot = allClevisPosSlots{ufPOS};
        uaSlot = allClevisPosSlots{uaPOS};
        lfSlot = allClevisPosSlots{lfPOS};
        laSlot = allClevisPosSlots{laPOS};

        key = sprintf('%s|%.1f|%s|%.1f|%s|%.1f|%s|%.1f|%d|%.1f', ...
                      ufSlot, ufY, uaSlot, uaY, lfSlot, lfY, laSlot, laY, ubjPOS, damperAxial);

        fprintf('[W%d %d/%d] %s  ', workerID, run, nRuns, key);

        % Reset base struct
        GEN3_KinematicParameters;

        % Apply clevis shim stacks
        vehicle = clevisOffset(vehicle, sprintf('%s.kinematics.%s.upperAArm.fore', manufacturer, axle), shims.UF, axle);
        vehicle = clevisOffset(vehicle, sprintf('%s.kinematics.%s.upperAArm.aft',  manufacturer, axle), shims.UA, axle);
        vehicle = clevisOffset(vehicle, sprintf('%s.kinematics.%s.lowerAArm.fore', manufacturer, axle), shims.LF, axle);
        vehicle = clevisOffset(vehicle, sprintf('%s.kinematics.%s.lowerAArm.aft',  manufacturer, axle), shims.LA, axle);

        % Apply POS offsets — key prefix depends on axle (R=rear, F=front)
        pfxUpper = upper(axle(1));
        POS = containers.Map();
        POS(sprintf('%sUF_POS', pfxUpper)) = ufPOS;
        POS(sprintf('%sUA_POS', pfxUpper)) = uaPOS;
        POS(sprintf('%sLF_POS', pfxUpper)) = lfPOS;
        POS(sprintf('%sLA_POS', pfxUpper)) = laPOS;
        POS(sprintf('%s_UBJ_UPRIGHT_POS', upper(axle))) = ubjPOS;  % Variable UBJ position
        vehicle = clevisPOSOffset(vehicle, manufacturer, POS, axle);

        % Apply damper chassis pickup offset along damper axial direction (RH adjuster)
        % Unit vector points from rocker pickup toward chassis pickup
        chassis_nom = vehicle.(manufacturer).kinematics.(axle).damper.chassisPickup(:)';
        rocker_pt   = vehicle.(manufacturer).kinematics.(axle).rocker.damperPickup(:)';
        axial_unit  = (chassis_nom - rocker_pt) / norm(chassis_nom - rocker_pt);
        vehicle.(manufacturer).kinematics.(axle).damper.chassisPickup = ...
            (chassis_nom + damperAxial * axial_unit)';

        % Apply absolute Y positions to connection points
        vehicle.(manufacturer).kinematics.(axle).upperAArm.fore(2) = ufY;
        vehicle.(manufacturer).kinematics.(axle).upperAArm.aft(2)  = uaY;
        vehicle.(manufacturer).kinematics.(axle).lowerAArm.fore(2) = lfY;
        vehicle.(manufacturer).kinematics.(axle).lowerAArm.aft(2)  = laY;

        % Kinematic sweep — branched for front vs rear
        try
            if strcmp(axle, 'rear')
                % ---- REAR ------------------------------------------------
                vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);
                vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle);

                radiiOffset = rearAArmCompensation(vehicle, manufacturer, axle, camberShims, 'CAD_ERROR', true);
                vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'axle', axle, ...
                    'newRadii', radiiOffset, 'geometrySystem', 'extendAArm', 'plotResults', false);

                radiiOffset = getOffset(vehicle, manufacturer, POS, axle);
                vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'axle', axle, ...
                    'newRadii', radiiOffset, 'geometrySystem', 'extendUBJ', 'plotResults', false);

                camberPreCorr = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber;
                vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'thetaL_range', vehicle.(manufacturer).kinematics.(axle).damper.thetaL);
                vehicle.(manufacturer).kinematics.(axle).camberSweep.camberCorrected = camberPreCorr;

                vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle);
                vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, 'contactChoice', 'tyreCentre');
                vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'wheelCentre', 'compensated');
                vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'wheelCentre', 'compensated');
                vehicle = calculateAntiGeometry(vehicle, 'manufacturer', manufacturer, ...
                    'axle', axle, 'CoGHeight', CoGHeight);

            else
                % ---- FRONT -----------------------------------------------
                vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);
                vehicle = camberOffset(vehicle, camberShims, manufacturer, axle);

                toeFidelity = 149;
                vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'isSteeringAngle', true, 'fidelity', toeFidelity);

                nSteerSteps = size(vehicle.(manufacturer).kinematics.(axle).toeSweep.toe, 2);
                for si = 1:nSteerSteps
                    vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, ...
                        'contactChoice', 'tyreCentre', 'toeIndex', si);
                end

                vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'wheelCentre', 'compensated');
                vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
                    'wheelCentre', 'compensated');
                vehicle = calculateAntiGeometry(vehicle, 'manufacturer', manufacturer, ...
                    'axle', axle, 'CoGHeight', CoGHeight);
            end

            % Ride-height snapshot
            kin = vehicle.(manufacturer).kinematics.(axle);
            wt  = kin.camberSweep.wheelTravel(:, 3);
            [~, rhIdx] = min(abs(wt));

            camberRH     = kin.camberSweep.camberCorrected(rhIdx);
            camberGainRH = kin.camberSweep.camberGain(rhIdx);

            [~, zIdx] = min(abs(kin.toeSweep.steeringRackDisplacement));
            toeRH     = kin.toeSweep.toe(rhIdx, zIdx);
            toeGainRH = kin.toeSweep.toeGain(rhIdx);

            rcRH     = kin.RC_height_array(rhIdx);
            rcGainRH = gradient(kin.RC_height_array, wt); rcGainRH = rcGainRH(rhIdx);
            antiRH   = kin.antiGeometry.percent(rhIdx);

            % Motion ratio: damper.length lives on its own trimmed rotation
            % grid (kin.damper.thetaL), not on the camberSweep grid used by
            % wt — interpolate wt onto damper's grid before differentiating.
            wt_onDamperGrid = interp1(kin.camberSweep.thetaL, wt, kin.damper.thetaL, 'linear', 'extrap');
            mrArray = gradient(wt_onDamperGrid, kin.damper.length);
            mrRH    = mrArray(kin.damper.thetaL_0Index);

            
            results(run,:) = {ufSlot, ufY, uaSlot, uaY, ...
                              lfSlot, lfY, laSlot, laY, ...
                              ubjPOS, damperAxial, ...
                              camberRH, camberGainRH, toeRH, toeGainRH, ...
                              rcRH, rcGainRH, antiRH, mrRH};

            fprintf('OK  Cam:%.2f  Toe:%.3f  RC:%.1f  Anti:%.1f%%\n', ...
                    camberRH, toeRH, rcRH, antiRH);

        catch ME
            results(run,:) = {ufSlot, ufY, uaSlot, uaY, ...
                              lfSlot, lfY, laSlot, laY, ...
                              ubjPOS, damperAxial, ...
                              NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN};
            fprintf('ERROR: %s\n', ME.message);
        end
    end

    % Save results and signal done
    save(fullfile(tmpDir, sprintf('results_%d.mat', workerID)), 'results', 'varNames');
    fid = fopen(fullfile(tmpDir, sprintf('done_%d.flag', workerID)), 'w');
    fprintf(fid, 'Worker %d complete at %s\n', workerID, datestr(now));
    fclose(fid);

    fprintf('\n========================================\n');
    fprintf('  DOE Worker %d complete  %s\n', workerID, datestr(now,'HH:MM:SS'));
    fprintf('========================================\n');
end