function l180_excel = smp_pair_l180(cfg)
%% l180_excel = smp_pair_l180(cfg)
% Match L180 .ld files against existing combined (ECU+TeamData) .ld files,
% validate alignment with RPM xcorr + trim UI + segment UI, merge L180
% channels into a new _combined_l180.ld output, and write an audit Excel.
%
% Workflow:
%   Phase 1  — Scan COM/ for *_combined.ld, scan L180/HOL/{session}/ for L180 files
%   Phase 2  — Filename stem match: L180 stem == Combined stem (TLA match)
%   Phase 3  — xcorr + trim UI + segment UI + immediate merge for each pair
%   Phase 4  — Write audit Excel
%
% Required cfg fields:
%   cfg.td_hol_output_dir — TeamData HOL folder (used to locate COM dir)
%   cfg.l180_hol_dir      — L180 HOL root folder
%   cfg.session           — session label e.g. 'Q19'
%   cfg.quality_min       — normalised xcorr quality threshold (0-1)
%   cfg.com_rpm_ch        — RPM channel name in combined file (e.g. 'ecu_Engine_Speed')
%   cfg.l180_rpm_ch       — RPM channel name in L180 files   (e.g. 'Engine_Speed')
%   cfg.resample_hz       — xcorr grid frequency (Hz)
%   cfg.max_offset_s      — max plausible offset before pair is rejected
%   cfg.rpm_min           — RPM below this is masked
%   cfg.overwrite         — true = reprocess even if _combined_l180.ld exists

l180_excel = '';

% =========================================================================
%  RESOLVE CONFIG
% =========================================================================
L180_HOL_DIR  = cfg.l180_hol_dir;
SESSION       = cfg.session;
QUALITY_MIN   = cfg.quality_min;
COM_RPM       = cfg_get(cfg, 'com_rpm_ch',  'Engine_Speed');
L180_RPM      = cfg_get(cfg, 'l180_rpm_ch', 'Engine_Speed');
RESAMPLE_HZ   = cfg.resample_hz;
MAX_OFFSET_S  = cfg.max_offset_s;
RPM_MIN       = cfg.rpm_min;
OVERWRITE     = isfield(cfg, 'overwrite') && cfg.overwrite;

COM_DIR     = fullfile(fileparts(cfg.td_hol_output_dir), 'COM');
COM_DIR = cfg.com_dir;
L180_DIR    = fullfile(L180_HOL_DIR, SESSION);
OUTPUT_FILE = fullfile(COM_DIR, sprintf('l180_pairs_%s_%s.xlsx', ...
    SESSION, datestr(now, 'yyyymmdd_HHMMSS')));

fprintf('=== smp_pair_l180  [%s] ===\n', SESSION);
fprintf('  COM  : %s\n', COM_DIR);
fprintf('  L180 : %s\n', L180_DIR);
fprintf('  Overwrite: %s\n\n', mat2str(OVERWRITE));

xcorr_cfg.resample_hz  = RESAMPLE_HZ;
xcorr_cfg.max_offset_s = MAX_OFFSET_S;
xcorr_cfg.rpm_min      = RPM_MIN;
xcorr_cfg.a_ecu_format = false;
xcorr_cfg.b_ecu_format = false;

% =========================================================================
%  PHASE 1 — SCAN FOLDERS
% =========================================================================
fprintf('--- Phase 1: Scan folders ---\n');

% Scan COM for *_combined.ld files (not _combined_l180 — those are outputs)
com_map  = build_combined_map(COM_DIR);
l180_map = build_stem_map(L180_DIR);

fprintf('  Combined : %d file(s)\n',   numel(fieldnames(com_map)));
fprintf('  L180     : %d file(s)\n\n', numel(fieldnames(l180_map)));

if isempty(fieldnames(l180_map))
    fprintf('[WARN] No L180 files found in: %s\n', L180_DIR);
    return;
end
if isempty(fieldnames(com_map))
    fprintf('[WARN] No combined files found in: %s\n  Run Phase 4 first.\n', COM_DIR);
    return;
end

% =========================================================================
%  PHASE 2 — FILENAME MATCH
% =========================================================================
fprintf('--- Phase 2: Filename match ---\n');

l180_stems = fieldnames(l180_map);
candidates  = {};
review_rows = {};

for i = 1 : numel(l180_stems)
    stem = l180_stems{i};
    if isfield(com_map, stem)
        candidates(end+1, :) = {com_map.(stem), l180_map.(stem), stem}; %#ok<AGROW>
        fprintf('  Match  : %s\n', stem);
    else
        review_rows(end+1, :) = {l180_map.(stem), 'L180', 'L180_NO_COMBINED', ''}; %#ok<AGROW>
        fprintf('  No combined: %s\n', stem);
    end
end

fprintf('\n  %d candidate pair(s)  |  %d review item(s)\n\n', ...
    size(candidates, 1), size(review_rows, 1));

if isempty(candidates)
    fprintf('[WARN] No matching pairs found — check L180 file naming matches TLA pattern.\n');
    return;
end

% =========================================================================
%  PHASE 3 — xcorr ALIGNMENT + MERGE: Combined vs L180
% =========================================================================
fprintf('--- Phase 3: Combined/L180 xcorr alignment + merge ---\n');

pair_rows    = {};
n_confirmed  = 0;
n_skipped    = 0;
n_xcorr_fail = 0;

for i = 1 : size(candidates, 1)
    com_file  = candidates{i, 1};
    l180_file = candidates{i, 2};
    stem      = candidates{i, 3};

    [~, tla] = extract_tla_session(stem);

    fprintf('  [%d/%d] %s\n', i, size(candidates, 1), stem);
    fprintf('    Combined : %s\n', com_file);
    fprintf('    L180     : %s\n', l180_file);

    % --- Overwrite check ---
    [~, com_base, com_ext] = fileparts(com_file);
    % Remove _combined suffix to get base TLA name, then build output name
    out_base      = regexprep(com_base, '_combined$', '');
    l180_out_file = fullfile(COM_DIR, [out_base '_combined_l180' com_ext]);

    if ~OVERWRITE && exist(l180_out_file, 'file')
        fprintf('    [SKIP] L180 combined file exists, overwrite=false\n');
        fprintf('           %s\n', l180_out_file);
        pair_rows(end+1, :) = {com_file, l180_file, tla, SESSION, ...
            NaN, NaN, l180_out_file, 'EXISTS'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        continue;
    end

    % --- xcorr ---
    [q, off, err_msg, seg_offsets] = xcorr_quality(com_file, l180_file, ...
        COM_RPM, L180_RPM, xcorr_cfg);

    % --- User skipped ---
    if ischar(seg_offsets) && strcmp(seg_offsets, 'SKIP')
        fprintf('    [SKIP] User skipped in segment alignment UI\n');
        review_rows(end+1, :) = {l180_file, 'L180', 'SKIP_USER', ''}; %#ok<AGROW>
        n_skipped = n_skipped + 1;
        continue;
    end

    % --- xcorr error ---
    if ~isempty(err_msg)
        fprintf('    [WARN] xcorr: %s\n', err_msg);
        review_rows(end+1, :) = {l180_file, 'L180', ['XCORR_ERROR: ' err_msg], ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    fprintf('    L180 quality=%.4f  offset=%+.3fs\n', q, off);

    if q < QUALITY_MIN
        review_rows(end+1, :) = {l180_file, 'L180', ...
            sprintf('XCORR_FAIL q=%.4f (min=%.4f)', q, QUALITY_MIN), ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [FAIL] quality %.4f below threshold %.4f\n', q, QUALITY_MIN);
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    % --- Merge ---
    merge_cfg                   = cfg;
    merge_cfg.offset_s          = off;
    merge_cfg.quality_score     = q;
    merge_cfg.seg_offsets       = seg_offsets;
    merge_cfg.show_ui           = false;
    merge_cfg.com_rpm_channel   = COM_RPM;
    merge_cfg.l180_rpm_channel  = L180_RPM;
    merge_cfg.out_file          = l180_out_file;

    fprintf('    -> Merging L180...\n');
    res = smp_merge_l180_pair(com_file, l180_file, merge_cfg);

    if res.success
        pair_rows(end+1, :) = {com_file, l180_file, tla, SESSION, ...
            off, q, res.out_file, 'MERGED'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        fprintf('    -> OK: %s\n', res.out_file);
    else
        review_rows(end+1, :) = {l180_file, 'L180', ...
            ['MERGE_ERROR: ' res.error_msg], sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [MERGE ERROR] %s\n', res.error_msg);
        n_xcorr_fail = n_xcorr_fail + 1;
    end
end

fprintf('\n  Confirmed: %d  |  Skipped: %d  |  Failed: %d\n\n', ...
    n_confirmed, n_skipped, n_xcorr_fail);

% =========================================================================
%  PHASE 4 — WRITE AUDIT EXCEL
% =========================================================================
fprintf('--- Phase 4: Write audit Excel ---\n');

pairs_hdr = {'COMBINED_FILE', 'L180_FILE', 'TLA', 'Session', ...
             'L180_offset_s', 'L180_quality', 'OUT_FILE', 'Status'};

if isempty(pair_rows)
    pairs_xl = [pairs_hdr; cell(0, numel(pairs_hdr))];
else
    pairs_xl = [pairs_hdr; pair_rows];
    for r = 2 : size(pairs_xl, 1)
        for c = 1 : size(pairs_xl, 2)
            if isnumeric(pairs_xl{r,c}) && isnan(pairs_xl{r,c})
                pairs_xl{r,c} = '';
            end
        end
    end
end

review_hdr = {'Filepath', 'Type', 'Reason', 'quality_score'};
if isempty(review_rows)
    review_xl = [review_hdr; cell(0, numel(review_hdr))];
else
    review_xl = [review_hdr; review_rows];
end

% Check output dir writable
if ~isfolder(COM_DIR)
    try
        mkdir(COM_DIR);
    catch me_mkdir
        fprintf('  [ERROR] Cannot create COM dir: %s\n  %s\n', COM_DIR, me_mkdir.message);
        return;
    end
end

if exist(OUTPUT_FILE, 'file')
    fid_test = fopen(OUTPUT_FILE, 'a');
    if fid_test == -1
        fprintf('  [ERROR] Excel file locked: %s\n', OUTPUT_FILE);
        return;
    end
    fclose(fid_test);
end

try
    writecell(pairs_xl,  OUTPUT_FILE, 'Sheet', 'Pairs');
    writecell(review_xl, OUTPUT_FILE, 'Sheet', 'Review');
    fprintf('  Saved: %s\n', OUTPUT_FILE);
catch err_xl
    fprintf('  [ERROR] Could not write Excel: %s\n', err_xl.message);
    return;
end

fprintf('\n=== Done  |  %d confirmed  |  %d skipped  |  %d failed ===\n', ...
    n_confirmed, n_skipped, n_xcorr_fail);

l180_excel = OUTPUT_FILE;

end  % function smp_pair_l180


% =========================================================================
%  smp_merge_l180_pair
% =========================================================================
function result = smp_merge_l180_pair(COM_FILE, L180_FILE, cfg)
%SMP_MERGE_L180_PAIR  Merge L180 channels into an existing combined .ld file.
%
%   Reads all channels from COM_FILE (ECU+TeamData combined) and L180_FILE,
%   resamples L180 channels onto the combined file's time axis using the
%   pre-computed offset and optional per-segment offsets, then writes a new
%   _combined_l180.ld file.
%
%   L180 channels are prefixed 'l180_' in the output.

    if nargin < 3 || isempty(cfg), cfg = struct(); end

    COM_RPM_CHANNEL  = cfg_get(cfg, 'com_rpm_channel',  'Engine_Speed'); %10/7 engine channel changed from ecu to Engine Speed (dash data)
    L180_RPM_CHANNEL = cfg_get(cfg, 'l180_rpm_channel', 'Engine_Speed');
    RESAMPLE_HZ      = cfg_get(cfg, 'resample_hz',      100);
    MAX_OFFSET_S     = cfg_get(cfg, 'max_offset_s',     300);
    RPM_MIN          = cfg_get(cfg, 'rpm_min',          500);
    PRESET_OFFSET_S  = cfg_get(cfg, 'offset_s',         []);
    PRESET_QUALITY   = cfg_get(cfg, 'quality_score',    NaN);
    SEG_OFFSETS      = cfg_get(cfg, 'seg_offsets',      []);
    OUT_FILE         = cfg_get(cfg, 'out_file',         '');
    show_ui          = cfg_get(cfg, 'show_ui',          isempty(PRESET_OFFSET_S));

    result = struct('success', false, 'error_msg', '', 'offset_s', NaN, ...
                    'quality_score', NaN, 'out_file', '', ...
                    'n_l180_merged', 0, 'n_l180_skipped', 0);
    try

%% STEP 1: Read files
        fprintf('=== Reading Combined file (all channels) ===\n  %s\n', COM_FILE);
        com = motec_ld_reader(COM_FILE);

        fprintf('\n=== Reading L180 file (all channels) ===\n  %s\n', L180_FILE);
        l180 = motec_ld_reader(L180_FILE);

%% STEP 2: Extract RPM time axes
        fprintf('\n=== Extracting RPM channels ===\n');

        rpm_com_field  = find_field(com,  COM_RPM_CHANNEL);
        rpm_l180_field = find_field(l180, L180_RPM_CHANNEL);

        if isempty(rpm_com_field)
            error('RPM channel "%s" not found in Combined file.\nAvailable: %s', ...
                COM_RPM_CHANNEL, strjoin(fieldnames(com)', ', '));
        end
        if isempty(rpm_l180_field)
            error('RPM channel "%s" not found in L180 file.\nAvailable: %s', ...
                L180_RPM_CHANNEL, strjoin(fieldnames(l180)', ', '));
        end

        rpm_com_t  = com.(rpm_com_field).time(:);
        rpm_com_v  = double(com.(rpm_com_field).data(:));
        rpm_l180_t = l180.(rpm_l180_field).time(:);
        rpm_l180_v = double(l180.(rpm_l180_field).data(:));

        fprintf('  Combined RPM: %.0f-%.0fs  (%d samples at %.0fHz)\n', ...
            rpm_com_t(1), rpm_com_t(end), numel(rpm_com_t), com.(rpm_com_field).sample_rate);
        fprintf('  L180 RPM    : %.0f-%.0fs  (%d samples at %.0fHz)\n', ...
            rpm_l180_t(1), rpm_l180_t(end), numel(rpm_l180_t), l180.(rpm_l180_field).sample_rate);

%% STEP 3: Determine offset
        if ~isempty(PRESET_OFFSET_S)
            offset_s      = PRESET_OFFSET_S;
            quality_score = PRESET_QUALITY;
            fprintf('\n=== Using pre-computed offset: %+.4fs  (quality=%.4f) ===\n', ...
                offset_s, quality_score);
        else
            fprintf('\n=== Computing xcorr alignment (%.0f Hz grid) ===\n', RESAMPLE_HZ);
            dt           = 1 / RESAMPLE_HZ;
            t_com_full   = (rpm_com_t(1)  : dt : rpm_com_t(end))';
            t_l180_full  = (rpm_l180_t(1) : dt : rpm_l180_t(end))';

            rpm_com_full  = interp1(rpm_com_t,  rpm_com_v,  t_com_full,  'linear', NaN);
            rpm_l180_full = interp1(rpm_l180_t, rpm_l180_v, t_l180_full, 'linear', NaN);

            valid_com  = rpm_com_full  >= RPM_MIN & ~isnan(rpm_com_full);
            valid_l180 = rpm_l180_full >= RPM_MIN & ~isnan(rpm_l180_full);

            fprintf('  Active RPM samples: Combined=%d  L180=%d\n', ...
                sum(valid_com), sum(valid_l180));

            rpm_c_xc = rpm_com_full;  rpm_l_xc = rpm_l180_full;
            rpm_c_xc(~valid_com)  = 0; rpm_l_xc(~valid_l180) = 0;
            rpm_c_xc(valid_com)   = rpm_c_xc(valid_com)  - mean(rpm_c_xc(valid_com));
            rpm_l_xc(valid_l180)  = rpm_l_xc(valid_l180) - mean(rpm_l_xc(valid_l180));

            [xc_vals, lags] = xcorr(rpm_c_xc, rpm_l_xc);
            [~, peak_idx]   = max(xc_vals);
            lag_samples     = lags(peak_idx);
            offset_s        = (rpm_com_t(1) - rpm_l180_t(1)) + lag_samples * dt;

            xc_norm = max(abs(xc_vals));
            xc_self = sqrt(sum(rpm_c_xc.^2) * sum(rpm_l_xc.^2));
            quality_score = 0;
            if xc_self > 0, quality_score = xc_norm / xc_self; end

            fprintf('  Offset: %+.4fs  quality=%.4f\n', offset_s, quality_score);

            if abs(offset_s) > MAX_OFFSET_S
                error('xcorr offset %.2fs exceeds MAX_OFFSET_S (%.0fs).', offset_s, MAX_OFFSET_S);
            end
        end

%% STEP 4: Resample L180 channels onto Combined time axis
        fprintf('\n=== Merging L180 channels onto Combined time axis ===\n');

        com_t        = rpm_com_t;
        merged       = com;
        l180_fields  = fieldnames(l180);
        n_merged_ok  = 0;
        n_merged_nan = 0;

        if ~isempty(SEG_OFFSETS) && isstruct(SEG_OFFSETS)
            offset_vec    = build_offset_vector(com_t, SEG_OFFSETS, offset_s);
            use_segmented = true;
            fprintf('  Segmented offset mode: %d segment(s)\n', numel(SEG_OFFSETS));
            for s = 1:numel(SEG_OFFSETS)
                fprintf('    Seg %d [%.0f-%.0fs]: offset=%+.3fs  quality=%.4f  [%s]\n', ...
                    s, SEG_OFFSETS(s).t_start, SEG_OFFSETS(s).t_end, ...
                    SEG_OFFSETS(s).offset_s, SEG_OFFSETS(s).quality, SEG_OFFSETS(s).status);
            end
        else
            use_segmented = false;
            fprintf('  Global offset mode: %+.4fs\n', offset_s);
        end

        for i = 1:numel(l180_fields)
            fn = l180_fields{i};
            ch = l180.(fn);
            l180_t = ch.time(:);
            l180_v = double(ch.data(:));

            if use_segmented
                l180_data_on_com = interp1(l180_t + offset_s, l180_v, ...
                    com_t - (offset_vec - offset_s), 'linear', NaN);
            else
                l180_data_on_com = interp1(l180_t + offset_s, l180_v, com_t, 'linear', NaN);
            end

            n_finite = sum(isfinite(l180_data_on_com));
            if n_finite == 0
                n_merged_nan = n_merged_nan + 1;
                fprintf('  [SKIP] l180_%s: 0 finite samples\n', fn);
                continue;
            end

            out_field                       = ['l180_' fn];
            merged.(out_field).data        = l180_data_on_com;
            merged.(out_field).time        = com_t;
            merged.(out_field).units       = ch.units;
            merged.(out_field).sample_rate = ch.sample_rate;
            merged.(out_field).raw_name    = ch.raw_name;
            % CRITICAL FIX: Preserve original dec_places from L180 file
            if isfield(ch, 'dec_places')
                merged.(out_field).dec_places = ch.dec_places;
            end
            n_merged_ok = n_merged_ok + 1;
            fprintf('  + l180_%s  [%d/%d finite]\n', fn, n_finite, numel(com_t));
        end

        fprintf('\n  Merged %d L180 channels  (%d skipped)\n', n_merged_ok, n_merged_nan);

%% STEP 5: Diagnostic figure
        if show_ui
            fig = figure('Color', 'white', 'Position', [80 80 1200 600], ...
                'Name', 'L180/Combined RPM Alignment');
            if use_segmented
                title_str = sprintf('L180 Alignment — %d segments  (global=%+.4fs  quality=%.4f)', ...
                    numel(SEG_OFFSETS), offset_s, quality_score);
            else
                title_str = sprintf('L180 Alignment  (offset=%+.4fs  quality=%.4f)', ...
                    offset_s, quality_score);
            end
            sgtitle(fig, title_str, 'FontSize', 11, 'FontWeight', 'bold');

            ax1 = subplot(2,1,1);
            hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');
            plot(ax1, rpm_com_t,  rpm_com_v,  'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Combined (ref)');
            plot(ax1, rpm_l180_t, rpm_l180_v, 'Color', [0.84 0.13 0.13], 'LineWidth', 1.0, 'DisplayName', 'L180 (raw)');
            ylabel(ax1, 'Engine RPM');
            title(ax1, 'Before Alignment', 'FontWeight', 'normal');
            legend(ax1, 'Location', 'best', 'Box', 'off');

            ax2 = subplot(2,1,2);
            hold(ax2,'on'); box(ax2,'on'); grid(ax2,'on');
            plot(ax2, rpm_com_t, rpm_com_v, 'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Combined (ref)');
            if use_segmented
                colours = {[0.84 0.13 0.13],[0.93 0.69 0.13],[0.2 0.7 0.3],[0.5 0.2 0.8],[0.1 0.6 0.8]};
                for s = 1:numel(SEG_OFFSETS)
                    col   = colours{mod(s-1,numel(colours))+1};
                    seg_t = rpm_l180_t + SEG_OFFSETS(s).offset_s;
                    in_w  = seg_t >= SEG_OFFSETS(s).t_start & seg_t <= SEG_OFFSETS(s).t_end;
                    plot(ax2, seg_t(in_w), rpm_l180_v(in_w), 'Color', col, 'LineWidth', 1.0, ...
                        'DisplayName', sprintf('L180 seg%d (%+.2fs)', s, SEG_OFFSETS(s).offset_s));
                end
            else
                plot(ax2, rpm_l180_t + offset_s, rpm_l180_v, 'Color', [0.84 0.13 0.13], ...
                    'LineWidth', 1.0, 'DisplayName', sprintf('L180 (shifted %+.4fs)', offset_s));
            end
            ylabel(ax2, 'Engine RPM'); xlabel(ax2, 'Time (s)');
            title(ax2, 'After Alignment', 'FontWeight', 'normal');
            legend(ax2, 'Location', 'best', 'Box', 'off');
            linkaxes([ax1, ax2], 'x');
        end

%% STEP 6: Write output combined_l180 file
        if isempty(OUT_FILE)
            [com_d, com_b, com_e] = fileparts(COM_FILE);
            out_base = regexprep(com_b, '_combined$', '');
            OUT_FILE = fullfile(com_d, [out_base '_combined_l180' com_e]);
        end

        if ~exist(fileparts(OUT_FILE), 'dir')
            mkdir(fileparts(OUT_FILE));
        end

        fprintf('\n=== Writing combined_l180 file ===\n');
        smp_write_combined_ld(COM_FILE, merged, OUT_FILE);
        fprintf('  %s\n', OUT_FILE);

        fprintf('\n  Combined channels : %d\n', numel(fieldnames(com)));
        fprintf('  L180 merged       : %d\n', n_merged_ok);
        fprintf('  L180 skipped      : %d\n', n_merged_nan);
        fprintf('  Total combined    : %d\n', numel(fieldnames(merged)));

        result.success       = true;
        result.offset_s      = offset_s;
        result.quality_score = quality_score;
        result.out_file      = OUT_FILE;
        result.n_l180_merged  = n_merged_ok;
        result.n_l180_skipped = n_merged_nan;

    catch ME
        result.error_msg = ME.message;
        fprintf('\n[ERROR] %s\n  %s\n', ME.message, ME.getReport('basic'));
    end
end


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function map = build_combined_map(com_dir)
% Scan COM folder for *_combined.ld files (excludes *_combined_l180.ld)
    map = struct();
    if ~isfolder(com_dir), return; end
    listing = dir(fullfile(com_dir, '**', '*_combined.ld'));
    listing = listing(~[listing.isdir]);
    listing = listing(~startsWith({listing.name}, '._'));
    for i = 1:numel(listing)
        [~, fname] = fileparts(listing(i).name);
        % Strip _combined suffix to get the TLA stem
        tla_stem  = regexprep(fname, '_combined$', '');
        safe_stem = matlab.lang.makeValidName(tla_stem);
        map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
    end
end

function map = build_stem_map(folder)
    map = struct();
    if ~isfolder(folder), return; end
    listing_temp = dir(fullfile(folder, '**', '*.ld'));
    listing = listing_temp(~[listing_temp.isdir]);
    listing = listing(~startsWith({listing.name}, '._'));
    listing = listing(~contains({listing.name}, '_shifted'));
    listing = listing(~contains({listing.name}, '_combined'));
    for i = 1:numel(listing)
        [~, stem]  = fileparts(listing(i).name);
        safe_stem  = matlab.lang.makeValidName(stem);
        map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
    end
end

function [tla, session] = extract_tla_session(stem)
    parts = strsplit(stem, '_');
    if numel(parts) >= 1, tla = parts{1}; else, tla = stem; end
    if numel(parts) >= 3, session = strjoin(parts(3:end), '_'); else, session = ''; end
end

function field = find_field(ch_struct, name)
    san    = regexprep(name, '[^a-zA-Z0-9_]', '_');
    san    = regexprep(san,  '_+', '_');
    fnames = fieldnames(ch_struct);
    field  = '';
    for k = 1:numel(fnames)
        if strcmpi(fnames{k}, name) || strcmpi(fnames{k}, san)
            field = fnames{k};
            return;
        end
    end
end

function offset_vec = build_offset_vector(com_t, seg_offsets, global_offset_s)
    offset_vec = repmat(global_offset_s, size(com_t));
    for s = 1:numel(seg_offsets)
        in_seg = com_t >= seg_offsets(s).t_start & com_t <= seg_offsets(s).t_end;
        offset_vec(in_seg) = seg_offsets(s).offset_s;
    end
end

function v = cfg_get(s, f, def)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end

function [quality, offset_s, err_msg, seg_offsets] = xcorr_quality(file_a, file_b, chan_a, chan_b, cfg)
% Compute xcorr-based alignment quality between two .ld files using a
% single named channel from each.
%
% Returns:
%   quality     — normalised xcorr peak 0-1 (0 on failure)
%   offset_s    — time to add to file_b timestamps to align to file_a (NaN on failure)
%   err_msg     — non-empty string if an error occurred
%   seg_offsets — struct array from segment UI, [] if global used, 'SKIP' if user skipped

    debug = false;

    quality     = 0;
    offset_s    = NaN;
    err_msg     = '';
    seg_offsets = [];

    RESAMPLE_HZ        = cfg.resample_hz;
    MAX_OFFSET_S       = cfg.max_offset_s;
    RPM_MIN            = cfg.rpm_min;
    ORPHAN_THRESHOLD_S = 60;

    a_ecu = isfield(cfg, 'a_ecu_format') && isscalar(cfg.a_ecu_format) && logical(cfg.a_ecu_format);
    b_ecu = isfield(cfg, 'b_ecu_format') && isscalar(cfg.b_ecu_format) && logical(cfg.b_ecu_format);

    % ---------------------------------------------------------------
    %  Load Dash (file_a)
    % ---------------------------------------------------------------
    chan_a_candidates = unique({chan_a, 'Engine_Speed'}, 'stable');

    da           = [];
    da_chan_used = '';
    for ci = 1:numel(chan_a_candidates)
        try
            tmp          = motec_ld_reader(file_a, {chan_a_candidates{ci}}, a_ecu);
            target_field = matlab.lang.makeValidName(chan_a_candidates{ci});
            fn_all       = fieldnames(tmp);
            match        = fn_all(strcmpi(fn_all, target_field));
            if isempty(match), continue; end
            candidate = tmp.(match{1});
            if numel(candidate.data) > 1000 && max(candidate.data) > RPM_MIN * 5
                da           = tmp;
                da_chan_used = match{1};
                break;
            end
        catch, end
    end
    if isempty(da)
        err_msg = sprintf('No usable RPM channel found in Dash: %s', file_a);
        return;
    end

    % ---------------------------------------------------------------
    %  Load L180 (file_b)
    % ---------------------------------------------------------------
    % L180 files use underscore channel naming (e.g. 'Engine_Speed'),
    % not dot notation — so 'Engine.Speed' is intentionally excluded.
    chan_b_candidates = unique({chan_b, 'Engine_Speed'}, 'stable');

    db           = [];
    db_chan_used = '';
    for ci = 1:numel(chan_b_candidates)
        try
            tmp          = motec_ld_reader(file_b, {chan_b_candidates{ci}}, b_ecu);
            target_field = matlab.lang.makeValidName(chan_b_candidates{ci});
            fn_all       = fieldnames(tmp);
            match        = fn_all(strcmpi(fn_all, target_field));
            if isempty(match), continue; end
            candidate = tmp.(match{1});
            if numel(candidate.data) > 1000 && max(candidate.data) > RPM_MIN * 5
                db           = tmp;
                db_chan_used = match{1};
                break;
            end
        catch, end
    end
    if isempty(db)
        err_msg = sprintf('No usable RPM channel found in L180: %s', file_b);
        return;
    end

    % ---------------------------------------------------------------
    %  Load ECU uptime for debug diagnostics
    % ---------------------------------------------------------------
    if debug
        ert_candidates = {'Engine_Run_Time', 'ECU_Uptime', 'Engine_Run_Time_'};
        for ci = 1:numel(ert_candidates)
            try
                tmp_ert      = motec_ld_reader(file_b, {ert_candidates{ci}}, b_ecu);
                target_field = matlab.lang.makeValidName(ert_candidates{ci});
                fn_all       = fieldnames(tmp_ert);
                match        = fn_all(strcmpi(fn_all, target_field));
                if ~isempty(match) && numel(tmp_ert.(match{1}).data) > 10
                    fprintf('[DEBUG] ECU uptime channel: %s  (%d samples)\n', ...
                        match{1}, numel(tmp_ert.(match{1}).data));
                    break;
                end
            catch, end
        end
    end

    % ---------------------------------------------------------------
    %  Extract channel structs
    % ---------------------------------------------------------------
    ch_a = da.(da_chan_used);
    ch_b = db.(db_chan_used);

    t_a = ch_a.time(:);
    v_a = double(ch_a.data(:));
    t_b = ch_b.time(:);
    v_b = double(ch_b.data(:));

    if numel(t_a) < 10 || numel(t_b) < 10
        err_msg = 'Insufficient samples for xcorr (< 10)';
        return;
    end

    % ---------------------------------------------------------------
    %  Resample both signals onto uniform grids at RESAMPLE_HZ
    % ---------------------------------------------------------------
    dt       = 1 / RESAMPLE_HZ;
    t_a_full = (t_a(1) : dt : t_a(end))';
    t_b_full = (t_b(1) : dt : t_b(end))';

    v_a_full = interp1(t_a, v_a, t_a_full, 'linear', NaN);
    v_b_full = interp1(t_b, v_b, t_b_full, 'linear', NaN);

    % ---------------------------------------------------------------
    %  Mask low-RPM and NaN regions
    % ---------------------------------------------------------------
    mask_a = v_a_full >= RPM_MIN & ~isnan(v_a_full);
    mask_b = v_b_full >= RPM_MIN & ~isnan(v_b_full);

    if sum(mask_a) < 200 || sum(mask_b) < 200
        err_msg = sprintf('Too few active-RPM samples: A=%d B=%d (need 200)', ...
            sum(mask_a), sum(mask_b));
        if debug
            xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
                mask_a, mask_b, [], [], NaN, 0, err_msg, file_a, file_b, RPM_MIN);
            waitfor(gcf);
        end
        return;
    end

    % ---------------------------------------------------------------
    %  Mean-centre active regions and run initial global xcorr
    % ---------------------------------------------------------------
    xc_a = v_a_full;   xc_b = v_b_full;
    xc_a(~mask_a) = 0; xc_b(~mask_b) = 0;
    xc_a(mask_a)  = xc_a(mask_a) - mean(xc_a(mask_a));
    xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));

    [xc_vals, lags] = xcorr(xc_a, xc_b);
    [~, peak_idx]   = max(xc_vals);
    lag_samples     = lags(peak_idx);

    offset_s = (t_a(1) - t_b(1)) + lag_samples * dt;

    % ---------------------------------------------------------------
    %  Normalised quality score
    % ---------------------------------------------------------------
    xc_norm  = max(abs(xc_vals));
    xc_self  = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
    if xc_self > 0
        quality = xc_norm / xc_self;
    end

    % ---------------------------------------------------------------
    %  Guards
    % ---------------------------------------------------------------
    if abs(offset_s) > MAX_OFFSET_S
        err_msg = sprintf('Offset %.2fs exceeds MAX_OFFSET_S (%.0fs)', offset_s, MAX_OFFSET_S);
        quality  = 0;
        offset_s = NaN;
        if debug
            xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
                mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
            waitfor(gcf);
        end
        return;
    end

    max_lag = numel(xc_a) + numel(xc_b) - 2;
    if abs(lag_samples) > 0.95 * max_lag
        err_msg = sprintf('xcorr peak at edge of range (lag=%d / max=%d) — files may not overlap', ...
            lag_samples, max_lag);
        quality  = 0;
        offset_s = NaN;
        if debug
            xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
                mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
            waitfor(gcf);
        end
        return;
    end

    % ---------------------------------------------------------------
    %  Orphan ECU detection
    % ---------------------------------------------------------------
    t_b_aligned       = t_b_full + offset_s;
    t_a_active_start  = t_a_full(find(mask_a, 1, 'first'));
    dt_b              = mean(diff(t_b_full(1:min(100, end))));
    orphan_samples    = sum(mask_b & (t_b_aligned < t_a_active_start));
    orphan_duration_s = orphan_samples * dt_b;

    if orphan_duration_s > ORPHAN_THRESHOLD_S
        fprintf('[TRIM] Orphan L180 data detected: %.0fs before dash start — launching trim UI\n', ...
            orphan_duration_s);

        trim_before_s = xcorr_quality_trim_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
            offset_s, RPM_MIN, file_a, file_b);

        if ~isempty(trim_before_s)
            trim_native = trim_before_s - offset_s;
            keep        = t_b_full >= trim_native;
            t_b_full    = t_b_full(keep);
            v_b_full    = v_b_full(keep);
            mask_b      = mask_b(keep);
            fprintf('[TRIM] L180 trimmed before %.3fs aligned (%.3fs native) — %d samples removed\n', ...
                trim_before_s, trim_native, sum(~keep));

            xc_b = v_b_full;
            xc_b(~mask_b) = 0;
            xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));

            [xc_vals, lags] = xcorr(xc_a, xc_b);
            [~, peak_idx]   = max(xc_vals);
            lag_samples     = lags(peak_idx);
            offset_s        = (t_a(1) - t_b_full(1)) + lag_samples * dt;

            xc_norm  = max(abs(xc_vals));
            xc_self  = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
            quality  = 0;
            if xc_self > 0
                quality = xc_norm / xc_self;
            end

            fprintf('[TRIM] Re-xcorr after trim: offset=%.3fs  quality=%.4f\n', offset_s, quality);
        end
    end

    % ---------------------------------------------------------------
    %  Segmented alignment UI
    % ---------------------------------------------------------------
    seg_offsets = xcorr_quality_segment_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
        mask_a, mask_b, offset_s, RPM_MIN, dt, file_a, file_b);

    if ischar(seg_offsets) && strcmp(seg_offsets, 'SKIP')
        quality  = 0;
        offset_s = NaN;
        return;
    end

    if ~isempty(seg_offsets) && isstruct(seg_offsets)
        % Use best segment quality as the representative score —
        % global quality is unreliable when files are very different lengths
        quality = max([seg_offsets.quality]);
        fprintf('[SEGMENT] %d segment offset(s) accepted.  best quality=%.4f\n', ...
            numel(seg_offsets), quality);
    else
        fprintf('[SEGMENT] Using global offset: %.3fs  quality=%.4f\n', offset_s, quality);
    end

    % ---------------------------------------------------------------
    %  Debug plot
    % ---------------------------------------------------------------
    if debug
        xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
            mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
        waitfor(gcf);
    end

end
% =========================================================================
%  xcorr_quality_debug_plot
% =========================================================================
function xcorr_quality_debug_plot(t_a, v_a, t_b, v_b, mask_a, mask_b, ...
    xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN)

    fig = figure('Name', 'xcorr_quality debug', 'NumberTitle', 'off', ...
        'Position', [100 100 1200 750]);

    has_xcorr = ~isempty(xc_vals);
    n_panels  = 2 + has_xcorr;

    [~, name_a] = fileparts(file_a);
    [~, name_b] = fileparts(file_b);

    ax1 = subplot(n_panels, 1, 1, 'Parent', fig);
    plot(ax1, t_a, v_a, 'b-', 'LineWidth', 0.8); hold(ax1, 'on');
    plot(ax1, t_b, v_b, 'r-', 'LineWidth', 0.8);
    yline(ax1, RPM_MIN, 'k--', 'LineWidth', 0.8, 'Label', sprintf('RPM\\_MIN=%d', RPM_MIN));
    fill_mask_shading(ax1, t_a, mask_a, [0 0.45 0.74], 0.12);
    fill_mask_shading(ax1, t_b, mask_b, [0.85 0.33 0.10], 0.12);
    legend(ax1, {['Combined: ' name_a], ['L180: ' name_b], 'RPM\_MIN'}, ...
        'Location', 'northeast', 'FontSize', 7);
    xlabel(ax1, 'Logger time (s)'); ylabel(ax1, 'Engine RPM');
    title(ax1, 'Raw RPM — own timestamps (blue=Combined, red=L180)');
    grid(ax1, 'on');

    ax2 = subplot(n_panels, 1, 2, 'Parent', fig);
    if ~isnan(offset_s)
        t_b_shifted = t_b + offset_s;
        plot(ax2, t_a, v_a, 'b-', 'LineWidth', 0.8); hold(ax2, 'on');
        plot(ax2, t_b_shifted, v_b, 'r-', 'LineWidth', 0.8);
        yline(ax2, RPM_MIN, 'k--', 'LineWidth', 0.8);
        title(ax2, sprintf('After offset (L180 shifted %.3fs) — quality=%.4f', offset_s, quality));
    else
        plot(ax2, t_a, v_a, 'b-', 'LineWidth', 0.8); hold(ax2, 'on');
        plot(ax2, t_b, v_b, 'r--', 'LineWidth', 0.8);
        yline(ax2, RPM_MIN, 'k--', 'LineWidth', 0.8);
        title(ax2, 'Aligned view — offset invalid (NaN), L180 shown unshifted');
    end
    xlabel(ax2, 'Aligned time (s)'); ylabel(ax2, 'Engine RPM');
    legend(ax2, {'Combined (ref)', 'L180 (shifted)'}, 'Location', 'northeast', 'FontSize', 7);
    grid(ax2, 'on');

    if has_xcorr
        ax3 = subplot(n_panels, 1, 3, 'Parent', fig);
        dt_approx = (t_a(end) - t_a(1)) / numel(t_a);
        lags_s    = lags * dt_approx;
        plot(ax3, lags_s, xc_vals, 'Color', [0.2 0.2 0.2], 'LineWidth', 0.8);
        hold(ax3, 'on');
        [pk_val, pk_idx] = max(xc_vals);
        plot(ax3, lags_s(pk_idx), pk_val, 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
        xline(ax3, lags_s(pk_idx), 'r--', 'LineWidth', 0.8, ...
            'Label', sprintf('peak=%.3fs', lags_s(pk_idx)));
        xlabel(ax3, 'Lag (s)'); ylabel(ax3, 'xcorr');
        title(ax3, sprintf('Cross-correlation — peak lag=%.3fs', lags_s(pk_idx)));
        grid(ax3, 'on');
    end

    if ~isempty(err_msg)
        annotation(fig, 'textbox', [0 0 1 0.04], 'String', ['ERROR: ' err_msg], ...
            'Color', 'r', 'FontSize', 8, 'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    else
        annotation(fig, 'textbox', [0 0 1 0.04], ...
            'String', sprintf('OK — offset=%.3fs  quality=%.4f', offset_s, quality), ...
            'Color', [0 0.5 0], 'FontSize', 8, 'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
end

% =========================================================================
%  fill_mask_shading
% =========================================================================
function fill_mask_shading(ax, t, mask, colour, alpha_val)
    if ~any(mask), return; end
    d      = diff([false; mask(:); false]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;
    yl     = ylim(ax);
    if yl(1) == yl(2), yl = [0 8000]; end
    for k = 1:numel(starts)
        i0 = starts(k);
        i1 = min(ends(k), numel(t));
        if i0 > numel(t), continue; end
        x = [t(i0) t(i1) t(i1) t(i0)];
        y = [yl(1)  yl(1)  yl(2)  yl(2)];
        patch(ax, x, y, colour, 'FaceAlpha', alpha_val, 'EdgeColor', 'none');
    end
end

% =========================================================================
%  xcorr_quality_trim_ui
% =========================================================================
function trim_before_s = xcorr_quality_trim_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
    offset_s, RPM_MIN, file_a, file_b)

    trim_before_s = [];

    [~, name_a] = fileparts(file_a);
    [~, name_b] = fileparts(file_b);

    % Derive logger type from file_b path (e.g. '...L180\HOL\Q19\...' -> 'L180')
    path_parts = strsplit(file_b, {'\','/'});
    l180_idx   = find(strcmpi(path_parts, 'L180'), 1);
    if isempty(l180_idx)
        error('xcorr_quality_trim_ui: could not find ''L180'' in file_b path:\n  %s', file_b);
    end
    logger_label = path_parts{l180_idx};   % preserves original casing

    t_b_aligned      = t_b_full + offset_s;
    mask_b_active    = v_b_full >= RPM_MIN & ~isnan(v_b_full);
    t_a_active_start = t_a_full(find(v_a_full >= RPM_MIN & ~isnan(v_a_full), 1, 'first'));
    orphan_mask      = mask_b_active & (t_b_aligned < t_a_active_start);
    orphan_duration  = sum(orphan_mask) / (1 / mean(diff(t_b_full(1:min(100,end)))));
    suggested_trim   = t_a_active_start;

    fig = uifigure('Name', [logger_label ' Trim Tool'], 'Position', [100 100 1100 700]);
    fig.UserData.confirmed = false;
    fig.UserData.trim_val  = [];

    ax = uiaxes(fig, 'Position', [30 180 1040 490]);

    uilabel(fig, 'Position', [30 120 500 22], ...
        'Text', sprintf('Orphan %s data detected: ~%.0fs before dash start.', logger_label, orphan_duration), ...
        'FontColor', [0.8 0.2 0.2], 'FontWeight', 'bold');

    uilabel(fig, 'Position', [30 85 200 22], 'Text', ['Trim ' logger_label ' before aligned time (s):']);
    trim_field = uieditfield(fig, 'numeric', ...
        'Position', [235 85 100 22], ...
        'Value',    round(suggested_trim), ...
        'Limits',   [-Inf Inf]);

    uibutton(fig, 'push', 'Text', 'Preview', ...
        'Position', [350 82 100 28], ...
        'ButtonPushedFcn', @(~,~) do_preview());

    uibutton(fig, 'push', 'Text', 'Confirm Trim', ...
        'Position', [465 82 120 28], ...
        'BackgroundColor', [0.2 0.7 0.3], 'FontColor', 'white', ...
        'ButtonPushedFcn', @(~,~) do_confirm());

    uibutton(fig, 'push', 'Text', 'Skip (No Trim)', ...
        'Position', [600 82 120 28], ...
        'BackgroundColor', [0.6 0.6 0.6], 'FontColor', 'white', ...
        'ButtonPushedFcn', @(~,~) do_skip());

    uilabel(fig, 'Position', [30 45 800 30], ...
        'Text', sprintf('Combined: %s     %s: %s     Offset applied: %.3fs', ...
            name_a, logger_label, name_b, offset_s), ...
        'FontSize', 9, 'FontColor', [0.4 0.4 0.4]);

    draw_plot(suggested_trim, false);
    waitfor(fig);
    if isvalid(fig), close(fig); end

    function draw_plot(trim_val, show_trim_line)
        cla(ax); hold(ax, 'on');
        plot(ax, t_a_full, v_a_full, 'b-', 'LineWidth', 0.8, 'DisplayName', ['Dash: ' name_a]);
        if show_trim_line
            orphan_idx = t_b_aligned < trim_val;
            plot(ax, t_b_aligned(orphan_idx),  v_b_full(orphan_idx),  ...
                'Color', [1 0.6 0.6], 'LineWidth', 0.6, 'DisplayName', [logger_label ' (trimmed)']);
            plot(ax, t_b_aligned(~orphan_idx), v_b_full(~orphan_idx), ...
                'r-', 'LineWidth', 0.8, 'DisplayName', [logger_label ' (kept)']);
            xline(ax, trim_val, 'r--', 'LineWidth', 1.5, ...
                'Label', sprintf('trim=%.0fs', trim_val), 'LabelVerticalAlignment', 'bottom');
            yl = ylim(ax);
            patch(ax, [t_b_aligned(1) trim_val trim_val t_b_aligned(1)], ...
                [yl(1) yl(1) yl(2) yl(2)], [1 0.8 0.8], ...
                'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', '');
        else
            plot(ax, t_b_aligned, v_b_full, 'r-', 'LineWidth', 0.8, ...
                'DisplayName', [logger_label ': ' name_b]);
        end
        yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, 'Label', sprintf('RPM\\_MIN=%d', RPM_MIN));
        legend(ax, 'Location', 'northeast', 'FontSize', 7);
        xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
        title(ax, sprintf('%s Trim Preview — offset=%.3fs', logger_label, offset_s));
        grid(ax, 'on'); hold(ax, 'off');
    end

    function do_preview()
        draw_plot(trim_field.Value, true);
    end

    function do_confirm()
        trim_before_s = trim_field.Value;
        close(fig);
    end

    function do_skip()
        trim_before_s = [];
        close(fig);
    end
end

% =========================================================================
%  xcorr_quality_segment_ui
% =========================================================================
% function seg_offsets = xcorr_quality_segment_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
%     mask_a, mask_b, global_offset_s, RPM_MIN, dt, file_a, file_b)
% 
%     MAX_SEGMENT_SHIFT_S = 60;
% 
%     [~, name_a] = fileparts(file_a);
%     [~, name_b] = fileparts(file_b);
% 
%     t_b_aligned = t_b_full + global_offset_s;
%     snap_mask   = v_a_full < RPM_MIN | isnan(v_a_full);
% 
%     markers     = [];
%     phase       = 1;
%     seg_results = [];
% 
%     fig = figure('Name', 'Segment Alignment Tool', 'NumberTitle', 'off', ...
%         'Position', [60 60 1200 780], ...
%         'CloseRequestFcn', @on_close);
% 
%     ax = axes('Parent', fig, 'Position', [0.05 0.30 0.92 0.66]);
% 
%     % Row 1 — phase 1 buttons
%     btn_done = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done Splitting', ...
%         'Units', 'pixels', 'Position', [20 130 130 28], ...
%         'BackgroundColor', [0.2 0.5 0.8], 'ForegroundColor', 'white', ...
%         'Callback', @(~,~) do_phase2());
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Clear Markers', ...
%         'Units', 'pixels', 'Position', [160 130 110 28], ...
%         'Callback', @(~,~) clear_markers());
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip This Pair', ...
%         'Units', 'pixels', 'Position', [285 130 120 28], ...
%         'BackgroundColor', [0.5 0.5 0.5], 'ForegroundColor', 'white', ...
%         'Callback', @(~,~) do_skip());
% 
%     % Row 2 — phase 2 buttons
%     btn_accept = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Accept Segments', ...
%         'Units', 'pixels', 'Position', [20 90 130 28], ...
%         'BackgroundColor', [0.2 0.7 0.3], 'ForegroundColor', 'white', ...
%         'Enable', 'off', ...
%         'Callback', @(~,~) do_accept());
% 
%     btn_revert = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Revert to Global', ...
%         'Units', 'pixels', 'Position', [160 90 130 28], ...
%         'BackgroundColor', [0.7 0.3 0.2], 'ForegroundColor', 'white', ...
%         'Enable', 'off', ...
%         'Callback', @(~,~) do_revert());
% 
%     % Row 3 — L180 pad controls
%     uicontrol(fig, 'Style', 'text', ...
%         'Units', 'pixels', 'Position', [20 55 160 22], ...
%         'String', 'Extend L180 by (s):', ...
%         'HorizontalAlignment', 'left', ...
%         'BackgroundColor', get(fig, 'Color'));
% 
%     pad_field = uicontrol(fig, 'Style', 'edit', ...
%         'Units', 'pixels', 'Position', [185 55 60 22], ...
%         'String', '30');
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Apply Pad + Re-run', ...
%         'Units', 'pixels', 'Position', [255 52 150 28], ...
%         'BackgroundColor', [0.4 0.2 0.6], 'ForegroundColor', 'white', ...
%         'Callback', @(~,~) do_pad_and_rerun());
%     uicontrol(fig, 'Style', 'text', ...
%     'Units', 'pixels', 'Position', [420 55 160 22], ...
%     'String', 'Max segment shift (s):', ...
%     'HorizontalAlignment', 'left', ...
%     'BackgroundColor', get(fig, 'Color'));
% 
%     shift_field = uicontrol(fig, 'Style', 'edit', ...
%         'Units', 'pixels', 'Position', [585 55 50 22], ...
%         'String', num2str(MAX_SEGMENT_SHIFT_S));
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', '+10 & Re-run', ...
%         'Units', 'pixels', 'Position', [645 52 110 28], ...
%         'BackgroundColor', [0.2 0.4 0.6], 'ForegroundColor', 'white', ...
%         'Callback', @(~,~) do_increase_shift());
%         % Status text
%         status_txt = uicontrol(fig, 'Style', 'text', ...
%             'Units', 'pixels', 'Position', [20 170 1100 22], ...
%             'String', 'PHASE 1 — Left-click to place split markers (snaps to RPM<500). Right-click to remove.', ...
%             'HorizontalAlignment', 'left', 'FontSize', 9, ...
%             'ForegroundColor', [0.2 0.2 0.7], 'FontWeight', 'bold', ...
%             'BackgroundColor', get(fig, 'Color'));
% 
%     % Info text
%     shift_info_txt = uicontrol(fig, 'Style', 'text', ...
%     'Units', 'pixels', 'Position', [20 18 1100 28], ...
%     'String', sprintf('Combined: %s     L180: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
%         name_a, name_b, global_offset_s, MAX_SEGMENT_SHIFT_S), ...
%     'HorizontalAlignment', 'left', 'FontSize', 8, ...
%     'ForegroundColor', [0.4 0.4 0.4], ...
%     'BackgroundColor', get(fig, 'Color'));
% 
%     set(ax, 'ButtonDownFcn', @on_click);
%     draw_phase1();
%     waitfor(fig);
% 
%     % Read result from UserData — nested variable scope unreliable after waitfor/delete
%     if isvalid(fig)
%         seg_offsets = fig.UserData.seg_results;
%         delete(fig);
%     else
%         seg_offsets = [];  % figure was force-closed
%     end
% 
%     % -------------------------------------------------------------------
%     function draw_phase1()
%         cla(ax); hold(ax, 'on');
%         plot(ax, t_a_full, v_a_full, 'b-', 'LineWidth', 0.8, ...
%             'DisplayName', ['Dash: ' name_a], 'HitTest', 'off');
%         plot(ax, t_b_aligned, v_b_full, 'r-', 'LineWidth', 0.8, ...
%             'DisplayName', ['L180 (global): ' name_b], 'HitTest', 'off');
%         yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, ...
%             'Label', sprintf('RPM\\_MIN=%d', RPM_MIN), 'HitTest', 'off');
%         draw_markers();
%         legend(ax, 'Location', 'northeast', 'FontSize', 7);
%         xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
%         title(ax, 'Phase 1 — Place split markers at power-cycle boundaries');
%         grid(ax, 'on'); hold(ax, 'off');
%         set(ax, 'ButtonDownFcn', @on_click);
%     end
% 
%     function draw_markers()
%         yl = ylim(ax);
%         if yl(1) == yl(2), yl = [0 8000]; end
%         for k = 1:numel(markers)
%             xline(ax, markers(k), 'm--', 'LineWidth', 1.5, ...
%                 'Label', sprintf('split %d  %.0fs', k, markers(k)), ...
%                 'LabelVerticalAlignment', 'bottom', ...
%                 'HandleVisibility', 'off', 'HitTest', 'off');
%         end
%     end
% 
%     function on_click(~, evt)
%         if phase ~= 1, return; end
%         click_t = evt.IntersectionPoint(1);
%         btn     = evt.Button;
%         if btn == 1
%             if any(snap_mask)
%                 snap_times = t_a_full(snap_mask);
%                 [~, si]    = min(abs(snap_times - click_t));
%                 snapped_t  = snap_times(si);
%             else
%                 snapped_t = click_t;
%             end
%             markers = sort([markers, snapped_t]);
%             fprintf('[SEGMENT] Marker placed at %.2fs (snapped from %.2fs)\n', snapped_t, click_t);
%         elseif btn == 3
%             if ~isempty(markers)
%                 [~, ri] = min(abs(markers - click_t));
%                 fprintf('[SEGMENT] Marker at %.2fs removed\n', markers(ri));
%                 markers(ri) = [];
%             end
%         end
%         draw_phase1();
%     end
% 
%     function clear_markers()
%         markers = [];
%         draw_phase1();
%     end
% 
%     function do_pad_and_rerun()
%         pad_s = str2double(get(pad_field, 'String'));
%         if isnan(pad_s) || pad_s <= 0, return; end
%         dt_b  = mean(diff(t_b_full(1:min(100,end))));
%         t_pad = (t_b_full(end) + dt_b : dt_b : t_b_full(end) + pad_s)';
%         if ~isempty(t_pad)
%             t_b_full    = [t_b_full;  t_pad];
%             v_b_full    = [v_b_full;  zeros(numel(t_pad), 1)];
%             mask_b      = [mask_b;    false(numel(t_pad), 1)];
%             t_b_aligned = t_b_full + global_offset_s;
%             fprintf('[SEGMENT] L180 extended by %.0fs (%d samples)\n', pad_s, numel(t_pad));
%         end
%         phase = 1;
%         set(btn_done,   'Enable', 'on');
%         set(btn_accept, 'Enable', 'off');
%         set(btn_revert, 'Enable', 'off');
%         set(status_txt, 'String', ...
%             'L180 extended — review markers then click Done Splitting to re-run alignment.', ...
%             'ForegroundColor', [0.5 0.2 0.7]);
%         draw_phase1();
%     end
%     function do_increase_shift()
%         MAX_SEGMENT_SHIFT_S = str2double(get(shift_field, 'String')) + 10;
%         set(shift_info_txt, 'String', ...
%             sprintf('Dash: %s     ECU: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
%                 name_a, name_b, global_offset_s, MAX_SEGMENT_SHIFT_S));
%                 % If already in phase 2, re-run immediately
%         if phase == 2
%             do_phase2();
%         end
%     end
%     function do_phase2()
%         phase = 2;
%         set(btn_done,   'Enable', 'off');
%         set(btn_accept, 'Enable', 'on');
%         set(btn_revert, 'Enable', 'on');
%         set(status_txt, 'String', ...
%             'PHASE 2 — Review segment alignment. Accept or revert to global offset.', ...
%             'ForegroundColor', [0.1 0.5 0.1]);
% 
%         seg_starts = [t_a_full(1),  markers(:)'];
%         seg_ends   = [markers(:)',  t_a_full(end)];
%         n_segs     = numel(seg_starts);
% 
%         fprintf('[SEGMENT] Running per-segment xcorr on %d segment(s)...\n', n_segs);
% 
%         results = struct('t_start', cell(1,n_segs), 't_end', cell(1,n_segs), ...
%                          'offset_s', cell(1,n_segs), 'quality', cell(1,n_segs), ...
%                          'status', cell(1,n_segs));
% 
%         for s = 1:n_segs
%             ts = seg_starts(s);
%             te = seg_ends(s);
% 
%             idx_a = t_a_full >= ts & t_a_full <= te;
%             t_b_native_start = (ts - MAX_SEGMENT_SHIFT_S) - global_offset_s;
%             t_b_native_end   = (te + MAX_SEGMENT_SHIFT_S) - global_offset_s;
%             idx_b = t_b_full >= t_b_native_start & t_b_full <= t_b_native_end;
% 
%             va_seg = v_a_full(idx_a);
%             vb_seg = v_b_full(idx_b);
%             ma_seg = mask_a(idx_a);
%             mb_seg = mask_b(idx_b);
% 
%             results(s).t_start = ts;
%             results(s).t_end   = te;
% 
%             if sum(ma_seg) < 50 || sum(mb_seg) < 50
%                 results(s).offset_s = global_offset_s;
%                 results(s).quality  = 0;
%                 results(s).status   = 'fallback';
%                 fprintf('  Seg %d [%.0f-%.0fs]: too few samples — using global offset\n', s, ts, te);
%                 continue;
%             end
% 
%             xc_a_s = va_seg; xc_b_s = vb_seg;
%             xc_a_s(~ma_seg) = 0; xc_b_s(~mb_seg) = 0;
%             xc_a_s(ma_seg)  = xc_a_s(ma_seg) - mean(xc_a_s(ma_seg));
%             xc_b_s(mb_seg)  = xc_b_s(mb_seg) - mean(xc_b_s(mb_seg));
% 
%             [xc_v, xc_l] = xcorr(xc_a_s, xc_b_s);
%             [~, pk]      = max(xc_v);
%             lag_s_seg    = xc_l(pk);
% 
%             t_a_seg_start = t_a_full(find(idx_a, 1, 'first'));
%             t_b_seg_start = t_b_full(find(idx_b, 1, 'first'));
%             seg_off       = (t_a_seg_start - t_b_seg_start) + lag_s_seg * dt;
% 
%             seg_off_clamped = max(global_offset_s - MAX_SEGMENT_SHIFT_S, ...
%                               min(global_offset_s + MAX_SEGMENT_SHIFT_S, seg_off));
% 
%             xc_norm = max(abs(xc_v));
%             xc_self = sqrt(sum(xc_a_s.^2) * sum(xc_b_s.^2));
%             qual    = 0;
%             if xc_self > 0, qual = xc_norm / xc_self; end
% 
%             if seg_off ~= seg_off_clamped
%                 status_str = 'clamped';
%                 fprintf('  Seg %d [%.0f-%.0fs]: offset %.3fs CLAMPED to %.3fs  quality=%.4f\n', ...
%                     s, ts, te, seg_off, seg_off_clamped, qual);
%             else
%                 status_str = 'ok';
%                 fprintf('  Seg %d [%.0f-%.0fs]: offset=%.3fs  quality=%.4f\n', ...
%                     s, ts, te, seg_off_clamped, qual);
%             end
% 
%             results(s).offset_s = seg_off_clamped;
%             results(s).quality  = qual;
%             results(s).status   = status_str;
%         end
% 
%         seg_results = results;
%         draw_phase2(results);
%     end
% 
%     function draw_phase2(results)
%         cla(ax); hold(ax, 'on');
%         plot(ax, t_a_full, v_a_full, 'b-', 'LineWidth', 0.9, ...
%             'DisplayName', ['Dash: ' name_a], 'HitTest', 'off');
% 
%         colours = struct('ok',       [0.85 0.33 0.10], ...
%                          'clamped',  [0.93 0.69 0.13], ...
%                          'fallback', [0.6  0.6  0.6 ]);
% 
%         for s = 1:numel(results)
%             sr  = results(s);
%             col = colours.(sr.status);
%             t_b_native_start = (sr.t_start - MAX_SEGMENT_SHIFT_S) - global_offset_s;
%             t_b_native_end   = (sr.t_end   + MAX_SEGMENT_SHIFT_S) - global_offset_s;
%             idx_b = t_b_full >= t_b_native_start & t_b_full <= t_b_native_end;
%             t_seg_aligned = t_b_full(idx_b) + sr.offset_s;
%             v_seg         = v_b_full(idx_b);
%             in_window     = t_seg_aligned >= sr.t_start & t_seg_aligned <= sr.t_end;
%             plot(ax, t_seg_aligned(in_window), v_seg(in_window), ...
%                 'Color', col, 'LineWidth', 0.8, 'HitTest', 'off', ...
%                 'DisplayName', sprintf('ECU seg%d (%.3fs, q=%.3f) [%s]', ...
%                     s, sr.offset_s, sr.quality, sr.status));
%             yl = ylim(ax);
%             if yl(1) == yl(2), yl = [0 8000]; end
%             patch(ax, [sr.t_start sr.t_start sr.t_end sr.t_end], ...
%                 [yl(1) yl(2) yl(2) yl(1)], col, ...
%                 'FaceAlpha', 0.05, 'EdgeColor', col, 'LineStyle', ':', ...
%                 'HandleVisibility', 'off', 'HitTest', 'off');
%             text(ax, (sr.t_start+sr.t_end)/2, yl(2)*0.92, ...
%                 sprintf('seg%d\n%.3fs', s, sr.offset_s), ...
%                 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col);
%         end
% 
%         for k = 1:numel(markers)
%             xline(ax, markers(k), 'm--', 'LineWidth', 1.5, ...
%                 'HandleVisibility', 'off', 'HitTest', 'off', ...
%                 'Label', sprintf('split %d', k), 'LabelVerticalAlignment', 'bottom');
%         end
% 
%         yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, 'HandleVisibility', 'off', 'HitTest', 'off');
%         legend(ax, 'Location', 'northeast', 'FontSize', 7);
%         xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
%         title(ax, 'Phase 2 — Per-segment alignment result');
%         grid(ax, 'on'); hold(ax, 'off');
%     end
% 
%     function do_accept()
%         fig.UserData.seg_results = seg_results;
%         close(fig);
%     end
%     function do_revert()
%         fig.UserData.seg_results = [];
%         close(fig);
%     end
%     function do_skip()
%         fig.UserData.seg_results = 'SKIP';
%         close(fig);
%     end
% 
%     function on_close(~,~)
%         if ~isfield(fig.UserData, 'seg_results')
%             fig.UserData.seg_results = seg_results;
%         end
%         delete(fig);
%     end
% end
% 
% =========================================================================
%  xcorr_quality_segment_ui
% =========================================================================
function seg_offsets = xcorr_quality_segment_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
    mask_a, mask_b, global_offset_s, RPM_MIN, dt, file_a, file_b)

    MAX_SEGMENT_SHIFT_S = 60;

    [~, name_a] = fileparts(file_a);
    [~, name_b] = fileparts(file_b);

    t_b_aligned = t_b_full + global_offset_s;
    snap_mask   = v_a_full < RPM_MIN | isnan(v_a_full);

    markers     = [];
    phase       = 1;
    seg_results = [];

    % Use root appdata as the handoff — survives figure deletion cleanly
    setappdata(0, 'smp_seg_results_tmp', []);

    fig = figure('Name', 'Segment Alignment Tool', 'NumberTitle', 'off', ...
        'Position', [60 60 1200 780], ...
        'CloseRequestFcn', @on_close);

    ax = axes('Parent', fig, 'Position', [0.05 0.30 0.92 0.66]);

    % Row 1 — phase 1 buttons
    btn_done = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done Splitting', ...
        'Units', 'pixels', 'Position', [20 130 130 28], ...
        'BackgroundColor', [0.2 0.5 0.8], 'ForegroundColor', 'white', ...
        'Callback', @(~,~) do_phase2());

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Clear Markers', ...
        'Units', 'pixels', 'Position', [160 130 110 28], ...
        'Callback', @(~,~) clear_markers());

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip This Pair', ...
        'Units', 'pixels', 'Position', [285 130 120 28], ...
        'BackgroundColor', [0.5 0.5 0.5], 'ForegroundColor', 'white', ...
        'Callback', @(~,~) do_skip());

    % Row 2 — phase 2 buttons
    btn_accept = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Accept Segments', ...
        'Units', 'pixels', 'Position', [20 90 130 28], ...
        'BackgroundColor', [0.2 0.7 0.3], 'ForegroundColor', 'white', ...
        'Enable', 'off', ...
        'Callback', @(~,~) do_accept());

    btn_revert = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Revert to Global', ...
        'Units', 'pixels', 'Position', [160 90 130 28], ...
        'BackgroundColor', [0.7 0.3 0.2], 'ForegroundColor', 'white', ...
        'Enable', 'off', ...
        'Callback', @(~,~) do_revert());

    % Row 3 — ECU pad controls
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [20 55 160 22], ...
        'String', 'Extend ECU by (s):', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', get(fig, 'Color'));

    pad_field = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'pixels', 'Position', [185 55 60 22], ...
        'String', '30');

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Apply Pad + Re-run', ...
        'Units', 'pixels', 'Position', [255 52 150 28], ...
        'BackgroundColor', [0.4 0.2 0.6], 'ForegroundColor', 'white', ...
        'Callback', @(~,~) do_pad_and_rerun());

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [420 55 160 22], ...
        'String', 'Max segment shift (s):', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', get(fig, 'Color'));

    shift_field = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'pixels', 'Position', [585 55 50 22], ...
        'String', num2str(MAX_SEGMENT_SHIFT_S));

    uicontrol(fig, 'Style', 'pushbutton', 'String', '+10 & Re-run', ...
        'Units', 'pixels', 'Position', [645 52 110 28], ...
        'BackgroundColor', [0.2 0.4 0.6], 'ForegroundColor', 'white', ...
        'Callback', @(~,~) do_increase_shift());

    % Status text
    status_txt = uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [20 170 1100 22], ...
        'String', 'PHASE 1 — Left-click to place split markers (snaps to RPM<500). Right-click to remove.', ...
        'HorizontalAlignment', 'left', 'FontSize', 9, ...
        'ForegroundColor', [0.2 0.2 0.7], 'FontWeight', 'bold', ...
        'BackgroundColor', get(fig, 'Color'));

    % Info text
    shift_info_txt = uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [20 18 1100 28], ...
        'String', sprintf('Dash: %s     ECU: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
            name_a, name_b, global_offset_s, MAX_SEGMENT_SHIFT_S), ...
        'HorizontalAlignment', 'left', 'FontSize', 8, ...
        'ForegroundColor', [0.4 0.4 0.4], ...
        'BackgroundColor', get(fig, 'Color'));

    set(ax, 'ButtonDownFcn', @on_click);
    draw_phase1();
    waitfor(fig);

    % Read result from root appdata — survives figure deletion
    seg_offsets = getappdata(0, 'smp_seg_results_tmp');
    if isappdata(0, 'smp_seg_results_tmp')
        rmappdata(0, 'smp_seg_results_tmp');
    end
    if isempty(seg_offsets) && ~ischar(seg_offsets)
        seg_offsets = [];
    end

    % -------------------------------------------------------------------
    function draw_phase1()
        cla(ax); hold(ax, 'on');
        plot(ax, t_a_full, v_a_full, 'b-', 'LineWidth', 0.8, ...
            'DisplayName', ['Dash: ' name_a], 'HitTest', 'off');
        plot(ax, t_b_aligned, v_b_full, 'r-', 'LineWidth', 0.8, ...
            'DisplayName', ['ECU (global): ' name_b], 'HitTest', 'off');
        yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, ...
            'Label', sprintf('RPM\\_MIN=%d', RPM_MIN), 'HitTest', 'off');
        draw_markers();
        legend(ax, 'Location', 'northeast', 'FontSize', 7);
        xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
        title(ax, 'Phase 1 — Place split markers at power-cycle boundaries');
        grid(ax, 'on'); hold(ax, 'off');
        set(ax, 'ButtonDownFcn', @on_click);
    end

    function draw_markers()
        yl = ylim(ax);
        if yl(1) == yl(2), yl = [0 8000]; end
        for k = 1:numel(markers)
            xline(ax, markers(k), 'm--', 'LineWidth', 1.5, ...
                'Label', sprintf('split %d  %.0fs', k, markers(k)), ...
                'LabelVerticalAlignment', 'bottom', ...
                'HandleVisibility', 'off', 'HitTest', 'off');
        end
    end

    function on_click(~, evt)
        if phase ~= 1, return; end
        click_t = evt.IntersectionPoint(1);
        btn     = evt.Button;
        if btn == 1
            if any(snap_mask)
                snap_times = t_a_full(snap_mask);
                [~, si]    = min(abs(snap_times - click_t));
                snapped_t  = snap_times(si);
            else
                snapped_t = click_t;
            end
            markers = sort([markers, snapped_t]);
            fprintf('[SEGMENT] Marker placed at %.2fs (snapped from %.2fs)\n', snapped_t, click_t);
        elseif btn == 3
            if ~isempty(markers)
                [~, ri] = min(abs(markers - click_t));
                fprintf('[SEGMENT] Marker at %.2fs removed\n', markers(ri));
                markers(ri) = [];
            end
        end
        draw_phase1();
    end

    function clear_markers()
        markers = [];
        draw_phase1();
    end

    function do_pad_and_rerun()
        pad_s = str2double(get(pad_field, 'String'));
        if isnan(pad_s) || pad_s <= 0, return; end
        dt_b  = mean(diff(t_b_full(1:min(100,end))));
        t_pad = (t_b_full(end) + dt_b : dt_b : t_b_full(end) + pad_s)';
        if ~isempty(t_pad)
            t_b_full    = [t_b_full;  t_pad];
            v_b_full    = [v_b_full;  zeros(numel(t_pad), 1)];
            mask_b      = [mask_b;    false(numel(t_pad), 1)];
            t_b_aligned = t_b_full + global_offset_s;
            fprintf('[SEGMENT] L180 extended by %.0fs (%d samples)\n', pad_s, numel(t_pad));
        end
        phase = 1;
        set(btn_done,   'Enable', 'on');
        set(btn_accept, 'Enable', 'off');
        set(btn_revert, 'Enable', 'off');
        set(status_txt, 'String', ...
            'L180 extended — review markers then click Done Splitting to re-run alignment.', ...
            'ForegroundColor', [0.5 0.2 0.7]);
        draw_phase1();
    end

    function do_increase_shift()
        MAX_SEGMENT_SHIFT_S = str2double(get(shift_field, 'String')) + 10;
        set(shift_field, 'String', num2str(MAX_SEGMENT_SHIFT_S));
        set(shift_info_txt, 'String', ...
            sprintf('Combined: %s     L180: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
                name_a, name_b, global_offset_s, MAX_SEGMENT_SHIFT_S));
        if phase == 2
            do_phase2();
        end
    end

    function do_phase2()
        phase = 2;
        set(btn_done,   'Enable', 'off');
        set(btn_accept, 'Enable', 'on');
        set(btn_revert, 'Enable', 'on');
        set(status_txt, 'String', ...
            'PHASE 2 — Review segment alignment. Accept or revert to global offset.', ...
            'ForegroundColor', [0.1 0.5 0.1]);

        seg_starts = [t_a_full(1),  markers(:)'];
        seg_ends   = [markers(:)',  t_a_full(end)];
        n_segs     = numel(seg_starts);

        fprintf('[SEGMENT] Running per-segment xcorr on %d segment(s)...\n', n_segs);

        results = struct('t_start', cell(1,n_segs), 't_end', cell(1,n_segs), ...
                         'offset_s', cell(1,n_segs), 'quality', cell(1,n_segs), ...
                         'status', cell(1,n_segs));

        for s = 1:n_segs
            ts = seg_starts(s);
            te = seg_ends(s);

            idx_a = t_a_full >= ts & t_a_full <= te;
            t_b_native_start = (ts - MAX_SEGMENT_SHIFT_S) - global_offset_s;
            t_b_native_end   = (te + MAX_SEGMENT_SHIFT_S) - global_offset_s;
            idx_b = t_b_full >= t_b_native_start & t_b_full <= t_b_native_end;

            va_seg = v_a_full(idx_a);
            vb_seg = v_b_full(idx_b);
            ma_seg = mask_a(idx_a);
            mb_seg = mask_b(idx_b);

            results(s).t_start = ts;
            results(s).t_end   = te;

            if sum(ma_seg) < 50 || sum(mb_seg) < 50
                results(s).offset_s = global_offset_s;
                results(s).quality  = 0;
                results(s).status   = 'fallback';
                fprintf('  Seg %d [%.0f-%.0fs]: too few samples — using global offset\n', s, ts, te);
                continue;
            end

            xc_a_s = va_seg; xc_b_s = vb_seg;
            xc_a_s(~ma_seg) = 0; xc_b_s(~mb_seg) = 0;
            xc_a_s(ma_seg)  = xc_a_s(ma_seg) - mean(xc_a_s(ma_seg));
            xc_b_s(mb_seg)  = xc_b_s(mb_seg) - mean(xc_b_s(mb_seg));

            [xc_v, xc_l] = xcorr(xc_a_s, xc_b_s);
            [~, pk]      = max(xc_v);
            lag_s_seg    = xc_l(pk);

            t_a_seg_start = t_a_full(find(idx_a, 1, 'first'));
            t_b_seg_start = t_b_full(find(idx_b, 1, 'first'));
            seg_off       = (t_a_seg_start - t_b_seg_start) + lag_s_seg * dt;

            seg_off_clamped = max(global_offset_s - MAX_SEGMENT_SHIFT_S, ...
                              min(global_offset_s + MAX_SEGMENT_SHIFT_S, seg_off));

            xc_norm = max(abs(xc_v));
            xc_self = sqrt(sum(xc_a_s.^2) * sum(xc_b_s.^2));
            qual    = 0;
            if xc_self > 0, qual = xc_norm / xc_self; end

            if seg_off ~= seg_off_clamped
                status_str = 'clamped';
                fprintf('  Seg %d [%.0f-%.0fs]: offset %.3fs CLAMPED to %.3fs  quality=%.4f\n', ...
                    s, ts, te, seg_off, seg_off_clamped, qual);
            else
                status_str = 'ok';
                fprintf('  Seg %d [%.0f-%.0fs]: offset=%.3fs  quality=%.4f\n', ...
                    s, ts, te, seg_off_clamped, qual);
            end

            results(s).offset_s = seg_off_clamped;
            results(s).quality  = qual;
            results(s).status   = status_str;
        end

        seg_results = results;
        draw_phase2(results);
    end

    function draw_phase2(results)
        cla(ax); hold(ax, 'on');
        plot(ax, t_a_full, v_a_full, 'b-', 'LineWidth', 0.9, ...
            'DisplayName', ['Dash: ' name_a], 'HitTest', 'off');

        colours = struct('ok',       [0.85 0.33 0.10], ...
                         'clamped',  [0.93 0.69 0.13], ...
                         'fallback', [0.6  0.6  0.6 ]);

        for s = 1:numel(results)
            sr  = results(s);
            col = colours.(sr.status);
            t_b_native_start = (sr.t_start - MAX_SEGMENT_SHIFT_S) - global_offset_s;
            t_b_native_end   = (sr.t_end   + MAX_SEGMENT_SHIFT_S) - global_offset_s;
            idx_b = t_b_full >= t_b_native_start & t_b_full <= t_b_native_end;
            t_seg_aligned = t_b_full(idx_b) + sr.offset_s;
            v_seg         = v_b_full(idx_b);
            in_window     = t_seg_aligned >= sr.t_start & t_seg_aligned <= sr.t_end;
            plot(ax, t_seg_aligned(in_window), v_seg(in_window), ...
                'Color', col, 'LineWidth', 0.8, 'HitTest', 'off', ...
                'DisplayName', sprintf('ECU seg%d (%.3fs, q=%.3f) [%s]', ...
                    s, sr.offset_s, sr.quality, sr.status));
            yl = ylim(ax);
            if yl(1) == yl(2), yl = [0 8000]; end
            patch(ax, [sr.t_start sr.t_start sr.t_end sr.t_end], ...
                [yl(1) yl(2) yl(2) yl(1)], col, ...
                'FaceAlpha', 0.05, 'EdgeColor', col, 'LineStyle', ':', ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            text(ax, (sr.t_start+sr.t_end)/2, yl(2)*0.92, ...
                sprintf('seg%d\n%.3fs', s, sr.offset_s), ...
                'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col);
        end

        for k = 1:numel(markers)
            xline(ax, markers(k), 'm--', 'LineWidth', 1.5, ...
                'HandleVisibility', 'off', 'HitTest', 'off', ...
                'Label', sprintf('split %d', k), 'LabelVerticalAlignment', 'bottom');
        end

        yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, 'HandleVisibility', 'off', 'HitTest', 'off');
        legend(ax, 'Location', 'northeast', 'FontSize', 7);
        xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
        title(ax, 'Phase 2 — Per-segment alignment result');
        grid(ax, 'on'); hold(ax, 'off');
    end

    function do_accept()
        setappdata(0, 'smp_seg_results_tmp', seg_results);
        delete(fig);
    end

    function do_revert()
        setappdata(0, 'smp_seg_results_tmp', []);
        delete(fig);
    end

    function do_skip()
        setappdata(0, 'smp_seg_results_tmp', 'SKIP');
        delete(fig);
    end

    function on_close(~,~)
        % X button — preserve whatever state we're in
        if ~isappdata(0, 'smp_seg_results_tmp')
            setappdata(0, 'smp_seg_results_tmp', seg_results);
        end
        delete(fig);
    end

end
% =========================================================================
%  HELPERS
% =========================================================================

function dur = read_session_dur(filepath)
    fid = fopen(filepath, 'rb');
    if fid < 0, error('read_session_dur: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid));
    fseek(fid, 0, 'eof');
    fsz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    ptr   = fread(fid, 1, 'uint32=>double', 0, 'l');
    dur   = 0;
    count = 0;
    while ptr ~= 0 && ptr < fsz
        fseek(fid, ptr, 'bof');
        rec  = fread(fid, 24, 'uint8=>uint8')';
        next = double(typecast(uint8(rec(5:8)),  'uint32'));
        n    = double(typecast(uint8(rec(13:16)), 'uint32'));
        sr   = double(typecast(uint8(rec(23:24)), 'uint16'));
        if sr > 0 && n > 0, dur = max(dur, n / sr); end
        ptr   = next;
        count = count + 1;
        if count > 5000, break; end
    end
end