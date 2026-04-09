function data = smp_custom_channels(data)
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

    fprintf('smp_custom_channels: computing derived channels...\n');

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

        data.brakeBiasVCH = make_channel(bias, data.Brake_Pressure_Front, '%', 'brakeBiasVCH');
        fprintf('  [+] brakeBiasVCH\n');
    end

    % ==================================================================
    %  EXAMPLE 2: Drive Index  (Throttle x Speed / 100)
    %  A simple aggression metric — higher = more throttle at higher speed
    % ==================================================================
    if isfield(data, 'ADR_Acceleration_X') && isfield(data, 'ADR_Acceleration_Y')

        long     = data.ADR_Acceleration_X.data;   % longitudinal G  (+ = accel, - = brake)
        lat      = data.ADR_Acceleration_Y.data;   % lateral G
        absLat   = abs(lat);
        throttle = data.Throttle_Pedal.data;

        % ------------------------------------------------------------------
        %  DRIVING GATES  — boolean masks only (1/0), no channel values saved
        %  Use these later by multiplying against any channel to isolate
        %  only the samples in that phase, then take non-zero mean etc.
        %
        %  Gate definitions (tune thresholds as needed):
        %    Braking    : decelerating hard, low lateral load
        %    Entry      : still braking but lateral load building
        %    Mid-Corner : peak lateral, minimal longitudinal
        %    Exit       : accelerating, lateral load unwinding
        % ------------------------------------------------------------------

        brakingMask    = (long  < -0.05) & (absLat <  0.10);
        entryMask      = (long  < -0.05) & (absLat >= 0.10) & (absLat < 0.75);
        midCornerMask  =                   (absLat >= 0.75);
        max(absLat)
        exitMask       = (long  >  0.10) & (absLat <  0.75);
        straightMask   = (throttle >= 99);
        % Save as double (0/1) — same time base as the source channel
        ref = data.ADR_Acceleration_X;   % reference channel for time/sample_rate

        data.brakingGateVCH   = make_channel(double(brakingMask),   ref, 'bool', 'brakingGateVCH');
        data.entryGateVCH     = make_channel(double(entryMask),     ref, 'bool', 'entryGateVCH');
        data.midCrnGateVCH    = make_channel(double(midCornerMask), ref, 'bool', 'midCrnGateVCH');
        data.exitGateVCH      = make_channel(double(exitMask),      ref, 'bool', 'exitGateVCH');
        data.straightGateVCH  = make_channel(double(straightMask),  ref, 'bool', 'straightGateVCH');
        fprintf('  [+] Gates: Braking | Entry | MidCorner | Exit | Straight\n');
        
    end

    if isfield(data, 'ADR_Acceleration_Y')
        %% Average Cornering Acceleration
           % longitudinal G  (+ = accel, - = brake)
        averageLat = data.ADR_Acceleration_Y.data .* midCornerMask;   % lateral G
        data.avgCRNVCH = make_channel(averageLat, data.ADR_Acceleration_Y, 'G', 'avgCRNVCH');
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
            rl = interp1(data.Wheel_Speed_Rear_Left.time,  data.Wheel_Speed_Rear_Left.data,  gnd_ch.time, 'linear', 'extrap');
           
            rear_avg = rl;
        elseif isfield(data, 'Wheel_Speed_Rear_Left')
            rear_avg = interp1(data.Wheel_Speed_Rear_Left.time, data.Wheel_Speed_Rear_Left.data, gnd_ch.time, 'linear', 'extrap');
        else
            rear_avg = [];
        end

        wheel_map = {
            'Wheel_Speed_Front_Left',  'FL_LockTimerVCH';
            'Wheel_Speed_Front_Right', 'FR_LockTimerVCH';
        };

        % append rear as a synthetic entry if we have it
        if ~isempty(rear_avg)
            % store temporarily so the loop can find it by field name
            data.Wheel_Speed_Rear_Avg__ = make_channel(rear_avg, gnd_ch, 'km/h', 'Wheel_Speed_Rear_Avg__');
            wheel_map(end+1,:) = {'Wheel_Speed_Rear_Avg__', 'RL_LockTimerVCH'};
        end

        for w = 1:size(wheel_map, 1)
            src = wheel_map{w,1};
            out = wheel_map{w,2};

            if ~isfield(data, src), continue; end

            ws        = interp1(data.(src).time, data.(src).data, gnd_ch.time, 'linear', 'extrap');
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

        % clean up the temp synthetic channel
        if isfield(data, 'Wheel_Speed_Rear_Avg__')
            data = rmfield(data, 'Wheel_Speed_Rear_Avg__');
        end
    end
    %% Rear Wheel Slip Calculation Acceleration
    if isfield(data, 'Wheel_Speed_Front_Left') && ...
       isfield(data, 'Wheel_Speed_Front_Right') && ...
       isfield(data, 'Vehicle_Speed')

        % Pick highest sample rate as reference
        if data.Wheel_Speed_Front_Left.sample_rate >= data.Vehicle_Speed.sample_rate
            ref = data.Wheel_Speed_Front_Left;
        else
            ref = data.Vehicle_Speed;
        end

        wfl = align_to(data.Wheel_Speed_Front_Left, ref);
        wfr = align_to(data.Wheel_Speed_Front_Right, ref);
        vs  = align_to(data.Vehicle_Speed , ref);

        wf_avg   = (wfl + wfr) / 2;
        slip_mask = wf_avg > (1/3.6);
        longSlip  = zeros(size(wf_avg));
        longSlip(slip_mask) = (vs(slip_mask) - wf_avg(slip_mask)) ./ wf_avg(slip_mask);

        data.longSlipFrontVCH = make_channel(longSlip, ref, 'ratio', 'longSlipFrontVCH');
        fprintf('  [+] longSlipFrontVCH\n');
    end
        
    if isfield(data, 'Wheel_Speed_Rear_Left')  && ...
       isfield(data, 'Wheel_Speed_Rear_Right') && ...
       isfield(data, 'Wheel_Speed_Front_Left') && ...
       isfield(data, 'Wheel_Speed_Front_Right')

        ref_ch = data.Wheel_Speed_Rear_Left;

        % average front wheels as reference vehicle speed
        fl = interp1(data.Wheel_Speed_Front_Left.time,  data.Wheel_Speed_Front_Left.data,  ref_ch.time, 'linear', 'extrap');
        fr = interp1(data.Wheel_Speed_Front_Right.time, data.Wheel_Speed_Front_Right.data, ref_ch.time, 'linear', 'extrap');
        car_spd = (fl + fr) / 2;

        rl = data.Wheel_Speed_Rear_Left.data;

        denom   = max(car_spd, 1.0);
        rl_slip = (rl - car_spd) ./ denom * 100;
        
        if isfield(data, 'exitGateVCH')
            gate = logical(data.exitGateVCH.data);
        else
            gate = true(size(rl));
        end

        data.RL_SlipVCH = make_channel(rl_slip .* double(gate), ref_ch, '%', 'RL_SlipVCH');
        data.RL_SlipVCH.interp_method = 'nearest';
        fprintf('  [+] RL_SlipVCH\n');
    end
    %% Air Jack Timer
   
    %%
    
    if isfield(data, 'Air_Jack_Timer_Switch') && ...
       isfield(data, 'Wheel_Speed_Rear_Left') && ...
       isfield(data, 'Clutch_Pressure')       && ...
       isfield(data, 'Throttle_Pedal')

        switchData = data.Air_Jack_Timer_Switch.data;
        risingEdge = [false; diff(switchData) > 0];   % moment jack switch activates

        maskScrutineer = risingEdge & ...
                         data.Wheel_Speed_Rear_Left.data > 0 & ...
                         data.Clutch_Pressure.data < 1000  & ...  % kPa
                         data.Throttle_Pedal.data > 1;

        data.flagOnJacksWSVCH = make_channel( ...
            double(maskScrutineer), ...
            data.Air_Jack_Timer_Switch, ...
            'bool', ...
            'flagOnJacksWSVCH');

        fprintf('  [+] flagOnJacksWSVCH\n');
    end
    
    if isfield(data, 'Ground_Speed') 

        data.Gate_LowSpeed  = double(data.Ground_Speed.data < 80);
        data.Gate_MidSpeed  = double(data.Ground_Speed.data >= 80  & data.Ground_Speed.data < 160);
        data.Gate_HighSpeed = double(data.Ground_Speed.data >= 160);
        data.Gate_LowSpeed = make_channel( ...
            double(data.Ground_Speed.data < 80), ...
            data.Ground_Speed, ...
            'bool', ...
            'Gate_LowSpeed');
        data.Gate_MidSpeed = make_channel( ...
            double(data.Ground_Speed.data >= 80  & data.Ground_Speed.data < 160), ...
            data.Ground_Speed, ...
            'bool', ...
            'Gate_MidSpeed');
        data.Gate_HighSpeed = make_channel( ...
            double(data.Ground_Speed.data >= 160), ...
            data.Ground_Speed, ...
            'bool', ...
            'Gate_HighSpeed');
        
    end

end


% ======================================================================
function ch = make_channel(values, reference_ch, units, name)
% Build a channel struct matching motec_ld_reader output format.
% reference_ch supplies the time vector and sample rate.
    ch.data        = values(:);               % force column vector
    ch.time        = reference_ch.time;
    ch.units       = units;
    ch.sample_rate = reference_ch.sample_rate;
    ch.raw_name    = name;
end

function out = align_to(source_ch, target_ch)
    s_t = source_ch.time(:);
    t_t = target_ch.time(:);
    if numel(s_t) == numel(t_t) && max(abs(s_t - t_t)) < 1e-9
        out = source_ch.data(:);
        return;
    end
    method = 'linear';
    if isfield(source_ch, 'interp_method')
        method = source_ch.interp_method;
    end
    t_q = min(max(t_t, s_t(1)), s_t(end));
    out = interp1(s_t, source_ch.data(:), t_q, method, 'extrap');
    out = out(:);
end