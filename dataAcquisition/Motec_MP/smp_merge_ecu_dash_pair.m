function result = smp_merge_ecu_dash_pair(DASH_FILE, ECU_FILE, cfg)
%SMP_MERGE_ECU_DASH_PAIR  Align and merge one Dash+ECU .ld pair.
%
%   result = smp_merge_ecu_dash_pair(DASH_FILE, ECU_FILE)
%   result = smp_merge_ecu_dash_pair(DASH_FILE, ECU_FILE, cfg)
%
%   cfg fields (all optional):
%     .dash_rpm_channel  — RPM channel name in Dash file  (default: 'Engine_Speed')
%     .ecu_rpm_channel   — RPM channel name in ECU file   (default: 'Engine.Speed')
%     .resample_hz       — xcorr grid rate Hz             (default: 100)
%     .max_offset_s      — max plausible ECU-Dash offset  (default: 300)
%     .rpm_min           — min RPM for xcorr masking      (default: 500)
%     .session_meta_file — path to session_metadata.xlsx
%                          (default: <this_dir>/channels/session_metadata.xlsx)
%     .show_ui           — show msgbox + diagnostic figures (default: true)
%
%   result fields:
%     .success       — logical
%     .error_msg     — char, empty on success
%     .offset_s      — detected phase shift (ECU + offset_s = Dash time)
%     .quality_score — xcorr normalised quality 0-1
%     .com_file      — path of written combined .ld (empty on failure)
%     .n_ecu_merged  — ECU channels merged
%     .n_ecu_skipped — ECU channels skipped

    if nargin < 3 || isempty(cfg), cfg = struct(); end
    DASH_RPM_CHANNEL      = cfg_get(cfg, 'dash_rpm_channel',  'Engine_Speed');
    ECU_RPM_CHANNEL       = cfg_get(cfg, 'ecu_rpm_channel',   'Engine.Speed');
    RESAMPLE_HZ           = cfg_get(cfg, 'resample_hz',       100);
    MAX_OFFSET_S          = cfg_get(cfg, 'max_offset_s',      300);
    RPM_MIN               = cfg_get(cfg, 'rpm_min',           500);
    SESSION_METADATA_FILE = cfg_get(cfg, 'session_meta_file', ...
        fullfile(fileparts(mfilename('fullpath')), 'channels', 'session_metadata.xlsx'));
    show_ui               = cfg_get(cfg, 'show_ui', true);

    result = struct('success', false, 'error_msg', '', 'offset_s', NaN, ...
                    'quality_score', NaN, 'com_file', '', ...
                    'n_ecu_merged', 0, 'n_ecu_skipped', 0);
    try

%% =========================================================
%  STEP 1: Read ALL channels from both .ld files
%% =========================================================

        fprintf('=== Reading Dash logger (all channels) ===\n  %s\n', DASH_FILE);
        dash = motec_ld_reader(DASH_FILE);

        fprintf('\n=== Reading ECU logger (all channels) ===\n  %s\n', ECU_FILE);
        ecu  = motec_ld_reader(ECU_FILE, {}, true);   % {} = all channels, true = ECU format

%% =========================================================
%  STEP 2: Extract RPM from both structs
%% =========================================================

        fprintf('\n=== Extracting RPM for alignment ===\n');

        rpm_dash_field = find_field(dash, DASH_RPM_CHANNEL);
        rpm_ecu_field  = find_field(ecu,  ECU_RPM_CHANNEL);

        if isempty(rpm_dash_field)
            error('RPM channel "%s" not found in Dash logger.\nAvailable: %s', ...
                DASH_RPM_CHANNEL, strjoin(fieldnames(dash)', ', '));
        end
        if isempty(rpm_ecu_field)
            error('RPM channel "%s" not found in ECU logger.\nAvailable: %s', ...
                ECU_RPM_CHANNEL, strjoin(fieldnames(ecu)', ', '));
        end

        rpm_dash_t = dash.(rpm_dash_field).time;
        rpm_dash_v = dash.(rpm_dash_field).data;
        rpm_ecu_t  = ecu.(rpm_ecu_field).time;
        rpm_ecu_v  = ecu.(rpm_ecu_field).data;

        fprintf('  Dash RPM: %.0f – %.0fs  (%d samples at %.0fHz)\n', ...
            rpm_dash_t(1), rpm_dash_t(end), numel(rpm_dash_t), dash.(rpm_dash_field).sample_rate);
        fprintf('  ECU  RPM: %.0f – %.0fs  (%d samples at %.0fHz)\n', ...
            rpm_ecu_t(1), rpm_ecu_t(end), numel(rpm_ecu_t), ecu.(rpm_ecu_field).sample_rate);

%% =========================================================
%  STEP 3: Resample both RPM signals to full-signal grids & xcorr
%% =========================================================

        fprintf('\n=== Computing xcorr alignment (%.0f Hz grid) ===\n', RESAMPLE_HZ);

        dt = 1 / RESAMPLE_HZ;

        % Resample each logger on its OWN full time axis.
        % Using the full signal (not the timestamp-overlap window) means xcorr
        % can detect offsets larger than the overlap — e.g. when one logger's
        % timestamps lead the other by hundreds of seconds.
        t_dash_full = (rpm_dash_t(1) : dt : rpm_dash_t(end))';
        t_ecu_full  = (rpm_ecu_t(1)  : dt : rpm_ecu_t(end))';

        rpm_dash_full = interp1(rpm_dash_t, rpm_dash_v, t_dash_full, 'linear', NaN);
        rpm_ecu_full  = interp1(rpm_ecu_t,  rpm_ecu_v,  t_ecu_full,  'linear', NaN);

        fprintf('  Dash signal: %.0f – %.0fs  (%d samples)\n', ...
            t_dash_full(1), t_dash_full(end), numel(t_dash_full));
        fprintf('  ECU  signal: %.0f – %.0fs  (%d samples)\n', ...
            t_ecu_full(1),  t_ecu_full(end),  numel(t_ecu_full));

        % Mask low-RPM and NaN regions independently in each signal.
        valid_dash   = rpm_dash_full >= RPM_MIN & ~isnan(rpm_dash_full);
        valid_ecu    = rpm_ecu_full  >= RPM_MIN & ~isnan(rpm_ecu_full);
        n_valid_dash = sum(valid_dash);
        n_valid_ecu  = sum(valid_ecu);

        fprintf('  Active RPM samples: Dash=%d  ECU=%d  (threshold %.0f RPM)\n', ...
            n_valid_dash, n_valid_ecu, RPM_MIN);

        if n_valid_dash < 200 || n_valid_ecu < 200
            warning(['Low active RPM samples: Dash=%d  ECU=%d  (threshold %d).\n' ...
                     'Alignment may be unreliable — consider lowering RPM_MIN.'], ...
                n_valid_dash, n_valid_ecu, 200);
        end

        % Zero masked regions; mean-centre active regions to remove DC
        rpm_d_xc = rpm_dash_full;
        rpm_e_xc = rpm_ecu_full;
        rpm_d_xc(~valid_dash) = 0;
        rpm_e_xc(~valid_ecu)  = 0;
        if any(valid_dash)
            rpm_d_xc(valid_dash) = rpm_d_xc(valid_dash) - mean(rpm_d_xc(valid_dash));
        end
        if any(valid_ecu)
            rpm_e_xc(valid_ecu) = rpm_e_xc(valid_ecu) - mean(rpm_e_xc(valid_ecu));
        end

        % Cross-correlate full signals.
        % MATLAB xcorr(x,y): c(lag) = sum_n x(n+lag)*y(n)
        % Peak at lag L means Dash is L samples ahead of ECU in timestamp space.
        [xc_vals, lags] = xcorr(rpm_d_xc, rpm_e_xc);
        [~, peak_idx]   = max(xc_vals);
        lag_samples     = lags(peak_idx);

        % Convert lag to offset_s (amount to add to ECU timestamps → Dash timestamps).
        % Derivation: same physical event at Dash index n and ECU index m.
        %   xcorr peak at L: Dash[n+L] ≈ ECU[n]
        %   → rpm_dash_t(1)+(n+L)*dt  =  rpm_ecu_t(1)+n*dt + offset_s
        %   →   offset_s = (rpm_dash_t(1) - rpm_ecu_t(1)) + L*dt
        offset_s = (rpm_dash_t(1) - rpm_ecu_t(1)) + lag_samples * dt;

        % Normalised quality score (0 to 1)
        xc_norm = max(abs(xc_vals));
        xc_self = sqrt(sum(rpm_d_xc.^2) * sum(rpm_e_xc.^2));
        quality_score = 0;
        if xc_self > 0
            quality_score = xc_norm / xc_self;
        end

        fprintf('  Raw offset:  %+.4fs  (lag = %d samples)\n', offset_s, lag_samples);

        % Guard: peak at the edge of xcorr range = negligible real overlap
        max_lag_possible = numel(rpm_d_xc) + numel(rpm_e_xc) - 2;
        if abs(lag_samples) > 0.95 * max_lag_possible
            warning(['Detected lag (%d samples) is at %.0f%% of xcorr range (%d samples).\n' ...
                     'One of the sessions may not overlap the other at all — check file paths.'], ...
                lag_samples, 100*abs(lag_samples)/max_lag_possible, max_lag_possible);
        end

        if abs(offset_s) > MAX_OFFSET_S
            error(['xcorr detected offset %.2fs which exceeds MAX_OFFSET_S (%.0fs).\n' ...
                   'If this offset is plausible, increase MAX_OFFSET_S.\n' ...
                   'If it looks wrong, check that both files are from the same session.'], ...
                offset_s, MAX_OFFSET_S);
        end

        fprintf('  Applied offset: %+.4fs\n', offset_s);
        fprintf('  xcorr quality: %.4f (1.0 = perfect)\n', quality_score);

%% =========================================================
%  STEP 4: Resample ECU channels onto Dash time axis
%% =========================================================

        fprintf('\n=== Merging ECU channels onto Dash time axis ===\n');

        dash_t     = rpm_dash_t;
        merged     = dash;
        ecu_fields = fieldnames(ecu);
        n_merged_ok  = 0;
        n_merged_nan = 0;

        for i = 1:numel(ecu_fields)
            fn  = ecu_fields{i};
            ch  = ecu.(fn);

            ecu_t_shifted    = ch.time + offset_s;
            ecu_data_on_dash = interp1(ecu_t_shifted, ch.data, dash_t, 'linear', NaN);
            n_finite         = sum(isfinite(ecu_data_on_dash));

            if n_finite == 0
                n_merged_nan = n_merged_nan + 1;
                fprintf('  [WARN] ecu_%s: 0 finite samples on Dash time axis — skipping.\n', fn);
                continue;
            end

            out_field                      = ['ecu_' fn];
            merged.(out_field).data        = ecu_data_on_dash;
            merged.(out_field).time        = dash_t;
            merged.(out_field).units       = ch.units;
            merged.(out_field).sample_rate = ch.sample_rate;
            merged.(out_field).raw_name    = ch.raw_name;

            n_merged_ok = n_merged_ok + 1;
            fprintf('  + ecu_%s  [%d/%d finite samples]\n', fn, n_finite, numel(dash_t));
        end

        fprintf('\n  Merged %d ECU channels (%d skipped — no overlap).\n', ...
            n_merged_ok, n_merged_nan);

%% =========================================================
%  STEP 5: Alignment quality popup
%% =========================================================

        % Raw timestamp overlap (informational — not used by xcorr)
        overlap_ts_s = max(0, min(rpm_dash_t(end), rpm_ecu_t(end)) ...
                            - max(rpm_dash_t(1),   rpm_ecu_t(1)));

        % Physical overlap after alignment
        ecu_sh_start    = rpm_ecu_t(1)   + offset_s;
        ecu_sh_end      = rpm_ecu_t(end) + offset_s;
        overlap_after_s = max(0, min(rpm_dash_t(end), ecu_sh_end) ...
                               - max(rpm_dash_t(1),   ecu_sh_start));

        if show_ui
            popup_msg = sprintf([ ...
                'Alignment Quality Report\n' ...
                '──────────────────────────────────\n' ...
                'Phase shift (ECU → Dash):  %+.4f s\n' ...
                'Timestamp overlap (raw):   %.1f s\n' ...
                'Physical overlap (aligned):%.1f s\n' ...
                'Active RPM pts Dash/ECU:   %d / %d\n' ...
                'xcorr quality score:       %.4f / 1.000\n' ...
                '──────────────────────────────────\n' ...
                'ECU channels merged:       %d\n' ...
                'ECU channels skipped:      %d\n'], ...
                offset_s, overlap_ts_s, overlap_after_s, ...
                n_valid_dash, n_valid_ecu, quality_score, n_merged_ok, n_merged_nan);
            msgbox(popup_msg, 'Merge Complete', 'none');
        end

%% =========================================================
%  STEP 6: Diagnostic figure — RPM before and after alignment
%% =========================================================

        if show_ui
            fig = figure('Color', 'white', 'Position', [80 80 1200 600], ...
                         'Name', 'ECU/Dash RPM Alignment');
            sgtitle(fig, sprintf('RPM Alignment  (offset = %+.4fs,  quality = %.4f)', ...
                offset_s, quality_score), 'FontSize', 11, 'FontWeight', 'bold');

            ax1 = subplot(2, 1, 1);
            hold(ax1, 'on'); box(ax1, 'on'); grid(ax1, 'on');
            set(ax1, 'GridAlpha', 0.25, 'GridLineStyle', '--', 'Color', [0.97 0.97 0.97]);
            plot(ax1, rpm_dash_t, rpm_dash_v, 'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Dash');
            plot(ax1, rpm_ecu_t,  rpm_ecu_v,  'Color', [0.84 0.13 0.13], 'LineWidth', 1.0, 'DisplayName', 'ECU (raw)');
            ylabel(ax1, 'Engine RPM', 'Interpreter', 'none');
            title(ax1, 'Before Alignment', 'FontWeight', 'normal');
            legend(ax1, 'Location', 'best', 'Box', 'off');

            ax2 = subplot(2, 1, 2);
            hold(ax2, 'on'); box(ax2, 'on'); grid(ax2, 'on');
            set(ax2, 'GridAlpha', 0.25, 'GridLineStyle', '--', 'Color', [0.97 0.97 0.97]);
            plot(ax2, rpm_dash_t,            rpm_dash_v, 'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Dash');
            plot(ax2, rpm_ecu_t + offset_s,  rpm_ecu_v,  'Color', [0.84 0.13 0.13], 'LineWidth', 1.0, 'DisplayName', 'ECU (shifted)');
            ylabel(ax2, 'Engine RPM', 'Interpreter', 'none');
            xlabel(ax2, 'Time (s)', 'FontSize', 10);
            title(ax2, sprintf('After Alignment  (ECU shifted by %+.4fs)', offset_s), 'FontWeight', 'normal');
            legend(ax2, 'Location', 'best', 'Box', 'off');

            linkaxes([ax1, ax2], 'x');
        end

        fprintf('\n  Dash fields:  %d\n', numel(fieldnames(dash)));
        fprintf('  ECU fields:   %d  (prefixed ecu_)\n', n_merged_ok);
        fprintf('  Total fields: %d\n', numel(fieldnames(merged)));

%% =========================================================
%  STEP 7: Write time-shifted ECU .ld file for MoTeC i2
%% =========================================================

        [ecu_dir, ecu_name, ecu_ext] = fileparts(ECU_FILE);
        ECU_SHIFTED_FILE = fullfile(ecu_dir, [ecu_name '_shifted' ecu_ext]);

        fprintf('\n=== Writing time-shifted ECU file ===\n');
        smp_shift_ld_time(ECU_FILE, ECU_SHIFTED_FILE, offset_s);
        fprintf('  %s\n', ECU_SHIFTED_FILE);

%% =========================================================
%  STEP 9: Write combined .ld (Dash + ECU, prefixed channel names)
%% =========================================================

        % COM folder sits alongside the Dash and ECU folders
        session_root = fileparts(fileparts(DASH_FILE));
        com_dir      = fullfile(session_root, 'COM');

        [~, dash_base, dash_ext] = fileparts(DASH_FILE);
        COM_FILE = fullfile(com_dir, [dash_base '_combined' dash_ext]);

        % Load session metadata (weather + mass) if the xlsx exists
        session_meta = struct();
        if exist(SESSION_METADATA_FILE, 'file')
            fprintf('\n=== Loading session metadata ===\n');
            session_meta = smp_session_metadata_load(SESSION_METADATA_FILE, DASH_FILE);
            meta_fields  = fieldnames(session_meta);
            if isempty(meta_fields)
                fprintf('  [WARN] No session metadata matched — check DASH_FILE path in session_metadata.xlsx\n');
                fprintf('         Looking for: %s\n', DASH_FILE);
            else
                for mf = 1:numel(meta_fields)
                    fn  = meta_fields{mf};
                    sch = session_meta.(fn);
                    fprintf('  %-20s = %.4f %s\n', sch.name, sch.value, sch.units);
                end
            end
        else
            fprintf('\n[INFO] session_metadata.xlsx not found — skipping metadata channels.\n');
        end

        fprintf('\n=== Writing combined .ld file ===\n');
        smp_write_combined_ld(DASH_FILE, merged, COM_FILE);
        fprintf('  %s\n', COM_FILE);

        if ~isempty(fieldnames(session_meta))
            fprintf('\n=== Appending session metadata channels ===\n');

            META_SR      = 5;
            meta_ses_dur = read_session_dur(COM_FILE);
            meta_n       = round(meta_ses_dur * META_SR);
            fprintf('  Session dur from file : %.1f s  →  n = %d @ %d Hz\n', meta_ses_dur, meta_n, META_SR);

            meta_ch_list = {};
            meta_fns = fieldnames(session_meta);
            for mci = 1:numel(meta_fns)
                mfn  = meta_fns{mci};
                msch = session_meta.(mfn);
                mval = double(msch.value);
                mdec = 0;
                for d = 4:-1:0
                    if abs(mval) * 10^d <= 32767
                        mdec = d;
                        break;
                    end
                end
                mc.name        = msch.name;
                mc.short_name  = msch.name(1:min(end,7));
                mc.units       = msch.units;
                mc.value       = repmat(mval, meta_n, 1);
                mc.sample_rate = META_SR;
                mc.dec_places  = mdec;
                mc.offset      = 0;
                mc.mul         = 1;
                mc.scale       = 1;
                meta_ch_list{end+1} = mc; %#ok<AGROW>
                fprintf('  + %-20s = %.*f %s  (n=%d)\n', msch.name, mdec, mval, msch.units, meta_n);
            end
            [com_d, com_b, com_e] = fileparts(COM_FILE);
            meta_tmp = fullfile(com_d, [com_b '_smeta_tmp' com_e]);
            ld_add_channel(COM_FILE, meta_tmp, meta_ch_list);
            movefile(meta_tmp, COM_FILE, 'f');
        end

        % Populate result
        result.success       = true;
        result.offset_s      = offset_s;
        result.quality_score = quality_score;
        result.com_file      = COM_FILE;
        result.n_ecu_merged  = n_merged_ok;
        result.n_ecu_skipped = n_merged_nan;

    catch ME
        result.error_msg = ME.message;
        fprintf('\n[ERROR] %s\n', ME.message);
    end

end

%% =========================================================
%  LOCAL HELPERS
%% =========================================================

function v = cfg_get(s, f, def)
    if isfield(s, f), v = s.(f); else, v = def; end
end

function field = find_field(ch_struct, name)
% Case-insensitive lookup. Also handles spaces -> underscores.
    san    = regexprep(name, '[^a-zA-Z0-9_]', '_');
    san    = regexprep(san, '_+', '_');
    fnames = fieldnames(ch_struct);
    field  = '';
    for k  = 1:numel(fnames)
        if strcmpi(fnames{k}, name) || strcmpi(fnames{k}, san)
            field = fnames{k};
            return;
        end
    end
end

function dur = read_session_dur(filepath)
% Binary walk of .ld channel linked list — return max(n/Hz) over all channels.
    fid = fopen(filepath, 'rb');
    if fid < 0, error('read_session_dur: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid));
    fseek(fid, 0, 'eof');
    fsz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    dur   = 0;
    count = 0;
    while ptr ~= 0 && ptr < fsz
        fseek(fid, ptr, 'bof');
        rec  = fread(fid, 24, 'uint8=>uint8')';
        next = double(typecast(uint8(rec(5:8)),  'uint32'));
        n    = double(typecast(uint8(rec(13:16)), 'uint32'));
        sr   = double(typecast(uint8(rec(23:24)), 'uint16'));
        if sr > 0 && n > 0
            dur = max(dur, n / sr);
        end
        ptr   = next;
        count = count + 1;
        if count > 5000, break; end
    end
end
