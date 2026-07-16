function data = smp_custom_channels(data, varargin)
% SMP_CUSTOM_CHANNELS  Compute derived channels from loaded MoTeC data.
%
% Call immediately after motec_ld_reader(), before caching.
% Adds new fields to the data struct matching the standard channel format:
%   .data        - double column vector of physical values
%   .time        - double column vector of timestamps [s]
%   .units       - string
%   .sample_rate - Hz
%   .raw_name    - string (display name)
%
% To add a new channel:
%   1. Add a new block following the TEMPLATE below
%   2. The field name becomes how you reference it everywhere downstream
%      e.g. data.Brake_Bias_Front -> plot config yAxis = 'Brake_Bias_Front'

    p = inputParser();
    addRequired(p,  'data');
    addParameter(p, 'startingValues', struct());
    addParameter(p, 'manufacturer',   '');
    addParameter(p, 'driver',         '');
    addParameter(p, 'patchRH', struct());
    addParameter(p, 'session', '');
    parse(p, data, varargin{:});

    startingValues = p.Results.startingValues;
    GEN3_KinematicParameters;
    % Prefer explicit parameters; fall back to data.info if not supplied.
    manufacturer = p.Results.manufacturer;
    driver       = p.Results.driver;
    patchRH      = p.Results.patchRH;
    session = p.Results.session;
    if isfield(data, 'info') && isstruct(data.info)
        if isempty(manufacturer) && isfield(data.info, 'manufacturer')
            manufacturer = data.info.manufacturer;
        end
        if isempty(driver) && isfield(data.info, 'driver')
            driver = data.info.driver;
        end
    end

    fprintf('smp_custom_channels: computing derived channels...\n');
    ref = longest_channel(data);   % highest-frequency channel — shared time base for all align_to calls

    % ==================================================================
    %  TEMPLATE — copy this block for each new channel.
    %  Use find_field(data, 'partial_name') instead of isfield for any
    %  channel whose name may vary by manufacturer prefix etc.
    % ==================================================================
    %{
    CHANNEL_NAME = 'My_Channel';
    REQUIRES     = {'Source_A', 'Source_B'};   % channels that must exist

    try
        if all(isfield(data, REQUIRES))
            a = data.Source_A.data;
            b = data.Source_B.data;
            % --- YOUR MATH HERE ---
            result = a ./ b;
            % ----------------------
            data.(CHANNEL_NAME) = make_channel(result, data.Source_A, 'unit_string', CHANNEL_NAME);
            fprintf('  [+] %s\n', CHANNEL_NAME);
        else
            fprintf('  [!] %s skipped — missing: %s\n', CHANNEL_NAME, ...
                strjoin(REQUIRES(~isfield(data, REQUIRES)), ', '));
        end
    catch ME; fprintf('  [!] %s failed: %s\n', CHANNEL_NAME, ME.message); end
    %}

    % ==================================================================
    %  Brake Bias (Front %)
    % ==================================================================
    try
        if isfield(data, 'Brake_Pressure_Front') && isfield(data, 'Brake_Pressure_Rear')
            f        = data.Brake_Pressure_Front.data;
            r        = data.Brake_Pressure_Rear.data;
            total    = f + r;
            biasMask = total > 0.5;
            bias     = zeros(size(total));
            bias(biasMask) = (f(biasMask) ./ total(biasMask)) * 100;
            data.brakeBiasVCH = make_channel(bias, data.Brake_Pressure_Front, '%', 'brake_Bias_VCH');
            fprintf('  [+] brake_Bias_VCH\n');
        end
    catch ME; fprintf('  [!] brakeBiasVCH failed: %s\n', ME.message); end

    % ==================================================================
    %  Driving Gates
    %  Requires: ADR_Acceleration_X/Y, Acceleration_X/Y_Filt,
    %            Throttle_Pedal, Ground_Speed
    % ==================================================================
    try
        if isfield(data, 'ADR_Acceleration_X') && isfield(data, 'ADR_Acceleration_Y') && ...
           isfield(data, 'Acceleration_X_Filt') && isfield(data, 'Acceleration_Y_Filt') && ...
           isfield(data, 'Throttle_Pedal') && isfield(data, 'Ground_Speed')

            long        = align_to(data.Acceleration_X_Filt, ref);
            lat         = align_to(data.Acceleration_Y_Filt, ref);
            absLat      = abs(lat);
            throttle    = align_to(data.Throttle_Pedal,      ref);
            groundSpeed = align_to(data.Ground_Speed,        ref);

            % Gate definitions (tune thresholds as needed):
            %   Braking    : decelerating hard, low lateral load
            %   Entry      : still braking but lateral load building
            %   Mid-Corner : peak lateral, minimal longitudinal
            %   Exit       : accelerating, lateral load unwinding
            brakingMask   = (long  < -0.05) & (movmean(absLat, 10) <  0.10);
            entryMask     = (long  < -0.05) & (movmean(absLat, 10) >= 0.10) & (absLat < 0.75);
            midCornerMask =                   (absLat >= 0.75);
            exitMask      = (long  >  0.10) & (absLat <  0.75);
            straightMask  = (throttle >= 99) & (absLat < 0.2);
            ParityMask    = straightMask & (groundSpeed > 220) & (groundSpeed < 240);

            data.brakingGateVCH   = make_channel(double(brakingMask),   ref, 'bool', 'braking_Gate_VCH');
            data.entryGateVCH     = make_channel(double(entryMask),     ref, 'bool', 'entry_Gate_VCH');
            data.midCrnGateVCH    = make_channel(double(midCornerMask), ref, 'bool', 'mid_Crn_Gate_VCH');
            data.exitGateVCH      = make_channel(double(exitMask),      ref, 'bool', 'exit_Gate_VCH');
            data.straightGateVCH  = make_channel(double(straightMask),  ref, 'bool', 'straight_Gate_VCH');
            data.ParityMaskVCH    = make_channel(double(ParityMask),    ref, 'bool', 'parity_Gate_VCH');
            fprintf('  [+] Gates: Braking | Entry | MidCorner | Exit | Straight | Parity\n');
        end
    catch ME; fprintf('  [!] Driving gates failed: %s\n', ME.message); end
    % =====================================================================
    % Driver KPI's
    % =====================================================================
    try %% Front wheel speed yaw formula
        if isfield(data, 'Wheel_Speed_Front_Left') && isfield(data, 'Wheel_Speed_Front_Right') 

            tempData = movmean((data.Wheel_Speed_Front_Right.data - data.Wheel_Speed_Front_Left.data)/10,20);
            data.Wheel_Speed_Yaw_Rate = make_channel(tempData, ref, 'N', 'Wheel Speed Yaw Rate');
            fprintf('  [+] Wheel_Speed_Yaw_Rate\n');

        end
    catch ME; fprintf('  [!]  Wheel Speed Yaw Failed: %s\n', ME.message); end


    % ==================================================================
    %  Average Cornering Acceleration
    % ==================================================================
    try
        if isfield(data, 'Steering_Angle')
            
            Steering_Aggression = cumtrapz(data.Steering_Angle.time, lowpass_filter(data.Steering_Angle.data, data.Steering_Angle.time, 0.8) - data.Steering_Angle.data)
            
            thr_lp = lowpass_filter(data.Throttle_Pedal.data, data.Throttle_Pedal.time, 0.8);

            % --- Condition (choose logic) ---
            if data.Throttle_Pedal.sample_rate > data.Brake_Pressure_Front.sample_rate
                brake = align_to(data.Brake_Pressure_Front, data.Throttle_Pedal);
            end 
            
            cond = (data.Throttle_Pedal.data < 99) & ...
                   (data.Throttle_Pedal.data > 1)  & ...
                   (data.Throttle_Pedal.data < 70) & ...
                   (brake < 10) & ...
                   (abs(thr_lp - data.Throttle_Pedal.data) > 10);
        
            indicator = double(cond);   % 1 where true, 0 where false
        
            % --- Integrate over time (trapezoidal, cumulative) ---
            result = cumtrapz(data.Throttle_Pedal.time, indicator(:));
            data.Throttle_Aggression = make_channel(result, data.Throttle_Pedal, '-', 'Throttle_Aggression');
                fprintf('  [+] Throttle_Aggression\n');
            data.Steering_Aggression = make_channel(Steering_Aggression, data.Steering_Angle, '-', 'Steering_Aggression');
                fprintf('  [+] Steering_Aggression\n');
        end
    catch ME; fprintf('  [!] avgCRNVCH failed: %s\n', ME.message); end


    % try % Lift and Coast averaging
    %     if isfield(data, 'Throttle_Pedal') && isfield(data, 'Brake_Pressure_Front') 
    %         brake = align_to(data.Brake_Pressure_Front, data.Throttle_Pedal);
    %         carSpeed = align_to(data.Ground_Speed, data.Throttle_Pedal);
    %         mask = double((data.Throttle_Pedal.data < 2 & brake < 2 & carSpeed > 50));
    %         result = cumtrapz(data.Throttle_Pedal.time, double(mask(:)));
    %         data.Lift_And_Coast_Time = make_channel(result, data.Throttle_Pedal, '-', 'Lift_And_Coast_Time');
    %         fprintf('  [+] Lift_And_Coast_Time\n');
    %     end
    % catch ME; fprintf('  [!]  Wheel Speed Yaw Failed: %s\n', ME.message); end

       try % Off Pedal Rotation Time (Lift & Coast / Rotation Limited)
        if isfield(data, 'Throttle_Pedal') && isfield(data, 'Brake_Pressure_Front')
            brake    = align_to(data.Brake_Pressure_Front, data.Throttle_Pedal);
            carSpeed = align_to(data.Ground_Speed, data.Throttle_Pedal);
            throttle = data.Throttle_Pedal.data(:);
            brake    = brake(:);
    
            throttleOn = throttle > 2;
            brakeOn    = brake > 2;
            neither    = ~throttleOn & ~brakeOn;
    
            % Forward-fill "which pedal was last active": 1 = throttle, 2 = brake
            rawState = nan(size(throttle));
            rawState(throttleOn) = 1;
            rawState(brakeOn)    = 2;
            state = fillmissing(rawState, 'previous');
    
            % Throttle -> Brake transition (lift and coast)
            liftMask = double(neither & state == 1 & carSpeed(:) > 50);
            liftResult = cumtrapz(data.Throttle_Pedal.time, liftMask);
            data.Lift_And_Coast_Time = make_channel(liftResult, data.Throttle_Pedal, '-', 'Lift_And_Coast_Time', 'overwrite', true);
            fprintf('  [+] Lift_And_Coast_Time\n');
    
            % Brake -> Throttle transition (rotation limited)
            rotMask = double(neither & state == 2 & carSpeed(:) > 50);
            rotResult = cumtrapz(data.Throttle_Pedal.time, rotMask);
            data.Rotation_Limited_Time = make_channel(rotResult, data.Throttle_Pedal, '-', 'Rotation_Limited_Time', 'overwrite', true);
            fprintf('  [+] Rotation_Limited_Time\n');
        end
    catch ME; fprintf('  [!]  Off Pedal Rotation Time Failed: %s\n', ME.message); end
    % ==================================================================
    %  Wheel Locking Timer
    % ==================================================================
    try
        if isfield(data, 'Wheel_Speed_Front_Left') && ...
           isfield(data, 'Wheel_Speed_Front_Right') && ...
           isfield(data, 'Ground_Speed')

            LOCK_THRESH_KMH = 15;
            BRAKE_THRESH    = 2;
            MIN_SPEED_KMH   = 30;

            if isfield(data, 'Corr_Speed')
                gnd_ch = data.Corr_Speed;
            else
                gnd_ch = data.Ground_Speed;
            end
            gnd      = gnd_ch.data;
            dt       = 1 / gnd_ch.sample_rate;
            speed_ok = gnd > MIN_SPEED_KMH;

            if isfield(data, 'Brake_Pressure_Front')
                brk = data.Brake_Pressure_Front.data > BRAKE_THRESH;
            else
                brk = true(size(gnd));
            end

            if isfield(data, 'Wheel_Speed_Rear_Left')
                rear_avg = align_to(data.Wheel_Speed_Rear_Left,  gnd_ch);
            elseif isfield(data, 'Wheel_Speed_Rear_Right')
                rear_avg = align_to(data.Wheel_Speed_Rear_Right, gnd_ch);
            else
                rear_avg = [];
            end

            wheel_map = {
                'Wheel_Speed_Front_Left',  'FL_LockTimerVCH';
                'Wheel_Speed_Front_Right', 'FR_LockTimerVCH';
            };
            if ~isempty(rear_avg)
                data.Wheel_Speed_Rear_Avg__ = make_channel(rear_avg, gnd_ch, 'km/h', 'Wheel_Speed_Rear_Avg__');
                wheel_map(end+1,:) = {'Wheel_Speed_Rear_Avg__', 'RL_Lock_Timer_VCH'};
            end

            for w = 1:size(wheel_map, 1)
                src = wheel_map{w,1};
                out = wheel_map{w,2};
                if ~isfield(data, src), continue; end
                ws        = align_to(data.(src), gnd_ch);
                lock_mask = (gnd - ws) > LOCK_THRESH_KMH & brk & speed_ok;
                cs        = cumsum(double(lock_mask) * dt);
                reset_src = cs .* double(~lock_mask);
                nz        = reset_src ~= 0;
                held      = zeros(size(cs));
                if any(nz)
                    grp         = cumsum(nz);
                    nz_pos      = find(nz);
                    valid       = grp > 0;
                    held(valid) = reset_src(nz_pos(grp(valid)));
                end
                lock_timer = max(0, cs - held) .* double(lock_mask);
                data.(out) = make_channel(lock_timer, gnd_ch, 's', out);
                data.(out).interp_method = 'nearest';
                fprintf('  [+] %s\n', out);
            end

            if isfield(data, 'Wheel_Speed_Rear_Avg__')
                data = rmfield(data, 'Wheel_Speed_Rear_Avg__');
            end
        end
    catch ME; fprintf('  [!] Wheel locking failed: %s\n', ME.message); end

    % ==================================================================
    %  Air Jack Timer
    % ==================================================================
    try
        if isfield(data, 'Air_Jack_Timer_Switch') && ...
           isfield(data, 'Wheel_Speed_Rear_Left') && ...
           isfield(data, 'Clutch_Pressure')       && ...
           isfield(data, 'Throttle_Pedal')

            switchData     = data.Air_Jack_Timer_Switch.data;
            risingEdge     = [false; diff(switchData) > 0];
            maskScrutineer = risingEdge & ...
                             data.Wheel_Speed_Rear_Left.data > 0 & ...
                             data.Clutch_Pressure.data < 1000  & ...
                             data.Throttle_Pedal.data > 1;
            data.flagOnJacksWSVCH = make_channel( ...
                double(maskScrutineer), data.Air_Jack_Timer_Switch, 'bool', 'flag_On_Jacks_WS_VCH');
            fprintf('  [+] flag_On_Jacks_WS_VCH\n');
        end
    catch ME; fprintf('  [!] Air jack timer failed: %s\n', ME.message); end

    % ==================================================================
    %  Speed Gates (Low / Mid / High)
    % ==================================================================
    try
        if isfield(data, 'Ground_Speed')
            data.Gate_LowSpeed  = make_channel(double(data.Ground_Speed.data < 80),                                    data.Ground_Speed, 'bool', 'Gate_LowSpeed_VCH');
            data.Gate_MidSpeed  = make_channel(double(data.Ground_Speed.data >= 80 & data.Ground_Speed.data < 160),    data.Ground_Speed, 'bool', 'Gate_MidSpeed_VCH');
            data.Gate_HighSpeed = make_channel(double(data.Ground_Speed.data >= 160),                                  data.Ground_Speed, 'bool', 'Gate_HighSpeed_VCH');
            fprintf('  [+] Gate_LowSpeed  Gate_MidSpeed  Gate_HighSpeed\n');
        end
    catch ME; fprintf('  [!] Speed gates failed: %s\n', ME.message); end

    % ==================================================================
    %  Tyre Radius Estimation (Pressure + Load + Speed Correction)
    %  Model:  r = (28.2200 + 0.0505*P + -0.000340*FZ + 0.0004*rotSpeed) * 10 [mm]
    %  Source: CALSPAN data
    % ==================================================================
    try
        if isfield(data, 'Wheel_Speed_Front_Left') && isfield(data, 'TPM1S_FL_WS_PRESS')
            data.Wheel_Speed_Loaded_Radius_FL = make_channel( ...
                tyreRadiusV1(data.TPM1S_FL_WS_PRESS, data.Wheel_Speed_Front_Left, 'front'), ...
                data.Wheel_Speed_Front_Left, 'mm', 'Wheel_Speed_Loaded_Radius_FL');
            fprintf('  [+] Wheel_Speed_Loaded_Radius_FL\n');
        end
        if isfield(data, 'Wheel_Speed_Front_Right') && isfield(data, 'TPM1S_FR_WS_PRESS')
            data.Wheel_Speed_Loaded_Radius_FR = make_channel( ...
                tyreRadiusV1(data.TPM1S_FR_WS_PRESS, data.Wheel_Speed_Front_Right, 'front'), ...
                data.Wheel_Speed_Front_Right, 'mm', 'Wheel_Speed_Loaded_Radius_FR');
            fprintf('  [+] Wheel_Speed_Loaded_Radius_FR\n');
        end
        if isfield(data, 'Wheel_Speed_Rear_Right') && isfield(data, 'TPM1S_RR_WS_PRESS')
            data.Wheel_Speed_Loaded_Radius_R = make_channel( ...
                tyreRadiusV1(data.TPM1S_RR_WS_PRESS, data.Wheel_Speed_Rear_Right, 'rear'), ...
                data.TPM1S_RR_WS_PRESS, 'mm', 'Wheel_Speed_Loaded_Radius_R');
            fprintf('  [+] Wheel_Speed_Loaded_Radius_R\n');
        end
    catch ME; fprintf('  [!] Tyre radius failed: %s\n', ME.message); end

    % ==================================================================
    %  Tyre Pressure / Temperature Averages
    % ==================================================================
    try
        if isfield(data, 'TPM1S_RR_WS_PRESS') && isfield(data, 'TPM1S_RL_WS_PRESS')
            if length(data.TPM1S_RR_WS_PRESS.data) > length(data.TPM1S_RL_WS_PRESS.data)
                newChan = align_to(data.TPM1S_RL_WS_PRESS, data.TPM1S_RR_WS_PRESS); refChan = data.TPM1S_RR_WS_PRESS;
            else
                newChan = align_to(data.TPM1S_RR_WS_PRESS, data.TPM1S_RL_WS_PRESS); refChan = data.TPM1S_RL_WS_PRESS;
            end
            data.tTyreRear_VCH_P = make_channel((newChan + refChan.data) ./ 2, refChan, 'psi', 'tTyreRear_VCH_P');
            fprintf('  [+] tTyreRear_VCH_P\n');
        end
        if isfield(data, 'TPM1S_RR_WS_TEMP') && isfield(data, 'TPM1S_RL_WS_TEMP')
            if length(data.TPM1S_RR_WS_TEMP.data) > length(data.TPM1S_RL_WS_TEMP.data)
                newChan = align_to(data.TPM1S_RL_WS_TEMP, data.TPM1S_RR_WS_TEMP); refChan = data.TPM1S_RR_WS_TEMP;
            else
                newChan = align_to(data.TPM1S_RR_WS_TEMP, data.TPM1S_RL_WS_TEMP); refChan = data.TPM1S_RL_WS_TEMP;
            end
            data.tTyreRear_VCH_T = make_channel((newChan + refChan.data) / 2, refChan, 'C', 'tTyreRear_VCH_T');
            fprintf('  [+] tTyreRear_VCH_T\n');
        end
        if isfield(data, 'TPM1S_FR_WS_PRESS') && isfield(data, 'TPM1S_FL_WS_PRESS')
            if length(data.TPM1S_FR_WS_PRESS.data) > length(data.TPM1S_FL_WS_PRESS.data)
                newChan = align_to(data.TPM1S_FL_WS_PRESS, data.TPM1S_FR_WS_PRESS); refChan = data.TPM1S_FR_WS_PRESS;
            else
                newChan = align_to(data.TPM1S_FR_WS_PRESS, data.TPM1S_FL_WS_PRESS); refChan = data.TPM1S_FL_WS_PRESS;
            end
            data.tTyreFront_VCH_P = make_channel((newChan + refChan.data) / 2, refChan, 'psi', 'tTyreFront_VCH_P');
            fprintf('  [+] tTyreFront_VCH_P\n');
        end
        if isfield(data, 'TPM1S_FR_WS_TEMP') && isfield(data, 'TPM1S_FL_WS_TEMP')
            if length(data.TPM1S_FR_WS_TEMP.data) > length(data.TPM1S_FL_WS_TEMP.data)
                newChan = align_to(data.TPM1S_FL_WS_TEMP, data.TPM1S_FR_WS_TEMP); refChan = data.TPM1S_FR_WS_TEMP;
            else
                newChan = align_to(data.TPM1S_FR_WS_TEMP, data.TPM1S_FL_WS_TEMP); refChan = data.TPM1S_FL_WS_TEMP;
            end
            data.tTyreFront_VCH_T = make_channel((newChan + refChan.data) / 2, refChan, 'C', 'tTyreFront_VCH_T');
            fprintf('  [+] tTyreFront_VCH_T\n');
        end
    catch ME; fprintf('  [!] Tyre pressure/temp averages failed: %s\n', ME.message); end

    % ==================================================================
    %  Fuel Density Calculation
    % ==================================================================
    try
        if isfield(data, 'Fuel_Used_Mass') && isfield(data, 'Fuel_Temperature')
            if length(data.Fuel_Temperature.data) > length(data.Fuel_Used_Mass.data)
                refFuel = data.Fuel_Temperature;
                x       = data.Fuel_Temperature.data;
            else
                x       = align_to(data.Fuel_Temperature, data.Fuel_Used_Mass);
                refFuel = data.Fuel_Used_Mass;
            end
            linearDensity = -0.8104 * x + 805.9;
            cubicDensity  = (-8.85e-7) * x.^3 + 0.0009464 * x.^2 - 0.8774 * x + 807;
            data.Fuel_Density_Corr_Cubic  = make_channel(cubicDensity  ./ (data.Fuel_Used_Mass.data * 1000), refFuel, 'L', 'Fuel_Density_Corr_Cubic');
            data.Fuel_Density_Corr_Linear = make_channel(linearDensity ./ (data.Fuel_Used_Mass.data * 1000), refFuel, 'L', 'Fuel_Density_Corr_Linear');
            fprintf('  [+] Fuel_Density_Corr_Cubic  Fuel_Density_Corr_Linear\n');
        end
    catch ME; fprintf('  [!] Fuel density failed: %s\n', ME.message); end

    % ==================================================================
    %  Pitch / Roll from IMU
    % ==================================================================
    try
        if isfield(data, 'Acceleration_X_Filt') && isfield(data, 'Acceleration_Y_Filt') && ...
           isfield(data, 'Acceleration_Z_Filt')
            IMU_Y = data.Acceleration_X_Filt.data;
            IMU_X = data.Acceleration_Y_Filt.data;
            if length(IMU_Y) > length(IMU_X)
                IMU_X = align_to(data.Acceleration_Y_Filt, data.Acceleration_X_Filt);
            else
                IMU_Y = align_to(data.Acceleration_X_Filt, data.Acceleration_Y_Filt);
            end
            roll  = movmean((atan(IMU_X ./ sqrt(IMU_Y.^2))), 10);
            pitch = movmean((atan(IMU_Y ./ abs(IMU_X))),     10);
            data.pitch_VCH = make_channel(pitch, data.Acceleration_Y_Filt, 'deg', 'pitch_VCH');
            data.roll_VCH  = make_channel(roll,  data.Acceleration_X_Filt, 'deg', 'roll_VCH');
            fprintf('  [+] pitch_VCH  roll_VCH\n');
        end
    catch ME; fprintf('  [!] Pitch/roll failed: %s\n', ME.message); end
    % ==================================================================
    %  Ride Height — Average Front Raw from L+R sensors
    %  Uses find_field so 'L180_Laser_Ride_Height_Front_L_Raw' also matches.
    % ==================================================================
    try
        damperFL = find_field(data, 'C1_Damper_Pos_FL');
        damperFR = find_field(data, 'C1_Damper_Pos_FR');
        damperRL = find_field(data, 'C1_Damper_Pos_RL');
        damperRR = find_field(data, 'C1_Damper_Pos_RR');
        if  ~isempty(damperFL) && ~isempty(damperFR) & ...
                ~isempty(damperFL) && ~isempty(damperFR)
            C1_Damper_Pos_FL_Zero = data.C1_Damper_Pos_FL.data - min(movmean(data.C1_Damper_Pos_FL.data,10)); % Zeroing the channel to all have the same starting point
            C1_Damper_Pos_FR_Zero = data.C1_Damper_Pos_FR.data - min(movmean(data.C1_Damper_Pos_FR.data,10)); % Zeroing the channel to all have the same starting point
            C1_Damper_Pos_RL_Zero = data.C1_Damper_Pos_RL.data - min(movmean(data.C1_Damper_Pos_RL.data,10)); % Zeroing the channel to all have the same starting point
            C1_Damper_Pos_RR_Zero = data.C1_Damper_Pos_RR.data - min(movmean(data.C1_Damper_Pos_RR.data,10)); % Zeroing the channel to all have the same starting point

            data.C1_Damper_Pos_FL_Zero = make_channel(C1_Damper_Pos_FL_Zero, data.C1_Damper_Pos_FL, 'mm', 'C1_Damper_Pos_FL_Zero', 'overwrite', true);
            fprintf('  [+] Zeroed Damper Front Left');
            data.C1_Damper_Pos_FR_Zero = make_channel(C1_Damper_Pos_FR_Zero, data.C1_Damper_Pos_FL, 'mm', 'C1_Damper_Pos_FR_Zero', 'overwrite', true);
            fprintf('  [+] Zeroed Damper Front Right');
            data.C1_Damper_Pos_RL_Zero = make_channel(C1_Damper_Pos_RL_Zero, data.C1_Damper_Pos_FL, 'mm', 'C1_Damper_Pos_RL_Zero', 'overwrite', true);
            fprintf('  [+] Zeroed Damper Rear Left');
            data.C1_Damper_Pos_RR_Zero = make_channel(C1_Damper_Pos_RR_Zero, data.C1_Damper_Pos_FL, 'mm', 'C1_Damper_Pos_RR_Zero', 'overwrite', true);
            fprintf('  [+] Zeroed Damper Rear Right');
        end
    catch ME; fprintf('  [!] Damper Zeroing Failed: %s\n', ME.message); end
    % ==================================================================
    %  Ride Height — Average Front Raw from L+R sensors
    %  Uses find_field so 'L180_Laser_Ride_Height_Front_L_Raw' also matches.
    % ==================================================================

   try
    damperFL = find_field(data, 'C1_Damper_Pos_FL_Zero');
    damperFR = find_field(data, 'C1_Damper_Pos_FR_Zero');
    damperRL = find_field(data, 'C1_Damper_Pos_RL_Zero');
    damperRR = find_field(data, 'C1_Damper_Pos_RR_Zero');

    if ~isempty(damperFL) && ~isempty(damperFR) && ~isempty(damperRL) && ~isempty(damperRR)

        % ---- Default offset by manufacturer ----
        if strcmp(manufacturer, 'Ford') || strcmp(manufacturer, 'Toyota') || strcmp(manufacturer, 'Chevrolet')
            mask = strcmp(patchRH.MAN, manufacturer);  % NOTE: needs a MAN column, see below
            FRH_Offset = mean(patchRH.FrontRH(mask));
            RRH_Offset = mean(patchRH.RearRH(mask));
        else
            FRH_Offset = mean(patchRH.FrontRH);
            RRH_Offset = mean(patchRH.RearRH);
        end

        % ---- Override with driver+session specific patch, if present ----
        driverMask = strcmp(patchRH.Driver, driver);
        if any(driverMask)
            driverPatch = patchRH(driverMask, :);
            sessionMask = strcmp(driverPatch.Session, cfg_session_placeholder); % pass Session in, see note
            if any(sessionMask)
                driverSessionPatch = driverPatch(sessionMask, :);
                FRH_Offset = driverSessionPatch.FrontRH(1);
                RRH_Offset = driverSessionPatch.RearRH(1);   % was lowercase .rearRH — typo
            end
        end

        Kinematic_Ride_Height_FL = -1*data.C1_Damper_Pos_FL_Zero.data + FRH_Offset;
        Kinematic_Ride_Height_FR = -1*data.C1_Damper_Pos_FR_Zero.data + FRH_Offset;
        Kinematic_Ride_Height_RL = -1*data.C1_Damper_Pos_RL_Zero.data + RRH_Offset;
        Kinematic_Ride_Height_RR = -1*data.C1_Damper_Pos_RR_Zero.data + RRH_Offset;

        data.Kinematic_Ride_Height_FL = make_channel(Kinematic_Ride_Height_FL, data.C1_Damper_Pos_FL, 'mm', 'Kinematic_Ride_Height_FL', 'overwrite', true);
        fprintf('  [+] Kinematic Ride Height FL\n');
        data.Kinematic_Ride_Height_FR = make_channel(Kinematic_Ride_Height_FR, data.C1_Damper_Pos_FR, 'mm', 'Kinematic_Ride_Height_FR', 'overwrite', true); % was FL as template — fine functionally since make_channel just copies metadata, but confirm intent
        fprintf('  [+] Kinematic Ride Height FR\n');
        data.Kinematic_Ride_Height_RL = make_channel(Kinematic_Ride_Height_RL, data.C1_Damper_Pos_RL, 'mm', 'Kinematic_Ride_Height_RL', 'overwrite', true);
        fprintf('  [+] Kinematic Ride Height RL\n');
        data.Kinematic_Ride_Height_RR = make_channel(Kinematic_Ride_Height_RR, data.C1_Damper_Pos_RR, 'mm', 'Kinematic_Ride_Height_RR', 'overwrite', true);
        fprintf('  [+] Kinematic Ride Height RR\n');
        data.Kinematic_Ride_Height_Front = make_channel((Kinematic_Ride_Height_FL + Kinematic_Ride_Height_FR)/2, data.C1_Damper_Pos_FR, 'mm', 'Kinematic_Ride_Height_Front', 'overwrite', true);
        fprintf('  [+] Kinematic Ride Height Front\n');
        data.Kinematic_Ride_Height_Rear = make_channel((Kinematic_Ride_Height_RL + Kinematic_Ride_Height_RR)/2, data.C1_Damper_Pos_RR, 'mm', 'Kinematic_Ride_Height_Rear', 'overwrite', true);
        fprintf('  [+] Kinematic Ride Height Rear\n');
        end
    catch ME
        fprintf('  [!] Failed Kinematic RH: %s\n', ME.message);
    end
    %% ====================================================================
    % Kinematic RH Aero Map 
    % =====================================================================
    try
        fn_frh_aero_kin = find_field(data, 'Kinematic_Ride_Height_Front');
        fn_rrh_aero_kin = find_field(data, 'Kinematic_Ride_Height_Rear');


        AERO_MAP_DIR = 'C:\SimEnv\vehicleModel\components\aerodynamics';
        
        if ~isempty(fn_frh_aero_kin) && ~isempty(fn_rrh_aero_kin) && ~isempty(manufacturer)
            aero = aeroMapChannels(data.(fn_frh_aero_kin), data.(fn_rrh_aero_kin), manufacturer, AERO_MAP_DIR);
            if ~isempty(aero)
                data.CLa_SCz_VCH = make_channel(aero.CLa_SCz, ref, '-', 'CLa_SCz_VCH_KIN', 'overwrite', true);
                data.AB_FRT_VCH  = make_channel(aero.AB_FRT,  ref, '%', 'AB_FRT_VCH_KIN', 'overwrite', true);
                data.CDa_SCx_VCH = make_channel(aero.CDa_SCx, ref, '-', 'CDa_SCx_VCH_KIN', 'overwrite', true);
                data.EFF_VCH     = make_channel(aero.EFF,     ref, '-', 'EFF_VCH_KIN');
                fprintf('  [+] CLa_SCz_VCH  AB_FRT_VCH  CDa_SCx_VCH  EFF_VCH  (%s map, roll=0)\n', manufacturer);

                aero2 = aeroMapChannels(data.(fn_frh_aero_kin), data.(fn_rrh_aero_kin), manufacturer, AERO_MAP_DIR, -2);
                if ~isempty(aero2)
                    data.CSa_Scy_VCH  = make_channel(aero2.CSa_Scy,  ref, '-', 'CSa_Scy_VCH_KIN', 'overwrite', true);
                    data.CSf_SCyF_VCH = make_channel(aero2.CSf_SCyF, ref, '-', 'CSf_SCyF_VCH_KIN', 'overwrite', true);
                    data.CSr_SCyR_VCH = make_channel(aero2.CSr_SCyR, ref, '-', 'CSr_SCyR_VCH_KIN', 'overwrite', true);
                    fprintf('  [+] CSa_Scy_VCH  CSf_SCyF_VCH  CSr_SCyR_VCH  (%s map, roll=-2)\n', manufacturer);
                end
            end
        else
            missing_rh = {};
            if isempty(fn_frh_aero_kin), missing_rh{end+1} = 'Laser_Ride_Height_Front_Raw'; end
            if isempty(fn_rrh_aero_kin), missing_rh{end+1} = 'Laser_Ride_Height_Rear_Raw';  end
            if ~isempty(missing_rh)
                fprintf('  [!] Aero map skipped — missing: %s\n', strjoin(missing_rh, ', '));
            elseif isempty(manufacturer)
                fprintf('  [!] Aero map skipped — manufacturer not set\n');
            end
        end
    catch ME; fprintf('  [!] Aero map channels failed: %s\n', ME.message); end

    try
        fn_frhL = find_field(data, 'Laser_Ride_Height_Front_L_Raw');
        fn_frhR = find_field(data, 'Laser_Ride_Height_Front_R_Raw');
        if ~isempty(fn_frhL) && ~isempty(fn_frhR)
            midPoint = 0.5 .* (data.(fn_frhL).data + data.(fn_frhR).data);
            data.Laser_Ride_Height_Front_Raw = make_channel(midPoint, data.(fn_frhL), 'mm', 'Laser_Ride_Height_Front_Raw');
            fprintf('  [+] Laser_Ride_Height_Front_Raw  (from %s + %s)\n', fn_frhL, fn_frhR);
        end
    catch ME; fprintf('  [!] Ride height front avg failed: %s\n', ME.message); end
    % ==================================================================
    % ==================================================================
    %  Ride Height Correction (IMU pitch/roll compensation)
    %  Uses find_field so prefixed channel names also match.
    % ==================================================================
    try
        fn_frh = find_field(data, 'Laser_Ride_Height_Front_Raw');
        fn_rrh = find_field(data, 'Laser_Ride_Height_Rear_Raw');
        if ~isempty(fn_frh) && ~isempty(fn_rrh) && ...
           isfield(data, 'pitch_VCH') && isfield(data, 'roll_VCH')

            FRH_data = align_to(data.(fn_frh), ref);
            RRH_data = align_to(data.(fn_rrh), ref);
            gamma    = deg2rad(align_to(data.roll_VCH,  ref));
            beta     = deg2rad(align_to(data.pitch_VCH, ref));

            frontTx =  33.9;  frontTy =  427.74;  frontTz = 30.9;
            rearTx  =  24.0;  rearTy  =  236.9;   rearTz  = 19.4;

            dz_FL = -sin(beta).*frontTx + cos(beta).*sin(gamma).*(-frontTy) + (cos(beta).*cos(gamma) - 1).*frontTz;
            dz_FR = -sin(beta).*frontTx + cos(beta).*sin(gamma).*( frontTy) + (cos(beta).*cos(gamma) - 1).*frontTz;
            dz_RL = -sin(beta).*rearTx  + cos(beta).*sin(gamma).*(-rearTy)  + (cos(beta).*cos(gamma) - 1).*rearTz;
            dz_RR = -sin(beta).*rearTx  + cos(beta).*sin(gamma).*( rearTy)  + (cos(beta).*cos(gamma) - 1).*rearTz;

            data.FRH_FL_VCH = make_channel(FRH_data + dz_FL, ref, 'mm', 'FRH_FL_VCH');  fprintf('  [+] FRH_FL_VCH\n');
            data.FRH_FR_VCH = make_channel(FRH_data + dz_FR, ref, 'mm', 'FRH_FR_VCH');  fprintf('  [+] FRH_FR_VCH\n');
            data.RRH_RL_VCH = make_channel(RRH_data + dz_RL, ref, 'mm', 'RRH_RL_VCH');  fprintf('  [+] RRH_RL_VCH\n');
            data.RRH_RR_VCH = make_channel(RRH_data + dz_RR, ref, 'mm', 'RRH_RR_VCH');  fprintf('  [+] RRH_RR_VCH\n');
        end
    catch ME; fprintf('  [!] Ride height correction failed: %s\n', ME.message); end

    % ==================================================================
    %  RH Correction via rawRideHeightCorrection
    %  Uses find_field so prefix variants of Laser_Ride_Height_Rear match.
    % ==================================================================
    try
        fn_rrh_corr = find_field(data, 'Laser_Ride_Height_Rear');
        if ~isempty(fn_rrh_corr) && ~isempty(manufacturer)
            data.FRH_corrected = make_channel(rawRideHeightCorrection(data, vehicle, 'front',...
                'L180_Laser_Ride_Height_Front_Ra',  'L180_Laser_Ride_Height_Rear_Raw'), ...
                ref, 'mm', 'Front Ride Height Corr','overwrite', true);
            data.RRH_corrected = make_channel(rawRideHeightCorrection(data, vehicle, 'rear', 'L180_Laser_Ride_Height_Front_Ra', 'L180_Laser_Ride_Height_Rear_Raw' ),  ref, 'mm', 'Rear Ride Height Corr','overwrite', true);
            fprintf('  [+] FRH_corrected  RRH_corrected  (matched: %s)\n', fn_rrh_corr);
        end
    catch ME; fprintf('  [!] rawRideHeightCorrection failed: %s\n', ME.message); end

    try
        warning('[Error] ECU RH Channel')
        fn_rrh_corr = find_field(data, 'Suspension');
        if ~isempty(fn_rrh_corr) && ~isempty(manufacturer)
            data.FRH_corrected = make_channel(rawRideHeightCorrection(data, vehicle, 'front', 'ECU_Suspension_Ride_Height_Fron', 'ECU_Suspension_Ride_Height_Rear'), ref, 'mm', 'Front Ride Height Corr','overwrite', true);
            data.RRH_corrected = make_channel(rawRideHeightCorrection(data, vehicle, 'rear', 'ECU_Suspension_Ride_Height_Fron', 'ECU_Suspension_Ride_Height_Rear'),  ref, 'mm', 'Rear Ride Height Corr','overwrite', true);
            fprintf('  [+] FRH_corrected  RRH_corrected  (matched: %s)\n', fn_rrh_corr);
        end
    catch ME; fprintf('  [!] rawRideHeightCorrection failed: %s\n', ME.message); end
    % ==================================================================
    %  Wheel Slip — Longitudinal (front wheels vs vehicle speed)
    % ==================================================================
    try
        if isfield(data, 'Wheel_Speed_Front_Left') && ...
           isfield(data, 'Wheel_Speed_Front_Right') && ...
           isfield(data, 'Vehicle_Speed')
            if data.Wheel_Speed_Front_Left.sample_rate >= data.Vehicle_Speed.sample_rate
                refSlip = data.Wheel_Speed_Front_Left;
            else
                refSlip = data.Vehicle_Speed;
            end
            wfl       = align_to(data.Wheel_Speed_Front_Left,  refSlip);
            wfr       = align_to(data.Wheel_Speed_Front_Right, refSlip);
            vs        = align_to(data.Vehicle_Speed,           refSlip);
            wf_avg    = (wfl + wfr) / 2;
            slip_mask = wf_avg > (1/3.6);
            longSlip  = zeros(size(wf_avg));
            longSlip(slip_mask) = (vs(slip_mask) - wf_avg(slip_mask)) ./ wf_avg(slip_mask);
            data.longSlipFrontVCH = make_channel(longSlip, refSlip, 'ratio', 'long_Slip_Front_VCH');
            fprintf('  [+] longSlipFrontVCH\n');
        end
    catch ME; fprintf('  [!] Long slip front failed: %s\n', ME.message); end

    % ==================================================================
    %  Wheel Slip — RL vs front average (gated to exit phase)
    % ==================================================================
    try
        if isfield(data, 'Wheel_Speed_Rear_Left')  && ...
           isfield(data, 'Wheel_Speed_Front_Left') && ...
           isfield(data, 'Wheel_Speed_Front_Right')
            fl      = align_to(data.Wheel_Speed_Front_Left,  ref);
            fr      = align_to(data.Wheel_Speed_Front_Right, ref);
            car_spd = (fl + fr) / 2;
            rl      = align_to(data.Wheel_Speed_Rear_Left, ref);
            rl_slip = (rl - car_spd) ./ car_spd * 100;
            if isfield(data, 'exitGateVCH')
                gate = logical(data.exitGateVCH.data);
            else
                gate = true(size(rl));
            end
            data.RL_SlipVCH = make_channel(rl_slip .* double(gate), ref, '%', 'RL_Slip_VCH');
            data.RL_SlipVCH.interp_method = 'nearest';
            fprintf('  [+] RL_SlipVCH\n');
        end
    catch ME; fprintf('  [!] RL slip failed: %s\n', ME.message); end

    % ==================================================================
    %  Aero Map Channels — CLa_SCz, AB_FRT, CDa_SCx, EFF at Roll=0
    %  Uses find_field so prefixed ride height names also match.
    % ==================================================================







    try
        fn_frh_aero = find_field(data, 'Front_Ride_Height_Corr');
        fn_rrh_aero = find_field(data, 'Rear_Ride_Height_Corr');
        AERO_MAP_DIR = 'C:\SimEnv\vehicleModel\components\aerodynamics';

        if ~isempty(fn_frh_aero) && ~isempty(fn_rrh_aero) && ~isempty(manufacturer)
            aero = aeroMapChannels(data.(fn_frh_aero), data.(fn_rrh_aero), manufacturer, AERO_MAP_DIR);
            if ~isempty(aero)
                data.CLa_SCz_VCH = make_channel(aero.CLa_SCz, ref, '-', 'CLa_SCz_VCH');
                data.AB_FRT_VCH  = make_channel(aero.AB_FRT,  ref, '%', 'AB_FRT_VCH');
                data.CDa_SCx_VCH = make_channel(aero.CDa_SCx, ref, '-', 'CDa_SCx_VCH');
                data.EFF_VCH     = make_channel(aero.EFF,     ref, '-', 'EFF_VCH');
                fprintf('  [+] CLa_SCz_VCH  AB_FRT_VCH  CDa_SCx_VCH  EFF_VCH  (%s map, roll=0)\n', manufacturer);

                aero2 = aeroMapChannels(data.(fn_frh_aero), data.(fn_rrh_aero), manufacturer, AERO_MAP_DIR, -2);
                if ~isempty(aero2)
                    data.CSa_Scy_VCH  = make_channel(aero2.CSa_Scy,  ref, '-', 'CSa_Scy_VCH');
                    data.CSf_SCyF_VCH = make_channel(aero2.CSf_SCyF, ref, '-', 'CSf_SCyF_VCH');
                    data.CSr_SCyR_VCH = make_channel(aero2.CSr_SCyR, ref, '-', 'CSr_SCyR_VCH');
                    fprintf('  [+] CSa_Scy_VCH  CSf_SCyF_VCH  CSr_SCyR_VCH  (%s map, roll=-2)\n', manufacturer);
                end
            end
        else
            missing_rh = {};
            if isempty(fn_frh_aero), missing_rh{end+1} = 'Laser_Ride_Height_Front_Raw'; end
            if isempty(fn_rrh_aero), missing_rh{end+1} = 'Laser_Ride_Height_Rear_Raw';  end
            if ~isempty(missing_rh)
                fprintf('  [!] Aero map skipped — missing: %s\n', strjoin(missing_rh, ', '));
            elseif isempty(manufacturer)
                fprintf('  [!] Aero map skipped — manufacturer not set\n');
            end
        end
    catch ME; fprintf('  [!] Aero map channels failed: %s\n', ME.message); end

    % ==================================================================
    %  Required Steer — no aero
    %  Guard includes exist('lat','var') to prevent scope leak from
    %  gating block failing silently.
    % ==================================================================
    try
        if isfield(data, 'Steering_Angle') && isfield(data, 'Ground_Speed') && ...
                ~isempty(manufacturer) && exist('lat', 'var')
            mfr_key = lower(manufacturer);
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;   % mm → m
            gravity         = 9.81;
            weightFrontAxle = 729.8 * gravity;
            weightRearAxle  = 617.7 * gravity;

            K = (1 / wheelBase) * ( ...
                (weightFrontAxle / corneringStiffnessFront) / gravity - ...
                (weightRearAxle  / corneringStiffnessRear)  / gravity);

            steerMask = abs(align_to(data.Steering_Angle, data.Ground_Speed)) < 0.5;
            carSpeed  = align_to(data.Ground_Speed, ref) / 3.6;   % m/s
            carSpeed = data.Ground_Speed.data;
            % radius = carSpeed.^2 ./ (lat * gravity);
            % radius(steerMask) = NaN;
            % requiredSteer = wheelBase ./ radius + K .* lat;
            % requiredSteer(steerMask) = 0;

            radius = carSpeed.^2 ./ (lat * gravity);
            radius(steerMask) = NaN;

            % guard near-zero lat (radius blow-up) independent of steerMask
            lowLatMask = abs(lat) < 0.05;   % tune threshold — g's
            radius(lowLatMask) = NaN;

            requiredSteer = wheelBase ./ radius + K .* lat;
            requiredSteer(steerMask | lowLatMask) = 0;

            % hard physical clamp as a last-resort safety net
            requiredSteer = max(min(requiredSteer, 1), -1);   % ~57° in rad, generous for a race car

            data.requiredSteer = make_channel(requiredSteer, ref, 'rad', 'Required_Steer_VCH');
            fprintf('  [+] Required_Steer_VCH\n');
            data.instantRadius = make_channel(radius, ref, 'm', 'radius_VCH');
            fprintf('  [+] radius_VCH\n');
            data.requiredSteer = make_channel(requiredSteer, ref, 'rad', 'Required_Steer_VCH');
            data.requiredSteer.datatype   = 2;      % int16 is fine now range is clamped to ±1 rad
            data.requiredSteer.dec_places = 4;      % explicit — don't let auto_dec_places see the pre-clamp range
            data.requiredSteer.offset     = 0;
            data.requiredSteer.mul        = 1;
            data.requiredSteer.scale      = 1;

            data.instantRadius = make_channel(radius, ref, 'm', 'radius_VCH');
            data.instantRadius.datatype   = 2     % int32 — radius can legitimately be large
            data.instantRadius.dec_places = 4
            data.instantRadius.offset     = 0
            data.instantRadius.mul        = 1
            data.instantRadius.scale      = 1
        end
    catch ME; fprintf('  [!] Required steer failed: %s\n', ME.message); end

    % ==================================================================
    %  Required Steer — with aero correction
    %  Guard includes exist() checks to prevent scope leaks from the
    %  required-steer and gating blocks above.
    % ==================================================================
    try
        if isfield(data, 'Ground_Speed') && isfield(data, 'Steering_Angle') && ...
                isfield(data, 'AB_FRT_VCH') && isfield(data, 'CLa_SCz_VCH') && ...
                ~isempty(manufacturer) && ...
                exist('lat',       'var') && exist('radius',    'var') && ...
                exist('steerMask', 'var') && exist('carSpeed',  'var')
            mfr_key = lower(manufacturer);
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;
            rho             = 1.225;
            gravity         = 9.81;
            weightFrontAxle = 729.8 * gravity;
            weightRearAxle  = 617.7 * gravity;
            CZ = data.CLa_SCz_VCH.data;
            ABFRNT = data.AB_FRT_VCH.data;
            frontAeroForce = 0.5 * carSpeed .* rho .* (ABFRNT/100        .* CZ);
            rearAeroForce  = 0.5 * carSpeed .* rho .* ((1 - ABFRNT/100)  .* CZ);

            K = (1 / wheelBase) * ( ...
                ((weightFrontAxle + frontAeroForce) ./ corneringStiffnessFront) ./ gravity - ...
                ((weightRearAxle  + rearAeroForce)  ./ corneringStiffnessRear)  ./ gravity);

            requiredSteer_Aero = wheelBase ./ radius + K .* lat;
            requiredSteer_Aero(steerMask) = 0;
            data.requiredSteer_Aero = make_channel(requiredSteer_Aero, ref, 'rad', 'Required_Steer_Aero_VCH');
            fprintf('  [+] Required_Steer_Aero_VCH\n');
                        data.Aero_Front_Force = make_channel(frontAeroForce, ref, 'N', 'Aero_Front_Force');
            fprintf('  [+] Aero_Front_Force\n');
                        data.Aero_Rear_Force = make_channel(rearAeroForce, ref, 'N', 'Aero_Rear_Force');
            fprintf('  [+] Aero_Rear_Force\n');
        end
    catch ME; fprintf('  [!] Required steer aero failed: %s\n', ME.message); end
    
    try %% Front wheel speed yaw formula
        if isfield(data, 'Wheel_Speed_Front_Left') && isfield(data, 'Wheel_Speed_Front_Right') 

            tempData = movmean((data.Wheel_Speed_Front_Right.data - data.Wheel_Speed_Front_Left.data)/10,20);
            data.Wheel_Speed_Yaw_Rate = make_channel(tempData, ref, 'N', 'Wheel Speed Yaw Rate');
            fprintf('  [+] Wheel_Speed_Yaw_Rate\n');

        end
    catch ME; fprintf('  [!]  Wheel Speed Yaw Failed: %s\n', ME.message); end

    try
        if isfield(data, 'Acceleration_X_Filt') && isfield(data, 'Acceleration_Y_Filt') && ...
                isfield(data, 'Acceleration_Z_Filt') && isfield
            
            data.requiredSteer_Aero = make_channel(RR, ref, 'N', 'nRear Right Accel Based');
            fprintf('  [+] nRear Right Accel Based\n');
       
        end
    catch ME; fprintf('  [!]  Accelerometer Correction Failed: %s\n', ME.message); end
    
    %% Tyre Squish calculation Deflection vs speed
    try
        if isfield(data, 'Front_Ride_Height_Corr') && isfield(data, 'Rear_Ride_Height_Corr')
           
            tyreSquish = align_to(data.Kinematic_Ride_Height_Front, ref) - align_to(data.Front_Ride_Height_Corr, ref); 
            tyreSquish(straightMask) = NaN;

            


            
            data.Front_Tyre_Squish = make_channel(tyreSquish, ref, 'mm', 'Front Tyre Squish');
            fprintf('  [+] Front Tyre Squish\n');
       
        end
    catch ME; fprintf('  [!]  Accelerometer Correction Failed: %s\n', ME.message); end


    %% Tyre Squish calulation Deflection vs speed
    
    % GPS heading formula
    try
        if isfield(data, 'GPS_Longitude') && isfield(data, 'GPS_Latitude') 
            [heading_unwrapped, yaw_rate] =  gpsHeadingChannel(data.GPS_Latitude, data.GPS_Longitude);
            data.unwrappedHeading = make_channel(heading_unwrapped, ref, 'deg', 'Heading Unwrapped');
            fprintf('  [+]  Heading Unwrapped\n');
            data.yaw_rate = make_channel(yaw_rate, ref, 'deg', 'Yaw_Rate_GPS');
            fprintf('  [+]  yaw_rate_GPS\n');
            
        end
    catch ME; fprintf('  [!]  Heading Unwrapped Failed: %s\n', ME.message); end
    try
        if isfield(data, 'Ground_Speed') && isfield(data, 'CLa_SCz_VCH') && ...
                isfield(data, 'Aero_Front_Force') && isfield(data, 'Aero_Rear_Force')
% isfield(data, 'X_Acceleration_Corr') && isfield(data, 'Y_Acceleration_Corr') && ...
            % Plan for channel determine the normal load at each wheel
            % Once normal load is determined create channel for lateral
            % tyre forces
            % no Cog reduction with RH compression ! will need if math is
            % determined to be worth while
            axleWeights = readtable('C:\SimEnv\dataAcquisition\Motec_MP\alias\E07_TSV\scrutineeringInformaition\T07_TSV_axleWeights.csv');
            axleWeights = axleWeights(axleWeights.Session == string("Q17"), :);
            axleWeights = axleWeights(axleWeights.CarNumber == 88, :);

            if isempty(axleWeights)
                frontAxleWeight = 730;
                rearAxleWeight = 620;
                CoG_Z = vehicle.(mfr_key).kinematics.body.CoG(3);
            else
                frontAxleWeight = axleWeights.FrontAxleWeight;
                rearAxleWeight = axleWeights.RearAxleWeight;
                CoG_Z = vehicle.(mfr_key).kinematics.body.CoG(3);
            end 
            
            %% Placeholder
            X_Acceleration_Corr = data.Acceleration_X_Filt.data * 9.81;
            Y_Acceleration_Corr = data.Acceleration_Y_Filt.data * 9.81;
            ABFRNT = data.AB_FRT_VCH.data;

            simplifiedWheelbase = 2.75675; %m
            simplifiedTrackWidth = 2.000; %m
            mfr_key = lower(manufacturer);
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;
            rho             = 1.225;
            gravity         = 9.81;
            % Load longitudinal transfer
            totalMass = frontAxleWeight + rearAxleWeight;
            loadTransferFrontAxleLong =  (totalMass .* -1*X_Acceleration_Corr * 0.284 / simplifiedWheelbase);
            loadTransferRearAxleLong  = (totalMass .*  -1*X_Acceleration_Corr * 0.284 / simplifiedWheelbase);
            frontAeroForce = 0.5 * carSpeed .* rho .* (ABFRNT        .* CZ);
            rearAeroForce  = 0.5 * carSpeed .* rho .* ((1 - ABFRNT)  .* CZ);
            totalMass = frontAxleWeight + rearAxleWeight;
            
            loadTransferFrontLat = totalMass .* Y_Acceleration_Corr * 0.284/ simplifiedTrackWidth;
            loadTransferRearLat  = totalMass .* Y_Acceleration_Corr * 0.284/ simplifiedTrackWidth;
            FR = (loadTransferFrontAxleLong - (frontAeroForce(1:10:end)) + loadTransferFrontLat) + (frontAxleWeight/2) * 9.81;
            FL = (loadTransferFrontAxleLong - (frontAeroForce(1:10:end)) - loadTransferFrontLat) + (frontAxleWeight/2) * 9.81;
            RL = (loadTransferRearAxleLong +  (rearAeroForce(1:10:end)) + loadTransferRearLat) + (rearAxleWeight/2) * 9.81;
            RR = (loadTransferRearAxleLong + (rearAeroForce(1:10:end)) - loadTransferRearLat) + (rearAxleWeight/2) * 9.81;
            % Lateral load transfer
            data.nFront_Left_Accel_Based2 = make_channel(FL*-1, ref, 'N', 'nFront Left Accel Based2', 'overwrite', true);
            fprintf('  [+] nFront Left Accel Based\n');
            data.nFront_Left_Accel_Based = make_channel(FL, ref, 'N', 'nFront Left Accel Based', 'overwrite', true);
            fprintf('  [+] nFront Left Accel Based\n');
            data.nFront_Right_Accel_Based = make_channel(FR, ref, 'N', 'nFront Right Accel Based');
            fprintf('  [+] nFront Right Accel Based\n');
            data.nRear_Left_Accel_Based = make_channel(RL, ref, 'N', 'nRear Left Accel Based');
            fprintf('  [+] nRear Left Accel Based\n');
            data.nRear_Right_Accel_Based = make_channel(RR, ref, 'N', 'nRear Right Accel Based');
            fprintf('  [+] nRear Right Accel Based\n');
            % Trouble Shoot
            data.loadTransferFrontAxleLong2 = make_channel(loadTransferFrontAxleLong, ref, 'N', 'loadTransferFrontAxleLong2');
            fprintf('  [+] nFront Left Accel Based\n');
            data.loadTransferFrontLat2 = make_channel(loadTransferFrontLat, ref, 'N', 'loadTransferFrontLat2');
            fprintf('  [+] nFront Right Accel Based\n');

       
        end
    catch ME;
        fprintf('  [!]  Accel Based Tyre Normal Force Failed [!]: %s\n', ME.message); 
    end
end

function ch = make_channel(values, reference_ch, units, name, varargin)
% MAKE_CHANNEL  Build a channel struct matching motec_ld_reader output format.
%
% reference_ch supplies the time vector and sample rate.
% dec_places is auto-selected: highest precision that fits int32 range.
% Override dec_places after the call: data.myVCH.dec_places = 1;
%
% Usage
% -----
%   ch = make_channel(values, reference_ch, 'kPa', 'Brake Pressure Calc');
%   ch = make_channel(values, reference_ch, '%',   'Brake Balance VCH', 'overwrite', true);

    p = inputParser();
    addRequired(p, 'values');
    addRequired(p, 'reference_ch');
    addRequired(p, 'units');
    addRequired(p, 'name');
    addParameter(p, 'overwrite', false);
    parse(p, values, reference_ch, units, name, varargin{:});

    n = numel(values);

    ch.data        = values(:);
    ch.units       = units;
    ch.raw_name    = name;
    ch.write_to_ld = true;
    ch.overwrite   = p.Results.overwrite;
    ch.dec_places  = auto_dec_places(values);

    if n == numel(reference_ch.time)
        % Same length — use reference time and rate directly.
        ch.time        = reference_ch.time;
        ch.sample_rate = reference_ch.sample_rate;
    else
        % Different length — span same duration, infer actual sample rate.
        t_start        = reference_ch.time(1);
        t_end          = reference_ch.time(end);
        ch.time        = linspace(t_start, t_end, n)';
        ch.sample_rate = round(n / (t_end - t_start));
    end
end

function dec = auto_dec_places(values)
% Choose highest dec in {4,3,2,1,0} where data_range * 10^dec <= 32767.
% i2 Pro reads raw bytes as uint16; MATLAB reads as int16. Both agree only
% for values in [0,32767], so the data range (not max_abs) is the limit.
    finite_vals = values(isfinite(values));
    if isempty(finite_vals)
        dec = 2;
        return;
    end
    data_range = max(finite_vals) - min(finite_vals);
    if data_range == 0
        dec = 2;
        return;
    end
    dec = 0;
    for d = 4:-1:0
        if data_range * 10^d <= 32767
            dec = d;
            break;
        end
    end
end

function val = get_starting_val(sv, field, default)
    if isstruct(sv) && isfield(sv, field)
        val = sv.(field);
    else
        fprintf('  [!] startingVal.%s not found — using default %.4f\n', field, default);
        val = default;
    end
end

function wheelSpeed = tyreRadiusV1(pTyre, vCar, axle)
% tyreRadiusV1  Estimate loaded tyre radius from inflation pressure,
%               car speed, and axle.
%
%   tyreRadius = tyreRadiusV1(pTyre, vCar, axle)
%
%   pTyre  – tyre inflation pressure (psi), scalar or array
%   vCar   – car speed (km/h), scalar or array matching pTyre
%   axle   – 'front' | 'rear'

    tyreStiffness = 0.00318062275116337;
    wheelRadius   = 0.332633831;          % m

    frontCoef = [-0.0125, -0.196832152];
    rearCoef  = [-0.0010, -0.745339228];

    % --- pressure compensation (vectorised, no loop) ---------------------
    pTyre = align_to(pTyre, vCar);
    k            = 0.0005 .* (pTyre < 20) + 0.001 .* (pTyre >= 20);
    pressureComp = 33.99 - (33.99 - 31.5) .* exp(-k .* (pTyre - 27));

    % --- axle selection --------------------------------------------------
    switch lower(axle)
        case 'front'
            coef = frontCoef;
            addition = 9;
        case 'rear'
            coef = rearCoef;
            addition = 7;
        otherwise
            error('tyreRadiusV1: axle must be ''front'' or ''rear''');
    end

    vMs = vCar.data ./ 3.6;

    Cz = coef(1) .* vMs + coef(2);
    Fz = (0.5 .* vMs.^2 .* Cz ./ 2) .* tyreStiffness;
    Rf = 0.0071 .* (vMs ./ wheelRadius) .* 60 ./ (2 .* pi);

    tyreRadius = (pressureComp + Fz + Rf) * 10 + addition;
    wheelSpeed = (tyreRadius / 1000) .* (vMs ./ wheelRadius) * 3.6;
    
end


function fname = find_field(data, keyword)
% FIND_FIELD  Return the first field name in data that contains keyword
% (case-insensitive partial match). Returns '' if nothing matches.
% Use instead of isfield() for channels whose names may change by prefix,
% manufacturer, or source (e.g. 'L180_Laser_Ride_Height_Rear_Raw').
%
%   fn = find_field(data, 'Laser_Ride_Height_Rear');
%   if ~isempty(fn)
%       ch = data.(fn);
%   end
    fields = fieldnames(data);
    idx    = find(contains(fields, keyword, 'IgnoreCase', true), 1);
    if isempty(idx)
        fname = '';
    else
        fname = fields{idx};
    end
end

function ref = longest_channel(data)
% Returns the channel struct with the most data samples.
% Skips non-channel fields (e.g. data.info).
% Use as the ref argument for align_to() throughout smp_custom_channels.
    fields   = fieldnames(data);
    best_n   = 0;
    ref      = [];
    for i = 1:numel(fields)
        ch = data.(fields{i});
        if isstruct(ch) && isfield(ch, 'data') && isfield(ch, 'time') && isnumeric(ch.data)
            n = numel(ch.data);
            if n > best_n
                best_n = n;
                ref    = ch;
            end
        end
    end
    if isempty(ref)
        error('longest_channel: no valid channel structs found in data');
    end
end