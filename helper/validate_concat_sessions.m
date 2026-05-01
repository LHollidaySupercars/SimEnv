%% VALIDATE_CONCAT_SESSIONS
%  Standalone script to verify concat_sessions behaviour.
%
%  --- REAL DATA (Section A) ---
%  Scans .ld files, groups into stints, loads raw channel data, runs
%  concat_sessions and pops up the fingerprint report.
%  This path ALWAYS runs regardless of the cache — it never compiles and
%  never writes to disk.
%
%  Set TOP_LEVEL_DIR and SESSION_FILTER in CONFIG.
%  Leave TOP_LEVEL_DIR = '' to skip and run synthetic tests only.
%
%  --- SYNTHETIC TESTS ---
%  8 in-memory checks: monotonicity, lap renumbering, mixed sample rates,
%  duplicate detection, superset detection, default behaviour.
%
%  Run from C:\SimEnv:
%    cd('C:\SimEnv');  run('helper/validate_concat_sessions.m')

clear; clc;
addpath(genpath('dataAcquisition/parseEventData'));
addpath(genpath('dataAcquisition/Motec_MP'));

% =========================================================================
%  CONFIG — edit here
% =========================================================================
TOP_LEVEL_DIR    = 'E:\2025\04_TAS\_TeamData';   % root team data folder, or '' to skip
SESSION_FILTER   = {'Q13'};    % session(s) to inspect — must match resolved session name
TEAM_FILTER      = {};         % {} = all teams, e.g. {'BRT','WAU'}
DRIVER_FILTER    = {};         % {} = all drivers, e.g. {'Lastname'}
EVENT_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias2025.xlsx';
DRIVER_ALIAS_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';
UNIQUE_FP        = true;   % drop duplicate/superset stints

fprintf('=== validate_concat_sessions ===\n\n');
pass = 0;
fail = 0;

% =========================================================================
%  SECTION A: REAL DATA  (skipped when TOP_LEVEL_DIR is empty)
%  Always runs — bypasses the cache entirely.
%  Pipeline: scan → group → load raw → concat_sessions → pop-up report
% =========================================================================
if ~isempty(TOP_LEVEL_DIR)
    fprintf('--- Real data: %s ---\n', TOP_LEVEL_DIR);
    fprintf('    Sessions : %s\n', strjoin(SESSION_FILTER, ', '));
    if ~isempty(TEAM_FILTER)
        fprintf('    Teams    : %s\n', strjoin(TEAM_FILTER, ', '));
    end
    if ~isempty(DRIVER_FILTER)
        fprintf('    Drivers  : %s\n', strjoin(DRIVER_FILTER, ', '));
    end
    fprintf('\n');

    alias      = smp_alias_load(EVENT_ALIAS_FILE);
    driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);

    % Scan and build to_load (same shape as smp_cache_diff output)
    scan_all = smp_scan_folders(TOP_LEVEL_DIR);
    if ~isempty(TEAM_FILTER)
        keep_mask = ismember({scan_all.acronym}, TEAM_FILTER);
        scan_all  = scan_all(keep_mask);
    end
    to_load = struct('path', {}, 'team_index', {}, 'team_acronym', {});
    n_tl = 0;
    for t = 1:numel(scan_all)
        for f = 1:numel(scan_all(t).files)
            n_tl = n_tl + 1;
            to_load(n_tl).path         = scan_all(t).files{f};
            to_load(n_tl).team_index   = scan_all(t).index;
            to_load(n_tl).team_acronym = scan_all(t).acronym;
        end
    end

    fprintf('  Files scanned: %d\n', numel(to_load));
    groups_all = smp_append_stints(to_load, driver_map, alias, SESSION_FILTER);
    fprintf('  Groups before driver filter: %d\n', numel(groups_all));
    for gi = 1:numel(groups_all)
        fprintf('    [%d] driver="%s"  session="%s"  team="%s"  files=%d\n', ...
            gi, groups_all(gi).driver, groups_all(gi).session, ...
            groups_all(gi).team_acronym, groups_all(gi).n_files);
    end

    groups = groups_all;
    if ~isempty(DRIVER_FILTER)
        keep_mask = ismember(lower({groups.driver}), lower(DRIVER_FILTER));
        groups    = groups(keep_mask);
        fprintf('  Groups after driver filter (%s): %d\n\n', strjoin(DRIVER_FILTER,','), numel(groups));
    end

    if isempty(groups)
        fprintf('  [SKIP] No groups found for session filter: %s\n\n', strjoin(SESSION_FILTER, ', '));
    else
        fprintf('  Groups found: %d\n\n', numel(groups));
        concat_opts.uniqueFingerprint = UNIQUE_FP;

        % CSV accumulator — written after all groups processed
        csv_rows    = {'Team,Driver,Session,File,Status,MatchedFile,Reason'};
        csv_has_data = false;

        for g = 1:numel(groups)
            grp = groups(g);
            fprintf('  [%d/%d]  %s | %s | %s  (%d file(s))\n', ...
                g, numel(groups), grp.team_acronym, grp.driver, grp.session, grp.n_files);
            for fi = 1:grp.n_files
                [~, fn, ext] = fileparts(grp.files{fi});
                fprintf('    Stint %d: %s%s\n', fi, fn, ext);
            end

            % Load raw sessions (no channel filter — we want fingerprint channels)
            all_sess = cell(grp.n_files, 1);
            load_ok  = true;
            for fi = 1:grp.n_files
                try
                    all_sess{fi} = motec_ld_reader(grp.files{fi}, {});
                catch ME
                    fprintf('    [ERROR] Load failed for stint %d: %s\n', fi, ME.message);
                    load_ok = false;
                end
            end
            if ~load_ok, fprintf('\n'); continue; end

            % Concat and capture report — this always runs, cache-independent
            [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
            smp_show_concat_report(fp_report, grp.key, grp.files, all_sess, merged_sess);

            % Accumulate CSV rows for this group
            for si = 1:numel(fp_report)
                if si > grp.n_files, break; end
                [~, fn, ext] = fileparts(grp.files{si});
                matched_file = '';
                if fp_report(si).matched_idx > 0 && fp_report(si).matched_idx <= grp.n_files
                    [~, mfn, mext] = fileparts(grp.files{fp_report(si).matched_idx});
                    matched_file = [mfn mext];
                end
                reason_safe = strrep(fp_report(si).reason, ',', ';');
                csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,%s,%s,"%s"', ...
                    grp.team_acronym, grp.driver, grp.session, fn, ext, ...
                    upper(fp_report(si).status), matched_file, reason_safe);
            end
            csv_has_data = true;
            fprintf('\n');
        end
        % Write CSV report
        if csv_has_data
            csv_path = fullfile(TOP_LEVEL_DIR, ...
                sprintf('concat_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
            fid = fopen(csv_path, 'w');
            if fid ~= -1
                for ri = 1:numel(csv_rows)
                    fprintf(fid, '%s\n', csv_rows{ri});
                end
                fclose(fid);
                fprintf('  CSV saved: %s\n', csv_path);
            else
                fprintf('  [WARN] Could not write CSV to: %s\n', csv_path);
            end
        end
    end
end

% =========================================================================
%  TEST 1: Time axis strictly monotonic (uniform 100 Hz channels)
% =========================================================================
fprintf('TEST 1: Time axis monotonicity (uniform 100 Hz channels)\n');
s1 = make_session([0 1 2 3], 120, 0.01, 100);
s2 = make_session([0 1 2],    90, 0.01, 150);
m  = concat_sessions({s1, s2});

if all(diff(m.Lap_Number.time) > 0)
    pass = pass+1; fprintf('  [PASS] Lap_Number time monotonic\n');
else
    fail = fail+1; fprintf('  [FAIL] Lap_Number time NOT monotonic\n');
end
if all(diff(m.Ground_Speed.time) > 0)
    pass = pass+1; fprintf('  [PASS] Ground_Speed time monotonic\n');
else
    fail = fail+1; fprintf('  [FAIL] Ground_Speed time NOT monotonic\n');
end

% =========================================================================
%  TEST 2: Lap_Number renumbering — no collisions
% =========================================================================
fprintf('\nTEST 2: Lap_Number renumbering\n');
laps = unique(round(m.Lap_Number.data));
if isequal(laps(:)', 0:6)
    pass = pass+1; fprintf('  [PASS] Lap numbers 0-6, no gaps/duplicates\n');
else
    fail = fail+1; fprintf('  [FAIL] Lap numbers: %s (expected 0-6)\n', mat2str(laps(:)')); 
end

% =========================================================================
%  TEST 3: Mixed sample rates — inter-session gap uses high-rate dt
% =========================================================================
fprintf('\nTEST 3: Mixed sample rates (1 Hz Lap_Number + 100 Hz Ground_Speed)\n');
s1m = make_mixed_rate_session([0 1 2], 120);
s2m = make_mixed_rate_session([0 1],    60);
mm  = concat_sessions({s1m, s2m});

if all(diff(mm.Ground_Speed.time) > 0)
    pass = pass+1; fprintf('  [PASS] Ground_Speed time strictly monotonic (mixed rate)\n');
else
    fail = fail+1; fprintf('  [FAIL] Ground_Speed time has overlap/reversal (mixed rate)\n');
end

% Find the join gap in Ground_Speed time axis
gs_diffs = diff(mm.Ground_Speed.time);
[max_gap, max_idx] = max(gs_diffs);
fprintf('  Largest gap in Ground_Speed time: %.4f s at index %d (should be ~0.01 s)\n', max_gap, max_idx);
if max_gap < 0.05
    pass = pass+1; fprintf('  [PASS] Inter-session gap <= 0.05 s (high-rate dt used)\n');
else
    fail = fail+1; fprintf('  [FAIL] Inter-session gap = %.4f s (slow-channel dt was used)\n', max_gap);
end

% =========================================================================
%  TEST 4: uniqueFingerprint=true — exact duplicate dropped
% =========================================================================
fprintf('\nTEST 4: uniqueFingerprint=true -- exact duplicate dropped\n');
s_orig = make_session([0 1 2 3], 120, 0.01, 100);
s_dup  = s_orig;

opts_fp.uniqueFingerprint = true;
w = warning('off', 'all');
m4 = concat_sessions({s_orig, s_dup}, opts_fp);
warning(w);

n_orig   = numel(s_orig.Ground_Speed.data);
n_merged = numel(m4.Ground_Speed.data);
if n_merged == n_orig
    pass = pass+1; fprintf('  [PASS] Duplicate dropped — merged length == single session (%d pts)\n', n_orig);
else
    fail = fail+1; fprintf('  [FAIL] Duplicate NOT dropped — merged = %d pts (expected %d)\n', n_merged, n_orig);
end

% =========================================================================
%  TEST 5: uniqueFingerprint=true — superset (Run1+Run2) detected
% =========================================================================
fprintf('\nTEST 5: uniqueFingerprint=true -- superset (Run1+Run2 combined) dropped\n');
s_run1  = make_session([0 1 2], 90, 0.01, 100);
s_run2  = make_session([0 1],   60, 0.01, 200);

s_super.Ground_Speed.data        = [s_run1.Ground_Speed.data; s_run2.Ground_Speed.data];
n_super = numel(s_super.Ground_Speed.data);
s_super.Ground_Speed.time        = (0 : n_super-1)' * 0.01;
s_super.Ground_Speed.sample_rate = 100;
s_super.Ground_Speed.units       = 'km/h';
s_super.Lap_Number.data          = [s_run1.Lap_Number.data; s_run2.Lap_Number.data];
s_super.Lap_Number.time          = s_super.Ground_Speed.time;
s_super.Lap_Number.sample_rate   = 100;
s_super.Lap_Number.units         = '';

w = warning('off', 'all');
m5 = concat_sessions({s_run1, s_run2, s_super}, opts_fp);
warning(w);

n_expected5 = numel(s_run1.Ground_Speed.data) + numel(s_run2.Ground_Speed.data);
n_got5      = numel(m5.Ground_Speed.data);
if n_got5 == n_expected5
    pass = pass+1; fprintf('  [PASS] Superset dropped — merged = Run1+Run2 only (%d pts)\n', n_expected5);
else
    fail = fail+1; fprintf('  [FAIL] Superset NOT dropped — merged = %d pts (expected %d)\n', n_got5, n_expected5);
end

% =========================================================================
%  TEST 6: uniqueFingerprint=false (default) — nothing dropped
% =========================================================================
fprintf('\nTEST 6: uniqueFingerprint=false (default) -- no sessions dropped\n');
s_a = make_session([0 1 2], 90, 0.01, 100);
s_b = s_a;
m6  = concat_sessions({s_a, s_b});

n_expected6 = numel(s_a.Ground_Speed.data) * 2;
n_got6      = numel(m6.Ground_Speed.data);
if n_got6 == n_expected6
    pass = pass+1; fprintf('  [PASS] Both sessions kept — uniqueFingerprint off by default (%d pts)\n', n_got6);
else
    fail = fail+1; fprintf('  [FAIL] Sessions unexpectedly dropped — merged = %d pts (expected %d)\n', n_got6, n_expected6);
end

% =========================================================================
%  Summary
% =========================================================================
fprintf('\n=== Results: %d passed, %d failed ===\n', pass, fail);
if fail == 0
    fprintf('All checks passed.\n');
else
    fprintf('Some checks FAILED -- review output above.\n');
end

% =========================================================================
%  Local functions (must be at end of script for R2020a)
% =========================================================================

% -------------------------------------------------------------------------
function s = make_session(lap_seq, dur_s, dt, speed_start)
    if nargin < 4, speed_start = 100; end
    n     = round(dur_s / dt);
    t     = (0 : n-1)' * dt;
    n_lap = numel(lap_seq);
    ppl   = floor(n / n_lap);
    lap_d = zeros(n, 1);
    for k = 1:n_lap
        i0 = (k-1)*ppl + 1;  i1 = min(k*ppl, n);
        lap_d(i0:i1) = lap_seq(k);
    end
    lap_d(n_lap*ppl+1:end) = lap_seq(end);
    s.Lap_Number.data        = lap_d;
    s.Lap_Number.time        = t;
    s.Lap_Number.sample_rate = 1/dt;
    s.Lap_Number.units       = '';
    s.Ground_Speed.data        = linspace(speed_start, speed_start+50, n)';
    s.Ground_Speed.time        = t;
    s.Ground_Speed.sample_rate = 1/dt;
    s.Ground_Speed.units       = 'km/h';
end

function s = make_mixed_rate_session(lap_seq, dur_s)
    dt_slow = 1.0;   dt_fast = 0.01;
    n_slow  = round(dur_s / dt_slow);
    n_fast  = round(dur_s / dt_fast);
    t_slow  = (0 : n_slow-1)' * dt_slow;
    t_fast  = (0 : n_fast-1)' * dt_fast;
    n_lap   = numel(lap_seq);
    ppl     = floor(n_slow / n_lap);
    lap_d   = zeros(n_slow, 1);
    for k = 1:n_lap
        i0 = (k-1)*ppl + 1;  i1 = min(k*ppl, n_slow);
        lap_d(i0:i1) = lap_seq(k);
    end
    lap_d(n_lap*ppl+1:end) = lap_seq(end);
    s.Lap_Number.data        = lap_d;
    s.Lap_Number.time        = t_slow;
    s.Lap_Number.sample_rate = 1/dt_slow;
    s.Lap_Number.units       = '';
    s.Ground_Speed.data        = linspace(100, 200, n_fast)';
    s.Ground_Speed.time        = t_fast;
    s.Ground_Speed.sample_rate = 1/dt_fast;
    s.Ground_Speed.units       = 'km/h';
end
