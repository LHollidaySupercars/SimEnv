%% SMP_PUSH_TO_SUPABASE
% Flatten an existing compiled cache and upload to Supabase lap_stats table.
%
% Prerequisites:
%   - cache already compiled (smp_compile_event) and saved to disk
%   - supabase_setup.sql has been run in Supabase SQL Editor
%   - smp_flatten_stats.m and smp_upload_supabase.m are on the MATLAB path
%
% Workflow:
%   1. Load cache from disk  (fast — no .ld re-reading)
%   2. Flatten stats to a per-lap MATLAB table
%   3. Upload to Supabase in batches
% =========================================================

%% ── CONFIG ──────────────────────────────────────────────────────────────

% Event label stored in every row of the DB (used for filtering in dashboard)
EVENT_NAME     = 'AGP';

% Path to your compiled team data folder (same as TOP_LEVEL_DIR in main_smp_report)
TOP_LEVEL_DIR  = 'E:\2026\02_AGP\_TeamData';

% Sessions to push — must match the session strings in your cache
% Leave empty {} to push ALL sessions currently loaded
SESSION_FILTER = {'RA4', 'RA5', 'RA6'};

% Supabase credentials
% Leave blank to read from environment variables SMP_SUPABASE_URL / SMP_SUPABASE_KEY
% or to be prompted interactively
SB_URL = 'https://vwrsistiqkqpucuzvcrp.supabase.co';   % e.g. 'https://xxxxxxxxxxxx.supabase.co'
SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3cnNpc3RpcWtxcHVjdXp2Y3JwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDU1NDMyMywiZXhwIjoyMDkwMTMwMzIzfQ.uIflsPWDrsyVDJGWQKxhNx600rlYZWOFc9DOs2_z3zo';   % service_role key from Project Settings → API

% Upload behaviour
OVERWRITE  = true;   % delete existing rows for this event+session before uploading
BATCH_SIZE = 150;    % rows per POST — reduce if you hit timeouts
DRY_RUN    = false;  % true = print JSON only, no DB writes

%% ── STEP 1: Load cache ───────────────────────────────────────────────────

fprintf('=== SMP Push to Supabase ===\n');
fprintf('Event      : %s\n', EVENT_NAME);
fprintf('Sessions   : %s\n', strjoin(SESSION_FILTER, ', '));
fprintf('Source     : %s\n\n', TOP_LEVEL_DIR);

cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

% Basic validation
if ~isfield(cache, 'stats') || isempty(fieldnames(cache.stats))
    error('Cache is empty or has no stats — run smp_compile_event first.');
end

if ~isfield(cache, 'manifest') || height(cache.manifest) == 0
    error('Cache manifest is empty.');
end

fprintf('Cache loaded: %d manifest rows, %d group keys.\n\n', ...
    height(cache.manifest), numel(fieldnames(cache.stats)));

%% ── STEP 2: Flatten stats to per-lap table ───────────────────────────────

fprintf('--- Flattening stats ---\n');
T = smp_flatten_stats(cache, EVENT_NAME);

if isempty(T) || height(T) == 0
    error('Flatten produced no rows.');
end

% Preview
fprintf('\nPreview (first 3 rows, identity columns only):\n');
id_cols = {'event','session','team','driver','manufacturer','lap_number','lap_time'};
disp(T(1:min(3, height(T)), id_cols));

%% ── STEP 3: Upload to Supabase ───────────────────────────────────────────

upload_opts.url       = SB_URL;
upload_opts.key       = SB_KEY;
upload_opts.table     = 'lap_stats';
upload_opts.batch     = BATCH_SIZE;
upload_opts.overwrite = OVERWRITE;
upload_opts.dry_run   = DRY_RUN;

fprintf('\n--- Uploading ---\n');
result = smp_upload_supabase(T, upload_opts);

if result.n_failed == 0
    fprintf('\nSuccess: %d rows uploaded.\n', result.n_uploaded);
else
    fprintf('\nCompleted with errors: %d uploaded, %d failed.\n', ...
        result.n_uploaded, result.n_failed);
end