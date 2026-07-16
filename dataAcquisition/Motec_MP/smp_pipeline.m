%% smp_pipeline.m
% Master pipeline: align TeamData, ECU, and L180 data for one event.
%
% Phases:
%   1  TeamData concat  — multi-stint .ld files → one HOL file per driver/session
%   2  ECU concat       — multi-file ECU per driver → single concatenated file
%   3  Split            — split ECU, L180, and TeamData HOL by ECU_Uptime boundaries
%   4  Pair             — match Dash/ECU/L180 by filename, validate with RPM xcorr
%   5  Merge            — write aligned COM .ld with ECU channels merged onto Dash

% addpath(genpath('dataAcquisition/Motec_MP'));
% addpath(genpath('dataAcquisition/parseEventData'));

% =========================================================================
%  AT-TRACK CONTROLS  — edit these, nothing else
% =========================================================================

SESSION   = 'Q19';   % session to process (used in all phases)

DRIVERS   = {};      % {} = all drivers
                     % car numbers:  {'18'}  or  {'18','99'}
                     % TLAs:         {'MOS'} or  {'MOS','DEP'}

OVERWRITE = true;    % true = re-process existing output files

% Phase 1 parallel options
PHASE1_MODE        = 'parallel';   % 'serial' | 'parallel'
N_WORKERS          = 'auto';     % 'auto' = one worker per driver, or integer e.g. 8
KEEP_WORKERS_OPEN  = true;       % true = cmd /k (windows stay open at report popup)
TMP_DIR            = '';         % '' = auto → <root_folder>\_tmp_parallel

% Phase toggles — turn off phases you don't need to re-run
RUN_TEAMDATA_CONCAT = true;
RUN_ECU_CONCAT      = true;
RUN_SPLIT           = true;
RUN_PAIR            = true;
RUN_MERGE           = false;

% =========================================================================
%  STATIC CONFIG  — only change when setting up a new event
% =========================================================================

cfg.root_folder       = 'E:\2026\E06_DAR';   % event root — all paths derived from here
cfg.hol_venue         = 'Hidden Valley';
cfg.hol_event         = 'E06_DAR';
fullfile('C:\SimEnv\dataAcquisition\Motec_MP\alias', cfg.hol_event, 'eventAlias.xlsx')
cfg.event_alias_file  = ...
    fullfile('C:\SimEnv\dataAcquisition\Motec_MP\alias', cfg.hol_event, 'eventAlias.xlsx')
cfg.driver_alias_file = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';

cfg.warmup_beacon_chs  = {'Lap Beacon Number','Lap_Beacon_Number','Lap_Number','Lap Number'};
cfg.ridealong_car_nums = {};

cfg.ecu_concat_dir    = fullfile(cfg.root_folder, 'ECU', 'HOL');
cfg.l180_input_dir    = fullfile(cfg.root_folder, 'L180');

% Phase 1 — TeamData concat
cfg.td_input_dir      = fullfile(cfg.root_folder, '_TeamData');
cfg.td_hol_output_dir = fullfile(cfg.root_folder, '_TeamData', '_HOL');
cfg.unique_fp         = true;
cfg.show_report       = true;

% Phase 2 — ECU concat
cfg.ecu_input_dir     = fullfile(cfg.root_folder, 'ECU', 'Q19');
cfg.ecu_concat_dir    = fullfile(cfg.root_folder, 'ECU', 'HOL');
cfg.ecu_format        = true;
cfg.max_overlap_s     = -30;

% Phase 3 — Split
cfg.ecu_hol_dir       = fullfile(cfg.root_folder, 'ECU',  'HOL');
cfg.l180_hol_dir      = fullfile(cfg.root_folder, 'L180', 'HOL');
cfg.l180_input_dir    = fullfile(cfg.root_folder, 'L180');
cfg.session_labels    = {'Q19'};
cfg.session_aliases   = {};
cfg.min_gap_s         = 1000;
cfg.min_seg_s         = 650;
cfg.split_on_reset    = true;
cfg.rename_output     = true;
cfg.l180_ecu_format   = false;
cfg.ecu_ert_names     = {'ECU_Uptime'};
cfg.l180_ert_names    = {'ECU_Uptime'};
cfg.td_ert_names      = {'ECU_Uptime'};

% Phase 4 — Pair
cfg.quality_min       = 0.6;
cfg.resample_hz       = 100;
cfg.max_offset_s      = 4500;
cfg.rpm_min           = 500;
cfg.dash_rpm_ch       = 'Engine_Speed';
cfg.ecu_rpm_ch        = 'Engine_Speed';
cfg.l180_rpm_ch       = 'Engine_Speed';

% Phase 5 — Merge
cfg.merge_resample_hz  = 100;
cfg.merge_max_offset_s = 4500;
cfg.merge_rpm_min      = 500;
cfg.session_meta_file  = fullfile(fileparts(mfilename('fullpath')), ...
                             'channels', 'session_metadata.xlsx');
                         
cfg.l180_hol_dir  = fullfile(cfg.root_folder, 'L180', 'HOL');
cfg.l180_rpm_ch   = 'Engine_Speed';
cfg.com_rpm_ch    = 'ecu_Engine_Speed';   % reference channel in combined file
% =========================================================================
%  DERIVE FROM AT-TRACK CONTROLS
% =========================================================================
cfg.overwrite        = OVERWRITE;
cfg.session          = SESSION;
cfg.session_filter   = {SESSION};
cfg.fix_filter       = DRIVERS;
cfg.driver_filter    = {};
cfg.team_filter      = {};
cfg.split_car_filter = {};

% =========================================================================
%  RESOLVE fix_filter → per-phase filters
% =========================================================================
if ~isempty(cfg.fix_filter)
    fix_driver_map = [];
    if isfile(cfg.driver_alias_file)
        try
            fix_driver_map = smp_driver_alias_load(cfg.driver_alias_file);
        catch, end
    end
    fix_canonicals = {};
    fix_tlas       = {};
    fix_car_nums   = {};
    if ~isempty(fix_driver_map)
        keys = fieldnames(fix_driver_map);
        for ki = 1 : numel(keys)
            e = fix_driver_map.(keys{ki});
            match = ismember(lower(cfg.fix_filter), lower(e.tla)) | ...
                    ismember(lower(cfg.fix_filter), lower(e.num));
            if any(match)
                fix_canonicals{end+1} = e.canonical;  
                fix_tlas{end+1}       = e.tla;       
                fix_car_nums{end+1}   = e.num;      
            end
        end
    end
    if ~isempty(fix_canonicals)
        cfg.driver_filter    = fix_canonicals;
        cfg.ecu_tla_filter   = fix_tlas;
        cfg.split_car_filter = fix_car_nums;
        fprintf('[fix_filter] Restricted to: TLAs=%s  Cars=%s\n', ...
            strjoin(fix_tlas,','), strjoin(fix_car_nums,','));
    else
        fprintf('[fix_filter] WARNING: no alias matches found for: %s\n', ...
            strjoin(cfg.fix_filter,','));
    end
else
    cfg.ecu_tla_filter = {};
end

% =========================================================================
%%  PHASE 1 — TEAMDATA CONCAT
% =========================================================================
if RUN_TEAMDATA_CONCAT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 1 — TeamData concat\n');
    fprintf('%s\n', repmat('=', 1, 60));
    smp_concat_teamdata(cfg);
end
% =========================================================================
%%  PHASE 1a — TEAMDATA CONCAT
% =========================================================================
RUN_TEAMDATA_CONCAT = 1;

if RUN_TEAMDATA_CONCAT
    concat_cfg.event_date          = '2026-06-21';   % event date; files outside tolerance flagged DATE?
    concat_cfg.date_tolerance_days = 0;              % accept files dated ±1 day of event_date
    concat_cfg.flagged_paths       = {};  % cell array of substrings to block; {} = off
    concat_cfg.root_folder       = cfg.root_folder;
    concat_cfg.td_input_dir      = fullfile(cfg.root_folder, '_TeamData');
    concat_cfg.td_hol_output_dir = fullfile(cfg.root_folder, '_HOL');
    concat_cfg.hol_venue         = cfg.hol_event;
    concat_cfg.hol_event         = sprintf('%s%s', cfg.hol_event, cfg.hol_venue);
    concat_cfg.event_alias_file  = cfg.event_alias_file;
    concat_cfg.driver_alias_file = cfg.driver_alias_file;
    concat_cfg.session_filter    = cfg.session_filter;
    concat_cfg.unique_fp         = true;
    concat_cfg.show_report       = true;
    concat_cfg.overwrite         = true;
    concat_cfg.driver_filter     = {};
    concat_cfg.team_filter       = {};
    if strcmp(PHASE1_MODE, 'serial')
        smp_concat_teamdata(concat_cfg);

    else
        % ==============================================================
        %  PARALLEL — one MATLAB instance per driver (or N_WORKERS)
        % ==============================================================

        % ---- Resolve tmp dir ----
        p1_tmp = TMP_DIR;
        if isempty(p1_tmp)
            p1_tmp = fullfile(cfg.root_folder, '_tmp_parallel');
        end
        if ~exist(p1_tmp, 'dir'), mkdir(p1_tmp); end
        delete(fullfile(p1_tmp, 'chunk_*.mat'));
        delete(fullfile(p1_tmp, 'worker_cfg.mat'));
        delete(fullfile(p1_tmp, 'done_*.flag'));

        % ---- Pre-scan to enumerate driver groups (no data loaded) ----
        alias_p1      = smp_alias_load(concat_cfg.event_alias_file);
        driver_map_p1 = smp_driver_alias_load(concat_cfg.driver_alias_file);
        scan_p1       = smp_scan_folders(concat_cfg.td_input_dir);
        if ~isempty(concat_cfg.team_filter)
            keep_p1  = ismember({scan_p1.acronym}, concat_cfg.team_filter);
            scan_p1  = scan_p1(keep_p1);
        end
        to_load_p1 = struct('path', {}, 'team_index', {}, 'team_acronym', {});
        n_tl_p1 = 0;
        for t_p1 = 1 : numel(scan_p1)
            for f_p1 = 1 : numel(scan_p1(t_p1).files)
                n_tl_p1 = n_tl_p1 + 1;
                to_load_p1(n_tl_p1).path         = scan_p1(t_p1).files{f_p1};
                to_load_p1(n_tl_p1).team_index   = scan_p1(t_p1).index;
                to_load_p1(n_tl_p1).team_acronym = scan_p1(t_p1).acronym;
            end
        end
        groups_p1 = smp_append_stints(to_load_p1, driver_map_p1, alias_p1, concat_cfg.session_filter);
        if ~isempty(concat_cfg.driver_filter)
            keep_p1   = ismember(lower({groups_p1.driver}), lower(concat_cfg.driver_filter));
            groups_p1 = groups_p1(keep_p1);
        end
        n_groups_p1 = numel(groups_p1);

        % ---- Resolve worker count ----
        if ischar(N_WORKERS) || N_WORKERS == 0
            n_workers_p1 = n_groups_p1;
        else
            n_workers_p1 = min(N_WORKERS, n_groups_p1);
        end

        fprintf('============================================\n');
        fprintf('  Parallel TeamData Concat\n');
        fprintf('  Groups  : %d\n', n_groups_p1);
        fprintf('  Workers : %d\n', n_workers_p1);
        fprintf('  TMP     : %s\n', p1_tmp);
        fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
        fprintf('============================================\n\n');

        % ---- Split groups across workers ----
        chunk_size_p1 = ceil(n_groups_p1 / n_workers_p1);
        for w = 1 : n_workers_p1
            i_start = (w-1)*chunk_size_p1 + 1;
            i_end   = min(w*chunk_size_p1, n_groups_p1);
            if i_start > n_groups_p1
                worker_groups = groups_p1([]); %#ok<NASGU>
                fprintf('Worker %d: no groups assigned\n', w);
            else
                worker_groups = groups_p1(i_start:i_end); %#ok<NASGU>
                fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
                    w, i_start, i_end, i_end - i_start + 1);
            end
            save(fullfile(p1_tmp, sprintf('chunk_%d.mat', w)), 'worker_groups');
        end

        % ---- Save shared worker cfg (driver_filter cleared — worker sets it) ----
        worker_cfg            = concat_cfg; %#ok<NASGU>
        worker_cfg.driver_filter = {};
        save(fullfile(p1_tmp, 'worker_cfg.mat'), 'worker_cfg');
        fprintf('\n');

        % ---- Launch workers ----
        motec_mp_dir = fileparts(mfilename('fullpath'));
        matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
        win_mode     = 'cmd /c';
        if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
        fprintf('Launching %d worker(s)...\n', n_workers_p1);
        for w = 1 : n_workers_p1
            sys_cmd = sprintf( ...
                'start "SMP Concat Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_concat_teamdata_worker(%d, ''%s'')"', ...
                w, win_mode, matlab_exe, ...
                strrep(motec_mp_dir, '\', '\\'), ...
                w, strrep(p1_tmp, '\', '\\'));
            system(sys_cmd);
            fprintf('  Worker %d launched\n', w);
            pause(1.5);
        end
        fprintf('\nWorkers running — report popups will appear per driver.\n');
        fprintf('done_N.flag written to TMP after each popup is dismissed.\n\n');
    end
end

% Point compiler at HOL output if pre-concat was used
if RUN_TEAMDATA_CONCAT
    COMPILE_DIR = fullfile(cfg.root_folder, '_HOL');
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION)
else
  d  COMPILE_DIR = cfg.root_folder;   % raw _TeamData as before
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION)
end

if RUN_TEAMDATA_CONCAT
    COMPILE_DIR = fullfile(cfg.root_folder, '_HOL');
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION)
    smp_sort_hol_to_teams(COMPILE_DIR_Sesh, cfg.driver_alias_file)
end

% =========================================================================
%%  PHASE 2 — ECU CONCAT - Havenn't Run to get into FINAL FORM 
% =========================================================================
if RUN_ECU_CONCAT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 2 — ECU concat\n');
    fprintf('%s\n', repmat('=', 1, 60));
    smp_concat_ecu_per_driver(cfg);
end

% =========================================================================
%%  PHASE 3 — SPLIT - Only nessacary if sessions are combined
% =========================================================================
if RUN_SPLIT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 3 — Split (ECU + L180 + TeamData)\n');
    fprintf('%s\n', repmat('=', 1, 60));
    smp_split_ecu_by_uptime(cfg);
end

% =========================================================================
%%  PHASE 4 — PAIR ECU + teamData
% =========================================================================
pairs_excel = '';
if RUN_PAIR
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4 — Pair sessions  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.overwrite = true;
    pairs_excel = smp_pair_sessions(cfg);
    cfg.pairs_excel = pairs_excel;
end

% =========================================================================
%%  PHASE 5 — PAIR [ECU;teamData] + L180
% =========================================================================


if RUN_L180_SORT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4b — Sort L180 to HOL  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.l180_input_dir        = 'E:\2026\E06_DAR\L180';   % raw L180 folder
    cfg.move                  = false;                     % copy first, move once confirmed
    cfg.dry_run               = false;
    cfg.event_date            = '2026-06';              % keep files on/around this date (yyyy-mm-dd)
    cfg.date_tolerance_days   = 0;                         % ±N days; 0 = exact date only
    smp_sort_l180_to_hol(cfg);
%     RUN_L180_SORT = false;
end
%%

if RUN_L180
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 5 — Pair L180 onto Combined  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.overwrite = false;
    smp_pair_l180(cfg);
end

fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('smp_pipeline complete.\n');
fprintf('%s\n\n', repmat('=', 1, 60));
%%

smp_plot_pair_check(...
    '/Volumes/JHU/E06_DAR/_TeamData/_HOL/Q17/ALL_2026_Q17.ld', ...
    '/Volumes/JHU/E06_DAR/ECU/HOL/Q17/ALL_2026_Q17.ld', ...
    'ALL Q17');


function smp_plot_pair_check(dash_file, ecu_file, session_label)
% SMP_PLOT_PAIR_CHECK  Visually verify Dash/ECU alignment after xcorr.
% Overlays RPM from both files on a shared time axis.
%
% Usage:
%   smp_plot_pair_check(dash_file, ecu_file)
%   smp_plot_pair_check(dash_file, ecu_file, 'ALL_Q17')

if nargin < 3
    [~, stem] = fileparts(dash_file);
    session_label = stem;
end

% ---- Load Dash RPM ----
fprintf('Loading Dash...\n');
da = motec_ld_reader(dash_file, {'Engine_Speed'}, false);
fn = fieldnames(da);
if isempty(fn)
    error('No usable RPM channel found in Dash file.');
end
ch_a = da.(fn{1});
t_a  = ch_a.time(:);
v_a  = double(ch_a.data(:));
fprintf('  Dash: %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
    fn{1}, ch_a.sample_rate, t_a(end), max(v_a));

% ---- Load ECU RPM ----
fprintf('Loading ECU...\n');
ecu_candidates = {'Engine.Speed', 'Engine_Speed'};
db = [];
for ci = 1:numel(ecu_candidates)
    try
        tmp = motec_ld_reader(ecu_file, {ecu_candidates{ci}}, true);
        fn2 = fieldnames(tmp);
        if ~isempty(fn2) && max(tmp.(fn2{1}).data) > 2500
            db = tmp; break;
        end
    catch, end
end
if isempty(db)
    error('No usable RPM channel found in ECU file.');
end
fn2  = fieldnames(db);
ch_b = db.(fn2{1});
t_b  = ch_b.time(:);
v_b  = double(ch_b.data(:));
fprintf('  ECU:  %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
    fn2{1}, ch_b.sample_rate, t_b(end), max(v_b));

% ---- Run xcorr to get offset ----
fprintf('Running xcorr...\n');
RESAMPLE_HZ = 50;
RPM_MIN     = 500;
dt          = 1 / RESAMPLE_HZ;

t_a_g = (t_a(1):dt:t_a(end))';
t_b_g = (t_b(1):dt:t_b(end))';
v_a_g = interp1(t_a, v_a, t_a_g, 'linear', NaN);
v_b_g = interp1(t_b, v_b, t_b_g, 'linear', NaN);

mask_a = v_a_g >= RPM_MIN & ~isnan(v_a_g);
mask_b = v_b_g >= RPM_MIN & ~isnan(v_b_g);

xc_a = v_a_g; xc_b = v_b_g;
xc_a(~mask_a) = 0; xc_b(~mask_b) = 0;
xc_a(mask_a)  = xc_a(mask_a) - mean(xc_a(mask_a));
xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));

[xc_vals, lags] = xcorr(xc_a, xc_b);
[~, peak_idx]   = max(xc_vals);
lag_samples     = lags(peak_idx);
offset_s        = (t_a(1) - t_b(1)) + lag_samples * dt;

xc_norm = max(abs(xc_vals));
xc_self = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
quality = 0;
if xc_self > 0, quality = xc_norm / xc_self; end

fprintf('  Offset: %+.3f s  |  Quality: %.4f\n', offset_s, quality);

% ---- Plot ----
t_b_aligned = t_b + offset_s;

figure('Name', ['Pair Check: ' session_label], 'Position', [100 100 1400 500]);

% Top: full signal overlay
subplot(2,1,1);
plot(t_a,         v_a, 'b',  'LineWidth', 0.8); hold on;
plot(t_b_aligned, v_b, 'r--','LineWidth', 0.8);
xlabel('Time (s)'); ylabel('RPM');
title(sprintf('%s  |  offset = %+.3fs  |  quality = %.4f', ...
    session_label, offset_s, quality));
legend('Dash (Engine\_Speed)', 'ECU (aligned)', 'Location', 'best');
grid on;

% Bottom: zoomed to first 300s of Dash for fine detail
subplot(2,1,2);
t_zoom = [t_a(1), min(t_a(1)+300, t_a(end))];
plot(t_a,         v_a, 'b',  'LineWidth', 1.0); hold on;
plot(t_b_aligned, v_b, 'r--','LineWidth', 1.0);
xlim(t_zoom);
xlabel('Time (s)'); ylabel('RPM');
title('Zoomed — first 300s of Dash');
legend('Dash', 'ECU (aligned)', 'Location', 'best');
grid on;
end