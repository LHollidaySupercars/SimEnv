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
    parse(p, data, varargin{:});

    startingValues = p.Results.startingValues;
    GEN3_KinematicParameters;
    % Prefer explicit parameters; fall back to data.info if not supplied.
    manufacturer = p.Results.manufacturer;
    driver       = p.Results.driver;
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
    %  TEMPLATE — copy this block for each new channel
    % ==================================================================
    %{
    CHANNEL_NAME = 'My_Channel';
    REQUIRES     = {'Source_A', 'Source_B'};   % channels that must exist

    if all(isfield(data, REQUIRES))
        a = data.Source_A.data;
        b = data.Source_B.data;

        % --- YOUR MATH HERE ---
        result = a ./ b;   % element-wise, same length as source channels
        % ----------------------

        data.(CHANNEL_NAME) = make_channel(result, data.Source_A, 'unit_string', CHANNEL_NAME);
        fprintf('  [+] %s\n', CHANNEL_NAME);
    else
        fprintf('  [!] %s skipped — missing: %s\n', CHANNEL_NAME, ...
            strjoin(REQUIRES(~isfield(data, REQUIRES)), ', '));
    end
    %}

    % ==================================================================
    %  EXAMPLE 1: Brake Bias (Front %)
    %  Requires: Brake_Pressure_Front, Brake_Pressure_Rear
    % ==================================================================
    if isfield(data, 'Brake_Pressure_Front') && isfield(data, 'Brake_Pressure_Rear')
        f     = data.Brake_Pressure_Front.data;
        r     = data.Brake_Pressure_Rear.data;
        total = f + r;
        bias  = zeros(size(total));
        mask  = total > 0.5;                          % avoid divide-by-zero at rest
        bias(mask) = (f(mask) ./ total(mask)) * 100;

        data.brakeBiasVCH = make_channel(bias, data.Brake_Pressure_Front, '%', 'brake_Bias_VCH');
        fprintf('  [+] brake_Bias_VCH\n');
    end

    % ==================================================================
    %  EXAMPLE 2: Driving Gates
    %  Requires: ADR_Acceleration_X/Y, Acceleration_X/Y_Filt,
    %            Throttle_Pedal, Ground_Speed
    % ==================================================================
%% Gating Section
    if isfield(data, 'ADR_Acceleration_X') && isfield(data, 'ADR_Acceleration_Y') && ...
       isfield(data, 'Acceleration_X_Filt') && isfield(data, 'Acceleration_Y_Filt') && ...
       isfield(data, 'Throttle_Pedal') && isfield(data, 'Ground_Speed')

        long        = align_to(data.Acceleration_X_Filt, ref);
        lat         = align_to(data.Acceleration_Y_Filt, ref);
        absLat      = abs(lat);
        throttle    = align_to(data.Throttle_Pedal,      ref);
        groundSpeed = align_to(data.Ground_Speed,        ref);

        % ------------------------------------------------------------------
        %  DRIVING GATES  — boolean masks only (1/0), no channel values saved
        %  Gate definitions (tune thresholds as needed):
        %    Braking    : decelerating hard, low lateral load
        %    Entry      : still braking but lateral load building
        %    Mid-Corner : peak lateral, minimal longitudinal
        %    Exit       : accelerating, lateral load unwinding
        % ------------------------------------------------------------------
        brakingMask    = (long  < -0.05) & (movmean(absLat, 10) <  0.10);
        entryMask      = (long  < -0.05) & (movmean(absLat, 10) >= 0.10) & (absLat < 0.75);
        midCornerMask  =                   (absLat >= 0.75);
        exitMask       = (long  >  0.10) & (absLat <  0.75);
        straightMask   = (throttle >= 99) & (absLat < 0.2);
        ParityMask     = straightMask & (groundSpeed > 220) & (groundSpeed < 240);

        data.brakingGateVCH   = make_channel(double(brakingMask),   ref, 'bool', 'braking_Gate_VCH');
        data.entryGateVCH     = make_channel(double(entryMask),     ref, 'bool', 'entry_Gate_VCH');
        data.midCrnGateVCH    = make_channel(double(midCornerMask), ref, 'bool', 'mid_Crn_Gate_VCH');
        data.exitGateVCH      = make_channel(double(exitMask),      ref, 'bool', 'exit_Gate_VCH');
        data.straightGateVCH  = make_channel(double(straightMask),  ref, 'bool', 'straight_Gate_VCH');
        data.ParityMaskVCH    = make_channel(double(ParityMask),    ref, 'bool', 'parity_Gate_VCH');
        fprintf('  [+] Gates: Braking | Entry | MidCorner | Exit | Straight | Parity \n');
    end
    if isfield(data, 'fuel_mass_used')
        % placem holder for mass correction
    end

    if isfield(data, 'ADR_Acceleration_X') && isfield(data, 'ADR_Acceleration_Y') && exist('midCornerMask', 'var')
        %% Average Cornering Acceleration
        averageLat = lat .* midCornerMask;   % lateral G — already on ref time base
        data.avgCRNVCH = make_channel(averageLat, ref, 'G', 'avg_CRN_VCH');
        fprintf('  [+] avgCRNVCH\n');
    end

    %% Wheel Locking Calculation
    if isfield(data, 'Wheel_Speed_Front_Left') ...
        && isfield(data, 'Wheel_Speed_Front_Right') ...
        && isfield(data, 'Ground_Speed')

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

        %% --- build averaged rear channel on the ground speed time base ---
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

    %% Air Jack Timer
    if isfield(data, 'Air_Jack_Timer_Switch') && ...
       isfield(data, 'Wheel_Speed_Rear_Left') && ...
       isfield(data, 'Clutch_Pressure')       && ...
       isfield(data, 'Throttle_Pedal')

        switchData = data.Air_Jack_Timer_Switch.data;
        risingEdge = [false; diff(switchData) > 0];

        maskScrutineer = risingEdge & ...
                         data.Wheel_Speed_Rear_Left.data > 0 & ...
                         data.Clutch_Pressure.data < 1000  & ...
                         data.Throttle_Pedal.data > 1;

        data.flagOnJacksWSVCH = make_channel( ...
            double(maskScrutineer), ...
            data.Air_Jack_Timer_Switch, ...
            'bool', ...
            'flag_On_Jacks_WS_VCH');
        fprintf('  [+] flag_On_Jacks_WS_VCH\n');
    end

    if isfield(data, 'Ground_Speed')
        data.Gate_LowSpeed  = make_channel(double(data.Ground_Speed.data < 80),                                     data.Ground_Speed, 'bool', 'Gate_LowSpeed_VCH');
        data.Gate_MidSpeed  = make_channel(double(data.Ground_Speed.data >= 80  & data.Ground_Speed.data < 160),    data.Ground_Speed, 'bool', 'Gate_MidSpeed_VCH');
        data.Gate_HighSpeed = make_channel(double(data.Ground_Speed.data >= 160),                                   data.Ground_Speed, 'bool', 'Gate_HighSpeed_VCH');
    end

    %% Tyre Radius Estimation (Pressure + Load + Speed Correction)
    % Model:  r = (28.2200 + 0.0505*P + -0.000340*FZ + 0.0004*rotSpeed) * 10  [mm]
    % Source: CALSPAN data

    if isfield(data, 'Wheel_Speed_Front_Left') && isfield(data, 'TPM1S_FL_WS_PRESS')
        wheelSpeed  = tyreRadiusV1(data.TPM1S_FL_WS_PRESS, data.Wheel_Speed_Front_Left, 'front');
        data.Wheel_Speed_Loaded_Radius_FL = make_channel(wheelSpeed, data.Wheel_Speed_Front_Left, 'mm', 'Wheel_Speed_Loaded_Radius_FL');
        fprintf('  [+] Wheel_Speed_Loaded_Radius_FL\n');
    end

    if isfield(data, 'Wheel_Speed_Front_Right') && isfield(data, 'TPM1S_FR_WS_PRESS')
        wheelSpeed  = tyreRadiusV1(data.TPM1S_FR_WS_PRESS, data.Wheel_Speed_Front_Right, 'front');
        data.Wheel_Speed_Loaded_Radius_FR = make_channel(wheelSpeed, data.Wheel_Speed_Front_Right, 'mm', 'Wheel_Speed_Loaded_Radius_FR');
        fprintf('  [+] Wheel_Speed_Loaded_Radius_FR\n');
    end

    if isfield(data, 'Wheel_Speed_Rear_Right') && isfield(data, 'TPM1S_RR_WS_PRESS')
        wheelSpeed  = tyreRadiusV1(data.TPM1S_RR_WS_PRESS, data.Wheel_Speed_Rear_Right, 'rear');
        data.Wheel_Speed_Loaded_Radius_R = make_channel(wheelSpeed, data.TPM1S_RR_WS_PRESS, 'mm', 'Wheel_Speed_Loaded_Radius_R');
        fprintf('  [+] Wheel_Speed_Loaded_Radius_R\n');
    end

    %% Tyre Pressure Average Calculation — Rear axle
    if isfield(data, 'TPM1S_RR_WS_PRESS') && isfield(data, 'TPM1S_RL_WS_PRESS')
        if length(data.TPM1S_RR_WS_PRESS.data) > length(data.TPM1S_RL_WS_PRESS.data)
            newChan = align_to(data.TPM1S_RL_WS_PRESS, data.TPM1S_RR_WS_PRESS);
            refChan = data.TPM1S_RR_WS_PRESS;
        else
            newChan = align_to(data.TPM1S_RR_WS_PRESS, data.TPM1S_RL_WS_PRESS);
            refChan = data.TPM1S_RL_WS_PRESS;
        end
        tTyreRear_VCH_P = (newChan + refChan.data) ./ 2;
        data.tTyreRear_VCH_P = make_channel(tTyreRear_VCH_P, refChan, 'psi', 'tTyreRear_VCH_P');
        fprintf('  [+] tTyreRear_VCH_P\n');
    end

    if isfield(data, 'TPM1S_RR_WS_TEMP') && isfield(data, 'TPM1S_RL_WS_TEMP')
        if length(data.TPM1S_RR_WS_TEMP.data) > length(data.TPM1S_RL_WS_TEMP.data)
            newChan = align_to(data.TPM1S_RL_WS_TEMP, data.TPM1S_RR_WS_TEMP);
            refChan = data.TPM1S_RR_WS_TEMP;
        else
            newChan = align_to(data.TPM1S_RR_WS_TEMP, data.TPM1S_RL_WS_TEMP);
            refChan = data.TPM1S_RL_WS_TEMP;
        end
        tTyreRear_VCH_T = (newChan + refChan.data) / 2;
        data.tTyreRear_VCH_T = make_channel(tTyreRear_VCH_T, refChan, 'C', 'tTyreRear_VCH_T');
        fprintf('  [+] tTyreRear_VCH_T\n');
    end

    %% Tyre Pressure Average Calculation — Front axle
    if isfield(data, 'TPM1S_FR_WS_PRESS') && isfield(data, 'TPM1S_FL_WS_PRESS')
        if length(data.TPM1S_FR_WS_PRESS.data) > length(data.TPM1S_FL_WS_PRESS.data)
            newChan = align_to(data.TPM1S_FL_WS_PRESS, data.TPM1S_FR_WS_PRESS);
            refChan = data.TPM1S_FR_WS_PRESS;
        else
            newChan = align_to(data.TPM1S_FR_WS_PRESS, data.TPM1S_FL_WS_PRESS);
            refChan = data.TPM1S_FL_WS_PRESS;
        end
        tTyreFront_VCH_P = (newChan + refChan.data) / 2;
        data.tTyreFront_VCH_P = make_channel(tTyreFront_VCH_P, refChan, 'psi', 'tTyreFront_VCH_P');
        fprintf('  [+] tTyreFront_VCH_P\n');
    end

    if isfield(data, 'TPM1S_FR_WS_TEMP') && isfield(data, 'TPM1S_FL_WS_TEMP')
        if length(data.TPM1S_FR_WS_TEMP.data) > length(data.TPM1S_FL_WS_TEMP.data)
            newChan = align_to(data.TPM1S_FL_WS_TEMP, data.TPM1S_FR_WS_TEMP);
            refChan = data.TPM1S_FR_WS_TEMP;
        else
            newChan = align_to(data.TPM1S_FR_WS_TEMP, data.TPM1S_FL_WS_TEMP);
            refChan = data.TPM1S_FL_WS_TEMP;
        end
        tTyreFront_VCH_T = (newChan + refChan.data) / 2;
        data.tTyreFront_VCH_T = make_channel(tTyreFront_VCH_T, refChan, 'C', 'tTyreFront_VCH_T');
        fprintf('  [+] tTyreFront_VCH_T\n');
    end

    %% Fuel Density Calculation
    if isfield(data, 'Fuel_Used_Mass') && isfield(data, 'Fuel_Temperature')
        if length(data.Fuel_Temperature.data) > length(data.Fuel_Used_Mass.data)
            refFuel = data.Fuel_Temperature;
            x = data.Fuel_Temperature.data;
        else
            x = align_to(data.Fuel_Temperature, data.Fuel_Used_Mass);
            refFuel = data.Fuel_Used_Mass;
        end

        linearDensity = -0.8104 * x + 805.9;
        cubicDensity  = (-8.85 * 10^-7) * x.^3 + 0.0009464 * x.^2 - 0.8774 * x + 807;

        fuelDensityCorrectedCubic  = cubicDensity  ./ (data.Fuel_Used_Mass.data * 1000);
        fuelDensityCorrectedLinear = linearDensity ./ (data.Fuel_Used_Mass.data * 1000);

        data.Fuel_Density_Corr_Cubic  = make_channel(fuelDensityCorrectedCubic,  refFuel, 'L', 'Fuel_Density_Corr_Cubic');
        fprintf('  [+] Fuel_Density_Corr_Cubic\n');
        data.Fuel_Density_Corr_Linear = make_channel(fuelDensityCorrectedLinear, refFuel, 'L', 'Fuel_Density_Corr_Linear');
        fprintf('  [+] Fuel_Density_Corr_Linear\n');
    end

    %% RH Correction
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
        fprintf('  [+] pitchVCH\n');
        data.roll_VCH  = make_channel(roll,  data.Acceleration_X_Filt, 'deg', 'roll_VCH');
        fprintf('  [+] rollVCH\n');
    end

    if isfield(data, 'Laser_Ride_Height_Front_L_Raw') && ...
       isfield(data, 'Laser_Ride_Height_Front_R_Raw')
        midPoint = 0.5 .* (data.Laser_Ride_Height_Front_L_Raw.data + data.Laser_Ride_Height_Front_R_Raw.data);
        data.Laser_Ride_Height_Front_Raw = make_channel(midPoint, data.Laser_Ride_Height_Front_L_Raw, 'mm', 'Laser_Ride_Height_Front_Raw');
        fprintf('  [+] Laser_Ride_Height_Front_Raw\n');
    end

    if isfield(data, 'Laser_Ride_Height_Front_Raw') && ...
       isfield(data, 'Laser_Ride_Height_Rear_Raw')  && ...
       isfield(data, 'pitch_VCH') && ...
       isfield(data, 'roll_VCH')

        FRH_data = align_to(data.Laser_Ride_Height_Front_Raw, ref);
        RRH_data = align_to(data.Laser_Ride_Height_Rear_Raw, ref);

%         if length(FRH.data) >= length(RRH.data)
%             ref_ch   = ref;
%             FRH_data = FRH.data(:);
%             RRH_data = align_to(RRH, ref);
%         else
%             ref_ch   = ref;
%             FRH_data = align_to(FRH, ref);
%             RRH_data = RRH.data(:);
%         end

        gamma = deg2rad(align_to(data.roll_VCH,  ref));
        beta  = deg2rad(align_to(data.pitch_VCH, ref));

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

    %% Rear Wheel Slip Calculation
    if isfield(data, 'Wheel_Speed_Front_Left') && ...
       isfield(data, 'Wheel_Speed_Front_Right') && ...
       isfield(data, 'Vehicle_Speed')

        if data.Wheel_Speed_Front_Left.sample_rate >= data.Vehicle_Speed.sample_rate
            refSlip = data.Wheel_Speed_Front_Left;
        else
            refSlip = data.Vehicle_Speed;
        end

        wfl = align_to(data.Wheel_Speed_Front_Left,  refSlip);
        wfr = align_to(data.Wheel_Speed_Front_Right, refSlip);
        vs  = align_to(data.Vehicle_Speed,           refSlip);

        wf_avg    = (wfl + wfr) / 2;
        slip_mask = wf_avg > (1/3.6);
        longSlip  = zeros(size(wf_avg));
        longSlip(slip_mask) = (vs(slip_mask) - wf_avg(slip_mask)) ./ wf_avg(slip_mask);

        data.longSlipFrontVCH = make_channel(longSlip, refSlip, 'ratio', 'long_Slip_Front_VCH');
        fprintf('  [+] longSlipFrontVCH\n');
    end

    if isfield(data, 'Wheel_Speed_Rear_Left')  && ...
       isfield(data, 'Wheel_Speed_Front_Left') && ...
       isfield(data, 'Wheel_Speed_Front_Right')
%         ref
%         ref_ch  = data.Wheel_Speed_Rear_Left;
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

    % ==================================================================
    %  AERO MAP CHANNELS — CLa_SCz, AB_FRT, CDa_SCx, EFF at Roll=0
    % ==================================================================
    AERO_REQUIRES = {'L180_Laser_Ride_Height_Rear_Raw'};
    
    AERO_REQUIRES = 'Laser_Ride_Height_Rear';

    fn = fieldnames(data);
    matchIdx = find(contains(fn, AERO_REQUIRES), 1);

    if ~isempty(matchIdx)

        matchedField = fn{matchIdx};
        fprintf('Matched field: %s\n', matchedField);

        RRH_corrected = rawRideHeightCorrection(data, vehicle, 'rear');
        FRH_corrected = rawRideHeightCorrection(data, vehicle, 'front');
        data.FRH_corrected     = make_channel(rawRideHeightCorrection(data, vehicle, 'front'),...
            ref, 'mm',  'Front Ride Height Corr');
        data.RRH_corrected     = make_channel(rawRideHeightCorrection(data, vehicle, 'rear'),...
            ref, 'mm',  'Rear Ride Height Corr');
    end
    
    
    AERO_REQUIRES = {'Laser_Ride_Height_Front_Raw', 'Laser_Ride_Height_Rear_Raw'};
    AERO_MAP_DIR  = 'C:\SimEnv\vehicleModel\components\aerodynamics';

    if all(isfield(data, AERO_REQUIRES)) && exist('manufacturer', 'var')
        aero = aeroMapChannels(data.Laser_Ride_Height_Front_Raw, ...
                               data.Laser_Ride_Height_Rear_Raw, ...
                               manufacturer, AERO_MAP_DIR);
        if ~isempty(aero)
%             ref_ch = data.Laser_Ride_Height_Front_Raw;
            data.CLa_SCz_VCH = make_channel(aero.CLa_SCz, ref, '-',  'CLa_SCz_VCH');
            data.AB_FRT_VCH  = make_channel(aero.AB_FRT,  ref, '%',  'AB_FRT_VCH');
            data.CDa_SCx_VCH = make_channel(aero.CDa_SCx, ref, '-',  'CDa_SCx_VCH');
            data.EFF_VCH     = make_channel(aero.EFF,     ref, '-',  'EFF_VCH');
            fprintf('  [+] CLa_SCz_VCH  AB_FRT_VCH  CDa_SCx_VCH  EFF_VCH  (%s map, roll=0)\n', manufacturer);

            aero2 = aeroMapChannels(data.Laser_Ride_Height_Front_Raw, ...
                                    data.Laser_Ride_Height_Rear_Raw, ...
                                    manufacturer, AERO_MAP_DIR, -2);
            if ~isempty(aero2)
                data.CSa_Scy_VCH  = make_channel(aero2.CSa_Scy,  ref, '-', 'CSa_Scy_VCH');
                data.CSf_SCyF_VCH = make_channel(aero2.CSf_SCyF, ref, '-', 'CSf_SCyF_VCH');
                data.CSr_SCyR_VCH = make_channel(aero2.CSr_SCyR, ref, '-', 'CSr_SCyR_VCH');
                fprintf('  [+] CSa_Scy_VCH  CSf_SCyF_VCH  CSr_SCyR_VCH  (%s map, roll=-2)\n', manufacturer);
            end
        end
    else
        missing = AERO_REQUIRES(~isfield(data, AERO_REQUIRES));
        if ~isempty(missing)
            fprintf('  [!] Aero map channels skipped — missing: %s\n', strjoin(missing, ', '));
        else
            fprintf('  [!] Aero map channels skipped — info.manufacturer not set\n');
        end
    end
    if isfield(data, 'Steering_Angle') && isfield(data, 'Ground_Speed')
        mfr_key = lower(manufacturer);
         corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
        corneringStiffnessRear = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
        wheelBase = vehicle.(mfr_key).maximumWheelbase/1000; % mm -> m
        
        gravity = 9.81; % m/s^2
        weightFrontAxle = 729.8 * gravity;
        weightRearAxle = 617.7 * gravity;
        negativeMask = sign(lat);
        
       
        K = (1 / wheelBase ) * ...
                    ( ...
                    ( ((weightFrontAxle) / corneringStiffnessFront)/gravity) - ...
                    ( ((weightRearAxle) / corneringStiffnessRear)/gravity) ...
                    );
        mask = abs(align_to(data.Steering_Angle, ref)) < 0.5;
        
        carSpeed = align_to(data.Ground_Speed, ref)/3.6; % m/s
        
        radius = carSpeed.^2./(lat * gravity);
        radius(mask) = NaN;
        requiredSteer = wheelBase./radius + K .* (lat);
        requiredSteer(mask) = 0;
        data.requiredSteer = make_channel(requiredSteer, ref, 'rad', 'Required_Steer_VCH');
        fprintf('  [+] Required_Steer_VCH \n', manufacturer);
        data.instantRadius = make_channel(radius, ref, 'm', 'radius_VCH')
        fprintf('  [+] radius_VCH \n', 'nice');
    end
    if isfield(data, 'Ground_Speed') && isfield(data, 'Steering_Angle') ...
            && isfield(data, 'AB_FRT_VCH') && isfield(data, 'CLa_SCz_VCH');
        mfr_key = lower(manufacturer);
        corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
        corneringStiffnessRear = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
        wheelBase = vehicle.(mfr_key).maximumWheelbase/1000; %mm -> m
        rho = 1.225; % kg/m^3
        gravity = 9.81; % m/s^2
        weightFrontAxle = 729.8 * gravity;
        weightRearAxle = 617.7 * gravity;
        ABFRNT = align_to(data.AB_FRT_VCH, ref); 
        CZ = align_to(data.CLa_SCz_VCH, ref);
        % add aero contribution
        frontAeroForce =  1/2 * carSpeed .* rho .* ((ABFRNT) .* CZ); % units 
        rearAeroForce =   1/2 * carSpeed .* rho .* ((1 - ABFRNT) .* CZ); % units 
        K = (1 / wheelBase ) * ...
                    ( ...
                    ( ((weightFrontAxle + frontAeroForce) ./ corneringStiffnessFront)./gravity) - ...
                    ( ((weightRearAxle + rearAeroForce) ./ corneringStiffnessRear)./gravity) ...
                    );
        
%         mask = abs(align_to(data.Steering_Angle, ref)) < 0.5;
        
        carSpeed = align_to(data.Ground_Speed, ref)/3.6; % m/s
        
        requiredSteer_Aero = wheelBase./radius + (K .* lat);
        requiredSteer_Aero(mask) = 0;
        data.requiredSteer_Aero = make_channel(requiredSteer_Aero, ref, 'rad', 'Required_Steer_Aero_VCH');
        fprintf('  [+] Required_Steer_Aero_VCH \n', manufacturer);

    end 
    data.oneNumberCheck = make_channel(ones(length(ref.data),1)*-1, ref, '', 'one_Number_Check');
    fprintf('  [+] oneNumberCheck \n', manufacturer);


    if isfield(data, 'Ground_Speed')
%         % using the Yaw Rate Estimate with One Acceleration Measurement
%         % Uses a bicycle model to estimate the state.
%         % does not do well with disturbances, would be okay for a car in
%         % isolation from any enviromental effects
%         % x describes the state variables
%         C_af = 3;
%         C_ar = 3;
%         m = 1350;
%         u_o = 200/3.6;
%         a = 1;
%         b = 1;
%         I_z = 1;
%         
%         A = [ (C_af + C_af) / m*u_0               ,(a * C-af - b * C_ar - m * u_0^2) / (m * u_0) , 0    ;
%               ( a * C_af - b * C_ar) / (I_z * u_0), (a^2 * C_af + b^2 * C_ar)/ (I_z * u_0)       , 0    ;
%               a_s * (C_af + C_ar) / (m*u_0)       , a_s * ( a * C_af - b * C_ar)/ ( m*u_0)       , -a_s];
%         B = [ -C_af / m      ; 
%               -a*C_af / I_z  ;
%               -a_s * C_af / m];
        
    end
    if isfield(data, 'ADR_Acceleration_X')
        % place holder for required steer calculation
    end
end

% ======================================================================
function ch = make_channel(values, reference_ch, units, name)
% Build a channel struct matching motec_ld_reader output format.
% reference_ch supplies the time vector and sample rate.
% dec_places is auto-selected: highest precision that fits int32 range.
% Override dec_places after the call: data.myVCH.dec_places = 1;
    n = numel(values);
    ch.data   = values(:);
    ch.units  = units;
    ch.raw_name    = name;
    ch.write_to_ld = true;
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