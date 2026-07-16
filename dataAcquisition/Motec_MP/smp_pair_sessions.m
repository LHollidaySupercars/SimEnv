function pairs_excel = smp_pair_sessions(cfg)
%% pairs_excel = smp_pair_sessions(cfg)
% Match TeamData HOL, ECU, and L180 .ld files for one session by filename
% stem (TLA_year_session), validate each candidate pair with RPM xcorr
% alignment, merge immediately on success, and write an audit Excel file.
%
% Workflow:
%   Phase 1  — Scan _TeamData/_HOL/{session}/ (recursive), ECU/HOL/{session}/,
%              L180/HOL/{session}/
%   Phase 2  — Filename match: ECU stem == Dash stem
%   Phase 3  — xcorr + trim UI + segment UI + immediate merge for each pair
%   Phase 4  — xcorr quality check for each Dash/L180 candidate pair
%   Phase 5  — Write audit Excel: 'Pairs' sheet + 'Review' sheet
%
% Required cfg fields:
%   cfg.td_hol_output_dir — TeamData HOL folder (Dash files)
%   cfg.ecu_hol_dir       — ECU HOL folder
%   cfg.l180_hol_dir      — L180 HOL folder
%   cfg.session           — session label e.g. 'Q19'
%   cfg.quality_min       — normalised xcorr quality threshold (0-1)
%   cfg.dash_rpm_ch       — RPM channel name in Dash files
%   cfg.ecu_rpm_ch        — RPM channel name in ECU files
%   cfg.l180_rpm_ch       — RPM channel name in L180 files
%   cfg.resample_hz       — xcorr grid frequency (Hz)
%   cfg.max_offset_s      — max plausible offset before pair is rejected
%   cfg.rpm_min           — RPM below this is masked
%   cfg.overwrite         — true = reprocess even if COM file exists

pairs_excel = '';

% =========================================================================
%  RESOLVE CONFIG
% =========================================================================
ECU_HOL_DIR     = cfg.ecu_hol_dir;
L180_HOL_DIR    = cfg.l180_hol_dir;
SESSION         = cfg.session;
QUALITY_MIN     = cfg.quality_min;
DASH_RPM        = cfg.dash_rpm_ch;
ECU_RPM         = cfg.ecu_rpm_ch;
L180_RPM        = cfg.l180_rpm_ch;
RESAMPLE_HZ     = cfg.resample_hz;
MAX_OFFSET_S    = cfg.max_offset_s;
RPM_MIN         = cfg.rpm_min;
OVERWRITE       = isfield(cfg, 'overwrite') && cfg.overwrite;
ECU_FORMAT      = isfield(cfg, 'ecu_format')      && cfg.ecu_format;
L180_ECU_FORMAT = isfield(cfg, 'l180_ecu_format') && cfg.l180_ecu_format;

% COM output folder — one level above td_hol_output_dir (i.e. HOL/COM/)
% COM_DIR = fullfile(fileparts(cfg.td_shol_output_dir), 'COM');
COM_DIR =  cfg.com_dir;
OUTPUT_FILE = fullfile(ECU_HOL_DIR, sprintf('session_pairs_%s_%s.xlsx', ...
    SESSION, datestr(now, 'yyyymmdd_HHMMSS')));

% =========================================================================
%  PATHS
% =========================================================================
dash_dir = fullfile(cfg.td_hol_output_dir, SESSION);
ecu_dir  = fullfile(ECU_HOL_DIR,  SESSION);
l180_dir = fullfile(L180_HOL_DIR, SESSION);

fprintf('=== smp_pair_sessions  [%s] ===\n', SESSION);
fprintf('  Dash : %s\n', dash_dir);
fprintf('  ECU  : %s\n', ecu_dir);
fprintf('  L180 : %s\n', l180_dir);
fprintf('  COM  : %s\n', COM_DIR);
fprintf('  Overwrite: %s\n\n', mat2str(OVERWRITE));

xcorr_cfg.resample_hz  = RESAMPLE_HZ;
xcorr_cfg.max_offset_s = MAX_OFFSET_S;
xcorr_cfg.rpm_min      = RPM_MIN;
xcorr_cfg.b_ecu_format = false;

% =========================================================================
%  PHASE 1 — SCAN FOLDERS
% =========================================================================
fprintf('--- Phase 1: Scan folders ---\n');

dash_map = build_stem_map(dash_dir);
ecu_map  = build_stem_map(ecu_dir);
l180_map = build_stem_map(l180_dir);

fprintf('  Dash  : %d file(s)\n',   numel(fieldnames(dash_map)));
fprintf('  ECU   : %d file(s)\n',   numel(fieldnames(ecu_map)));
fprintf('  L180  : %d file(s)\n\n', numel(fieldnames(l180_map)));

if isempty(fieldnames(ecu_map)) && isempty(fieldnames(dash_map))
    fprintf('[WARN] No .ld files found in Dash or ECU folders. Nothing to do.\n');
    return;
end

% =========================================================================
%  PHASE 2 — FILENAME MATCH
% =========================================================================
fprintf('--- Phase 2: Filename match ---\n');

ecu_stems  = fieldnames(ecu_map);
dash_stems = fieldnames(dash_map);

candidates  = {};
review_rows = {};

for i = 1 : numel(ecu_stems)
    stem = ecu_stems{i};
    if isfield(dash_map, stem)
        candidates(end+1, :) = {dash_map.(stem), ecu_map.(stem), stem}; %#ok<AGROW>
        fprintf('  Match  : %s\n', stem);
    else
        review_rows(end+1, :) = {ecu_map.(stem), 'ECU', 'ECU_NO_DASH', ''}; %#ok<AGROW>
        fprintf('  No Dash: %s\n', stem);
    end
end

matched_dash_stems = candidates(:, 3);
for i = 1 : numel(dash_stems)
    stem = dash_stems{i};
    if ~any(strcmp(matched_dash_stems, stem))
        review_rows(end+1, :) = {dash_map.(stem), 'Dash', 'DASH_NO_ECU', ''}; %#ok<AGROW>
        fprintf('  No ECU : %s\n', stem);
    end
end

% TLA filter
if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
    keep = false(size(candidates, 1), 1);
    for i = 1 : size(candidates, 1)
        [stem_tla, ~] = extract_tla_session(candidates{i, 3});
        keep(i) = any(strcmpi(stem_tla, cfg.ecu_tla_filter));
    end
    n_before   = size(candidates, 1);
    candidates = candidates(keep, :);
    fprintf('  TLA filter applied: %d -> %d candidate(s)\n', n_before, size(candidates, 1));
end

% ---- Early overwrite filter — drop candidates whose COM file already exists ----
if ~OVERWRITE && ~isempty(candidates)
    keep_cand = true(size(candidates, 1), 1);
    for i = 1 : size(candidates, 1)
        [~, dash_base, dash_ext] = fileparts(candidates{i, 1});
        com_check = fullfile(COM_DIR, [dash_base '_combined' dash_ext]);
        if exist(com_check, 'file')
            keep_cand(i) = false;
            fprintf('  [SKIP] COM exists (overwrite=false): %s\n', candidates{i, 3});
            [~, tla_chk] = extract_tla_session(candidates{i, 3});
            review_rows(end+1, :) = {candidates{i, 1}, 'Dash', 'EXISTS', com_check}; %#ok<AGROW>
        end
    end
    n_skipped_early = sum(~keep_cand);
    candidates = candidates(keep_cand, :);
    if n_skipped_early > 0
        fprintf('  Early skip: %d pair(s) already have COM files\n', n_skipped_early);
    end
end

fprintf('\n  %d candidate pair(s) to process  |  %d review item(s)\n\n', ...
    size(candidates, 1), size(review_rows, 1));

% =========================================================================
%  PHASE 3 — xcorr ALIGNMENT + MERGE: Dash vs ECU
% =========================================================================
fprintf('--- Phase 3: Dash/ECU xcorr alignment + merge ---\n');

pair_rows    = {};
n_confirmed  = 0;
n_skipped    = 0;
n_xcorr_fail = 0;

for i = 1 : size(candidates, 1)
    dash_file = candidates{i, 1};
    ecu_file  = candidates{i, 2};
    stem      = candidates{i, 3};

    [~, tla] = extract_tla_session(stem);

    fprintf('  [%d/%d] %s\n', i, size(candidates, 1), stem);
    fprintf('    Dash : %s\n', dash_file);
    fprintf('    ECU  : %s\n', ecu_file);

    % --- Overwrite check ---
    [~, dash_base, dash_ext] = fileparts(dash_file);
    com_file_expected = fullfile(COM_DIR, [dash_base '_combined' dash_ext]);

    if ~OVERWRITE && exist(com_file_expected, 'file')
        fprintf('    [SKIP] COM file exists, overwrite=false\n');
        fprintf('           %s\n', com_file_expected);
        pair_rows(end+1, :) = {dash_file, ecu_file, '', tla, SESSION, ...
            NaN, NaN, NaN, NaN, com_file_expected, 'EXISTS'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        continue;
    end

    % --- xcorr ---
    xcorr_cfg.b_ecu_format = ECU_FORMAT;
    [q, off, err_msg, seg_offsets] = xcorr_quality(dash_file, ecu_file, ...
        DASH_RPM, ECU_RPM, xcorr_cfg);

    % --- User skipped in segment UI ---
    if ischar(seg_offsets) && strcmp(seg_offsets, 'SKIP')
        fprintf('    [SKIP] User skipped in segment alignment UI\n');
        review_rows(end+1, :) = {ecu_file, 'ECU', 'SKIP_USER', ''}; %#ok<AGROW>
        n_skipped = n_skipped + 1;
        continue;
    end

    % --- xcorr error ---
    if ~isempty(err_msg)
        fprintf('    [WARN] xcorr: %s\n', err_msg);
        review_rows(end+1, :) = {ecu_file, 'ECU', ['XCORR_ERROR: ' err_msg], ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    fprintf('    ECU  quality=%.4f  offset=%+.3fs\n', q, off);

    if q < QUALITY_MIN
        review_rows(end+1, :) = {ecu_file, 'ECU', ...
            sprintf('XCORR_FAIL q=%.4f (min=%.4f)', q, QUALITY_MIN), ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [FAIL] quality %.4f below threshold %.4f\n', q, QUALITY_MIN);
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    % --- Merge ---
    merge_cfg                  = cfg;
    merge_cfg.offset_s         = off;
    merge_cfg.quality_score    = q;
    merge_cfg.seg_offsets      = seg_offsets;
    merge_cfg.show_ui          = false;
    merge_cfg.dash_rpm_channel = DASH_RPM;
    merge_cfg.ecu_rpm_channel  = ECU_RPM;
    merge_cfg.ecu_format       = ECU_FORMAT;
    merge_cfg.com_dir          = COM_DIR;

    fprintf('    -> Merging...\n');
    res = smp_merge_ecu_dash_pair(dash_file, ecu_file, merge_cfg);

    if res.success
        pair_rows(end+1, :) = {dash_file, ecu_file, '', tla, SESSION, ...
            off, q, NaN, NaN, res.com_file, 'MERGED'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        fprintf('    -> OK: %s\n', res.com_file);
    else
        review_rows(end+1, :) = {ecu_file, 'ECU', ...
            ['MERGE_ERROR: ' res.error_msg], sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [MERGE ERROR] %s\n', res.error_msg);
        n_xcorr_fail = n_xcorr_fail + 1;
    end
end

fprintf('\n  Confirmed: %d  |  Skipped: %d  |  Failed: %d\n\n', ...
    n_confirmed, n_skipped, n_xcorr_fail);

% =========================================================================
%  PHASE 4 — xcorr ALIGNMENT: Dash vs L180
% =========================================================================
fprintf('--- Phase 4: Dash/L180 xcorr alignment ---\n');

l180_stems = fieldnames(l180_map);

if isempty(l180_stems)
    fprintf('  No L180 files — skipping.\n\n');
else
    for i = 1 : size(pair_rows, 1)
        dash_file = pair_rows{i, 1};
        stem      = extract_stem(dash_file);

        if isfield(l180_map, stem)
            l180_file = l180_map.(stem);
            fprintf('  [%d/%d] L180 candidate: %s\n', i, size(pair_rows, 1), stem);

            xcorr_cfg.b_ecu_format = L180_ECU_FORMAT;
            [q180, off180, err180] = xcorr_quality(dash_file, l180_file, ...
                DASH_RPM, L180_RPM, xcorr_cfg);

            if ~isempty(err180)
                fprintf('    [WARN] L180 xcorr: %s\n', err180);
                review_rows(end+1, :) = {l180_file, 'L180', ...
                    ['XCORR_ERROR: ' err180], sprintf('%.4f', q180)}; %#ok<AGROW>
            elseif q180 >= QUALITY_MIN
                pair_rows{i, 3}  = l180_file;
                pair_rows{i, 8}  = off180;
                pair_rows{i, 9}  = q180;
                fprintf('    L180 quality=%.4f  offset=%+.3fs -> assigned\n', q180, off180);
            else
                review_rows(end+1, :) = {l180_file, 'L180', ...
                    sprintf('XCORR_FAIL q=%.4f', q180), sprintf('%.4f', q180)}; %#ok<AGROW>
                fprintf('    [FAIL] L180 quality %.4f below threshold %.4f\n', q180, QUALITY_MIN);
            end
        else
            fprintf('  [%d/%d] No L180 match for: %s\n', i, size(pair_rows, 1), stem);
        end
    end

    if size(pair_rows, 2) >= 1
        confirmed_dash_stems = cellfun(@(f) extract_stem(f), pair_rows(:,1), ...
            'UniformOutput', false);
    else
        confirmed_dash_stems = {};
    end
    for i = 1 : numel(l180_stems)
        stem = l180_stems{i};
        if ~any(strcmp(confirmed_dash_stems, stem))
            review_rows(end+1, :) = {l180_map.(stem), 'L180', 'L180_NO_PAIR', ''}; %#ok<AGROW>
            fprintf('  No pair: L180 %s\n', stem);
        end
    end
    fprintf('\n');
end

% =========================================================================
%  PHASE 5 — WRITE AUDIT EXCEL
% =========================================================================
fprintf('--- Phase 5: Write audit Excel ---\n');

pairs_hdr = {'DASH_FILE', 'ECU_FILE', 'L180_FILE', 'TLA', 'Session', ...
             'ECU_offset_s', 'ECU_quality', 'L180_offset_s', 'L180_quality', ...
             'COM_FILE', 'Status'};

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

% Check output dir exists and is writable
[out_dir, ~, ~] = fileparts(OUTPUT_FILE);
if ~isfolder(out_dir)
    try
        mkdir(out_dir);
    catch me_mkdir
        fprintf('  [ERROR] Cannot create output dir: %s\n  %s\n', ...
            out_dir, me_mkdir.message);
        pairs_excel = '';
        return;
    end
end

% Check file is not locked
if exist(OUTPUT_FILE, 'file')
    fid_test = fopen(OUTPUT_FILE, 'a');
    if fid_test == -1
        fprintf('  [ERROR] Excel file is locked (open in another app?): %s\n', OUTPUT_FILE);
        pairs_excel = '';
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
    pairs_excel = '';
    return;
end

fprintf('\n=== Done  |  %d confirmed  |  %d skipped  |  %d failed  |  %d review items ===\n', ...
    n_confirmed, n_skipped, n_xcorr_fail, size(review_rows, 1));

pairs_excel = OUTPUT_FILE;

end  % function smp_pair_sessions


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

% function map = build_stem_map(folder)
%     map = struct();
%     if ~isfolder(folder), return; end
%     listing_temp = dir(fullfile(folder, '**', '*.ld'));
%     listing = listing_temp(~[listing_temp.isdir]);
%     listing = listing(~startsWith({listing.name}, '._'));
%     for i = 1 : numel(listing)
%         [~, stem]  = fileparts(listing(i).name);
%         safe_stem  = matlab.lang.makeValidName(stem);
%         map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
%     end
% end
function map = build_stem_map(folder)
    map = struct();
    if ~isfolder(folder), return; end
    listing_temp = dir(fullfile(folder, '**', '*.ld'));
    listing = listing_temp(~[listing_temp.isdir]);
    listing = listing(~startsWith({listing.name}, '._'));
    listing = listing(~contains({listing.name}, '_shifted'));  % exclude shifted ECU files
    for i = 1 : numel(listing)
        [~, stem]  = fileparts(listing(i).name);
        safe_stem  = matlab.lang.makeValidName(stem);
        map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
    end
end

function stem = extract_stem(filepath)
    [~, name] = fileparts(filepath);
    stem = matlab.lang.makeValidName(name);
end

function [tla, session] = extract_tla_session(stem)
    parts = strsplit(stem, '_');
    if numel(parts) >= 1, tla = parts{1}; else, tla = stem; end
    if numel(parts) >= 3, session = strjoin(parts(3:end), '_'); else, session = ''; end
end

% =========================================================================
%  xcorr_quality
% =========================================================================
% function [quality, offset_s, err_msg, seg_offsets] = xcorr_quality(file_a, file_b, chan_a, chan_b, cfg)
% % Compute xcorr-based alignment quality between two .ld files using a
% % single named channel from each.
% %
% % Returns:
% %   quality     — normalised xcorr peak 0-1 (0 on failure)
% %   offset_s    — time to add to file_b timestamps to align to file_a (NaN on failure)
% %   err_msg     — non-empty string if an error occurred
% %   seg_offsets — struct array from segment UI, [] if global used, 'SKIP' if user skipped
% 
%     debug = false;
% 
%     quality     = 0;
%     offset_s    = NaN;
%     err_msg     = '';
%     seg_offsets = [];
% 
%     RESAMPLE_HZ        = cfg.resample_hz;
%     MAX_OFFSET_S       = cfg.max_offset_s;
%     RPM_MIN            = cfg.rpm_min;
%     ORPHAN_THRESHOLD_S = 60;
% 
%     a_ecu = isfield(cfg, 'a_ecu_format') && isscalar(cfg.a_ecu_format) && logical(cfg.a_ecu_format);
%     b_ecu = isfield(cfg, 'b_ecu_format') && isscalar(cfg.b_ecu_format) && logical(cfg.b_ecu_format);
% 
%     % ---------------------------------------------------------------
%     %  Load Dash (file_a)
%     % ---------------------------------------------------------------
%     chan_a_candidates = unique({chan_a, 'Engine_Speed'}, 'stable');
% 
%     da           = [];
%     da_chan_used = '';
%     for ci = 1:numel(chan_a_candidates)
%         try
%             tmp          = motec_ld_reader(file_a, {chan_a_candidates{ci}}, a_ecu);
%             target_field = matlab.lang.makeValidName(chan_a_candidates{ci});
%             fn_all       = fieldnames(tmp);
%             match        = fn_all(strcmpi(fn_all, target_field));
%             if isempty(match), continue; end
%             candidate = tmp.(match{1});
%             if numel(candidate.data) > 1000 && max(candidate.data) > RPM_MIN * 5
%                 da           = tmp;
%                 da_chan_used = match{1};
%                 break;
%             end
%         catch, end
%     end
%     if isempty(da)
%         err_msg = sprintf('No usable RPM channel found in Dash: %s', file_a);
%         return;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Load ECU (file_b)
%     % ---------------------------------------------------------------
%     chan_b_candidates = unique({chan_b, 'Engine.Speed', 'Engine_Speed'}, 'stable');
% 
%     db           = [];
%     db_chan_used = '';
%     for ci = 1:numel(chan_b_candidates)
%         try
%             tmp          = motec_ld_reader(file_b, {chan_b_candidates{ci}}, b_ecu);
%             target_field = matlab.lang.makeValidName(chan_b_candidates{ci});
%             fn_all       = fieldnames(tmp);
%             match        = fn_all(strcmpi(fn_all, target_field));
%             if isempty(match), continue; end
%             candidate = tmp.(match{1});
%             if numel(candidate.data) > 1000 && max(candidate.data) > RPM_MIN * 5
%                 db           = tmp;
%                 db_chan_used = match{1};
%                 break;
%             end
%         catch, end
%     end
%     if isempty(db)
%         err_msg = sprintf('No usable RPM channel found in ECU: %s', file_b);
%         return;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Load ECU uptime for debug diagnostics
%     % ---------------------------------------------------------------
%     if debug
%         ert_candidates = {'Engine_Run_Time', 'ECU_Uptime', 'Engine_Run_Time_'};
%         for ci = 1:numel(ert_candidates)
%             try
%                 tmp_ert      = motec_ld_reader(file_b, {ert_candidates{ci}}, b_ecu);
%                 target_field = matlab.lang.makeValidName(ert_candidates{ci});
%                 fn_all       = fieldnames(tmp_ert);
%                 match        = fn_all(strcmpi(fn_all, target_field));
%                 if ~isempty(match) && numel(tmp_ert.(match{1}).data) > 10
%                     fprintf('[DEBUG] ECU uptime channel: %s  (%d samples)\n', ...
%                         match{1}, numel(tmp_ert.(match{1}).data));
%                     break;
%                 end
%             catch, end
%         end
%     end
% 
%     % ---------------------------------------------------------------
%     %  Extract channel structs
%     % ---------------------------------------------------------------
%     ch_a = da.(da_chan_used);
%     ch_b = db.(db_chan_used);
% 
%     t_a = ch_a.time(:);
%     v_a = double(ch_a.data(:));
%     t_b = ch_b.time(:);
%     v_b = double(ch_b.data(:));
% 
%     if numel(t_a) < 10 || numel(t_b) < 10
%         err_msg = 'Insufficient samples for xcorr (< 10)';
%         return;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Resample both signals onto uniform grids at RESAMPLE_HZ
%     % ---------------------------------------------------------------
%     dt       = 1 / RESAMPLE_HZ;
%     t_a_full = (t_a(1) : dt : t_a(end))';
%     t_b_full = (t_b(1) : dt : t_b(end))';
% 
%     v_a_full = interp1(t_a, v_a, t_a_full, 'linear', NaN);
%     v_b_full = interp1(t_b, v_b, t_b_full, 'linear', NaN);
% 
%     % ---------------------------------------------------------------
%     %  Mask low-RPM and NaN regions
%     % ---------------------------------------------------------------
%     mask_a = v_a_full >= RPM_MIN & ~isnan(v_a_full);
%     mask_b = v_b_full >= RPM_MIN & ~isnan(v_b_full);
% 
%     if sum(mask_a) < 200 || sum(mask_b) < 200
%         err_msg = sprintf('Too few active-RPM samples: A=%d B=%d (need 200)', ...
%             sum(mask_a), sum(mask_b));
%         if debug
%             xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
%                 mask_a, mask_b, [], [], NaN, 0, err_msg, file_a, file_b, RPM_MIN);
%             waitfor(gcf);
%         end
%         return;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Mean-centre active regions and run initial global xcorr
%     % ---------------------------------------------------------------
%     xc_a = v_a_full;   xc_b = v_b_full;
%     xc_a(~mask_a) = 0; xc_b(~mask_b) = 0;
%     xc_a(mask_a)  = xc_a(mask_a) - mean(xc_a(mask_a));
%     xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));
% 
%     [xc_vals, lags] = xcorr(xc_a, xc_b);
%     [~, peak_idx]   = max(xc_vals);
%     lag_samples     = lags(peak_idx);
% 
%     offset_s = (t_a(1) - t_b(1)) + lag_samples * dt;
% 
%     % ---------------------------------------------------------------
%     %  Normalised quality score
%     % ---------------------------------------------------------------
%     xc_norm  = max(abs(xc_vals));
%     xc_self  = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
%     if xc_self > 0
%         quality = xc_norm / xc_self;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Guards
%     % ---------------------------------------------------------------
%     if abs(offset_s) > MAX_OFFSET_S
%         err_msg = sprintf('Offset %.2fs exceeds MAX_OFFSET_S (%.0fs)', offset_s, MAX_OFFSET_S);
%         quality  = 0;
%         offset_s = NaN;
%         if debug
%             xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
%                 mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
%             waitfor(gcf);
%         end
%         return;
%     end
% 
%     max_lag = numel(xc_a) + numel(xc_b) - 2;
%     if abs(lag_samples) > 0.95 * max_lag
%         err_msg = sprintf('xcorr peak at edge of range (lag=%d / max=%d) — files may not overlap', ...
%             lag_samples, max_lag);
%         quality  = 0;
%         offset_s = NaN;
%         if debug
%             xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
%                 mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
%             waitfor(gcf);
%         end
%         return;
%     end
% 
%     % ---------------------------------------------------------------
%     %  Orphan ECU detection
%     % ---------------------------------------------------------------
%     t_b_aligned       = t_b_full + offset_s;
%     t_a_active_start  = t_a_full(find(mask_a, 1, 'first'));
%     dt_b              = mean(diff(t_b_full(1:min(100, end))));
%     orphan_samples    = sum(mask_b & (t_b_aligned < t_a_active_start));
%     orphan_duration_s = orphan_samples * dt_b;
% 
%     if orphan_duration_s > ORPHAN_THRESHOLD_S
%         fprintf('[TRIM] Orphan ECU data detected: %.0fs before dash start — launching trim UI\n', ...
%             orphan_duration_s);
% 
%         trim_before_s = xcorr_quality_trim_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
%             offset_s, RPM_MIN, file_a, file_b);
% 
%         if ~isempty(trim_before_s)
%             trim_native = trim_before_s - offset_s;
%             keep        = t_b_full >= trim_native;
%             t_b_full    = t_b_full(keep);
%             v_b_full    = v_b_full(keep);
%             mask_b      = mask_b(keep);
%             fprintf('[TRIM] ECU trimmed before %.3fs aligned (%.3fs native) — %d samples removed\n', ...
%                 trim_before_s, trim_native, sum(~keep));
% 
%             xc_b = v_b_full;
%             xc_b(~mask_b) = 0;
%             xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));
% 
%             [xc_vals, lags] = xcorr(xc_a, xc_b);
%             [~, peak_idx]   = max(xc_vals);
%             lag_samples     = lags(peak_idx);
%             offset_s        = (t_a(1) - t_b_full(1)) + lag_samples * dt;
% 
%             xc_norm  = max(abs(xc_vals));
%             xc_self  = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
%             quality  = 0;
%             if xc_self > 0
%                 quality = xc_norm / xc_self;
%             end
% 
%             fprintf('[TRIM] Re-xcorr after trim: offset=%.3fs  quality=%.4f\n', offset_s, quality);
%         end
%     end
% 
%     % ---------------------------------------------------------------
%     %  Segmented alignment UI
%     % ---------------------------------------------------------------
%     seg_offsets = xcorr_quality_segment_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
%         mask_a, mask_b, offset_s, RPM_MIN, dt, file_a, file_b);
% 
%     if ischar(seg_offsets) && strcmp(seg_offsets, 'SKIP')
%         % User skipped — propagate sentinel up to caller
%         quality  = 0;
%         offset_s = NaN;
%         return;
%     end
% 
%     if ~isempty(seg_offsets)
%         fprintf('[SEGMENT] %d segment offset(s) accepted.\n', numel(seg_offsets));
%     else
%         fprintf('[SEGMENT] Using global offset: %.3fs\n', offset_s);
%     end
% 
%     % ---------------------------------------------------------------
%     %  Debug plot
%     % ---------------------------------------------------------------
%     if debug
%         xcorr_quality_debug_plot(t_a_full, v_a_full, t_b_full, v_b_full, ...
%             mask_a, mask_b, xc_vals, lags, offset_s, quality, err_msg, file_a, file_b, RPM_MIN);
%         waitfor(gcf);
%     end
% 
% end
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
    %  Load ECU (file_b)
    % ---------------------------------------------------------------
    chan_b_candidates = unique({chan_b, 'Engine.Speed', 'Engine_Speed'}, 'stable');

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
        err_msg = sprintf('No usable RPM channel found in ECU: %s', file_b);
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
        fprintf('[TRIM] Orphan ECU data detected: %.0fs before dash start — launching trim UI\n', ...
            orphan_duration_s);

        trim_before_s = xcorr_quality_trim_ui(t_a_full, v_a_full, t_b_full, v_b_full, ...
            offset_s, RPM_MIN, file_a, file_b);

        if ~isempty(trim_before_s)
            trim_native = trim_before_s - offset_s;
            keep        = t_b_full >= trim_native;
            t_b_full    = t_b_full(keep);
            v_b_full    = v_b_full(keep);
            mask_b      = mask_b(keep);
            fprintf('[TRIM] ECU trimmed before %.3fs aligned (%.3fs native) — %d samples removed\n', ...
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
    legend(ax1, {['Dash: ' name_a], ['ECU: ' name_b], 'RPM\_MIN'}, ...
        'Location', 'northeast', 'FontSize', 7);
    xlabel(ax1, 'Logger time (s)'); ylabel(ax1, 'Engine RPM');
    title(ax1, 'Raw RPM — own timestamps (blue=Dash, red=ECU)');
    grid(ax1, 'on');

    ax2 = subplot(n_panels, 1, 2, 'Parent', fig);
    if ~isnan(offset_s)
        t_b_shifted = t_b + offset_s;
        plot(ax2, t_a, v_a, 'b-', 'LineWidth', 0.8); hold(ax2, 'on');
        plot(ax2, t_b_shifted, v_b, 'r-', 'LineWidth', 0.8);
        yline(ax2, RPM_MIN, 'k--', 'LineWidth', 0.8);
        title(ax2, sprintf('After offset (ECU shifted %.3fs) — quality=%.4f', offset_s, quality));
    else
        plot(ax2, t_a, v_a, 'b-', 'LineWidth', 0.8); hold(ax2, 'on');
        plot(ax2, t_b, v_b, 'r--', 'LineWidth', 0.8);
        yline(ax2, RPM_MIN, 'k--', 'LineWidth', 0.8);
        title(ax2, 'Aligned view — offset invalid (NaN), ECU shown unshifted');
    end
    xlabel(ax2, 'Aligned time (s)'); ylabel(ax2, 'Engine RPM');
    legend(ax2, {'Dash (ref)', 'ECU (shifted)'}, 'Location', 'northeast', 'FontSize', 7);
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

    t_b_aligned      = t_b_full + offset_s;
    mask_b_active    = v_b_full >= RPM_MIN & ~isnan(v_b_full);
    t_a_active_start = t_a_full(find(v_a_full >= RPM_MIN & ~isnan(v_a_full), 1, 'first'));
    orphan_mask      = mask_b_active & (t_b_aligned < t_a_active_start);
    orphan_duration  = sum(orphan_mask) / (1 / mean(diff(t_b_full(1:min(100,end)))));
    suggested_trim   = t_a_active_start;

    fig = uifigure('Name', 'ECU Trim Tool', 'Position', [100 100 1100 700]);
    fig.UserData.confirmed = false;
    fig.UserData.trim_val  = [];

    ax = uiaxes(fig, 'Position', [30 180 1040 490]);

    uilabel(fig, 'Position', [30 120 500 22], ...
        'Text', sprintf('Orphan ECU data detected: ~%.0fs before dash start.', orphan_duration), ...
        'FontColor', [0.8 0.2 0.2], 'FontWeight', 'bold');

    uilabel(fig, 'Position', [30 85 200 22], 'Text', 'Trim ECU before aligned time (s):');
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
        'Text', sprintf('Dash: %s     ECU: %s     Offset applied: %.3fs', ...
            name_a, name_b, offset_s), ...
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
                'Color', [1 0.6 0.6], 'LineWidth', 0.6, 'DisplayName', 'ECU (trimmed)');
            plot(ax, t_b_aligned(~orphan_idx), v_b_full(~orphan_idx), ...
                'r-', 'LineWidth', 0.8, 'DisplayName', 'ECU (kept)');
            xline(ax, trim_val, 'r--', 'LineWidth', 1.5, ...
                'Label', sprintf('trim=%.0fs', trim_val), 'LabelVerticalAlignment', 'bottom');
            yl = ylim(ax);
            patch(ax, [t_b_aligned(1) trim_val trim_val t_b_aligned(1)], ...
                [yl(1) yl(1) yl(2) yl(2)], [1 0.8 0.8], ...
                'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', '');
        else
            plot(ax, t_b_aligned, v_b_full, 'r-', 'LineWidth', 0.8, ...
                'DisplayName', ['ECU: ' name_b]);
        end
        yline(ax, RPM_MIN, 'k--', 'LineWidth', 0.8, 'Label', sprintf('RPM\\_MIN=%d', RPM_MIN));
        legend(ax, 'Location', 'northeast', 'FontSize', 7);
        xlabel(ax, 'Aligned time (s)'); ylabel(ax, 'Engine RPM');
        title(ax, sprintf('ECU Trim Preview — offset=%.3fs', offset_s));
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
%     % Row 3 — ECU pad controls
%     uicontrol(fig, 'Style', 'text', ...
%         'Units', 'pixels', 'Position', [20 55 160 22], ...
%         'String', 'Extend ECU by (s):', ...
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
%     'String', sprintf('Dash: %s     ECU: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
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
%             'DisplayName', ['ECU (global): ' name_b], 'HitTest', 'off');
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
%             fprintf('[SEGMENT] ECU extended by %.0fs (%d samples)\n', pad_s, numel(t_pad));
%         end
%         phase = 1;
%         set(btn_done,   'Enable', 'on');
%         set(btn_accept, 'Enable', 'off');
%         set(btn_revert, 'Enable', 'off');
%         set(status_txt, 'String', ...
%             'ECU extended — review markers then click Done Splitting to re-run alignment.', ...
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
            fprintf('[SEGMENT] ECU extended by %.0fs (%d samples)\n', pad_s, numel(t_pad));
        end
        phase = 1;
        set(btn_done,   'Enable', 'on');
        set(btn_accept, 'Enable', 'off');
        set(btn_revert, 'Enable', 'off');
        set(status_txt, 'String', ...
            'ECU extended — review markers then click Done Splitting to re-run alignment.', ...
            'ForegroundColor', [0.5 0.2 0.7]);
        draw_phase1();
    end

    function do_increase_shift()
        MAX_SEGMENT_SHIFT_S = str2double(get(shift_field, 'String')) + 10;
        set(shift_field, 'String', num2str(MAX_SEGMENT_SHIFT_S));
        set(shift_info_txt, 'String', ...
            sprintf('Dash: %s     ECU: %s     Global offset: %.3fs     Max segment shift: ±%.0fs', ...
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
%  smp_merge_ecu_dash_pair
% =========================================================================
function result = smp_merge_ecu_dash_pair(DASH_FILE, ECU_FILE, cfg)
%SMP_MERGE_ECU_DASH_PAIR  Align and merge one Dash+ECU .ld pair.

    if nargin < 3 || isempty(cfg), cfg = struct(); end

    DASH_RPM_CHANNEL      = cfg_get(cfg, 'dash_rpm_channel',  'Engine_Speed');
    ECU_RPM_CHANNEL       = cfg_get(cfg, 'ecu_rpm_channel',   'Engine.Speed');
    RESAMPLE_HZ           = cfg_get(cfg, 'resample_hz',       100);
    MAX_OFFSET_S          = cfg_get(cfg, 'max_offset_s',      300);
    RPM_MIN               = cfg_get(cfg, 'rpm_min',           500);
    PRESET_OFFSET_S       = cfg_get(cfg, 'offset_s',          []);
    PRESET_QUALITY        = cfg_get(cfg, 'quality_score',     NaN);
    SEG_OFFSETS           = cfg_get(cfg, 'seg_offsets',       []);
    SESSION_METADATA_FILE = cfg_get(cfg, 'session_meta_file', ...
        fullfile(fileparts(mfilename('fullpath')), 'channels', 'session_metadata.xlsx'));
    ECU_FORMAT            = cfg_get(cfg, 'ecu_format',        true);
    COM_DIR_OVERRIDE      = cfg_get(cfg, 'com_dir',           '');
    show_ui               = cfg_get(cfg, 'show_ui',           isempty(PRESET_OFFSET_S));

    result = struct('success', false, 'error_msg', '', 'offset_s', NaN, ...
                    'quality_score', NaN, 'com_file', '', ...
                    'n_ecu_merged', 0, 'n_ecu_skipped', 0);
    try

%% STEP 1: Read files
        fprintf('=== Reading Dash logger ===\n  %s\n', DASH_FILE);
        dash = motec_ld_reader(DASH_FILE);

        fprintf('\n=== Reading ECU logger ===\n  %s\n', ECU_FILE);
        ecu = motec_ld_reader(ECU_FILE, {}, ECU_FORMAT);

%% STEP 2: Extract RPM
        fprintf('\n=== Extracting RPM channels ===\n');

        rpm_dash_field = find_field(dash, DASH_RPM_CHANNEL);
        rpm_ecu_field  = find_field(ecu,  ECU_RPM_CHANNEL);

        if isempty(rpm_dash_field)
            error('RPM channel "%s" not found in Dash.\nAvailable: %s', ...
                DASH_RPM_CHANNEL, strjoin(fieldnames(dash)', ', '));
        end
        if isempty(rpm_ecu_field)
            error('RPM channel "%s" not found in ECU.\nAvailable: %s', ...
                ECU_RPM_CHANNEL, strjoin(fieldnames(ecu)', ', '));
        end

        rpm_dash_t = dash.(rpm_dash_field).time(:);
        rpm_dash_v = double(dash.(rpm_dash_field).data(:));
        rpm_ecu_t  = ecu.(rpm_ecu_field).time(:);
        rpm_ecu_v  = double(ecu.(rpm_ecu_field).data(:));

        fprintf('  Dash RPM: %.0f-%.0fs  (%d samples at %.0fHz)\n', ...
            rpm_dash_t(1), rpm_dash_t(end), numel(rpm_dash_t), dash.(rpm_dash_field).sample_rate);
        fprintf('  ECU  RPM: %.0f-%.0fs  (%d samples at %.0fHz)\n', ...
            rpm_ecu_t(1), rpm_ecu_t(end), numel(rpm_ecu_t), ecu.(rpm_ecu_field).sample_rate);

%% STEP 3: Determine offset
        if ~isempty(PRESET_OFFSET_S)
            offset_s      = PRESET_OFFSET_S;
            quality_score = PRESET_QUALITY;
            fprintf('\n=== Using pre-computed offset: %+.4fs  (quality=%.4f) ===\n', ...
                offset_s, quality_score);
        else
            fprintf('\n=== Computing xcorr alignment (%.0f Hz grid) ===\n', RESAMPLE_HZ);
            dt          = 1 / RESAMPLE_HZ;
            t_dash_full = (rpm_dash_t(1) : dt : rpm_dash_t(end))';
            t_ecu_full  = (rpm_ecu_t(1)  : dt : rpm_ecu_t(end))';

            rpm_dash_full = interp1(rpm_dash_t, rpm_dash_v, t_dash_full, 'linear', NaN);
            rpm_ecu_full  = interp1(rpm_ecu_t,  rpm_ecu_v,  t_ecu_full,  'linear', NaN);

            valid_dash = rpm_dash_full >= RPM_MIN & ~isnan(rpm_dash_full);
            valid_ecu  = rpm_ecu_full  >= RPM_MIN & ~isnan(rpm_ecu_full);

            fprintf('  Active RPM samples: Dash=%d  ECU=%d\n', sum(valid_dash), sum(valid_ecu));

            if sum(valid_dash) < 200 || sum(valid_ecu) < 200
                warning('Low active RPM samples — alignment may be unreliable.');
            end

            rpm_d_xc = rpm_dash_full; rpm_e_xc = rpm_ecu_full;
            rpm_d_xc(~valid_dash) = 0; rpm_e_xc(~valid_ecu) = 0;
            rpm_d_xc(valid_dash)  = rpm_d_xc(valid_dash) - mean(rpm_d_xc(valid_dash));
            rpm_e_xc(valid_ecu)   = rpm_e_xc(valid_ecu)  - mean(rpm_e_xc(valid_ecu));

            [xc_vals, lags] = xcorr(rpm_d_xc, rpm_e_xc);
            [~, peak_idx]   = max(xc_vals);
            lag_samples     = lags(peak_idx);
            offset_s        = (rpm_dash_t(1) - rpm_ecu_t(1)) + lag_samples * dt;

            xc_norm = max(abs(xc_vals));
            xc_self = sqrt(sum(rpm_d_xc.^2) * sum(rpm_e_xc.^2));
            quality_score = 0;
            if xc_self > 0, quality_score = xc_norm / xc_self; end

            fprintf('  Offset: %+.4fs  quality=%.4f\n', offset_s, quality_score);

            if abs(offset_s) > MAX_OFFSET_S
                error('xcorr offset %.2fs exceeds MAX_OFFSET_S (%.0fs).', offset_s, MAX_OFFSET_S);
            end
        end

%% STEP 4: Resample ECU onto Dash time axis
        fprintf('\n=== Merging ECU channels onto Dash time axis ===\n');

        dash_t       = rpm_dash_t;
        merged       = dash;
        ecu_fields   = fieldnames(ecu);
        n_merged_ok  = 0;
        n_merged_nan = 0;

        if ~isempty(SEG_OFFSETS) && isstruct(SEG_OFFSETS)
            offset_vec    = build_offset_vector(dash_t, SEG_OFFSETS, offset_s);
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

        for i = 1:numel(ecu_fields)
            fn = ecu_fields{i};
            ch = ecu.(fn);
            ecu_t = ch.time(:);
            ecu_v = double(ch.data(:));

            if use_segmented
                ecu_data_on_dash = interp1(ecu_t + offset_s, ecu_v, ...
                    dash_t - (offset_vec - offset_s), 'linear', NaN);
            else
                ecu_data_on_dash = interp1(ecu_t + offset_s, ecu_v, dash_t, 'linear', NaN);
            end

            n_finite = sum(isfinite(ecu_data_on_dash));
            if n_finite == 0
                n_merged_nan = n_merged_nan + 1;
                fprintf('  [SKIP] ecu_%s: 0 finite samples\n', fn);
                continue;
            end

            out_field                      = ['ecu_' fn];
            merged.(out_field).data        = ecu_data_on_dash;
            merged.(out_field).time        = dash_t;
            merged.(out_field).units       = ch.units;
            merged.(out_field).sample_rate = ch.sample_rate;
            merged.(out_field).raw_name    = ch.raw_name;
            n_merged_ok = n_merged_ok + 1;
            fprintf('  + ecu_%s  [%d/%d finite]\n', fn, n_finite, numel(dash_t));
        end

        fprintf('\n  Merged %d ECU channels  (%d skipped)\n', n_merged_ok, n_merged_nan);

%% STEP 5: Diagnostic figure
        if show_ui
            fig = figure('Color', 'white', 'Position', [80 80 1200 600], ...
                'Name', 'ECU/Dash RPM Alignment');
            if use_segmented
                title_str = sprintf('RPM Alignment — %d segments  (global=%+.4fs  quality=%.4f)', ...
                    numel(SEG_OFFSETS), offset_s, quality_score);
            else
                title_str = sprintf('RPM Alignment  (offset=%+.4fs  quality=%.4f)', ...
                    offset_s, quality_score);
            end
            sgtitle(fig, title_str, 'FontSize', 11, 'FontWeight', 'bold');

            ax1 = subplot(2,1,1);
            hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');
            plot(ax1, rpm_dash_t, rpm_dash_v, 'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Dash');
            plot(ax1, rpm_ecu_t,  rpm_ecu_v,  'Color', [0.84 0.13 0.13], 'LineWidth', 1.0, 'DisplayName', 'ECU (raw)');
            ylabel(ax1, 'Engine RPM');
            title(ax1, 'Before Alignment', 'FontWeight', 'normal');
            legend(ax1, 'Location', 'best', 'Box', 'off');

            ax2 = subplot(2,1,2);
            hold(ax2,'on'); box(ax2,'on'); grid(ax2,'on');
            plot(ax2, rpm_dash_t, rpm_dash_v, 'Color', [0.12 0.31 0.64], 'LineWidth', 1.2, 'DisplayName', 'Dash');
            if use_segmented
                colours = {[0.84 0.13 0.13],[0.93 0.69 0.13],[0.2 0.7 0.3],[0.5 0.2 0.8],[0.1 0.6 0.8]};
                for s = 1:numel(SEG_OFFSETS)
                    col   = colours{mod(s-1,numel(colours))+1};
                    seg_t = rpm_ecu_t + SEG_OFFSETS(s).offset_s;
                    in_w  = seg_t >= SEG_OFFSETS(s).t_start & seg_t <= SEG_OFFSETS(s).t_end;
                    plot(ax2, seg_t(in_w), rpm_ecu_v(in_w), 'Color', col, 'LineWidth', 1.0, ...
                        'DisplayName', sprintf('ECU seg%d (%+.2fs)', s, SEG_OFFSETS(s).offset_s));
                end
            else
                plot(ax2, rpm_ecu_t + offset_s, rpm_ecu_v, 'Color', [0.84 0.13 0.13], ...
                    'LineWidth', 1.0, 'DisplayName', sprintf('ECU (shifted %+.4fs)', offset_s));
            end
            ylabel(ax2, 'Engine RPM'); xlabel(ax2, 'Time (s)');
            title(ax2, 'After Alignment', 'FontWeight', 'normal');
            legend(ax2, 'Location', 'best', 'Box', 'off');
            linkaxes([ax1, ax2], 'x');
        end

%% STEP 6: Write time-shifted ECU file
        [ecu_dir, ecu_name, ecu_ext] = fileparts(ECU_FILE);
        ECU_SHIFTED_FILE = fullfile(ecu_dir, [ecu_name '_shifted' ecu_ext]);
        fprintf('\n=== Writing time-shifted ECU file ===\n');
        smp_shift_ld_time(ECU_FILE, ECU_SHIFTED_FILE, offset_s);
        fprintf('  %s\n', ECU_SHIFTED_FILE);

%% STEP 7: Write combined .ld
        % Use explicit com_dir if passed in, otherwise infer from DASH_FILE
        if ~isempty(COM_DIR_OVERRIDE)
            com_dir = COM_DIR_OVERRIDE;
        else
            com_dir = fullfile(fileparts(fileparts(DASH_FILE)), 'COM');
        end
        if ~exist(com_dir, 'dir')
                mkdir(com_dir)
        end
        if ~exist(com_dir, 'dir')
                mkdir(com_dir)
        end
        [~, dash_base, dash_ext] = fileparts(DASH_FILE);
        COM_FILE = fullfile(com_dir, [dash_base '_combined' dash_ext]);

        session_meta = struct();
        if exist(SESSION_METADATA_FILE, 'file')
            fprintf('\n=== Loading session metadata ===\n');
            session_meta = smp_session_metadata_load(SESSION_METADATA_FILE, DASH_FILE);
            meta_fields  = fieldnames(session_meta);
            if isempty(meta_fields)
                fprintf('  [WARN] No metadata matched for: %s\n', DASH_FILE);
            else
                for mf = 1:numel(meta_fields)
                    sch = session_meta.(meta_fields{mf});
                    fprintf('  %-20s = %.4f %s\n', sch.name, sch.value, sch.units);
                end
            end
        else
            fprintf('\n[INFO] session_metadata.xlsx not found — skipping.\n');
        end

        fprintf('\n=== Writing combined .ld file ===\n');
        smp_write_combined_ld(DASH_FILE, merged, COM_FILE);
        fprintf('  %s\n', COM_FILE);

        if ~isempty(fieldnames(session_meta))
            fprintf('\n=== Appending session metadata channels ===\n');
            META_SR      = 5;
            meta_ses_dur = read_session_dur(COM_FILE);
            meta_n       = round(meta_ses_dur * META_SR);
            fprintf('  Session duration: %.1f s  n=%d @ %dHz\n', meta_ses_dur, meta_n, META_SR);

            meta_ch_list = {};
            meta_fns = fieldnames(session_meta);
            for mci = 1:numel(meta_fns)
                msch = session_meta.(meta_fns{mci});
                mval = double(msch.value);
                mdec = 0;
                for d = 4:-1:0
                    if abs(mval) * 10^d <= 32767, mdec = d; break; end
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
                fprintf('  + %-20s = %.*f %s\n', msch.name, mdec, mval, msch.units);
            end
            [com_d, com_b, com_e] = fileparts(COM_FILE);
            meta_tmp = fullfile(com_d, [com_b '_smeta_tmp' com_e]);
            ld_add_channel(COM_FILE, meta_tmp, meta_ch_list);
            movefile(meta_tmp, COM_FILE, 'f');
        end

        fprintf('\n  Dash channels : %d\n', numel(fieldnames(dash)));
        fprintf('  ECU merged    : %d\n', n_merged_ok);
        fprintf('  ECU skipped   : %d\n', n_merged_nan);
        fprintf('  Total combined: %d\n', numel(fieldnames(merged)));

        result.success       = true;
        result.offset_s      = offset_s;
        result.quality_score = quality_score;
        result.com_file      = COM_FILE;
        result.n_ecu_merged  = n_merged_ok;
        result.n_ecu_skipped = n_merged_nan;

    catch ME
        result.error_msg = ME.message;
        fprintf('\n[ERROR] %s\n  %s\n', ME.message, ME.getReport('basic'));
    end
end

% =========================================================================
%  HELPERS
% =========================================================================

function v = cfg_get(s, f, def)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
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

function offset_vec = build_offset_vector(dash_t, seg_offsets, global_offset_s)
    offset_vec = repmat(global_offset_s, size(dash_t));
    for s = 1:numel(seg_offsets)
        in_seg = dash_t >= seg_offsets(s).t_start & dash_t <= seg_offsets(s).t_end;
        offset_vec(in_seg) = seg_offsets(s).offset_s;
    end
end

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