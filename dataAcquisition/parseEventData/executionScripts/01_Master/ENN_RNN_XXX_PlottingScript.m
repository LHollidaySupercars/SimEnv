%% =========================================================
%  ENN_RNN_PLOTTINGSCRIPT
%  =========================================================
%  Reporting pipeline for one event/session: compile cache (serial or
%  parallel), filter to session(s) of interest, generate plots + PPTX,
%  optionally upload, save cache.
%
%  NOTE: TeamData concat and channel augmentation (custom/gated channels
%  written back to .ld) are handled upstream by the VCS_*_CombineDatasets
%  script. This script assumes _HOL / COM data already exists and only
%  compiles/reports on it.
% =========================================================
clear; clc; close all;
t_script = tic;
%%

% =========================================================================
%  AT-TRACK CONTROLS  — edit these, nothing else
% =========================================================================

cfg.event          = 'ENN';
cfg.track          = 'XXX';
cfg.event_name     = 'XXX';
cfg.team_filter    = {};           % {} = all teams, e.g. {'T8R', 'WAU'}
cfg.session_filter = {'RNN'};
cfg.workshop       = false;        % true = no session filter on stint grouping
cfg.save_cache     = true;
cfg.plotting       = true;
cfg.parallel_save  = true;

cfg.mode           = 'parallel';     % 'serial' | 'parallel'   (compile mode)

% ---- Parallel worker options (ignored in serial mode) ----
cfg.n_workers          = 6;
cfg.tmp_dir            = fullfile(tempdir, 'smp_parallel');
cfg.poll_interval_s    = 3;
cfg.timeout_s          = 3600;
cfg.keep_workers_open  = false;    % false = cmd /c (auto-close on success)
                                    % true  = cmd /k (leave window open — for debugging)

% ---- Upload options ----
cfg.upload_target  = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
cfg.run_upload     = false;
cfg.batch_size     = 200;
cfg.overwrite      = false;

% =========================================================================
%  EVENT CONFIG  — edit when setting up a new event
% =========================================================================
cfg.root_folder      = fullfile('E:\2026',join([cfg.event,'_',cfg.track]) ,'COM');
% cfg.root_folder      = fullfile('E:\2026',join([cfg.event,'_',cfg.track]) ,'_HOL\teamData'); % dirty replacement step to get pitstops
cfg.channels_file    = fullfile(pwd,'dataAcquisition/Motec_MP/channels/channels.xlsx');
cfg.event_alias_file = fullfile(pwd,'dataAcquisition\parseEventData\executionScripts',join([cfg.event,'_',cfg.track]),'eventAlias.xlsx');
cfg.driver_alias_file= fullfile(pwd,'dataAcquisition/Motec_MP/alias/driverAlias.xlsx');
cfg.plot_config_files= {fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['PR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx'])),...
                        fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['AR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx'])),...
                        fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['SR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx']))};
cfg.season_file      = fullfile(pwd,'trackDB/seasonOverview.xlsx');
cfg.pptx_template    = fullfile(pwd,'dataAcquisition/Motec_MP/plot/templates/SuperCars_PPT.pptx');
cfg.output_dir       = fullfile(pwd,'dataAcquisition/Motec_MP/plot/output',join([cfg.event,'_',cfg.track]));
cfg.date_from        = SESSIONDATE_DATETIME;   % auto-filled from sessionDate.xlsx (this session's date)
% cfg.plot_config_files= {'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\E07_TSV\PR_E07TSV_plotRequest.xlsx',...
% ---- Tuning defaults (rarely changed) ----
cfg.max_traces        = 4;
cfg.dist_n_points     = 1000;
cfg.dist_channel      = 'Odometer';
cfg.br2_channel       = 'BR2_Beacon_Number';
cfg.br2_protocol      = 'standard';    % 'standard' | 'TAS2025'
cfg.fcy_channel       = 'Sw_State_SC'; % Full Course Yellow flag channel
cfg.detect_pitlane    = true;
cfg.load_all_channels = false;          % true = load full file, no channel filter
cfg.show_concat_report= false;

% =========================================================================
%  PHASE DETERMINATION
% =========================================================================
PHASE_1_CONFIG_RUN   = true;
PHASE_2_COMPILE_RUN  = true;
PHASE_3_PLOT_RUN     = true;
PHASE_4_SAVE_RUN     = true;
PHASE_5_TYRE_CHANGE  = true;

% =========================================================================
%  DERIVED  — built automatically by resolve_cfg_plotting, do not edit
% =========================================================================
cfg = resolve_cfg_plotting(cfg);

fprintf('=== %s Report — %s ===\n\n', upper(cfg.mode), cfg.track);

% =========================================================================

% =========================================================================
%%  PHASE 1: LOAD CONFIG FILES
% =========================================================================
if PHASE_1_CONFIG_RUN
season                    = smp_season_load(cfg.season_file);
[channels, channel_rules] = smp_channel_config_load(cfg.channels_file);
alias                     = smp_alias_load(cfg.event_alias_file);
driver_map                = smp_driver_alias_load(cfg.driver_alias_file);
T_gated                   = readtable(cfg.channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');

% ---- compile_opts: everything smp_compile_event needs ----
compile_opts = build_compile_opts(cfg, channel_rules, T_gated);

% ---- plot_opts ----
plot_opts.fig_width  = 1200;
plot_opts.fig_height = 650;
plot_opts.font_size  = 11;
plot_opts.n_laps_avg = 3;
plot_opts.verbose    = true;
plot_opts.venue      = cfg.track;
end

% =========================================================================
%%  PHASE 2: COMPILE
%  Run this cell when you have new/changed .ld files.
%  Already-cached files are skipped automatically.
% =========================================================================
if PHASE_2_COMPILE_RUN
tic;
[needed_channels, channel_ops_map] = smp_build_required_stats(cfg.plot_config_files);

% ---- Infrastructure channels the pipeline needs internally, regardless
%      of what's actually plotted ----
INFRA_REQUIRED = {'Lap_Number', 'Lap_Time', 'Beacon', ...
                   'Ground_Speed', 'Corr_Dist', 'Odometer', ...
                   'GPS_Time', 'Speedkmh', 'Speed', ...
                   'Lateral_Acc', 'Longitudinal_Acc', ...
                   'Engine_Speed', 'Engine_RPM', 'RPM'};

% channel_rules-driven cleaning targets — pulled directly from the config,
% not hardcoded, since this list is Excel-driven and can change.
if ~isempty(channel_rules)
    rule_channels = {channel_rules.channel};
    INFRA_REQUIRED = union(INFRA_REQUIRED, rule_channels);
end

channels = union(needed_channels, INFRA_REQUIRED);

cfg.mode = 'serial';                                                      
cfg.diarrhea_mode = true;
cfg.flush_every_n = 1;
cfg.n_workers     = 2;
cfg.channel_ops_map = channel_ops_map;   % <-- NEW: carried on cfg from here on


% ---- Debug scope: only the troublesome L180 team(s) ----
cfg.team_filter = {};   % <-- replace with the actual team acronym(s) from job 1 / job 4's log

if strcmp(cfg.mode, 'serial')
    compile_opts.beacon_check = true;
    compile_opts.l180_mode       = 'keep_separate';
    compile_opts.channel_ops_map = cfg.channel_ops_map;   % <-- NEW
    cache = smp_compile_serial(cfg, compile_opts, channels, season, driver_map, alias);
    
elseif strcmp(cfg.mode, 'parallel')
    compile_opts.l180_mode       = 'keep_separate';
    cache = smp_compile_parallel(cfg, compile_opts, channels, channel_rules, season, driver_map, alias);
else
    warning('Unknown cfg.mode "%s" — use ''serial'' or ''parallel''.', cfg.mode);
end
parallelCompile = toc;
end

% =========================================================================
%%  PHASE 3: PLOTS + POWERPOINT 
% =========================================================================
if PHASE_3_PLOT_RUN
    SMP_filtered = smp_filter_cache(cache, alias, 'Session', cfg.session_filter);
    smp_filter_summary(SMP_filtered);

    if cfg.plotting
        PLOT = true;
        CLOSEALL = false;
        run_plotting(cfg, SMP_filtered, driver_map, plot_opts, PLOT, CLOSEALL);
    end
end

%% =========================================================================
%  SECTION 5a: SAVE CACHE
% =========================================================================
if PHASE_4_SAVE_RUN
    t_script = tic;
    if cfg.save_cache
        fprintf('\nSaving cache...\n');
        try
            if isfield(cfg, 'parallel_save') && cfg.parallel_save
                smp_save_parallel(cfg.root_folder, cache, compile_opts.save_mode, alias, cfg);
            else
                smp_cache_save(cfg.root_folder, cache, compile_opts.save_mode, alias);
            end
            fprintf('Cache saved.\n');
        catch ME_save
            fprintf('[ERROR] Cache save failed: %s\n', ME_save.message);
        end
    end
    
    fprintf('\n=== Total time: %.1f minutes (%.0f seconds) ===\n', ...
        toc(t_script)/60, toc(t_script));
end

%% =========================================================================
%  PHASE 5: TYRE CHANGES
    pit_summary = smp_tyre_changes_from_cache(cache, driver_map);
    disp(pit_summary);
    saveLocation =fullfile(pwd,'dataAcquisition\parseEventData\pitStop', join([cfg.event, '_',cfg.track], '_'));
    if ~isfolder(saveLocation)
        mkdir(saveLocation)
    end
    function cfg = resolve_cfg_plotting(cfg)
    % RESOLVE_CFG_PLOTTING  Derive compile paths from event config.
    %   Assumes _HOL concat + team-sort has already been done by the
    %   VCS_*_CombineDatasets script — this script only compiles from it.
        cfg.compile_dir      = fullfile(cfg.root_folder);
        cfg.compile_dir_sesh = fullfile(cfg.compile_dir, cfg.session_filter{1});
    end
end


function compile_opts = build_compile_opts(cfg, channel_rules, T_gated)
% BUILD_COMPILE_OPTS  Assemble the options struct passed to smp_compile_event.
    compile_opts.mode              = 'stream';
    compile_opts.track             = cfg.track;
    compile_opts.max_traces        = cfg.max_traces;
    compile_opts.dist_n_points     = cfg.dist_n_points;
    compile_opts.dist_channel      = cfg.dist_channel;
    compile_opts.verbose           = true;
    compile_opts.date_from         = cfg.date_from;
    compile_opts.saveCache         = true;
    compile_opts.save_mode         = 'session';   % 'legacy' | 'session'
    compile_opts.session_filter    = cfg.session_filter;
    compile_opts.load_all_channels = cfg.load_all_channels;
    compile_opts.concat_csv_dir    = cfg.output_dir;   % '' = skip CSV
    compile_opts.showConcatReport  = cfg.show_concat_report;
    compile_opts.br2_channel       = cfg.br2_channel;
    compile_opts.br2_protocol      = cfg.br2_protocol;
    compile_opts.channel_rules     = channel_rules;
    compile_opts.detect_pitlane    = cfg.detect_pitlane;
    compile_opts.fcy_channel       = cfg.fcy_channel;
    compile_opts.beacon_check      = false;   % overridden to true for serial mode
    compile_opts.T_gated           = T_gated; % gated channels computed during compile
    if isfield(cfg, 'l180_mode') && ~isempty(cfg.l180_mode)
        compile_opts.l180_mode = cfg.l180_mode;
    else
        compile_opts.l180_mode = 'drop_duplicate';
    end
end



function cache = smp_compile_serial(cfg, compile_opts, channels, season, driver_map, alias)
% SMP_COMPILE_SERIAL  Serial compile of cfg.compile_dir_sesh.
%   Sorts cfg.team_filter by total on-disk .ld size (largest first) before
%   compiling, so heavy files are hit early — useful for debugging, since
%   crashes tied to file/channel size surface sooner instead of waiting
%   through lighter teams first.

cfg.team_filter = sort_teams_by_size(cfg.team_filter, cfg.compile_dir_sesh);

cache = smp_compile_event(cfg.compile_dir_sesh, cfg.team_filter, channels, ...
    season, driver_map, alias, compile_opts);
end


% ======================================================================= %
function sorted_teams = sort_teams_by_size(team_filter, compile_dir_sesh)
% SORT_TEAMS_BY_SIZE  Order team acronyms by total .ld bytes on disk,
%   largest first. Falls back to the original order if team_filter is
%   empty (process-all mode) or no files are found for a team.

if isempty(team_filter)
    sorted_teams = team_filter;
    return;
end

n = numel(team_filter);
team_bytes = zeros(n, 1);

for i = 1:n
    team_acro = team_filter{i};
    % Team folders are typically named like "01_T8R" — match by
    % acronym suffix so this works regardless of the numeric prefix.
    team_dirs = dir(fullfile(compile_dir_sesh, ['*' team_acro]));
    team_dirs = team_dirs([team_dirs.isdir]);

    total_bytes = 0;
    for d = 1:numel(team_dirs)
        ld_files = dir(fullfile(compile_dir_sesh, team_dirs(d).name, '**', '*.ld'));
        total_bytes = total_bytes + sum([ld_files.bytes]);
    end
    team_bytes(i) = total_bytes;
end

[~, order]    = sort(team_bytes, 'descend');
sorted_teams  = team_filter(order);

fprintf('smp_compile_serial: team order by size (largest first):\n');
for i = 1:numel(sorted_teams)
    fprintf('  %-6s  %.1f MB\n', sorted_teams{i}, team_bytes(order(i)) / 1e6);
end
fprintf('\n');
end


function run_plotting(cfg, SMP_filtered, driver_map, plot_opts, PLOT, CLOSEALL)
% RUN_PLOTTING  Generate plots + PPTX for each configured plot-request file.
    if iscell(cfg.session_filter)
        session_str = strjoin(cfg.session_filter, '_');
    else
        session_str = cfg.session_filter;
    end
    team_str         = strjoin(cfg.team_filter, '_'); %#ok<NASGU>
    base_report_name = sprintf('26VCS_%s%s_%s', cfg.event, cfg.track, session_str); %#ok<NASGU>

    plot_config_files = cfg.plot_config_files;
    if ischar(plot_config_files)
        plot_config_files = {plot_config_files};
    end

    for k = 1:numel(plot_config_files)
        fprintf('\n=== Report %d/%d: %s ===\n', k, numel(plot_config_files), plot_config_files{k});

        plots    = smp_plot_config_load(plot_config_files{k});
        holdFigs = smp_plot_from_config(SMP_filtered, plots, smp_colours(), driver_map, plot_opts);

        handles = unique([holdFigs{~cellfun(@isempty, holdFigs)}]);
        set(handles, 'Visible', 'off');
        if PLOT
        smp_generate_pptx_report(holdFigs, plots, cfg.pptx_template, cfg.output_dir, ...
                                  base_report_name, plot_config_files{k}, ...
                                  cfg.session_filter, cfg.team_filter, cfg.track);
        end
        if CLOSEALL
            close all;
        end
    end
end