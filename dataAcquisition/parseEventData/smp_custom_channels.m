function data = smp_custom_channels(data, varargin)
% SMP_CUSTOM_CHANNELS  Compute derived channels from loaded MoTeC data.
%
% Call immediately after motec_ld_reader(), before caching.
% Channel format fields: .data .time .units .sample_rate .raw_name
%
% Naming convention:
%   Struct field : Word_Word_VCH[_Variant]   (PascalCase, underscores)
%   raw_name     : 'Word Word VCH [Variant]' (spaces — field with _ -> space)
%
% Dependency tiers — keep each block inside its correct section:
%   TIER 0 — raw transforms only
%   TIER 1 — intermediate derived (pitch/roll, dampers, gates)
%   TIER 2 — depends on Tier 1 (kinematic RH, corrected laser RH)
%   TIER 3 — depends on Tier 2 (aero maps)
%   TIER 4 — depends on Tier 1+3 (steer, slip, squish)
%   TIER 5 — depends on Tier 3+4 (aero-corrected dynamics, normal forces)

    p = inputParser();
    addRequired(p,  'data');
    addParameter(p, 'startingValues', struct());
    addParameter(p, 'manufacturer',   '');
    addParameter(p, 'driver',         '');
    addParameter(p, 'patchRH', struct());
    addParameter(p, 'session', '');
    addParameter(p, 'constants', struct());
    parse(p, data, varargin{:});

    startingValues = p.Results.startingValues;  %#ok<NASGU>
    GEN3_KinematicParameters;
    manufacturer = p.Results.manufacturer;
    driver       = p.Results.driver;
    patchRH      = p.Results.patchRH;
    session      = p.Results.session;
    constants    = p.Results.constants;          %#ok<NASGU>
    StaticWheelRadius = 0.332633831;
    if isfield(data, 'info') && isstruct(data.info)
        if isempty(manufacturer) && isfield(data.info, 'manufacturer')
            manufacturer = data.info.manufacturer;
        end
        if isempty(driver) && isfield(data.info, 'driver')
            driver = data.info.driver;
        end
    end
    AERO_MAP_DIR = fullfile(pwd, '\vehicleModel\components\aerodynamics');
    fprintf('smp_custom_channels: computing derived channels...\n');

    % ==================================================================
    %  TEMPLATE — copy into the correct tier section for new channels.
    % ==================================================================
    %{
    try
        ref = pick_ref(data, {'Source_A', 'Source_B'});
        if ~isempty(ref) && isfield(data,'Source_A') && isfield(data,'Source_B')
            a = align_to(data.Source_A, ref);
            b = align_to(data.Source_B, ref);
            data.My_Channel_VCH = make_channel(a ./ b, ref, 'units', 'My Channel VCH');
            fprintf('  [+] My_Channel_VCH\n');
        end
    catch ME; fprintf('  [!] My_Channel_VCH failed: %s\n', ME.message); end
    %}

    %% ================================================================
    %  TIER 0 — raw channel transforms (no inter-block dependencies)
    % =================================================================

    % ------------------------------------------------------------------
    %  Brake Bias Front (%)
    % ------------------------------------------------------------------
    try
        ref = pick_ref(data, {'Brake_Pressure_Front', 'Brake_Pressure_Rear'});
        if ~isempty(ref) && isfield(data,'Brake_Pressure_Front') && isfield(data,'Brake_Pressure_Rear')
            f        = align_to(data.Brake_Pressure_Front, ref);
            r        = align_to(data.Brake_Pressure_Rear,  ref);
            total    = f + r;
            bias     = zeros(size(total));
            mask     = total > 0.5;
            bias(mask) = (f(mask) ./ total(mask)) * 100;
            data.Brake_Bias_Front_VCH = make_channel(bias, ref, '%', 'Brake Bias Front VCH');
            fprintf('  [+] Brake_Bias_Front_VCH\n');
        end
    catch ME; fprintf('  [!] Brake_Bias_Front_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Speed Gates (Low / Mid / High)
    % ------------------------------------------------------------------
    try
        ref = pick_ref(data, {'Ground_Speed'});
        if ~isempty(ref)
            data.Gate_Low_Speed_VCH  = make_channel(double(ref.data < 80),                   ref, 'bool', 'Gate Low Speed VCH');
            data.Gate_Mid_Speed_VCH  = make_channel(double(ref.data >= 80 & ref.data < 160), ref, 'bool', 'Gate Mid Speed VCH');
            data.Gate_High_Speed_VCH = make_channel(double(ref.data >= 160),                 ref, 'bool', 'Gate High Speed VCH');
            fprintf('  [+] Gate_Low_Speed_VCH  Gate_Mid_Speed_VCH  Gate_High_Speed_VCH\n');
        end
    catch ME; fprintf('  [!] Speed gates failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Wheel Speed (rad/s)
    % ------------------------------------------------------------------
    try
        if isfield(data, 'Wheel_Speed_Front_Left')
            data.Wheel_Speed_FL_Omega_VCH = make_channel( ...
                data.Wheel_Speed_Front_Left.data ./ (3.6 .* StaticWheelRadius), ...
                data.Wheel_Speed_Front_Left, 'w', 'Wheel Speed FL Omega VCH');
            fprintf('  [+] Wheel_Speed_FL_Omega_VCH\n');
        end
        if isfield(data, 'Wheel_Speed_Front_Right')
            data.Wheel_Speed_FR_Omega_VCH = make_channel( ...
                data.Wheel_Speed_Front_Right.data ./ (3.6 .* StaticWheelRadius), ...
                data.Wheel_Speed_Front_Right, 'w', 'Wheel Speed FR Omega VCH');
            fprintf('  [+] Wheel_Speed_FR_Omega_VCH\n');
        end
        if isfield(data, 'Wheel_Speed_Rear_Left')
            data.Wheel_Speed_RL_Omega_VCH = make_channel( ...
                data.Wheel_Speed_Rear_Left.data ./ (3.6 .* StaticWheelRadius), ...
                data.Wheel_Speed_Rear_Left, 'w', 'Wheel Speed RL Omega VCH');
            fprintf('  [+] Wheel_Speed_RL_Omega_VCH\n');
        end
        if isfield(data, 'Wheel_Speed_Rear_Right')
            data.Wheel_Speed_RR_Omega_VCH = make_channel( ...
                data.Wheel_Speed_Rear_Right.data ./ (3.6 .* StaticWheelRadius), ...
                data.Wheel_Speed_Rear_Right, 'w', 'Wheel Speed RR Omega VCH');
            fprintf('  [+] Wheel_Speed_RR_Omega_VCH\n');
        end
    catch ME; fprintf('  [!] Wheel Speed Omega failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Wheel Speed Yaw Rate
    % ------------------------------------------------------------------
    try
        ref = pick_ref(data, {'Wheel_Speed_Front_Left', 'Wheel_Speed_Front_Right'});
        if ~isempty(ref) && isfield(data,'Wheel_Speed_Front_Left') && isfield(data,'Wheel_Speed_Front_Right')
            fl = align_to(data.Wheel_Speed_Front_Left,  ref);
            fr = align_to(data.Wheel_Speed_Front_Right, ref);
            data.Yaw_Rate_Wheel_Speed_VCH = make_channel(movmean((fr - fl) / 10, 20), ref, 'w', 'Yaw Rate Wheel Speed VCH');
            fprintf('  [+] Yaw_Rate_Wheel_Speed_VCH\n');
        end
    catch ME; fprintf('  [!] Yaw_Rate_Wheel_Speed_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Tyre Radius Estimation (CALSPAN model)
    % ------------------------------------------------------------------
    try
        if isfield(data,'Wheel_Speed_Front_Left') && isfield(data,'TPM1S_FL_WS_PRESS')
            data.Tyre_Radius_FL_VCH = make_channel( ...
                tyreRadiusV1(data.TPM1S_FL_WS_PRESS, data.Wheel_Speed_Front_Left, 'front'), ...
                data.Wheel_Speed_Front_Left, 'mm', 'Tyre Radius FL VCH');
            fprintf('  [+] Tyre_Radius_FL_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Front_Right') && isfield(data,'TPM1S_FR_WS_PRESS')
            data.Tyre_Radius_FR_VCH = make_channel( ...
                tyreRadiusV1(data.TPM1S_FR_WS_PRESS, data.Wheel_Speed_Front_Right, 'front'), ...
                data.Wheel_Speed_Front_Right, 'mm', 'Tyre Radius FR VCH');
            fprintf('  [+] Tyre_Radius_FR_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Rear_Right') && isfield(data,'TPM1S_RR_WS_PRESS')
            data.Tyre_Radius_RR_VCH = make_channel( ...
                tyreRadiusV1(data.TPM1S_RR_WS_PRESS, data.Wheel_Speed_Rear_Right, 'rear'), ...
                data.TPM1S_RR_WS_PRESS, 'mm', 'Tyre Radius RR VCH');
            fprintf('  [+] Tyre_Radius_RR_VCH\n');
        end
    catch ME; fprintf('  [!] Tyre radius failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Constant Camber
    % ------------------------------------------------------------------
    try
        if strcmp(manufacturer,'Ford') || strcmp(manufacturer,'Toyota') || strcmp(manufacturer,'Chevrolet')
            mask = strcmp(patchRH.MAN, manufacturer);
            CFL = mean(patchRH.CamberFL(mask)); CFR = mean(patchRH.CamberFR(mask));
            CRL = mean(patchRH.CamberRL(mask)); CRR = mean(patchRH.CamberRR(mask));
        else
            CFL = mean(patchRH.CamberFL); CFR = mean(patchRH.CamberFR);
            CRL = mean(patchRH.CamberRL); CRR = mean(patchRH.CamberRR);
        end
        if isnan(CFL), CFL = mean(patchRH.CamberFL(~isnan(patchRH.CamberFL))); end
        if isnan(CFR), CFR = mean(patchRH.CamberFR(~isnan(patchRH.CamberFR))); end
        if isnan(CRL), CRL = mean(patchRH.CamberRL(~isnan(patchRH.CamberRL))); end
        if isnan(CRR), CRR = mean(patchRH.CamberRR(~isnan(patchRH.CamberRR))); end
        driverMask = strcmp(patchRH.Driver, driver);
        if any(driverMask)
            dp = patchRH(driverMask, :);
            sm = strcmp(dp.Session, session);
            if any(sm)
                p2 = dp(sm, :);
                CFL = p2.CamberFL(1); CFR = p2.CamberFR(1);
                CRL = p2.CamberRL(1); CRR = p2.CamberRR(1);
            end
        end
        if isfield(data,'Wheel_Speed_Front_Left')
            data.Camber_FL_VCH = make_channel(CFL + zeros(size(data.Wheel_Speed_Front_Left.data)),  data.Wheel_Speed_Front_Left,  'deg', 'Camber FL VCH');
            fprintf('  [+] Camber_FL_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Front_Right')
            data.Camber_FR_VCH = make_channel(CFR + zeros(size(data.Wheel_Speed_Front_Right.data)), data.Wheel_Speed_Front_Right, 'deg', 'Camber FR VCH');
            fprintf('  [+] Camber_FR_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Rear_Left')
            data.Camber_RL_VCH = make_channel(CRL + zeros(size(data.Wheel_Speed_Rear_Left.data)),   data.Wheel_Speed_Rear_Left,   'deg', 'Camber RL VCH');
            fprintf('  [+] Camber_RL_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Rear_Right')
            data.Camber_RR_VCH = make_channel(CRR + zeros(size(data.Wheel_Speed_Rear_Right.data)),  data.Wheel_Speed_Rear_Right,  'deg', 'Camber RR VCH');
            fprintf('  [+] Camber_RR_VCH\n');
        end
    catch ME; fprintf('  [!] Constant camber failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Constant Toe
    % ------------------------------------------------------------------
    try
        if strcmp(manufacturer,'Ford') || strcmp(manufacturer,'Toyota') || strcmp(manufacturer,'Chevrolet')
            mask = strcmp(patchRH.MAN, manufacturer);
            TF = mean(patchRH.ToeFront(mask)); TR = mean(patchRH.ToeRear(mask));
        else
            TF = mean(patchRH.ToeFront); TR = mean(patchRH.ToeRear);
        end
        if isnan(TF), TF = mean(patchRH.ToeFront(~isnan(patchRH.ToeFront))); end
        if isnan(TR), TR = mean(patchRH.ToeRear(~isnan(patchRH.ToeRear)));   end
        driverMask = strcmp(patchRH.Driver, driver);
        if any(driverMask)
            dp = patchRH(driverMask, :);
            sm = strcmp(dp.Session, session);
            if any(sm)
                p2 = dp(sm, :);
                TF = p2.ToeFront(1); TR = p2.ToeRear(1);
            end
        end
        if isfield(data,'Wheel_Speed_Front_Left')
            data.Toe_FL_VCH = make_channel(TF + zeros(size(data.Wheel_Speed_Front_Left.data)),  data.Wheel_Speed_Front_Left,  'deg', 'Toe FL VCH');
            fprintf('  [+] Toe_FL_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Front_Right')
            data.Toe_FR_VCH = make_channel(TF + zeros(size(data.Wheel_Speed_Front_Right.data)), data.Wheel_Speed_Front_Right, 'deg', 'Toe FR VCH');
            fprintf('  [+] Toe_FR_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Rear_Left')
            data.Toe_RL_VCH = make_channel(TR + zeros(size(data.Wheel_Speed_Rear_Left.data)),   data.Wheel_Speed_Rear_Left,   'deg', 'Toe RL VCH');
            fprintf('  [+] Toe_RL_VCH\n');
        end
        if isfield(data,'Wheel_Speed_Rear_Right')
            data.Toe_RR_VCH = make_channel(TR + zeros(size(data.Wheel_Speed_Rear_Right.data)),  data.Wheel_Speed_Rear_Right,  'deg', 'Toe RR VCH');
            fprintf('  [+] Toe_RR_VCH\n');
        end
    catch ME; fprintf('  [!] Constant toe failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Tyre Pressure / Temperature Averages
    % ------------------------------------------------------------------
    try
        ref = pick_ref(data, {'TPM1S_RR_WS_PRESS', 'TPM1S_RL_WS_PRESS'});
        if ~isempty(ref) && isfield(data,'TPM1S_RR_WS_PRESS') && isfield(data,'TPM1S_RL_WS_PRESS')
            data.Tyre_Pressure_Rear_VCH = make_channel( ...
                (align_to(data.TPM1S_RR_WS_PRESS,ref) + align_to(data.TPM1S_RL_WS_PRESS,ref)) / 2, ...
                ref, 'psi', 'Tyre Pressure Rear VCH');
            fprintf('  [+] Tyre_Pressure_Rear_VCH\n');
        end
        ref = pick_ref(data, {'TPM1S_RR_WS_TEMP', 'TPM1S_RL_WS_TEMP'});
        if ~isempty(ref) && isfield(data,'TPM1S_RR_WS_TEMP') && isfield(data,'TPM1S_RL_WS_TEMP')
            data.Tyre_Temp_Rear_VCH = make_channel( ...
                (align_to(data.TPM1S_RR_WS_TEMP,ref) + align_to(data.TPM1S_RL_WS_TEMP,ref)) / 2, ...
                ref, 'C', 'Tyre Temp Rear VCH');
            fprintf('  [+] Tyre_Temp_Rear_VCH\n');
        end
        ref = pick_ref(data, {'TPM1S_FR_WS_PRESS', 'TPM1S_FL_WS_PRESS'});
        if ~isempty(ref) && isfield(data,'TPM1S_FR_WS_PRESS') && isfield(data,'TPM1S_FL_WS_PRESS')
            data.Tyre_Pressure_Front_VCH = make_channel( ...
                (align_to(data.TPM1S_FR_WS_PRESS,ref) + align_to(data.TPM1S_FL_WS_PRESS,ref)) / 2, ...
                ref, 'psi', 'Tyre Pressure Front VCH');
            fprintf('  [+] Tyre_Pressure_Front_VCH\n');
        end
        ref = pick_ref(data, {'TPM1S_FR_WS_TEMP', 'TPM1S_FL_WS_TEMP'});
        if ~isempty(ref) && isfield(data,'TPM1S_FR_WS_TEMP') && isfield(data,'TPM1S_FL_WS_TEMP')
            data.Tyre_Temp_Front_VCH = make_channel( ...
                (align_to(data.TPM1S_FR_WS_TEMP,ref) + align_to(data.TPM1S_FL_WS_TEMP,ref)) / 2, ...
                ref, 'C', 'Tyre Temp Front VCH');
            fprintf('  [+] Tyre_Temp_Front_VCH\n');
        end
    catch ME; fprintf('  [!] Tyre pressure/temp averages failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Fuel Density Calculation
    % ------------------------------------------------------------------
    try
        if isfield(data,'Fuel_Used_Mass') && isfield(data,'Fuel_Temperature')
            ref  = pick_ref(data, {'Fuel_Used_Mass', 'Fuel_Temperature'});
            x    = align_to(data.Fuel_Temperature, ref);
            fmA  = align_to(data.Fuel_Used_Mass,   ref);
            linearDensity = -0.8104 * x + 805.9;
            cubicDensity  = (-8.85e-7) * x.^3 + 0.0009464 * x.^2 - 0.8774 * x + 807;
            data.Fuel_Density_Cubic_VCH  = make_channel(cubicDensity  ./ (fmA * 1000), ref, 'L', 'Fuel Density Cubic VCH');
            data.Fuel_Density_Linear_VCH = make_channel(linearDensity ./ (fmA * 1000), ref, 'L', 'Fuel Density Linear VCH');
            fprintf('  [+] Fuel_Density_Cubic_VCH  Fuel_Density_Linear_VCH\n');
        end
    catch ME; fprintf('  [!] Fuel density failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Fuel In Car / Car Mass
    % ------------------------------------------------------------------
    try
        if isfield(data,'Refuel_Head') && isfield(data,'Fuel_Density') && ...
                isfield(data,'Fuel_Flow_Used_Mass') && isfield(data,'Fuel_Pot_Level_Mass')
            if isempty(data.Fuel_Pot_Level_Mass.data)
                error('Fuel_Pot_Level_Mass is empty.');
            end
            finishingFuel_Offset = min(data.Fuel_Pot_Level_Mass.data((end-6000):end));
            if strcmp(manufacturer,'Ford') || strcmp(manufacturer,'Toyota') || strcmp(manufacturer,'Chevrolet')
                mask = strcmp(patchRH.MAN, manufacturer);
                startFuel    = mean(patchRH.StartingFuel(mask));
                refuelRate   = mean(patchRH.RefuelRate(mask));
                frontAxleMass = mean(patchRH.FrontAxleMass(mask));
                rearAxleMass  = mean(patchRH.RearAxleMass(mask));
            else
                startFuel    = mean(patchRH.StartingFuel);
                refuelRate   = mean(patchRH.RefuelRate);
                frontAxleMass = mean(patchRH.FrontAxleMass);
                rearAxleMass  = mean(patchRH.RearAxleMass);
            end
            driverMask = strcmp(patchRH.Driver, driver);
            if any(driverMask)
                dp = patchRH(driverMask, :);
                sm = strcmp(dp.Session, session);
                if any(sm)
                    p2 = dp(sm, :);
                    startFuel     = p2.StartingFuel(1);
                    refuelRate    = p2.RefuelRate(1);
                    frontAxleMass = p2.FrontAxleMass(1);
                    rearAxleMass  = p2.RearAxleMass(1);
                end
            end
            if isnan(startFuel) || isnan(refuelRate)
                error('startFuel or refuelRate resolved to NaN.');
            end
            refFuel = pick_ref(data, {'Refuel_Head', 'Fuel_Density'});
            data.Fuel_Density.data = align_to(data.Fuel_Density,  data.Refuel_Head)
            corrDensity      = data.Fuel_Density.data / 1000;
            cumFuelUsed      = cumtrapz(data.Fuel_Flow_Used_Mass.data) / 1000;
            cumRefuel        = cumtrapz(data.Refuel_Head.data) .*corrDensity .* refuelRate;
            FuelMass         = startFuel - cumFuelUsed + cumRefuel;
            activeIdx = find(data.Refuel_Head.data >= 1);
            if ~isempty(activeIdx)
                lastIdx       = activeIdx(end);
                finalIdx      = (lastIdx + 1):length(FuelMass);
                if ~isempty(finalIdx)
                    flowSince = cumFuelUsed(finalIdx) - cumFuelUsed(lastIdx);
                    totalFlow = cumFuelUsed(end)      - cumFuelUsed(lastIdx);
                    FuelMass(finalIdx) = finishingFuel_Offset + (totalFlow - flowSince);
                    fprintf('  [+] Final stint corrected idx %d-%d (anchor=%.2f kg)\n', ...
                        lastIdx+1, length(FuelMass), finishingFuel_Offset);
                end
            else
                fprintf('  [!] No refuel activity — final-stint correction skipped\n');
            end
            if length(FuelMass) ~= length(refFuel.data)
                error('FuelMass length (%d) != ref length (%d).', length(FuelMass), length(refFuel.data));
            end
            data.Fuel_Mass_VCH = make_channel(FuelMass, refFuel, 'kg', 'Fuel Mass VCH', 'overwrite', true);
            fprintf('  [+] Fuel_Mass_VCH\n');
            data.Car_Mass_VCH  = make_channel(FuelMass + frontAxleMass + rearAxleMass, refFuel, 'kg', 'Car Mass VCH', 'overwrite', true);
            fprintf('  [+] Car_Mass_VCH\n');
            data.Car_Mass_VCH  = make_channel(FuelMass.*0 +frontAxleMass + rearAxleMass, refFuel, 'kg', 'Static Car Mass VCH', 'overwrite', true);
            fprintf('  [+] Car_Mass_VCH\n');
        end
    catch ME; fprintf('  [!] Fuel_Mass_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Air Jack Timer
    % ------------------------------------------------------------------
    try
        if isfield(data,'Air_Jack_Timer_Switch') && isfield(data,'Wheel_Speed_Rear_Left') && ...
                isfield(data,'Clutch_Pressure') && isfield(data,'Throttle_Pedal')
            sw  = data.Air_Jack_Timer_Switch.data;
            msk = [false; diff(sw) > 0] & ...
                  data.Wheel_Speed_Rear_Left.data > 0 & ...
                  data.Clutch_Pressure.data < 1000 & ...
                  data.Throttle_Pedal.data > 1;
            data.Flag_On_Jacks_VCH = make_channel(double(msk), data.Air_Jack_Timer_Switch, 'bool', 'Flag On Jacks VCH');
            fprintf('  [+] Flag_On_Jacks_VCH\n');
        end
    catch ME; fprintf('  [!] Flag_On_Jacks_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Wheel Locking Timer
    % ------------------------------------------------------------------
    try
        if isfield(data,'Wheel_Speed_Front_Left') && isfield(data,'Wheel_Speed_Front_Right') && isfield(data,'Ground_Speed')
            LOCK_THRESH = 15;  BRAKE_THRESH = 2;  MIN_SPEED = 30;
            gnd_ch = pick_ref(data, {'Corr_Speed', 'Ground_Speed'});
            gnd    = gnd_ch.data;
            dt     = 1 / gnd_ch.sample_rate;
            spd_ok = gnd > MIN_SPEED;
            if isfield(data,'Brake_Pressure_Front')
                brk = align_to(data.Brake_Pressure_Front, gnd_ch) > BRAKE_THRESH;
            else
                brk = true(size(gnd));
            end
            rear_avg = [];
            if isfield(data,'Wheel_Speed_Rear_Left')
                rear_avg = align_to(data.Wheel_Speed_Rear_Left, gnd_ch);
            elseif isfield(data,'Wheel_Speed_Rear_Right')
                rear_avg = align_to(data.Wheel_Speed_Rear_Right, gnd_ch);
            end
            wheel_map = {
                'Wheel_Speed_Front_Left',  'Lock_Timer_FL_VCH', 'Lock Timer FL VCH';
                'Wheel_Speed_Front_Right', 'Lock_Timer_FR_VCH', 'Lock Timer FR VCH';
            };
            if ~isempty(rear_avg)
                data.Wheel_Speed_Rear_Avg__ = make_channel(rear_avg, gnd_ch, 'km/h', 'Wheel Speed Rear Avg');
                wheel_map(end+1,:) = {'Wheel_Speed_Rear_Avg__', 'Lock_Timer_RL_VCH', 'Lock Timer RL VCH'};
            end
            for w = 1:size(wheel_map,1)
                src = wheel_map{w,1};  out = wheel_map{w,2};  raw = wheel_map{w,3};
                if ~isfield(data, src), continue; end
                ws        = align_to(data.(src), gnd_ch);
                lock_mask = (gnd - ws) > LOCK_THRESH & brk & spd_ok;
                cs        = cumsum(double(lock_mask) * dt);
                reset_src = cs .* double(~lock_mask);
                nz        = reset_src ~= 0;
                held      = zeros(size(cs));
                if any(nz)
                    grp = cumsum(nz);  nz_pos = find(nz);  valid = grp > 0;
                    held(valid) = reset_src(nz_pos(grp(valid)));
                end
                lock_timer = max(0, cs - held) .* double(lock_mask);
                data.(out) = make_channel(lock_timer, gnd_ch, 's', raw);
                data.(out).interp_method = 'nearest';
                fprintf('  [+] %s\n', out);
            end
            if isfield(data,'Wheel_Speed_Rear_Avg__'), data = rmfield(data,'Wheel_Speed_Rear_Avg__'); end
        end
    catch ME; fprintf('  [!] Wheel locking failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Off-Pedal Rotation Time (Lift & Coast / Rotation Limited)
    % ------------------------------------------------------------------
    try
        if isfield(data,'Throttle_Pedal') && isfield(data,'Brake_Pressure_Front') && isfield(data,'Ground_Speed')
            ref      = pick_ref(data, {'Throttle_Pedal', 'Brake_Pressure_Front', 'Ground_Speed'});
            throttle = align_to(data.Throttle_Pedal,       ref);
            brake    = align_to(data.Brake_Pressure_Front, ref);
            speed    = align_to(data.Ground_Speed,         ref);
            tOn = throttle > 2;  bOn = brake > 2;  neither = ~tOn & ~bOn;
            rawState = nan(size(throttle));
            rawState(tOn) = 1;  rawState(bOn) = 2;
            state = fillmissing(rawState, 'previous');
            liftMask = double(neither & state == 1 & speed > 50);
            rotMask  = double(neither & state == 2 & speed > 50);
            data.Lift_Coast_Time_VCH    = make_channel(cumtrapz(ref.time, liftMask), ref, '-', 'Lift Coast Time VCH',    'overwrite', true);
            data.Rotation_Limited_VCH   = make_channel(cumtrapz(ref.time, rotMask),  ref, '-', 'Rotation Limited VCH',   'overwrite', true);
            data.Gate_Lift_Coast_VCH    = make_channel(liftMask,                                ref, 'bool', 'Gate Lift Coast VCH');
            data.Gate_Off_Pedal_VCH     = make_channel(double(neither & speed > 50),            ref, 'bool', 'Gate Off Pedal VCH');
            data.Gate_Full_Throttle_VCH = make_channel(double(throttle >= 99),                  ref, 'bool', 'Gate Full Throttle VCH');
            fprintf('  [+] Lift_Coast_Time_VCH  Rotation_Limited_VCH  Gate_Lift_Coast/Off_Pedal/Full_Throttle_VCH\n');
        end
    catch ME; fprintf('  [!] Off-pedal time failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Throttle / Steering Aggression
    % ------------------------------------------------------------------
    try
        if isfield(data,'Steering_Angle') && isfield(data,'Throttle_Pedal') && isfield(data,'Brake_Pressure_Front')
            steer_agg = cumtrapz(data.Steering_Angle.time, ...
                abs(lowpass_filter(data.Steering_Angle.data, data.Steering_Angle.time, 0.8) - data.Steering_Angle.data));
            thr_lp = lowpass_filter(data.Throttle_Pedal.data, data.Throttle_Pedal.time, 0.8);
            brake  = align_to(data.Brake_Pressure_Front, data.Throttle_Pedal);
            thr    = data.Throttle_Pedal.data;
            cond   = (thr < 99) & (thr > 1) & (thr < 70) & (brake < 10) & (abs(thr_lp - thr) > 10);
            data.Throttle_Aggression_VCH = make_channel(cumtrapz(data.Throttle_Pedal.time, double(cond(:))), data.Throttle_Pedal, '-', 'Throttle Aggression VCH');
            data.Steering_Aggression_VCH = make_channel(steer_agg, data.Steering_Angle, '-', 'Steering Aggression VCH');
            fprintf('  [+] Throttle_Aggression_VCH  Steering_Aggression_VCH\n');
        end
    catch ME; fprintf('  [!] Aggression channels failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  GPS Heading / Yaw Rate
    % ------------------------------------------------------------------
    try
        if isfield(data,'GPS_Longitude') && isfield(data,'GPS_Latitude')
            ref = pick_ref(data, {'GPS_Latitude', 'GPS_Longitude'});
            [heading_unwrapped, yaw_rate_gps] = gpsHeadingChannel(data.GPS_Latitude, data.GPS_Longitude);
            data.Heading_Unwrapped_VCH = make_channel(heading_unwrapped, ref, 'deg', 'Heading Unwrapped VCH');
            data.Yaw_Rate_GPS_VCH      = make_channel(yaw_rate_gps,      ref, 'deg', 'Yaw Rate GPS VCH');
            fprintf('  [+] Heading_Unwrapped_VCH  Yaw_Rate_GPS_VCH\n');
        end
    catch ME; fprintf('  [!] GPS heading failed: %s\n', ME.message); end

    %% ================================================================
    %  TIER 1 — intermediate derived (depends only on raw channels)
    % =================================================================

    % ------------------------------------------------------------------
    %  Pitch / Roll from IMU
    % ------------------------------------------------------------------
    try
        if isfield(data,'Acceleration_X_Filt') && isfield(data,'Acceleration_Y_Filt') && isfield(data,'Acceleration_Z_Filt')
            ref   = pick_ref(data, {'Acceleration_X_Filt', 'Acceleration_Y_Filt', 'Acceleration_Z_Filt'});
            IMU_Y = align_to(data.Acceleration_X_Filt, ref);
            IMU_X = align_to(data.Acceleration_Y_Filt, ref);
            data.Roll_VCH  = make_channel(movmean(atan(IMU_X ./ sqrt(IMU_Y.^2)), 10), ref, 'deg', 'Roll VCH');
            data.Pitch_VCH = make_channel(movmean(atan(IMU_Y ./ abs(IMU_X)),     10), ref, 'deg', 'Pitch VCH');
            fprintf('  [+] Pitch_VCH  Roll_VCH\n');
        end
    catch ME; fprintf('  [!] Pitch/Roll failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Damper Zeroing
    % ------------------------------------------------------------------
    try
        fnFL = find_field(data, 'C1_Damper_Pos_FL');
        fnFR = find_field(data, 'C1_Damper_Pos_FR');
        fnRL = find_field(data, 'C1_Damper_Pos_RL');
        fnRR = find_field(data, 'C1_Damper_Pos_RR');
        if ~isempty(fnFL) && ~isempty(fnFR) && ~isempty(fnRL) && ~isempty(fnRR)
            data.Damper_FL_Zero_VCH = make_channel( ...
                data.(fnFL).data - min(movmean(data.(fnFL).data,10)), data.(fnFL), 'mm', 'Damper FL Zero VCH', 'overwrite', true);
            data.Damper_FR_Zero_VCH = make_channel( ...
                data.(fnFR).data - min(movmean(data.(fnFR).data,10)), data.(fnFR), 'mm', 'Damper FR Zero VCH', 'overwrite', true);
            data.Damper_RL_Zero_VCH = make_channel( ...
                data.(fnRL).data - min(movmean(data.(fnRL).data,10)), data.(fnRL), 'mm', 'Damper RL Zero VCH', 'overwrite', true);
            data.Damper_RR_Zero_VCH = make_channel( ...
                data.(fnRR).data - min(movmean(data.(fnRR).data,10)), data.(fnRR), 'mm', 'Damper RR Zero VCH', 'overwrite', true);
            fprintf('  [+] Damper_FL/FR/RL/RR_Zero_VCH\n');
        end
    catch ME; fprintf('  [!] Damper zeroing failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Laser Ride Height Front Raw (average of L + R sensors)
    % ------------------------------------------------------------------
    try
        fn_frhL = find_field(data, 'Laser_Ride_Height_Front_L_Raw');
        fn_frhR = find_field(data, 'Laser_Ride_Height_Front_R_Raw');
        if ~isempty(fn_frhL) && ~isempty(fn_frhR)
            ref = pick_ref(data, {fn_frhL, fn_frhR});
            data.RH_Laser_Front_Raw_VCH = make_channel( ...
                0.5 .* (align_to(data.(fn_frhL),ref) + align_to(data.(fn_frhR),ref)), ...
                ref, 'mm', 'RH Laser Front Raw VCH');
            fprintf('  [+] RH_Laser_Front_Raw_VCH  (from %s + %s)\n', fn_frhL, fn_frhR);
        end
    catch ME; fprintf('  [!] RH_Laser_Front_Raw_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Driving Gates
    %  ADR accelerometers preferred; falls back to L180 if ADR absent.
    % ------------------------------------------------------------------
    % try
    %     hasADR = isfield(data,'ADR_Acceleration_X') && isfield(data,'ADR_Acceleration_Y') && ...
    %              isfield(data,'Acceleration_X_Filt') && isfield(data,'Acceleration_Y_Filt');
    %     hasL180 = isfield(data,'L180_ADR_Acceleration_X') && isfield(data,'L180_ADR_Acceleration_Y');
    %     hasPedals = isfield(data,'Throttle_Pedal') && isfield(data,'Ground_Speed');
    %     if (hasADR || hasL180) && hasPedals
    %         if hasADR
    %             ref  = pick_ref(data, {'Acceleration_X_Filt','Acceleration_Y_Filt','Throttle_Pedal','Ground_Speed'});
    %             long = align_to(data.Acceleration_X_Filt, ref);
    %             lat  = align_to(data.Acceleration_Y_Filt, ref);
    %             src_label = 'ADR';
    %         else
    %             ref  = pick_ref(data, {'L180_ADR_Acceleration_X','L180_ADR_Acceleration_Y','Throttle_Pedal','Ground_Speed'});
    %             long = align_to(data.L180_ADR_Acceleration_X, ref);
    %             lat  = align_to(data.L180_ADR_Acceleration_Y, ref);
    %             src_label = 'L180';
    %         end
    %         absLat   = abs(lat);
    %         throttle = align_to(data.Throttle_Pedal, ref);
    %         gspeed   = align_to(data.Ground_Speed,   ref);
    %         brakingMask   = (long  < -0.8) & (movmean(absLat,10) <  0.15) ;
    %         entryMask     = (long  < -0.05) & (movmean(absLat,10) >= 0.15) & (absLat < 0.75);
    %         midCornerMask =                   (absLat >= 0.75) & throttle < 99;
    %         exitMask      = (long  >  0.10) & (absLat <  0.75);
    %         straightMask  = (throttle >= 99) & (absLat < 0.2);
    %         parityMask    = straightMask & (gspeed > 220) & (gspeed < 240);
    %         data.Gate_Braking_VCH    = make_channel(double(brakingMask),   ref, 'bool', 'Gate Braking VCH');
    %         data.Gate_Entry_VCH      = make_channel(double(entryMask),     ref, 'bool', 'Gate Entry VCH');
    %         data.Gate_Mid_Corner_VCH = make_channel(double(midCornerMask), ref, 'bool', 'Gate Mid Corner VCH');
    %         data.Gate_Exit_VCH       = make_channel(double(exitMask),      ref, 'bool', 'Gate Exit VCH');
    %         data.Gate_Straight_VCH   = make_channel(double(straightMask),  ref, 'bool', 'Gate Straight VCH');
    %         data.Gate_Parity_VCH     = make_channel(double(parityMask),    ref, 'bool', 'Gate Parity VCH');
    %         fprintf('  [+] Gates: Braking|Entry|MidCorner|Exit|Straight|Parity  (%s)\n', src_label);
    %     end
    % catch ME; fprintf('  [!] Driving gates failed: %s\n', ME.message); end

    try
        hasADR = isfield(data,'ADR_Acceleration_X') && isfield(data,'ADR_Acceleration_Y') && ...
                 isfield(data,'Acceleration_X_Filt') && isfield(data,'Acceleration_Y_Filt');
        hasL180 = isfield(data,'L180_ADR_Acceleration_X') && isfield(data,'L180_ADR_Acceleration_Y');
        hasPedals = isfield(data,'Throttle_Pedal') && isfield(data,'Ground_Speed');
        if (hasADR || hasL180) && hasPedals
            if hasADR
                ref  = pick_ref(data, {'Acceleration_X_Filt','Acceleration_Y_Filt','Throttle_Pedal','Ground_Speed'});
                long = align_to(data.Acceleration_X_Filt, ref);
                lat  = align_to(data.Acceleration_Y_Filt, ref);
                src_label = 'ADR';
            else
                ref  = pick_ref(data, {'L180_ADR_Acceleration_X','L180_ADR_Acceleration_Y','Throttle_Pedal','Ground_Speed'});
                long = align_to(data.L180_ADR_Acceleration_X, ref);
                lat  = align_to(data.L180_ADR_Acceleration_Y, ref);
                src_label = 'L180';
            end
            long     = long(:);
            lat      = lat(:);
            throttle = align_to(data.Throttle_Pedal, ref);  throttle = throttle(:);
            gspeed   = align_to(data.Ground_Speed,   ref);  gspeed   = gspeed(:);
            N = numel(long);

            % ---- thresholds ----
            gc.zone_on = -0.70; gc.zone_off = -0.15;   % g, hard-braking zone hysteresis
            gc.brk_frac = 0.70;                        % Braking = decel >= this fraction of event peak
            gc.bp_on = 3;                              % bar: brake pressure extends the braking zone
            gc.cor_on = 0.50; gc.cor_off = 0.35;       % g, corner detection on smoothed |lat|
            gc.turnin = 0.15;                          % g, |lat| level where turn-in starts
            gc.mid_start_frac = 0.80;                  % Mid starts at this fraction of the corner's p90 |lat|
            gc.entry_min_s = 0.30;                     % s: Entry lasts at least this long after braking ends
            gc.max_exit_s = 4;                         % s: cap on Exit length
            gc.lift_thr = 90;                          % % throttle: below this inside a corner counts as a lift
            gc.pin_lat = 0.80;                         % g: no-lift, no-brake corner needs this p90 |lat| to count
            gc.thr_exit = 50;                          % % throttle: Exit start (after lat apex)
            gc.thr_full = 99;                          % % throttle: full throttle / lift reference
            gc.full_hold_s = 0.25;                     % s, full-throttle hold; Exit ends at its start + this
            gc.str_lat = 0.20; gc.par_v = [220 240];   % g, km/h
            gc.smooth_s = 0.20; gc.lat_smooth_s = 0.50;
            gc.gap_s = 0.30; gc.cor_gap_s = 0.50; gc.min_brk_s = 0.30; gc.min_cor_s = 0.50;
            gc.lookback_s = 4; gc.max_evt_s = 15;      % s: lift lookback / max Exit run-on

            fs = ref.sample_rate;
            S  = @(s) max(1, round(s*fs));
            longS = movmean(long, S(gc.smooth_s));
            latS  = abs(movmean(lat, S(gc.smooth_s)));       % smooth signed, then abs: noise cancels, corners split at sign changes
            latC  = abs(movmean(lat, S(gc.lat_smooth_s)));

            hasBP = isfield(data,'Brake_Pressure_Front');
            if hasBP, bp = align_to(data.Brake_Pressure_Front, ref); bp = bp(:); end

            % ---- hard braking (independent of corners) ----
            zRaw = hyst(longS, gc.zone_on, gc.zone_off, 'below');
            if hasBP, zRaw = zRaw | ((bp > gc.bp_on) & (longS < -0.10)); end
            zone = clean_runs(zRaw, S(gc.gap_s), 1);
            d = diff([0; zone; 0]);  zs = find(d==1);  ze = find(d==-1)-1;
            brakeM = false(N,1);
            for k = 1:numel(zs)
                idx  = zs(k):ze(k);
                hard = idx(longS(idx) <= gc.brk_frac*min(longS(idx)));
                if numel(hard) < S(gc.min_brk_s), continue; end
                brakeM(hard(1):hard(end)) = true;
            end

            % ---- corners from lateral accel only ----
            cor = clean_runs(hyst(latC, gc.cor_on, gc.cor_off, 'above'), S(gc.cor_gap_s), S(gc.min_cor_s));
            d = diff([0; cor; 0]);  cs_ = find(d==1);  ce_ = find(d==-1)-1;

            hold = S(gc.full_hold_s);
            entryM = false(N,1); midM = entryM; exitM = entryM; transM = entryM;
            for k = 1:numel(cs_)
                s0 = cs_(k);  e0 = ce_(k);
                if k > 1, prevEnd = ce_(k-1); else, prevEnd = 0; end
                if k < numel(cs_), lim = cs_(k+1)-1; else, lim = N; end
                lim = min(lim, e0 + S(gc.max_evt_s));
                nz = zs(find(zs > e0, 1));
                if ~isempty(nz), lim = min(lim, nz-1); end

                % earliest of turn-in and throttle lift (walking back from corner start)
                t0 = s0;
                while t0 > prevEnd+1 && latC(t0-1) > gc.turnin, t0 = t0-1; end
                l0 = s0;  lb = max(prevEnd+1, s0 - S(gc.lookback_s));
                while l0 > lb && throttle(l0-1) < gc.thr_full, l0 = l0-1; end
                b0 = min(t0, l0);

                % Mid start and lateral apex from a robust (p90) corner level
                seg = s0:e0;
                v   = sort(latC(seg));
                pkv = v(max(1, ceil(0.90*numel(v))));
                ms  = s0 - 1 + find(latC(seg) >= gc.mid_start_frac*pkv, 1);
                ap  = s0 - 1 + find(latC(seg) >= pkv, 1);
                if isempty(ms) || isempty(ap), continue; end

                % keep only real corners: braked (incl. trail braking into it), lifted, or strongly pinned
                braked = any(brakeM(b0:ms));
                lifted = min(throttle(b0:e0)) < gc.lift_thr;
                if ~braked && ~lifted && pkv < gc.pin_lat, continue; end

                % Exit start: throttle back on after the apex
                xs = ap - 1 + find(throttle(ap:lim) >= gc.thr_exit, 1);
                if isempty(xs), xs = e0; end

                % Exit end: later of corner end and full-throttle hold, capped
                xe = e0;
                fr = throttle(xs:lim) >= gc.thr_full;
                dd = diff([0; fr; 0]);  rs = find(dd==1);  re = find(dd==-1)-1;
                okr = find((re - rs + 1) >= hold, 1);
                if ~isempty(okr), xe = max(xe, xs + rs(okr) - 1 + hold); end
                xe = min(xe, lim);
                xe = min(xe, xs + S(gc.max_exit_s));
                xs = min(xs, xe);

                if braked                              % hard braking led in
                    bl = b0 - 1 + find(brakeM(b0:ms), 1, 'last');
                    ms = min(max(ms, bl + S(gc.entry_min_s)), xs);   % always leave an Entry window
                    entryM(bl+1:ms-1) = true;
                    midM(ms:xs-1)     = true;
                    exitM(xs:xe)      = true;
                else                                   % lift-only or pinned corner
                    transM(b0:e0) = true;
                end
            end
            entryM(brakeM) = false;  midM(brakeM) = false;  exitM(brakeM) = false;  transM(brakeM) = false;

            strM = (throttle >= gc.thr_full) & (latS < gc.str_lat) & ~brakeM & ~entryM & ~midM & ~exitM & ~transM;
            parM = strM & (gspeed > gc.par_v(1)) & (gspeed < gc.par_v(2));

            data.Gate_Braking_VCH    = make_channel(double(brakeM), ref, 'bool', 'Gate Braking VCH',    'overwrite', true);
            data.Gate_Entry_VCH      = make_channel(double(entryM), ref, 'bool', 'Gate Entry VCH',      'overwrite', true);
            data.Gate_Mid_Corner_VCH = make_channel(double(midM),   ref, 'bool', 'Gate Mid Corner VCH', 'overwrite', true);
            data.Gate_Exit_VCH       = make_channel(double(exitM),  ref, 'bool', 'Gate Exit VCH',       'overwrite', true);
            data.Gate_Transient_VCH  = make_channel(double(transM), ref, 'bool', 'Gate Transient VCH',  'overwrite', true);
            data.Gate_Straight_VCH   = make_channel(double(strM),   ref, 'bool', 'Gate Straight VCH',   'overwrite', true);
            data.Gate_Parity_VCH     = make_channel(double(parM),   ref, 'bool', 'Gate Parity VCH',     'overwrite', true);

            % NaN where a gate is closed so i2 draws a gap; float32 (internal datatype 5) holds NaN
            gateNames = {'Gate_Braking_VCH','Gate_Entry_VCH','Gate_Mid_Corner_VCH','Gate_Exit_VCH', ...
                         'Gate_Transient_VCH','Gate_Straight_VCH','Gate_Parity_VCH'};
            for gi = 1:numel(gateNames)
                g = data.(gateNames{gi});
                g.data(g.data == 0) = NaN;
                g.datatype = 5;  g.offset = 0;  g.dec_places = 0;  g.mul = 1;  g.scale = 1;
                data.(gateNames{gi}) = g;
            end
            fprintf('  [+] Gates: Braking|Entry|MidCorner|Exit|Transient|Straight|Parity  (%s)\n', src_label);
        end
    catch ME; fprintf('  [!] Driving gates failed: %s\n', ME.message); end
    %% ================================================================
    %  TIER 2 — depends on Tier 1 VCH channels
    % =================================================================

    % ------------------------------------------------------------------
    %  Kinematic Ride Height (zeroed dampers + patch offset)
    % ------------------------------------------------------------------
    try
        fnFL = find_field(data, 'Damper_FL_Zero');
        fnFR = find_field(data, 'Damper_FR_Zero');
        fnRL = find_field(data, 'Damper_RL_Zero');
        fnRR = find_field(data, 'Damper_RR_Zero');
        if ~isempty(fnFL) && ~isempty(fnFR) && ~isempty(fnRL) && ~isempty(fnRR)
            if strcmp(manufacturer,'Ford') || strcmp(manufacturer,'Toyota') || strcmp(manufacturer,'Chevrolet')
                mask = strcmp(patchRH.MAN, manufacturer);
                FRH_Offset = mean(patchRH.FrontRH(mask), 'omitnan');
                RRH_Offset = mean(patchRH.RearRH(mask),  'omitnan');
            else
                FRH_Offset = mean(patchRH.FrontRH, 'omitnan');
                RRH_Offset = mean(patchRH.RearRH,  'omitnan');
            end
            if isnan(FRH_Offset), FRH_Offset = mean(patchRH.FrontRH(~isnan(patchRH.FrontRH))); end
            if isnan(RRH_Offset), RRH_Offset = mean(patchRH.RearRH(~isnan(patchRH.RearRH)));   end
            driverMask = strcmp(patchRH.Driver, driver);
            if any(driverMask)
                dp = patchRH(driverMask, :);
                sm = strcmp(dp.Session, session);
                if any(sm)
                    p2 = dp(sm, :);
                    FRH_Offset = p2.FrontRH(1);
                    RRH_Offset = p2.RearRH(1);
                end
            end
            if isnan(FRH_Offset); FRH_Offset = 50; end
            if isnan(RRH_Offset); RRH_Offset = 70; end
            RH_FL = -data.(fnFL).data + FRH_Offset;
            RH_FR = -data.(fnFR).data + FRH_Offset;
            RH_RL = -data.(fnRL).data + RRH_Offset;
            RH_RR = -data.(fnRR).data + RRH_Offset;
            data.RH_Kin_FL_VCH    = make_channel(RH_FL,               data.(fnFL), 'mm', 'RH Kin FL VCH',    'overwrite', true);
            data.RH_Kin_FR_VCH    = make_channel(RH_FR,               data.(fnFR), 'mm', 'RH Kin FR VCH',    'overwrite', true);
            data.RH_Kin_RL_VCH    = make_channel(RH_RL,               data.(fnRL), 'mm', 'RH Kin RL VCH',    'overwrite', true);
            data.RH_Kin_RR_VCH    = make_channel(RH_RR,               data.(fnRR), 'mm', 'RH Kin RR VCH',    'overwrite', true);
            data.RH_Kin_Front_VCH = make_channel((RH_FL + RH_FR) / 2, data.(fnFR), 'mm', 'RH Kin Front VCH', 'overwrite', true);
            data.RH_Kin_Rear_VCH  = make_channel((RH_RL + RH_RR) / 2, data.(fnRR), 'mm', 'RH Kin Rear VCH',  'overwrite', true);
            fprintf('  [+] RH_Kin_FL/FR/RL/RR_VCH  RH_Kin_Front/Rear_VCH\n');
        end
    catch ME; fprintf('  [!] Kinematic RH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Ride Height IMU Correction (pitch/roll compensation on laser)
    % ------------------------------------------------------------------
    try
        fn_frh = find_field(data, 'RH_Laser_Front_Raw');
        fn_rrh = find_field(data, 'Laser_Ride_Height_Rear_Raw');
        if ~isempty(fn_frh) && ~isempty(fn_rrh) && isfield(data,'Pitch_VCH') && isfield(data,'Roll_VCH')
            ref      = pick_ref(data, {fn_frh, fn_rrh, 'Pitch_VCH', 'Roll_VCH'});
            FRH_data = align_to(data.(fn_frh),   ref);
            RRH_data = align_to(data.(fn_rrh),   ref);
            gamma    = deg2rad(align_to(data.Roll_VCH,  ref));
            beta     = deg2rad(align_to(data.Pitch_VCH, ref));
            frontTx = 33.9;   frontTy = 427.74;  frontTz = 30.9;
            rearTx  = 24.0;   rearTy  = 236.9;   rearTz  = 19.4;
            dz_FL = -sin(beta).*frontTx + cos(beta).*sin(gamma).*(-frontTy) + (cos(beta).*cos(gamma)-1).*frontTz;
            dz_FR = -sin(beta).*frontTx + cos(beta).*sin(gamma).*( frontTy) + (cos(beta).*cos(gamma)-1).*frontTz;
            dz_RL = -sin(beta).*rearTx  + cos(beta).*sin(gamma).*(-rearTy)  + (cos(beta).*cos(gamma)-1).*rearTz;
            dz_RR = -sin(beta).*rearTx  + cos(beta).*sin(gamma).*( rearTy)  + (cos(beta).*cos(gamma)-1).*rearTz;
            data.RH_FL_VCH = make_channel(FRH_data + dz_FL, ref, 'mm', 'RH FL VCH');
            data.RH_FR_VCH = make_channel(FRH_data + dz_FR, ref, 'mm', 'RH FR VCH');
            data.RH_RL_VCH = make_channel(RRH_data + dz_RL, ref, 'mm', 'RH RL VCH');
            data.RH_RR_VCH = make_channel(RRH_data + dz_RR, ref, 'mm', 'RH RR VCH');
            fprintf('  [+] RH_FL/FR/RL/RR_VCH\n');
        end
    catch ME; fprintf('  [!] RH IMU correction failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Raw Ride Height Correction — L180 laser source
    % ------------------------------------------------------------------
    try
        fn = find_field(data, 'Laser_Ride_Height_Rear');
        if ~isempty(fn) && ~isempty(manufacturer)
            ref = pick_ref(data, {fn});
            data.RH_Front_Corr_VCH = make_channel( ...
                rawRideHeightCorrection(data, vehicle, 'front', 'L180_Laser_Ride_Height_Front_Ra', 'L180_Laser_Ride_Height_Rear_Raw'), ...
                ref, 'mm', 'RH Front Corr VCH', 'overwrite', true);
            data.RH_Rear_Corr_VCH = make_channel( ...
                rawRideHeightCorrection(data, vehicle, 'rear',  'L180_Laser_Ride_Height_Front_Ra', 'L180_Laser_Ride_Height_Rear_Raw'), ...
                ref, 'mm', 'RH Rear Corr VCH',  'overwrite', true);
            fprintf('  [+] RH_Front/Rear_Corr_VCH  (L180, matched: %s)\n', fn);
        end
    catch ME; fprintf('  [!] RH_Corr_VCH L180 failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Raw Ride Height Correction — ECU suspension source
    % ------------------------------------------------------------------
    try
        fn = find_field(data, 'Suspension');
        if ~isempty(fn) && ~isempty(manufacturer)
            ref = pick_ref(data, {fn});
            data.RH_Front_Corr_VCH = make_channel( ...
                rawRideHeightCorrection(data, vehicle, 'front', 'ECU_Suspension_Ride_Height_Fron', 'ECU_Suspension_Ride_Height_Rear'), ...
                ref, 'mm', 'RH Front Corr VCH', 'overwrite', true);
            data.RH_Rear_Corr_VCH = make_channel( ...
                rawRideHeightCorrection(data, vehicle, 'rear',  'ECU_Suspension_Ride_Height_Fron', 'ECU_Suspension_Ride_Height_Rear'), ...
                ref, 'mm', 'RH Rear Corr VCH',  'overwrite', true);
            fprintf('  [+] RH_Front/Rear_Corr_VCH  (ECU, matched: %s)\n', fn);
        end
    catch ME; fprintf('  [!] RH_Corr_VCH ECU failed: %s\n', ME.message); end

    %% ================================================================
    %  TIER 3 — aero maps (depends on Tier 2 ride height channels)
    % =================================================================

    % ------------------------------------------------------------------
    %  Aero Map — Kinematic RH source
    % ------------------------------------------------------------------
    try
        fn_f = find_field(data, 'RH_Kin_Front_VCH');
        fn_r = find_field(data, 'RH_Kin_Rear_VCH');
        if ~isempty(fn_f) && ~isempty(fn_r) && ~isempty(manufacturer)
            ref  = pick_ref(data, {fn_f, fn_r});
            aero = aeroMapChannels(data.(fn_f), data.(fn_r), manufacturer, AERO_MAP_DIR);
            if ~isempty(aero)
                newBal = aero.CLf_SCzF ./ (aero.CLf_SCzF + aero.CLr_SCzR);
                data.Aero_Cz_VCH_KIN          = make_channel(aero.CLa_SCz,                ref, '-',  'Aero Cz VCH KIN',            'overwrite', true);
                data.Aero_Balance_Front_VCH_KIN = make_channel(newBal,                     ref, '%', 'Aero Balance Front VCH KIN', 'overwrite', true);
                data.Aero_Cx_VCH_KIN           = make_channel(aero.CDa_SCx,               ref, '-',  'Aero Cx VCH KIN',            'overwrite', true);
                data.Aero_Efficiency_VCH_KIN    = make_channel(aero.CLa_SCz./aero.CDa_SCx, ref, '-', 'Aero Efficiency VCH KIN',    'overwrite', true);
                fprintf('  [+] Aero_CLa/Balance_Front/CDa/Efficiency_VCH_KIN  (%s roll=0)\n', manufacturer);
                aero2 = aeroMapChannels(data.(fn_f), data.(fn_r), manufacturer, AERO_MAP_DIR, -2);
                if ~isempty(aero2)
                    data.Aero_Cy_VCH_KIN = make_channel(aero2.CSa_Scy,  ref, '-', 'Aero Cy VCH KIN', 'overwrite', true);
                    data.Aero_Cyf_VCH_KIN = make_channel(aero2.CSf_SCyF, ref, '-', 'Aero Cyf VCH KIN', 'overwrite', true);
                    data.Aero_Cyr_VCH_KIN = make_channel(aero2.CSr_SCyR, ref, '-', 'Aero Cyf VCH KIN', 'overwrite', true);
                    fprintf('  [+] Aero_CSa/CSf/CSr_VCH_KIN  (%s roll=-2)\n', manufacturer);
                end
            end
        elseif isempty(manufacturer)
            fprintf('  [!] Aero map KIN skipped — manufacturer not set\n');
        end
    catch ME; fprintf('  [!] Aero map KIN failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Aero Map — Corrected Laser RH source
    % ------------------------------------------------------------------
    try
        fn_f = find_field(data, 'RH_Front_Corr_VCH');
        fn_r = find_field(data, 'RH_Rear_Corr_VCH');
        if ~isempty(fn_f) && ~isempty(fn_r) && ~isempty(manufacturer)
            ref  = pick_ref(data, {fn_f, fn_r});
            aero = aeroMapChannels(data.(fn_f), data.(fn_r), manufacturer, AERO_MAP_DIR);
            if ~isempty(aero)
                newBal = aero.CLf_SCzF ./ (aero.CLf_SCzF + aero.CLr_SCzR);
                data.Aero_Cz_VCH_MEAS          = make_channel(aero.CLa_SCz,                ref, '-',  'Aero Cz VCH MEAS');
                data.Aero_Balance_Front_VCH_MEAS = make_channel(newBal,                     ref, '%', 'Aero Balance Front VCH MEAS');
                data.Aero_Cx_VCH_MEAS           = make_channel(aero.CDa_SCx,               ref, '-',  'Aero Cx VCH MEAS');
                data.Aero_Efficiency_VCH_MEAS    = make_channel(aero.CLa_SCz./aero.CDa_SCx, ref, '-', 'Aero Efficiency VCH MEAS');
                fprintf('  [+] Aero_CLa/Balance_Front/CDa/Efficiency_VCH_MEAS  (%s roll=0)\n', manufacturer);
                aero2 = aeroMapChannels(data.(fn_f), data.(fn_r), manufacturer, AERO_MAP_DIR, -2);
                if ~isempty(aero2)
                    data.Aero_Cx_VCH_MEAS = make_channel(aero2.CSa_Scy,  ref, '-', 'Aero Cy VCH MEAS');
                    data.Aero_Cyf_VCH_MEAS = make_channel(aero2.CSf_SCyF, ref, '-', 'Aero Cyf VCH MEAS');
                    data.Aero_Cyr_VCH_MEAS = make_channel(aero2.CSr_SCyR, ref, '-', 'Aero Cyr VCH MEAS');
                    fprintf('  [+] Aero_CSa/CSf/CSr_VCH_MEAS  (%s roll=-2)\n', manufacturer);
                end
            end
        elseif isempty(manufacturer)
            fprintf('  [!] Aero map MEAS skipped — manufacturer not set\n');
        end
    catch ME; fprintf('  [!] Aero map MEAS failed: %s\n', ME.message); end

    %% ================================================================
    %  TIER 4 — depends on Tier 1 gates and/or Tier 3 aero maps
    % =================================================================

    % ------------------------------------------------------------------
    %  Wheel Slip — Longitudinal (front vs vehicle speed)
    % ------------------------------------------------------------------
    try
        if isfield(data,'Wheel_Speed_Front_Left') && isfield(data,'Wheel_Speed_Front_Right') && isfield(data,'Vehicle_Speed')
            ref   = pick_ref(data, {'Wheel_Speed_Front_Left','Wheel_Speed_Front_Right','Vehicle_Speed'});
            wfl   = align_to(data.Wheel_Speed_Front_Left,  ref);
            wfr   = align_to(data.Wheel_Speed_Front_Right, ref);
            vs    = align_to(data.Vehicle_Speed,           ref);
            wf_avg    = (wfl + wfr) / 2;
            slip_mask = wf_avg > (1/3.6);
            longSlip  = zeros(size(wf_avg));
            longSlip(slip_mask) = (vs(slip_mask) - wf_avg(slip_mask)) ./ wf_avg(slip_mask);
            data.Slip_Long_Front_VCH = make_channel(longSlip, ref, 'ratio', 'Slip Long Front VCH');
            fprintf('  [+] Slip_Long_Front_VCH\n');
        end
    catch ME; fprintf('  [!] Slip_Long_Front_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Wheel Slip — RL vs front average (gated to exit phase)
    % ------------------------------------------------------------------
    try
        if isfield(data,'Wheel_Speed_Rear_Left') && isfield(data,'Wheel_Speed_Front_Left') && isfield(data,'Wheel_Speed_Front_Right')
            ref     = pick_ref(data, {'Wheel_Speed_Rear_Left','Wheel_Speed_Front_Left','Wheel_Speed_Front_Right'});
            fl      = align_to(data.Wheel_Speed_Front_Left,  ref);
            fr      = align_to(data.Wheel_Speed_Front_Right, ref);
            car_spd = (fl + fr) / 2;
            rl      = align_to(data.Wheel_Speed_Rear_Left,   ref);
            rl_slip = (rl - car_spd) ./ car_spd * 100;
            if isfield(data,'Gate_Exit_VCH')
                gate = align_to(data.Gate_Exit_VCH, ref) == 1;
            else
                gate = true(size(rl));
            end
            data.Slip_RL_VCH = make_channel(rl_slip .* double(gate), ref, '%', 'Slip RL VCH');
            data.Slip_RL_VCH.interp_method = 'nearest';
            fprintf('  [+] Slip_RL_VCH\n');
        end
    catch ME; fprintf('  [!] Slip_RL_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Required Steer — no aero correction
    % ------------------------------------------------------------------
    try
        if isfield(data,'Steering_Angle') && isfield(data,'Ground_Speed') && ...
                isfield(data,'Acceleration_Y_Filt') && ~isempty(manufacturer)
            mfr_key = lower(manufacturer);
            ref     = pick_ref(data, {'Steering_Angle','Ground_Speed','Acceleration_Y_Filt'});
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;
            gravity         = 9.81;
            weightFrontAxle = 729.8 * gravity;
            weightRearAxle  = 617.7 * gravity;
            K = (1/wheelBase) * ( ...
                (weightFrontAxle/corneringStiffnessFront)/gravity - ...
                (weightRearAxle /corneringStiffnessRear )/gravity);
            lat       = align_to(data.Acceleration_Y_Filt, ref);
            carSpeed  = align_to(data.Ground_Speed,        ref) / 3.6;
            steerMask = abs(align_to(data.Steering_Angle,  ref)) < 0.5;
            radius    = carSpeed.^2 ./ (lat * gravity);
            radius(steerMask)       = NaN;
            radius(abs(lat) < 0.05) = NaN;
            requiredSteer = max(min(wheelBase ./ radius + K .* lat, 1), -1);
            requiredSteer(steerMask) = 0;
            data.Steer_Required_VCH = make_channel(requiredSteer, ref, 'rad', 'Steer Required VCH');
            data.Steer_Required_VCH.datatype = 2;  data.Steer_Required_VCH.dec_places = 4;
            data.Steer_Required_VCH.offset   = 0;  data.Steer_Required_VCH.mul = 1;  data.Steer_Required_VCH.scale = 1;
            fprintf('  [+] Steer_Required_VCH\n');
            data.Radius_Instant_VCH = make_channel(radius, ref, 'm', 'Radius Instant VCH');
            data.Radius_Instant_VCH.datatype = 2;  data.Radius_Instant_VCH.dec_places = 4;
            data.Radius_Instant_VCH.offset   = 0;  data.Radius_Instant_VCH.mul = 1;  data.Radius_Instant_VCH.scale = 1;
            fprintf('  [+] Radius_Instant_VCH\n');
        end
    catch ME; fprintf('  [!] Steer_Required_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Tyre Squish (kinematic RH minus corrected laser RH)
    % ------------------------------------------------------------------
    try
        fn_kf = find_field(data, 'RH_Kin_Front_VCH');
        fn_kr = find_field(data, 'RH_Kin_Rear_VCH');
        fn_cf = find_field(data, 'RH_Front_Corr_VCH');
        fn_cr = find_field(data, 'RH_Rear_Corr_VCH');
        if ~isempty(fn_kf) && ~isempty(fn_kr) && ~isempty(fn_cf) && ~isempty(fn_cr)
            ref     = pick_ref(data, {fn_kf, fn_kr, fn_cf, fn_cr});
            squishF = align_to(data.(fn_kf), ref) - align_to(data.(fn_cf), ref);
            squishR = align_to(data.(fn_kr), ref) - align_to(data.(fn_cr), ref);
            if isfield(data,'Gate_Straight_VCH')
                sm = align_to(data.Gate_Straight_VCH, ref) == 1;
                squishF(sm) = NaN;  squishR(sm) = NaN;
            end
            data.Tyre_Squish_Front_VCH = make_channel(squishF, ref, 'mm', 'Tyre Squish Front VCH');
            fprintf('  [+] Tyre_Squish_Front_VCH\n');
            data.Tyre_Squish_Rear_VCH  = make_channel(squishR, ref, 'mm', 'Tyre Squish Rear VCH');
            fprintf('  [+] Tyre_Squish_Rear_VCH\n');
        end
    catch ME; fprintf('  [!] Tyre squish failed: %s\n', ME.message); end

    %% ================================================================
    %  TIER 5 — depends on Tier 3 aero maps and/or Tier 4 dynamics
    % =================================================================

    % ------------------------------------------------------------------
    %  Required Steer — MEAS aero correction
    % ------------------------------------------------------------------
    try
        if isfield(data,'Steering_Angle') && isfield(data,'Ground_Speed') && ...
                isfield(data,'Acceleration_Y_Filt') && ...
                isfield(data,'Aero_Balance_Front_VCH_MEAS') && isfield(data,'Aero_CLa_VCH_MEAS') && ...
                ~isempty(manufacturer)
            mfr_key = lower(manufacturer);
            ref     = pick_ref(data, {'Steering_Angle','Ground_Speed','Acceleration_Y_Filt', ...
                                      'Aero_Balance_Front_VCH_MEAS','Aero_CLa_VCH_MEAS'});
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;
            gravity = 9.81;  rho = 1.225;
            weightFrontAxle = 729.8 * gravity;  weightRearAxle = 617.7 * gravity;
            lat       = align_to(data.Acceleration_Y_Filt,           ref);
            carSpeed  = align_to(data.Ground_Speed,                   ref) / 3.6;
            steerMask = abs(align_to(data.Steering_Angle,             ref)) < 0.5;
            CZ        = align_to(data.Aero_CLa_VCH_MEAS,             ref);
            ABFRNT    = align_to(data.Aero_Balance_Front_VCH_MEAS,   ref) / 100;
            radius    = carSpeed.^2 ./ (lat * gravity);
            radius(steerMask) = NaN;  radius(abs(lat) < 0.05) = NaN;
            aeroF = 0.5 .* carSpeed.^2 .* rho .* (ABFRNT       .* CZ);
            aeroR = 0.5 .* carSpeed.^2 .* rho .* ((1 - ABFRNT) .* CZ);
            K = (1/wheelBase) * ( ...
                ((weightFrontAxle + aeroF) ./ corneringStiffnessFront) ./ gravity - ...
                ((weightRearAxle  + aeroR) ./ corneringStiffnessRear)  ./ gravity);
            rs = wheelBase ./ radius + K .* lat;
            rs(steerMask) = 0;
            data.Steer_Required_Aero_VCH = make_channel(rs,    ref, 'rad', 'Steer Required Aero VCH');
            data.Aero_Force_Front_VCH    = make_channel(aeroF, ref, 'N',   'Aero Force Front VCH');
            data.Aero_Force_Rear_VCH     = make_channel(aeroR, ref, 'N',   'Aero Force Rear VCH');
            fprintf('  [+] Steer_Required_Aero_VCH  Aero_Force_Front/Rear_VCH  (MEAS)\n');
        end
    catch ME; fprintf('  [!] Steer_Required_Aero_VCH failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Required Steer — KIN aero correction
    % ------------------------------------------------------------------
    try
        if isfield(data,'Steering_Angle') && isfield(data,'Ground_Speed') && ...
                isfield(data,'Acceleration_Y_Filt') && ...
                isfield(data,'Aero_Balance_Front_VCH_KIN') && isfield(data,'Aero_CLa_VCH_KIN') && ...
                ~isempty(manufacturer)
            mfr_key = lower(manufacturer);
            ref     = pick_ref(data, {'Steering_Angle','Ground_Speed','Acceleration_Y_Filt', ...
                                      'Aero_Balance_Front_VCH_KIN','Aero_CLa_VCH_KIN'});
            corneringStiffnessFront = vehicle.(mfr_key).kinematics.front.tyreCorneringStiffness;
            corneringStiffnessRear  = vehicle.(mfr_key).kinematics.rear.tyreCorneringStiffness;
            wheelBase       = vehicle.(mfr_key).maximumWheelbase / 1000;
            gravity = 9.81;  rho = 1.225;
            weightFrontAxle = 729.8 * gravity;  weightRearAxle = 617.7 * gravity;
            lat       = align_to(data.Acceleration_Y_Filt,          ref);
            carSpeed  = align_to(data.Ground_Speed,                  ref) / 3.6;
            steerMask = abs(align_to(data.Steering_Angle,            ref)) < 0.5;
            CZ        = align_to(data.Aero_CLa_VCH_KIN,             ref);
            ABFRNT    = align_to(data.Aero_Balance_Front_VCH_KIN,   ref) / 100;
            radius    = carSpeed.^2 ./ (lat * gravity);
            radius(steerMask) = NaN;  radius(abs(lat) < 0.05) = NaN;
            aeroF = 0.5 .* carSpeed.^2 .* rho .* (ABFRNT       .* CZ);
            aeroR = 0.5 .* carSpeed.^2 .* rho .* ((1 - ABFRNT) .* CZ);
            K = (1/wheelBase) * ( ...
                ((weightFrontAxle + aeroF) ./ corneringStiffnessFront) ./ gravity - ...
                ((weightRearAxle  + aeroR) ./ corneringStiffnessRear)  ./ gravity);
            rs = wheelBase ./ radius + K .* lat;
            rs(steerMask) = 0;
            data.Steer_Required_Aero_VCH_KIN = make_channel(rs,    ref, 'rad', 'Steer Required Aero VCH KIN');
            data.Aero_Force_Front_VCH_KIN    = make_channel(aeroF, ref, 'N',   'Aero Force Front VCH KIN');
            data.Aero_Force_Rear_VCH_KIN     = make_channel(aeroR, ref, 'N',   'Aero Force Rear VCH KIN');
            fprintf('  [+] Steer_Required_Aero_VCH_KIN  Aero_Force_Front/Rear_VCH_KIN\n');
        end
    catch ME; fprintf('  [!] Steer_Required_Aero_VCH_KIN failed: %s\n', ME.message); end

    % ------------------------------------------------------------------
    %  Tyre Normal Force — KIN aero source
    % ------------------------------------------------------------------
    try
        if isfield(data,'Ground_Speed') && isfield(data,'Aero_CLa_VCH_KIN') && ...
                isfield(data,'Acceleration_X_Filt') && isfield(data,'Acceleration_Y_Filt') && ...
                isfield(data,'Acceleration_Z_Filt') && isfield(data,'Aero_Balance_Front_VCH_KIN') && ...
                ~isempty(manufacturer)
            mfr_key = lower(manufacturer);
            if strcmp(manufacturer,'Ford') || strcmp(manufacturer,'Toyota') || strcmp(manufacturer,'Chevrolet')
                mask = strcmp(patchRH.MAN, manufacturer);
                frontAxleMass = mean(patchRH.FrontAxleMass(mask));
                rearAxleMass  = mean(patchRH.RearAxleMass(mask));
            else
                frontAxleMass = mean(patchRH.FrontAxleMass);
                rearAxleMass  = mean(patchRH.RearAxleMass);
            end
            if isnan(frontAxleMass), frontAxleMass = mean(patchRH.FrontAxleMass(~isnan(patchRH.FrontAxleMass))); end
            if isnan(rearAxleMass),  rearAxleMass  = mean(patchRH.RearAxleMass(~isnan(patchRH.RearAxleMass)));   end
            driverMask = strcmp(patchRH.Driver, driver);
            if any(driverMask)
                dp = patchRH(driverMask, :);
                sm = strcmp(dp.Session, session);
                if any(sm)
                    p2 = dp(sm, :);
                    frontAxleMass = p2.FrontAxleMass(1);
                    rearAxleMass  = p2.RearAxleMass(1);
                end
            end
            try
                wb  = vehicle.(mfr_key).maximumWheelbase / 1000;
                trk = vehicle.(mfr_key).kinematics.body.trackWidth / 1000;
            catch
                wb = 2.75675;  trk = 2.000;
            end
            ref = pick_ref(data, {'Acceleration_X_Filt','Acceleration_Y_Filt','Acceleration_Z_Filt', ...
                                   'Aero_Balance_Front_VCH_KIN','Aero_CLa_VCH_KIN','Ground_Speed'});
            IMU_X  = align_to(data.Acceleration_X_Filt,           ref);
            IMU_Y  = align_to(data.Acceleration_Y_Filt,           ref);
            IMU_Z  = align_to(data.Acceleration_Z_Filt,           ref);
            AB     = align_to(data.Aero_Balance_Front_VCH_KIN,    ref) / 100;
            CLz    = align_to(data.Aero_CLa_VCH_KIN,              ref);
            spd    = align_to(data.Ground_Speed,                   ref) / 3.6;
            IMU_Z  = IMU_Z - mean(IMU_Z);
            g      = 9.81;  rho = 1.225;
            Xa = IMU_X * g;  Ya = IMU_Y * g;
            totalMass = (frontAxleMass + rearAxleMass) .* (1 + IMU_Z);
            ltLF =  totalMass .* (-Xa) .* 0.284 ./ wb;
            ltLR =  totalMass .*   Xa  .* 0.284 ./ wb;
            aF   = 0.5 .* spd.^2 .* rho .* (AB          .* CLz);
            aR   = 0.5 .* spd.^2 .* rho .* (min(1-AB,1) .* CLz);
            ltTF = totalMass .* (-Ya) .* 0.284 ./ trk;
            ltTR = totalMass .* (-Ya) .* 0.284 ./ trk;
            FL = (ltLF/2 - aF/2 - ltTF/2) + (frontAxleMass/2) * g;
            FR = (ltLF/2 - aF/2 + ltTF/2) + (frontAxleMass/2) * g;
            RL = (ltLR/2 - aR/2 - ltTR/2) + (rearAxleMass/2)  * g;
            RR = (ltLR/2 - aR/2 + ltTR/2) + (rearAxleMass/2)  * g;
            data.Normal_Force_FL_VCH_KIN    = make_channel(FL,   ref, 'N', 'Normal Force FL VCH KIN',    'overwrite', true);
            data.Normal_Force_FR_VCH_KIN    = make_channel(FR,   ref, 'N', 'Normal Force FR VCH KIN',    'overwrite', true);
            data.Normal_Force_RL_VCH_KIN    = make_channel(RL,   ref, 'N', 'Normal Force RL VCH KIN',    'overwrite', true);
            data.Normal_Force_RR_VCH_KIN    = make_channel(RR,   ref, 'N', 'Normal Force RR VCH KIN',    'overwrite', true);
            data.Load_Transfer_Long_VCH_KIN = make_channel(ltLF, ref, 'N', 'Load Transfer Long VCH KIN', 'overwrite', true);
            data.Load_Transfer_Lat_VCH_KIN  = make_channel(ltTF, ref, 'N', 'Load Transfer Lat VCH KIN',  'overwrite', true);
            fprintf('  [+] Normal_Force_FL/FR/RL/RR_VCH_KIN  Load_Transfer_Long/Lat_VCH_KIN\n');
            data.Damper_Force_FL_VCH_KIN = make_channel(FL ./ 0.788, ref, 'N', 'Damper Force FL VCH KIN', 'overwrite', true);
            data.Damper_Force_FR_VCH_KIN = make_channel(FR ./ 0.788, ref, 'N', 'Damper Force FR VCH KIN', 'overwrite', true);
            data.Damper_Force_RL_VCH_KIN = make_channel(RL ./ 0.788, ref, 'N', 'Damper Force RL VCH KIN', 'overwrite', true);
            data.Damper_Force_RR_VCH_KIN = make_channel(RR ./ 0.788, ref, 'N', 'Damper Force RR VCH KIN', 'overwrite', true);
            fprintf('  [+] Damper_Force_FL/FR/RL/RR_VCH_KIN\n');
        end
    catch ME; fprintf('  [!] Normal Force KIN failed: %s\n', ME.message); end

end

% ======================================================================
%  LOCAL FUNCTIONS
% ======================================================================

function ref = pick_ref(data, names)
% Returns the channel with the highest sample_rate from the named list.
    names = names(isfield(data, names));
    if isempty(names), ref = []; return; end
    rates = cellfun(@(n) data.(n).sample_rate, names);
    [~, i] = max(rates);
    ref = data.(names{i});
end

function ch = make_channel(values, reference_ch, units, name, varargin)
% Build a channel struct matching motec_ld_reader output format.
p = inputParser();
addRequired(p, 'values');
addRequired(p, 'reference_ch');
addRequired(p, 'units');
addRequired(p, 'name');
addParameter(p, 'overwrite', true);
addParameter(p, 'templateChannel', []);
addParameter(p, 'mul', []);
addParameter(p, 'scale', []);
addParameter(p, 'offset', []);
addParameter(p, 'dec_places', []);
parse(p, values, reference_ch, units, name, varargin{:});
tmpl = p.Results.templateChannel;
n = numel(values);
ch.data        = values(:);
ch.units       = units;
ch.raw_name    = name;
ch.write_to_ld = true;
ch.overwrite   = p.Results.overwrite;
if ~isempty(p.Results.dec_places)
    ch.dec_places = p.Results.dec_places;
elseif ~isempty(tmpl) && isfield(tmpl, 'dec_places')
    ch.dec_places = tmpl.dec_places;
else
    ch.dec_places = auto_dec_places(values);
end
if ~isempty(p.Results.mul)
    ch.mul = p.Results.mul;
elseif ~isempty(tmpl) && isfield(tmpl, 'mul')
    ch.mul = tmpl.mul;
else
    ch.mul = 1;
end
if ~isempty(p.Results.scale)
    ch.scale = p.Results.scale;
elseif ~isempty(tmpl) && isfield(tmpl, 'scale')
    ch.scale = tmpl.scale;
else
    ch.scale = 1;
end
if ~isempty(p.Results.offset)
    ch.offset = p.Results.offset;
elseif ~isempty(tmpl) && isfield(tmpl, 'offset')
    ch.offset = tmpl.offset;
else
    vals = values(isfinite(values));
    if ~isempty(vals) && min(vals) < 0
        ch.offset = floor(min(vals)) - 1;
    else
        ch.offset = 0;
    end
end
if n == numel(reference_ch.time)
    ch.time        = reference_ch.time;
    ch.sample_rate = reference_ch.sample_rate;
else
    t_start        = reference_ch.time(1);
    t_end          = reference_ch.time(end);
    ch.time        = linspace(t_start, t_end, n)';
    ch.sample_rate = round(n / (t_end - t_start));
end
end

function dec = auto_dec_places(values)
% Highest dec in {4..0} where data_range * 10^dec <= 32767 (int16 limit).
    finite_vals = values(isfinite(values));
    if isempty(finite_vals), dec = 2; return; end
    data_range = max(finite_vals) - min(finite_vals);
    if data_range == 0, dec = 2; return; end
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
% Estimate loaded tyre radius from inflation pressure, car speed, and axle.
    tyreStiffness = 0.00318062275116337;
    wheelRadius   = 0.332633831;
    frontCoef = [-0.0125, -0.196832152];
    rearCoef  = [-0.0010, -0.745339228];
    pTyre = align_to(pTyre, vCar);
    k            = 0.0005 .* (pTyre < 20) + 0.001 .* (pTyre >= 20);
    pressureComp = 33.99 - (33.99 - 31.5) .* exp(-k .* (pTyre - 27));
    switch lower(axle)
        case 'front', coef = frontCoef; addition = 9;
        case 'rear',  coef = rearCoef;  addition = 7;
        otherwise,    error('tyreRadiusV1: axle must be ''front'' or ''rear''');
    end
    vMs = vCar.data ./ 3.6;
    Cz  = coef(1) .* vMs + coef(2);
    Fz  = (0.5 .* vMs.^2 .* Cz ./ 2) .* tyreStiffness;
    Rf  = 0.0071 .* (vMs ./ wheelRadius) .* 60 ./ (2 .* pi);
    tyreRadius = (pressureComp + Fz + Rf) * 10 + addition;
    wheelSpeed = (tyreRadius / 1000) .* (vMs ./ wheelRadius) * 3.6;
end

function fname = find_field(data, keyword)
% Returns first field name containing keyword (case-insensitive). Returns '' if none.
    fields = fieldnames(data);
    idx    = find(contains(fields, keyword, 'IgnoreCase', true), 1);
    if isempty(idx), fname = ''; else, fname = fields{idx}; end
end
function m = hyst(x, on, off, dir)
m = false(size(x)); st = false;
for i = 1:numel(x)
    if strcmp(dir,'above')
        if ~st && x(i) >= on, st = true; elseif st && x(i) < off, st = false; end
    else
        if ~st && x(i) <= on, st = true; elseif st && x(i) > off, st = false; end
    end
    m(i) = st;
end
end

function m = clean_runs(m, gapN, minN)
m = m(:);
d = diff([0; m; 0]); s = find(d==1); e = find(d==-1)-1;
for k = 1:numel(s)-1
    if s(k+1)-e(k)-1 <= gapN, m(e(k):s(k+1)) = true; end
end
d = diff([0; m; 0]); s = find(d==1); e = find(d==-1)-1;
for k = 1:numel(s)
    if e(k)-s(k)+1 < minN, m(s(k):e(k)) = false; end
end
end