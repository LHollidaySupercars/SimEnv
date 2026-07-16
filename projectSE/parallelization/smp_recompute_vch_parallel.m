% SMP_RECOMPUTE_VCH_PARALLEL
% Parallel recompute of custom channel (VCH) stats in the session cache.
%
% Re-reads .ld files, reruns smp_custom_channels + smp_gated_channels,
% and overwrites only the custom channel stat fields in cache.stats.
% All other channel stats (Ground_Speed, Brake_Pressure etc.) are untouched.
%
% Usage: run section by section or as a script.

clear; clc;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================
TOP_LEVEL_DIR    = 'E:\2026\02_AGP\_TeamData';

CHANNELS_FILE    = 'C:\SimEnv\dataAcquisition\Motec_MP\channels.xlsx';
EVENT_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
DRIVER_ALIAS_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
SEASON_FILE      = 'C:\SimEnv\trackDB\seasonOverview.xlsx';
GATED_EXCEL      = 'C:\SimEnv\dataAcquisition\Motec_MP\channels\channels.xlsx';

%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================
TRACK          = 'AGP';
SESSION_FILTER = {'RA1', 'RA2', 'RA3'};
N_WORKERS      = 6;

TMP_DIR          = fullfile(tempdir, 'smp_vch_recompute');
POLL_INTERVAL_S  = 3;
TIMEOUT_S        = 3600;

%% =========================================================
%  SECTION 3: LOAD CONFIG
% =========================================================
fprintf('=== SMP Recompute VCH (Parallel) — %s ===\n\n', TRACK);

season     = smp_season_load(SEASON_FILE);
channels   = smp_channel_config_load(CHANNELS_FILE);
alias      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);

[min_lt, max_lt] = smp_season_get(season, TRACK);
fprintf('Lap time limits: %.1fs – %.1fs\n\n', min_lt, max_lt);

%% =========================================================
%  SECTION 4: LOAD CACHE + BUILD GROUP LIST
% =========================================================
cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

if height(cache.manifest) == 0
    error('Cache is empty — nothing to recompute.');
end

% Build group list from manifest (same logic as serial version)
groups = groups_from_manifest(cache.manifest, SESSION_FILTER);
n_groups = numel(groups);
fprintf('%d group(s) to recompute across %d worker(s).\n\n', n_groups, N_WORKERS);

%% =========================================================
%  SECTION 5: SETUP TMP DIR
% =========================================================
if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
delete(fullfile(TMP_DIR, 'vch_chunk_*.mat'));
delete(fullfile(TMP_DIR, 'vch_partial_*.mat'));
delete(fullfile(TMP_DIR, 'vch_done_*.flag'));
delete(fullfile(TMP_DIR, 'vch_worker_cfg.mat'));

% ---- Load gated channel table once ----
try
    T_gated = readtable(GATED_EXCEL, 'Sheet', 'gatedChannels', 'TextType', 'char');
    fprintf('Loaded gated channel definitions: %d row(s)\n', height(T_gated));
catch ME
    warning('Could not read gatedChannels: %s', ME.message);
    T_gated = table();
end

% ---- Save shared worker config ----
worker_cfg.channels_to_extract = channels;
worker_cfg.driver_map          = driver_map;
worker_cfg.min_lt              = min_lt;
worker_cfg.max_lt              = max_lt;
worker_cfg.T_gated             = T_gated;
save(fullfile(TMP_DIR, 'vch_worker_cfg.mat'), 'worker_cfg');

% ---- Split groups into chunks ----
chunk_size = ceil(n_groups / N_WORKERS);
for w = 1:N_WORKERS
    i_start = (w-1)*chunk_size + 1;
    i_end   = min(w*chunk_size, n_groups);
    if i_start > n_groups
        worker_groups = groups([]); %#ok<NASGU>
        fprintf('Worker %d: no groups assigned\n', w);
    else
        worker_groups = groups(i_start:i_end); %#ok<NASGU>
        fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
            w, i_start, i_end, i_end - i_start + 1);
    end
    save(fullfile(TMP_DIR, sprintf('vch_chunk_%d.mat', w)), 'worker_groups');
end
fprintf('\n');

%% =========================================================
%  SECTION 6: LAUNCH WORKERS
% =========================================================
fprintf('Launching %d worker(s)...\n', N_WORKERS);
matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');

for w = 1:N_WORKERS
    sys_cmd = sprintf('start "VCH Worker %d" cmd /k ""%s" -batch "smp_recompute_vch_worker(%d, ''%s'')"', ...
        w, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
    system(sys_cmd);
    fprintf('  Worker %d launched\n', w);
    pause(1.5);
end

%% =========================================================
%  SECTION 7: POLL FOR COMPLETION
% =========================================================
fprintf('\nWaiting for workers...\n\n');
t_start    = tic;
last_count = -1;

while true
    done_flags = dir(fullfile(TMP_DIR, 'vch_done_*.flag'));
    n_done     = numel(done_flags);

    if n_done ~= last_count
        fprintf('[%s]  %d / %d worker(s) done\n', ...
            datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
        last_count = n_done;
    end

    if n_done >= N_WORKERS
        fprintf('\nAll workers finished.\n\n');
        break;
    end

    if toc(t_start) > TIMEOUT_S
        error('Timeout after %ds — check worker windows for errors.', TIMEOUT_S);
    end

    pause(POLL_INTERVAL_S);
end

%% =========================================================
%  SECTION 8: MERGE RESULTS BACK INTO CACHE
% =========================================================
fprintf('Merging partial results into cache...\n');

for w = 1:N_WORKERS
    partial_file = fullfile(TMP_DIR, sprintf('vch_partial_%d.mat', w));
    if ~exist(partial_file, 'file')
        fprintf('  [WARN] Worker %d produced no output — skipping.\n', w);
        continue;
    end

    loaded  = load(partial_file, 'partial');
    partial = loaded.partial;

    keys = fieldnames(partial.vch_stats);
    for k = 1:numel(keys)
        gk = keys{k};
        if ~isfield(cache.stats, gk)
            fprintf('  [WARN] group_key "%s" not in cache — skipping.\n', gk);
            continue;
        end
        vch_keys = fieldnames(partial.vch_stats.(gk));
        for v = 1:numel(vch_keys)
            cache.stats.(gk).(vch_keys{v}) = partial.vch_stats.(gk).(vch_keys{v});
        end
        fprintf('  Merged %d VCH channel(s) into cache.stats.%s\n', numel(vch_keys), gk);
    end
end

%% =========================================================
%  SECTION 9: SAVE CACHE
% =========================================================
fprintf('\nSaving cache...\n');
tic;
smp_cache_save(TOP_LEVEL_DIR, cache, cache.save_mode, alias);
fprintf('Cache saved in %.1fs.\n\n', toc);

fprintf('============================================\n');
fprintf('  Recompute VCH complete  [%s]\n', datestr(now,'HH:MM:SS'));
fprintf('============================================\n');


% ======================================================================= %
%  LOCAL: BUILD GROUP LIST FROM MANIFEST
% ======================================================================= %
function groups = groups_from_manifest(manifest, session_filter)
    groups = struct('key', {}, 'team_acronym', {}, 'driver', {}, ...
                    'session', {}, 'files', {});

    if ~isempty(session_filter)
        keep     = ismember(manifest.Session, session_filter);
        manifest = manifest(keep, :);
    end

    ok       = manifest.LoadOK & ~cellfun(@isempty, manifest.GroupKey);
    manifest = manifest(ok, :);

    if height(manifest) == 0, return; end

    unique_keys = unique(manifest.GroupKey, 'stable');

    for k = 1:numel(unique_keys)
        gk   = unique_keys{k};
        rows = manifest(strcmp(manifest.GroupKey, gk), :);

        g.key          = gk;
        g.team_acronym = rows.TeamAcronym{1};
        g.driver       = rows.Driver{1};
        g.session      = rows.Session{1};
        g.files        = rows.Path;

        groups(end+1) = g; %#ok<AGROW>
    end
end
