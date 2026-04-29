

% --- Configuration ---------------------------------------
excel_file = 'C:\SimEnv\vehicleModel\components\aerodynamics\PARITY_AERO_MAPS.xlsx';
road_spd   = 55.5;

% Raw channel names — used for filter definitions and sgn() only
ch_frh_raw = 'Laser Ride Height Front';
ch_rrh_raw = 'Laser Ride Height Rear';
ch_yaw_raw = 'YawPitot Yaw Angle';
ch_roll    = 'Roll';

% Filtered channel names — used in all polynomial expressions
ch_frh = 'Laser Ride Height Front_filt';
ch_rrh = 'Laser Ride Height Rear_filt';
ch_yaw = 'YawPitot Yaw Angle_filt';

% Filter cutoff frequencies (Hz)
filt_FRH = 10;
filt_RRH = 10;
filt_YAW = 2;

% Manufacturer config: { sheet, file, prefix, vehicle id, colour index, degree }
mfr_config = {
    'GM',     'Performance_GM.xml',   'GM',   'GEN3 Camaro',   0, 3;
    'FORD',   'Performance_FORD.xml', 'FORD', 'GEN3 Ford',     2, 3;
    'TOYOTA', 'Performance_TOY.xml',  'TOY',  'GEN3 Toyota',   1, 3;
};

% MoTeC colour index mapping
% 0 = orange (GM), 1 = red (Toyota), 2 = blue (Ford)
motec_colours = containers.Map({0,1,2}, {[0.93 0.53 0.07], [0.85 0.11 0.11], [0.07 0.33 0.80]});

output_names = {'Cz','Cx','CzF','CzR', ...
                'ABf','EFF','Cy','CyF','CyR'};

% Plot channels — roll and simple rows
plot_idx    = [1, 3, 4, 5];
plot_labels = {'Cz (total)','CzF (front)','CzR (rear)','ABf (balance)'};

% Plot channels — yaw row
plot_idx_yaw    = [7, 8, 9, 5];
plot_labels_yaw = {'Cy (total)','CyF (front)','CyR (rear)','ABf (balance)'};

% Number of yaw terms — fixed at 19 (yaw-only terms, no intercept)
n_yaw = 19;

% --- Storage for comparison plots ------------------------
store = struct();

% --- Fit quality header ----------------------------------
fprintf('\n=========================================================\n');
fprintf(' FIT QUALITY SUMMARY\n');
fprintf('%-6s  %-6s  %-12s   R²        RMSE\n', 'Mfr', 'Type', 'Output');
fprintf('---------------------------------------------------------\n');

% --- Loop manufacturers ----------------------------------
for m = 1:size(mfr_config, 1)

    sheet      = mfr_config{m, 1};
    out_file   = mfr_config{m, 2};
    prefix     = mfr_config{m, 3};
    vehicle_id = mfr_config{m, 4};
    col_idx    = mfr_config{m, 5};
    degree     = mfr_config{m, 6};

    % Number of terms per fit type
    if degree == 2
        n_roll   = 10;
        n_simple = 6;
    else
        n_roll   = 20;
        n_simple = 10;
    end

    terms_roll   = arrayfun(@(x) sprintf('b%d',x), 1:n_roll,   'UniformOutput', false);
    terms_simple = arrayfun(@(x) sprintf('b%d',x), 1:n_simple, 'UniformOutput', false);
    terms_yaw    = arrayfun(@(x) sprintf('b%d',x), 1:n_yaw,    'UniformOutput', false);

    % --- Load and filter ---------------------------------
    raw    = readtable(excel_file, 'Sheet', sheet);
    d      = raw(raw.road_spd == road_spd, :);

    % Roll fit dataset — negative roll only, abs(roll) as input
    d_roll = d(d.roll_deg <= 0, :);

    % Simplified dataset — zero roll and zero yaw only
    d0     = d(d.roll_deg == 0 & d.yaw_deg == 0, :);

    % Yaw fit dataset — positive yaw > 1 only (signed input)
    d_yaw  = d(d.yaw_deg > 1, :);

    % --- Inputs — roll fit -------------------------------
    FRH  = d_roll.FRH_mm;
    RRH  = d_roll.RRH_mm;
    Roll = abs(d_roll.roll_deg);

    % --- Inputs — simplified fit -------------------------
    FRH0 = d0.FRH_mm;
    RRH0 = d0.RRH_mm;

    % --- Inputs — yaw fit (signed yaw) -------------------
    FRH_y = d_yaw.FRH_mm;
    RRH_y = d_yaw.RRH_mm;
    Yaw_y = d_yaw.yaw_deg;   % signed — no abs()

    % --- Outputs — roll fit dataset ----------------------
    Cz  = d_roll.CLf_SCzF + d_roll.CLr_SCzR;
    Cx  = d_roll.CDa_SCx;
    CzF = d_roll.CLf_SCzF;
    CzR = d_roll.CLr_SCzR;
    ABf = d_roll.AB_FRT;
    EFF = d_roll.EFF;
    Cy  = d_roll.CSa_Scy;
    CyF = d_roll.CSf_SCyF;
    CyR = d_roll.CSr_SCyR;

    outputs_roll = {Cz, Cx, CzF, CzR, ABf, EFF, Cy, CyF, CyR};

    % --- Outputs — simplified dataset --------------------
    Cz0  = d0.CLf_SCzF + d0.CLr_SCzR;
    Cx0  = d0.CDa_SCx;
    CzF0 = d0.CLf_SCzF;
    CzR0 = d0.CLr_SCzR;
    ABf0 = d0.AB_FRT;
    EFF0 = d0.EFF;
    Cy0  = d0.CSa_Scy;
    CyF0 = d0.CSf_SCyF;
    CyR0 = d0.CSr_SCyR;

    outputs_simple = {Cz0, Cx0, CzF0, CzR0, ABf0, EFF0, Cy0, CyF0, CyR0};

    % --- Outputs — yaw fit dataset -----------------------
    Cz_y  = d_yaw.CLf_SCzF + d_yaw.CLr_SCzR;
    Cx_y  = d_yaw.CDa_SCx;
    CzF_y = d_yaw.CLf_SCzF;
    CzR_y = d_yaw.CLr_SCzR;
    ABf_y = d_yaw.AB_FRT;
    EFF_y = d_yaw.EFF;
    Cy_y  = d_yaw.CSa_Scy;
    CyF_y = d_yaw.CSf_SCyF;
    CyR_y = d_yaw.CSr_SCyR;

    outputs_yaw = {Cz_y, Cx_y, CzF_y, CzR_y, ABf_y, EFF_y, Cy_y, CyF_y, CyR_y};

    % --- Design matrices ---------------------------------
    X_roll   = build_design_matrix(FRH,   RRH,   Roll,  degree);
    X_simple = build_design_matrix(FRH0,  RRH0,  [],    degree);
    X_yaw    = build_design_matrix_yaw(FRH_y, RRH_y, Yaw_y);

    % --- Storage -----------------------------------------
    beta_roll   = zeros(n_roll,   length(output_names));
    beta_simple = zeros(n_simple, length(output_names));
    beta_yaw    = zeros(n_yaw,    length(output_names));
    R2_roll     = zeros(1, length(output_names));
    R2_simple   = zeros(1, length(output_names));
    R2_yaw      = zeros(1, length(output_names));

    % --- Fit each output ---------------------------------
    for i = 1:length(output_names)

        % Full fit with |roll|
        y = outputs_roll{i};
        b = X_roll \ y;
        beta_roll(:, i) = b;
        res = y - X_roll * b;
        R2_roll(i) = 1 - sum(res.^2) / sum((y - mean(y)).^2);
        fprintf('%-6s  roll    %-12s   %.6f  %.6f\n', ...
            prefix, output_names{i}, R2_roll(i), sqrt(mean(res.^2)));

        % Simplified fit
        y = outputs_simple{i};
        b = X_simple \ y;
        beta_simple(:, i) = b;
        res = y - X_simple * b;
        R2_simple(i) = 1 - sum(res.^2) / sum((y - mean(y)).^2);
        fprintf('%-6s  base    %-12s   %.6f  %.6f\n', ...
            prefix, output_names{i}, R2_simple(i), sqrt(mean(res.^2)));

        % Yaw fit — degree 3, yaw-only terms, signed yaw
        y = outputs_yaw{i};
        b = X_yaw \ y;
        beta_yaw(:, i) = b;
        res = y - X_yaw * b;
        R2_yaw(i) = 1 - sum(res.^2) / sum((y - mean(y)).^2);
        fprintf('%-6s  yaw     %-12s   %.6f  %.6f\n', ...
            prefix, output_names{i}, R2_yaw(i), sqrt(mean(res.^2)));

    end

    % --- Store for plots ---------------------------------
    store(m).prefix         = prefix;
    store(m).col_idx        = col_idx;
    store(m).colour         = motec_colours(col_idx);
    store(m).vehicle_id     = vehicle_id;
    store(m).degree         = degree;
    store(m).n_roll         = n_roll;
    store(m).n_simple       = n_simple;
    store(m).n_yaw          = n_yaw;
    store(m).X_roll         = X_roll;
    store(m).X_simple       = X_simple;
    store(m).X_yaw          = X_yaw;
    store(m).beta_roll      = beta_roll;
    store(m).beta_simple    = beta_simple;
    store(m).beta_yaw       = beta_yaw;
    store(m).outputs_roll   = outputs_roll;
    store(m).outputs_simple = outputs_simple;
    store(m).outputs_yaw    = outputs_yaw;
    store(m).R2_roll        = R2_roll;
    store(m).R2_simple      = R2_simple;
    store(m).R2_yaw         = R2_yaw;

    % --- Write XML file ----------------------------------
    fid = fopen(out_file, 'w');

    fprintf(fid, '<?xml version="1.0"?>\n');
    fprintf(fid, '<Maths Locale="English_Australia.1252" DefaultLocale="C" Id="%s" Condition="''Vehicle Id'' == &quot;%s&quot;">\n\n', ...
        strrep(out_file, '.xml', ''), vehicle_id);

    % --- Constants block ---------------------------------
    fprintf(fid, ' <MathConstants>\n\n');

    % Filter cutoff constants
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- Filter cutoff frequencies                -->\n');
    fprintf(fid, '  <!-- ======================================== -->\n\n');
    fprintf(fid, '  <MathConstant Name="filt_FRH" Value="%.1f" Unit="Hz"/>\n',   filt_FRH);
    fprintf(fid, '  <MathConstant Name="filt_RRH" Value="%.1f" Unit="Hz"/>\n',   filt_RRH);
    fprintf(fid, '  <MathConstant Name="filt_YAW" Value="%.1f" Unit="Hz"/>\n\n', filt_YAW);

    % Roll constants
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — roll fit (degree %d)                 -->\n', prefix, degree);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        fprintf(fid, '  <!-- %s_%s_roll -->\n', prefix, output_names{i});
        for j = 1:n_roll
            fprintf(fid, '  <MathConstant Name="%s_%s_roll_%s" Value="%.8f" Unit=""/>\n', ...
                prefix, output_names{i}, terms_roll{j}, beta_roll(j,i));
        end
        fprintf(fid, '\n');
    end

    % Simple constants
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — simplified fit no roll (degree %d)   -->\n', prefix, degree);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        fprintf(fid, '  <!-- %s_%s -->\n', prefix, output_names{i});
        for j = 1:n_simple
            fprintf(fid, '  <MathConstant Name="%s_%s_%s" Value="%.8f" Unit=""/>\n', ...
                prefix, output_names{i}, terms_simple{j}, beta_simple(j,i));
        end
        fprintf(fid, '\n');
    end

    % Yaw constants
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — yaw fit (degree 3, 19 terms)         -->\n', prefix);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        fprintf(fid, '  <!-- %s_%s_yaw -->\n', prefix, output_names{i});
        for j = 1:n_yaw
            fprintf(fid, '  <MathConstant Name="%s_%s_yaw_%s" Value="%.8f" Unit=""/>\n', ...
                prefix, output_names{i}, terms_yaw{j}, beta_yaw(j,i));
        end
        fprintf(fid, '\n');
    end

    fprintf(fid, ' </MathConstants>\n\n');

    % --- Expressions block -------------------------------
    fprintf(fid, ' <MathExpressions>\n\n');

    % Roll channel definition
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- Roll channel definition                  -->\n');
    fprintf(fid, '  <!-- ======================================== -->\n\n');
    fprintf(fid, '  <MathExpression Id="Roll" DisplayUnit="deg" DisplayDPS="2" DisplayColorIndex="%d" Interpolate="1" Script="(atan2(''C1_Damper Pos FL'' [mm] -''C1_Damper Pos FR'' [mm], 1600) + atan2(''C1_Damper Pos RL'' [mm] -''C1_Damper Pos RR'' [mm], 1600)) /2" SampleRate="0" Unit="rad"/>\n\n', col_idx);

    % Filtered input channel definitions
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- Filtered input channels                  -->\n');
    fprintf(fid, '  <!-- ======================================== -->\n\n');
    fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="2" DisplayColorIndex="%d" Interpolate="1" Script="filter_lp(''%s'' [mm], ''filt_FRH'' [])" SampleRate="0" Unit="mm"/>\n\n', ...
        ch_frh, col_idx, ch_frh_raw);
    fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="2" DisplayColorIndex="%d" Interpolate="1" Script="filter_lp(''%s'' [mm], ''filt_RRH'' [])" SampleRate="0" Unit="mm"/>\n\n', ...
        ch_rrh, col_idx, ch_rrh_raw);
    fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="2" DisplayColorIndex="%d" Interpolate="1" Script="abs(filter_lp(''%s'' [deg], ''filt_YAW'' []))" SampleRate="0" Unit="deg"/>\n\n', ...
        ch_yaw, col_idx, ch_yaw_raw);

    % Roll expressions
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — roll fit (degree %d)                 -->\n', prefix, degree);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        n = sprintf('%s_%s_roll', prefix, output_names{i});
        fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="4" DisplayColorIndex="%d" Interpolate="1" Script="\n', n, col_idx);
        write_roll_expression(fid, n, ch_frh, ch_rrh, ch_roll, degree);
        fprintf(fid, '  " SampleRate="0" Unit=""/>\n\n');
    end

    % Simple expressions
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — simplified fit no roll (degree %d)   -->\n', prefix, degree);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        n = sprintf('%s_%s', prefix, output_names{i});
        fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="4" DisplayColorIndex="%d" Interpolate="1" Script="\n', n, col_idx);
        write_simple_expression(fid, n, ch_frh, ch_rrh, degree);
        fprintf(fid, '  " SampleRate="0" Unit=""/>\n\n');
    end

    % Yaw expressions
    fprintf(fid, '  <!-- ======================================== -->\n');
    fprintf(fid, '  <!-- %s — yaw fit (degree 3, Cy=0 at yaw=0)    -->\n', prefix);
    fprintf(fid, '  <!-- ======================================== -->\n\n');

    for i = 1:length(output_names)
        n = sprintf('%s_%s_yaw', prefix, output_names{i});
        fprintf(fid, '  <MathExpression Id="%s" DisplayDPS="4" DisplayColorIndex="%d" Interpolate="1" Script="\n', n, col_idx);
        write_yaw_expression(fid, n, ch_frh, ch_rrh, ch_yaw, ch_yaw_raw);
        fprintf(fid, '  " SampleRate="0" Unit=""/>\n\n');
    end

    fprintf(fid, ' </MathExpressions>\n\n');
    fprintf(fid, '</Maths>\n');

    fclose(fid);
    fprintf('\n Output written to: %s (roll degree %d, yaw degree 3)\n', out_file, degree);

end

% =========================================================
% FIT COMPARISON PLOTS — one figure per manufacturer
% =========================================================

for m = 1:size(mfr_config, 1)

    c      = store(m).colour;
    prefix = store(m).prefix;
    vid    = store(m).vehicle_id;
    deg    = store(m).degree;

    figure('Name', sprintf('Fit Comparison — %s', prefix), ...
           'Position', [100 + (m-1)*60, 100 + (m-1)*60, 1400, 900]);

    sgtitle(sprintf('Aeromap Fit Comparison — %s (%s)', prefix, vid), ...
            'FontSize', 14, 'FontWeight', 'bold');

    for p = 1:length(plot_idx)

        % --- Roll fit subplot ----------------------------
        subplot(3, length(plot_idx), p);
        hold on; grid on; box on;
        y_actual = store(m).outputs_roll{plot_idx(p)};
        y_fit    = store(m).X_roll * store(m).beta_roll(:, plot_idx(p));
        R2       = store(m).R2_roll(plot_idx(p));
        scatter(y_actual, y_fit, 35, c, 'filled', 'MarkerFaceAlpha', 0.75);
        lims = [min([y_actual; y_fit]), max([y_actual; y_fit])];
        plot(lims, lims, 'k--', 'LineWidth', 1.0);
        title(sprintf('%s — with |roll| (deg %d)\nR² = %.4f', plot_labels{p}, deg, R2), 'FontSize', 9);
        xlabel('Actual'); ylabel('Poly fit');

        % --- Simple fit subplot --------------------------
        subplot(3, length(plot_idx), p + length(plot_idx));
        hold on; grid on; box on;
        y_actual = store(m).outputs_simple{plot_idx(p)};
        y_fit    = store(m).X_simple * store(m).beta_simple(:, plot_idx(p));
        R2       = store(m).R2_simple(plot_idx(p));
        scatter(y_actual, y_fit, 35, c, 'filled', 'MarkerFaceAlpha', 0.75);
        lims = [min([y_actual; y_fit]), max([y_actual; y_fit])];
        plot(lims, lims, 'k--', 'LineWidth', 1.0);
        title(sprintf('%s — no roll (deg %d)\nR² = %.4f', plot_labels{p}, deg, R2), 'FontSize', 9);
        xlabel('Actual'); ylabel('Poly fit');

        % --- Yaw fit subplot — Cy, CyF, CyR, ABf --------
        subplot(3, length(plot_idx), p + 2*length(plot_idx));
        hold on; grid on; box on;
        y_actual = store(m).outputs_yaw{plot_idx_yaw(p)};
        y_fit    = store(m).X_yaw * store(m).beta_yaw(:, plot_idx_yaw(p));
        R2       = store(m).R2_yaw(plot_idx_yaw(p));
        scatter(y_actual, y_fit, 35, c, 'filled', 'MarkerFaceAlpha', 0.75);
        lims = [min([y_actual; y_fit]), max([y_actual; y_fit])];
        plot(lims, lims, 'k--', 'LineWidth', 1.0);
        title(sprintf('%s — with yaw (deg 3)\nR² = %.4f', plot_labels_yaw{p}, R2), 'FontSize', 9);
        xlabel('Actual'); ylabel('Poly fit');

    end
end

fprintf('\n=========================================================\n');
fprintf(' All 3 files written — ready to import into MoTeC i2\n');
fprintf(' Performance_GM.xml   — Vehicle: GEN3 Camaro  (roll deg 2, yaw deg 3)\n');
fprintf(' Performance_FORD.xml — Vehicle: GEN3 Ford    (roll deg 3, yaw deg 3)\n');
fprintf(' Performance_TOY.xml  — Vehicle: GEN3 Toyota  (roll deg 2, yaw deg 3)\n');
fprintf(' Filter cutoffs: FRH = %.0fHz, RRH = %.0fHz, YAW = %.0fHz\n', filt_FRH, filt_RRH, filt_YAW);
fprintf('=========================================================\n');

% =========================================================
% Helper functions
% =========================================================


function X = build_design_matrix(FRH, RRH, Roll, degree)
    if isempty(Roll)
        if degree == 2
            X = [ones(size(FRH)), ...
                 FRH,    RRH, ...
                 FRH.^2, RRH.^2, FRH.*RRH];
        else
            X = [ones(size(FRH)), ...
                 FRH,      RRH, ...
                 FRH.^2,   RRH.^2,   FRH.*RRH, ...
                 FRH.^3,   RRH.^3,   FRH.^2.*RRH, FRH.*RRH.^2];
        end
    else
        if degree == 2
            X = [ones(size(FRH)), ...
                 FRH,       RRH,       Roll, ...
                 FRH.^2,    RRH.^2,    Roll.^2, ...
                 FRH.*RRH,  FRH.*Roll, RRH.*Roll];
        else
            X = [ones(size(FRH)), ...
                 FRH,          RRH,          Roll, ...
                 FRH.^2,       RRH.^2,       Roll.^2, ...
                 FRH.*RRH,     FRH.*Roll,    RRH.*Roll, ...
                 FRH.^3,       RRH.^3,       Roll.^3, ...
                 FRH.^2.*RRH,  FRH.^2.*Roll, RRH.^2.*FRH, ...
                 RRH.^2.*Roll, Roll.^2.*FRH, Roll.^2.*RRH, ...
                 FRH.*RRH.*Roll];
        end
    end
end

function X = build_design_matrix_yaw(FRH, RRH, Yaw)
    % Degree 3 — yaw-only terms — guarantees Cy = 0 at Yaw = 0
    % 19 terms, all containing at least one power of Yaw
    X = [Yaw, ...                                    % b1
         FRH.*Yaw,         RRH.*Yaw,      Yaw.^2, ...% b2 b3 b4
         FRH.^2.*Yaw,      RRH.^2.*Yaw, ...           % b5 b6
         FRH.*RRH.*Yaw,    Yaw.^3, ...                % b7 b8
         FRH.*Yaw.^2,      RRH.*Yaw.^2, ...           % b9 b10
         FRH.^3.*Yaw,      RRH.^3.*Yaw, ...           % b11 b12
         FRH.^2.*RRH.*Yaw, FRH.*RRH.^2.*Yaw, ...     % b13 b14
         FRH.^2.*Yaw.^2,   RRH.^2.*Yaw.^2, ...       % b15 b16
         FRH.*RRH.*Yaw.^2, Yaw.^3.*FRH, ...          % b17 b18
         Yaw.^3.*RRH];                                % b19
end

function write_roll_expression(fid, n, ch_frh, ch_rrh, ch_roll, degree)
    fprintf(fid, '    ''%s_b1'' []\n', n);
    fprintf(fid, '    + ''%s_b2'' [] * ''%s'' [mm]\n',                           n, ch_frh);
    fprintf(fid, '    + ''%s_b3'' [] * ''%s'' [mm]\n',                           n, ch_rrh);
    fprintf(fid, '    + ''%s_b4'' [] * abs(''%s'' [deg])\n',                     n, ch_roll);
    fprintf(fid, '    + ''%s_b5'' [] * ''%s'' [mm] * ''%s'' [mm]\n',             n, ch_frh, ch_frh);
    fprintf(fid, '    + ''%s_b6'' [] * ''%s'' [mm] * ''%s'' [mm]\n',             n, ch_rrh, ch_rrh);
    fprintf(fid, '    + ''%s_b7'' [] * abs(''%s'' [deg]) * abs(''%s'' [deg])\n', n, ch_roll, ch_roll);
    fprintf(fid, '    + ''%s_b8'' [] * ''%s'' [mm] * ''%s'' [mm]\n',             n, ch_frh, ch_rrh);
    fprintf(fid, '    + ''%s_b9'' [] * ''%s'' [mm] * abs(''%s'' [deg])\n',       n, ch_frh, ch_roll);
    fprintf(fid, '    + ''%s_b10'' [] * ''%s'' [mm] * abs(''%s'' [deg])\n',      n, ch_rrh, ch_roll);
    if degree == 3
        fprintf(fid, '    + ''%s_b11'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',                       n, ch_frh, ch_frh, ch_frh);
        fprintf(fid, '    + ''%s_b12'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',                       n, ch_rrh, ch_rrh, ch_rrh);
        fprintf(fid, '    + ''%s_b13'' [] * abs(''%s'' [deg]) * abs(''%s'' [deg]) * abs(''%s'' [deg])\n',     n, ch_roll, ch_roll, ch_roll);
        fprintf(fid, '    + ''%s_b14'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',                       n, ch_frh, ch_frh, ch_rrh);
        fprintf(fid, '    + ''%s_b15'' [] * ''%s'' [mm] * ''%s'' [mm] * abs(''%s'' [deg])\n',                 n, ch_frh, ch_frh, ch_roll);
        fprintf(fid, '    + ''%s_b16'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',                       n, ch_rrh, ch_rrh, ch_frh);
        fprintf(fid, '    + ''%s_b17'' [] * ''%s'' [mm] * ''%s'' [mm] * abs(''%s'' [deg])\n',                 n, ch_rrh, ch_rrh, ch_roll);
        fprintf(fid, '    + ''%s_b18'' [] * abs(''%s'' [deg]) * abs(''%s'' [deg]) * ''%s'' [mm]\n',           n, ch_roll, ch_roll, ch_frh);
        fprintf(fid, '    + ''%s_b19'' [] * abs(''%s'' [deg]) * abs(''%s'' [deg]) * ''%s'' [mm]\n',           n, ch_roll, ch_roll, ch_rrh);
        fprintf(fid, '    + ''%s_b20'' [] * ''%s'' [mm] * ''%s'' [mm] * abs(''%s'' [deg])\n',                 n, ch_frh, ch_rrh, ch_roll);
    end
end

function write_simple_expression(fid, n, ch_frh, ch_rrh, degree)
    fprintf(fid, '    ''%s_b1'' []\n', n);
    fprintf(fid, '    + ''%s_b2'' [] * ''%s'' [mm]\n',               n, ch_frh);
    fprintf(fid, '    + ''%s_b3'' [] * ''%s'' [mm]\n',               n, ch_rrh);
    fprintf(fid, '    + ''%s_b4'' [] * ''%s'' [mm] * ''%s'' [mm]\n', n, ch_frh, ch_frh);
    fprintf(fid, '    + ''%s_b5'' [] * ''%s'' [mm] * ''%s'' [mm]\n', n, ch_rrh, ch_rrh);
    fprintf(fid, '    + ''%s_b6'' [] * ''%s'' [mm] * ''%s'' [mm]\n', n, ch_frh, ch_rrh);
    if degree == 3
        fprintf(fid, '    + ''%s_b7'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',  n, ch_frh, ch_frh, ch_frh);
        fprintf(fid, '    + ''%s_b8'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',  n, ch_rrh, ch_rrh, ch_rrh);
        fprintf(fid, '    + ''%s_b9'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n',  n, ch_frh, ch_frh, ch_rrh);
        fprintf(fid, '    + ''%s_b10'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm]\n', n, ch_frh, ch_rrh, ch_rrh);
    end
end

function write_yaw_expression(fid, n, ch_frh, ch_rrh, ch_yaw, ch_yaw_raw)
    % 19 terms — all contain yaw — Cy = 0 at yaw = 0 by construction
    % sgn() on raw unfiltered yaw for correct sign at zero crossing
    % magnitude driven by abs(filtered) yaw channel
    fprintf(fid, '    sgn(''%s'' [deg]) * (\n', ch_yaw_raw);
    fprintf(fid, '    ''%s_b1'' [] * ''%s'' [deg]\n',                                                    n, ch_yaw);
    fprintf(fid, '    + ''%s_b2'' [] * ''%s'' [mm] * ''%s'' [deg]\n',                                    n, ch_frh, ch_yaw);
    fprintf(fid, '    + ''%s_b3'' [] * ''%s'' [mm] * ''%s'' [deg]\n',                                    n, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b4'' [] * ''%s'' [deg] * ''%s'' [deg]\n',                                   n, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b5'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',                      n, ch_frh, ch_frh, ch_yaw);
    fprintf(fid, '    + ''%s_b6'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',                      n, ch_rrh, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b7'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',                      n, ch_frh, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b8'' [] * ''%s'' [deg] * ''%s'' [deg] * ''%s'' [deg]\n',                    n, ch_yaw, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b9'' [] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg]\n',                     n, ch_frh, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b10'' [] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg]\n',                    n, ch_rrh, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b11'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',       n, ch_frh, ch_frh, ch_frh, ch_yaw);
    fprintf(fid, '    + ''%s_b12'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',       n, ch_rrh, ch_rrh, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b13'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',       n, ch_frh, ch_frh, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b14'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg]\n',       n, ch_frh, ch_rrh, ch_rrh, ch_yaw);
    fprintf(fid, '    + ''%s_b15'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg]\n',      n, ch_frh, ch_frh, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b16'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg]\n',      n, ch_rrh, ch_rrh, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b17'' [] * ''%s'' [mm] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg]\n',      n, ch_frh, ch_rrh, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b18'' [] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg] * ''%s'' [deg]\n',     n, ch_frh, ch_yaw, ch_yaw, ch_yaw);
    fprintf(fid, '    + ''%s_b19'' [] * ''%s'' [mm] * ''%s'' [deg] * ''%s'' [deg] * ''%s'' [deg]\n',     n, ch_rrh, ch_yaw, ch_yaw, ch_yaw);
    fprintf(fid, '    )\n');
end
