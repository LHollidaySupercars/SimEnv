%% smp_cross_check_sessions.m
% Cross-check ECU and L180 split .ld files using two tiers:
%
%   Tier 1 (filename, ADVISORY):
%       Parse {year}_{session}_{driver}.ld from each filename and compare
%       ECU vs L180.  This is a quick sanity check — not a guarantee —
%       based on the naming applied by smp_split_ecu_by_uptime (RENAME_OUTPUT=true).
%
%   Tier 2 (xcorr, AUTHORITATIVE):
%       Load Engine RPM from each file, resample to a common rate, and
%       xcorr to measure correlation (r) and time offset (lag_s) between
%       the ECU and L180 recordings of the same session.
%       Positive lag = ECU leads L180.
%
% Run after smp_split_ecu_by_uptime.m with RENAME_OUTPUT=true.
% Expected folder layout:
%   ROOT_DIR/ECU/<session>/<year>_<session>_<driver>.ld
%   ROOT_DIR/L180/<session>/<year>_<session>_<driver>.ld

% clear; clc;
% addpath(genpath('dataAcquisition/Motec_MP'));
% addpath(genpath('dataAcquisition/parseEventData'));

% =========================================================================
%  CONFIG
% =========================================================================
ROOT_DIR          = 'E:\2026\E05_TAS\HOL';

EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';

SESSION_FILTER    = {};    % {} = all;  or e.g. {'Q14','Q15'}
DRIVER_FILTER     = {};    % {} = all;  or e.g. {'Smith'}

XCORR_SR          = 10;    % Hz — common resample rate for cross-correlation
MAX_LAG_S         = 120;   % s  — max xcorr search window (+/-)
MATCH_THRESH      = 0.85;  % r >= this -> MATCH;  >= 0.7*this -> WEAK

RPM_CANDIDATES    = {'Engine_Speed', 'Engine_RPM', 'RPM', 'Engine_Speed_rpm'};

ECU_FORMAT_ECU    = true;   % true = M1 ECU logger format
ECU_FORMAT_L180   = false;  % false = dash / L180 logger format

TIER1_ONLY        = false;  % true = skip xcorr, report filename check only

% =========================================================================
%  SETUP
% =========================================================================
ecu_dir  = fullfile(ROOT_DIR, 'ECU');
l180_dir = fullfile(ROOT_DIR, 'L180');

for chk = {ecu_dir, l180_dir}
    if ~isfolder(chk{1})
        error('Folder not found: %s', chk{1});
    end
end

fprintf('=== smp_cross_check_sessions ===\n');
fprintf('Root : %s\n\n', ROOT_DIR);

% =========================================================================
%  PHASE 1 — Scan both folders
% =========================================================================
fprintf('--- Phase 1: Scan folders ---\n');

alias      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);

ecu_groups  = scan_folder_headers(ecu_dir,  'ECU',  driver_map, alias, SESSION_FILTER);
l180_groups = scan_folder_headers(l180_dir, 'L180', driver_map, alias, SESSION_FILTER);

fprintf('  ECU  groups : %d\n', numel(ecu_groups));
fprintf('  L180 groups : %d\n\n', numel(l180_groups));

if ~isempty(DRIVER_FILTER)
    keep_e = ismember(lower({ecu_groups.driver}),  lower(DRIVER_FILTER));
    keep_l = ismember(lower({l180_groups.driver}), lower(DRIVER_FILTER));
    ecu_groups  = ecu_groups(keep_e);
    l180_groups = l180_groups(keep_l);
    fprintf('  After driver filter -- ECU: %d  L180: %d\n\n', ...
        numel(ecu_groups), numel(l180_groups));
end

if isempty(ecu_groups) || isempty(l180_groups)
    fprintf('[WARN] One or both folders returned no groups -- nothing to cross-check.\n');
    return;
end

% =========================================================================
%  PHASE 2 — Match groups by session + driver key
% =========================================================================
fprintf('--- Phase 2: Match by session | driver ---\n');

ecu_keys  = lower(strcat({ecu_groups.session},  '|', {ecu_groups.driver}));
l180_keys = lower(strcat({l180_groups.session}, '|', {l180_groups.driver}));

all_keys = unique([ecu_keys, l180_keys], 'stable');

pairs     = struct('ecu_idx',{},'l180_idx',{},'key',{});
unmatched = {};
for k = 1:numel(all_keys)
    ei = find(strcmp(ecu_keys,  all_keys{k}), 1);
    li = find(strcmp(l180_keys, all_keys{k}), 1);
    if ~isempty(ei) && ~isempty(li)
        pairs(end+1) = struct('ecu_idx',ei,'l180_idx',li,'key',all_keys{k}); %#ok<AGROW>
    else
        if isempty(ei)
            unmatched{end+1} = sprintf('  [NO_ECU ] %s', all_keys{k}); %#ok<AGROW>
        else
            unmatched{end+1} = sprintf('  [NO_L180] %s', all_keys{k}); %#ok<AGROW>
        end
    end
end

if ~isempty(unmatched)
    fprintf('  Unmatched:\n');
    for u = 1:numel(unmatched), fprintf('%s\n', unmatched{u}); end
end
fprintf('  Matched pairs: %d\n\n', numel(pairs));

% =========================================================================
%  PHASE 3 — Tier 1 (filename) + Tier 2 (xcorr) per matched pair
% =========================================================================
fprintf('--- Phase 3: Tier 1 filename  +  Tier 2 xcorr ---\n\n');

results = {};

for p = 1:numel(pairs)
    pr = pairs(p);
    eg = ecu_groups(pr.ecu_idx);
    lg = l180_groups(pr.l180_idx);

    key_parts  = strsplit(pr.key, '|');
    sess_label = key_parts{1};
    drv_label  = key_parts{2};

    fprintf('  [%d/%d]  session="%s"  driver="%s"\n', ...
        p, numel(pairs), upper(sess_label), drv_label);

    ecu_file  = eg.files{1};
    l180_file = lg.files{1};
    [~, ecu_fname]  = fileparts(ecu_file);
    [~, l180_fname] = fileparts(l180_file);

    % ------------------------------------------------------------------
    %  Tier 1: filename advisory check
    % ------------------------------------------------------------------
    ecu_pn  = parse_std_name(ecu_file);
    l180_pn = parse_std_name(l180_file);

    if isempty(ecu_pn) || isempty(l180_pn)
        t1_status = 'NAME_UNPARSED';
        fprintf('    Tier 1: %-30s  ECU:"%s"  L180:"%s"\n', ...
            t1_status, ecu_fname, l180_fname);
    else
        tla_ok  = strcmpi(ecu_pn.tla,     l180_pn.tla);
        yr_ok   = strcmp(ecu_pn.year,     l180_pn.year);
        sess_ok = strcmpi(ecu_pn.session, l180_pn.session);

        if tla_ok && yr_ok && sess_ok
            t1_status = 'NAME_OK';
        else
            parts = {};
            if ~tla_ok,  parts{end+1} = sprintf('tla(%s/%s)',   ecu_pn.tla,     l180_pn.tla);     end %#ok<AGROW>
            if ~yr_ok,   parts{end+1} = sprintf('year(%s/%s)',  ecu_pn.year,    l180_pn.year);    end %#ok<AGROW>
            if ~sess_ok, parts{end+1} = sprintf('sess(%s/%s)',  ecu_pn.session, l180_pn.session); end %#ok<AGROW>
            if numel(parts) == 3
                t1_status = 'NAME_MISMATCH';
            else
                t1_status = ['NAME_PARTIAL:' strjoin(parts, ',')];
            end
        end
        fprintf('    Tier 1: %-30s  ECU:"%s"  L180:"%s"\n', t1_status, ecu_fname, l180_fname);
    end

    % ------------------------------------------------------------------
    %  Tier 2: xcorr alignment
    % ------------------------------------------------------------------
    rpm_ch    = '';
    r_peak    = NaN;
    lag_s     = NaN;
    t2_status = 'SKIPPED';

    if ~TIER1_ONLY
        rpm_ecu  = load_rpm(ecu_file,  RPM_CANDIDATES, ECU_FORMAT_ECU);
        rpm_l180 = load_rpm(l180_file, RPM_CANDIDATES, ECU_FORMAT_L180);

        if isempty(rpm_ecu) || isempty(rpm_l180)
            t2_status = 'NO_DATA';
            if isempty(rpm_ecu),  fprintf('    Tier 2: No RPM in ECU  file\n'); end
            if isempty(rpm_l180), fprintf('    Tier 2: No RPM in L180 file\n'); end
        else
            rpm_ch = rpm_ecu.name;
            fprintf('    Tier 2: ch="%s"  ECU %.1fs@%gHz  L180 %.1fs@%gHz\n', ...
                rpm_ch, rpm_ecu.time(end), rpm_ecu.sample_rate, ...
                rpm_l180.time(end), rpm_l180.sample_rate);

            [r_peak, lag_s] = rpm_xcorr(rpm_ecu, rpm_l180, XCORR_SR, MAX_LAG_S);

            if     r_peak >= MATCH_THRESH,        t2_status = 'MATCH';
            elseif r_peak >= MATCH_THRESH * 0.7,  t2_status = 'WEAK';
            else,                                  t2_status = 'MISMATCH';
            end

            fprintf('    Tier 2: r=%.3f  lag=%+.1fs  ->  %s\n', r_peak, lag_s, t2_status);
        end
    end

    fprintf('\n');

    results{end+1} = {sess_label, drv_label, ...
        ecu_file, l180_file, t1_status, ...
        rpm_ch, r_peak, lag_s, t2_status}; %#ok<AGROW>
end

% =========================================================================
%  PHASE 4 — Write CSV report
% =========================================================================
fprintf('--- Phase 4: Write report ---\n');

n_name_ok   = sum(cellfun(@(r) strcmp(r{5},'NAME_OK'),    results));
n_name_bad  = sum(cellfun(@(r) ~strcmp(r{5},'NAME_OK') & ~strcmp(r{5},'NAME_UNPARSED'), results));
n_t2_match  = sum(cellfun(@(r) strcmp(r{9},'MATCH'),      results));
n_t2_weak   = sum(cellfun(@(r) strcmp(r{9},'WEAK'),       results));
n_t2_mis    = sum(cellfun(@(r) strcmp(r{9},'MISMATCH'),   results));
n_t2_nodata = sum(cellfun(@(r) strcmp(r{9},'NO_DATA'),    results));

csv_path = fullfile(ROOT_DIR, ...
    sprintf('cross_check_%s.csv', datestr(now,'yyyymmdd_HHMMSS')));

fid = fopen(csv_path, 'w');
if fid ~= -1
    fprintf(fid, 'session,driver,ecu_file,l180_file,tier1_name_check,rpm_channel,xcorr_r,lag_s,tier2_xcorr\n');
    for ri = 1:numel(results)
        row     = results{ri};
        r_str   = ''; if ~isnan(row{7}), r_str   = sprintf('%.4f', row{7}); end
        lag_str = ''; if ~isnan(row{8}), lag_str = sprintf('%.2f',  row{8}); end
        fprintf(fid, '%s,%s,"%s","%s",%s,%s,%s,%s,%s\n', ...
            row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, r_str, lag_str, row{9});
    end
    fclose(fid);
    fprintf('  Saved: %s\n', csv_path);
else
    fprintf('  [WARN] Could not write CSV to: %s\n', csv_path);
end

fprintf('\n=== Tier 1 summary: NAME_OK=%d  MISMATCH/PARTIAL=%d ===\n', n_name_ok, n_name_bad);
fprintf('=== Tier 2 summary: MATCH=%d  WEAK=%d  MISMATCH=%d  NO_DATA=%d ===\n', ...
    n_t2_match, n_t2_weak, n_t2_mis, n_t2_nodata);


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function groups = scan_folder_headers(folder, type_tag, driver_map, alias, session_filter)
% Recursively scan folder for .ld files; group via smp_append_stints.
    groups = struct('key',{},'driver',{},'car',{},'session',{},...
                    'venue',{},'log_date',{},'time_str',{},'run_number',{},...
                    'team_acronym',{},'files',{},'n_files',{});
    if ~isfolder(folder), return; end
    ld_files = recursive_find_ld(folder);
    if isempty(ld_files), return; end
    file_list = struct('path',{},'team_acronym',{});
    for i = 1:numel(ld_files)
        file_list(i).path         = ld_files{i};
        file_list(i).team_acronym = type_tag;
    end
    groups = smp_append_stints(file_list, driver_map, alias, session_filter);
end


function files = recursive_find_ld(folder)
% Recursively find all .ld files under folder.
    files = {};
    if ~isfolder(folder), return; end
    d = dir(fullfile(folder, '*.ld'));
    for i = 1:numel(d)
        files{end+1} = fullfile(folder, d(i).name); %#ok<AGROW>
    end
    subdirs = dir(folder);
    subdirs = subdirs([subdirs.isdir]);
    subdirs = subdirs(~ismember({subdirs.name},{'.','..'}));
    for i = 1:numel(subdirs)
        sub   = recursive_find_ld(fullfile(folder, subdirs(i).name));
        files = [files, sub]; %#ok<AGROW>
    end
end


function parsed = parse_std_name(filepath)
% Parse {TLA}_{year}_{session}.ld from a filename.
% Returns struct with .tla/.year/.session, or [] if pattern doesn't match.
    parsed = [];
    [~, name] = fileparts(filepath);
    tok = regexp(name, '^([A-Za-z]{2,4})_(\d{4})_([^_].*)$', 'tokens', 'once');
    if isempty(tok), return; end
    parsed.tla     = tok{1};
    parsed.year    = tok{2};
    parsed.session = tok{3};
end


function rpm = load_rpm(filepath, candidates, ecu_format)
% Load first matching RPM channel from a .ld file. Returns [] if none found.
    rpm = [];
    try
        d = motec_ld_reader(filepath, candidates, ecu_format);
    catch ME
        fprintf('    [WARN] motec_ld_reader: %s\n', ME.message);
        return;
    end
    fns = fieldnames(d);
    for ci = 1:numel(candidates)
        cand_safe = regexprep(candidates{ci}, '[^a-zA-Z0-9_]', '_');
        for fi = 1:numel(fns)
            if strcmpi(fns{fi}, candidates{ci}) || strcmpi(fns{fi}, cand_safe)
                ch = d.(fns{fi});
                if isstruct(ch) && isfield(ch,'data') && numel(ch.data) > 10
                    if ~isfield(ch, 'name'), ch.name = candidates{ci}; end
                    rpm = ch;
                    return;
                end
            end
        end
    end
end


function [r_peak, lag_s] = rpm_xcorr(rpm_a, rpm_b, target_sr, max_lag_s)
% Cross-correlate two RPM structs (.data + .time).
% Returns peak Pearson r and lag in seconds (positive = a leads b).
    t_max = min(rpm_a.time(end), rpm_b.time(end));
    if t_max < 10
        r_peak = 0; lag_s = 0; return;
    end

    t_vec = (0 : 1/target_sr : t_max)';

    sig_a = interp1(double(rpm_a.time), double(rpm_a.data), t_vec, 'linear', NaN);
    sig_b = interp1(double(rpm_b.time), double(rpm_b.data), t_vec, 'linear', NaN);

    valid = ~isnan(sig_a) & ~isnan(sig_b);
    if sum(valid) < 20
        r_peak = 0; lag_s = 0; return;
    end
    sig_a = sig_a(valid) - mean(sig_a(valid));
    sig_b = sig_b(valid) - mean(sig_b(valid));

    max_lag_samp  = round(max_lag_s * target_sr);
    [xc, lags]    = xcorr(sig_a, sig_b, max_lag_samp, 'normalized');
    [r_peak, idx] = max(xc);
    lag_s         = lags(idx) / target_sr;
end
