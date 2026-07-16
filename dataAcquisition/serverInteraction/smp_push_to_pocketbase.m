%% SMP_PUSH_TO_POCKETBASE
% Flatten a compiled SMP cache and upload to local PocketBase instance.
%
% Prerequisites:
%   - PocketBase running: pocketbase.exe serve
%   - lap_stats collection created via pb_create_collection.m
%   - smp_flatten_stats.m on MATLAB path
%
% Usage:
%   Run section by section, or run all at once.
% =========================================================

%% ── CONFIG ──────────────────────────────────────────────────────────────

EVENT_NAME     = 'AGP';
TOP_LEVEL_DIR  = 'E:\2026\02_AGP\_TeamData';
SESSION_FILTER = {'RA4', 'RA5', 'RA6'};

PB_URL         = 'http://127.0.0.1:8090';   % PocketBase local URL
OVERWRITE      = true;    % delete existing rows for this event+session first
DRY_RUN        = false;   % true = print first row JSON only, no writes

%% ── STEP 1: Load cache ───────────────────────────────────────────────────

fprintf('=== SMP Push to PocketBase ===\n');
fprintf('Event    : %s\n', EVENT_NAME);
fprintf('Sessions : %s\n', strjoin(SESSION_FILTER, ', '));
fprintf('Source   : %s\n\n', TOP_LEVEL_DIR);

cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

if ~isfield(cache, 'stats') || isempty(fieldnames(cache.stats))
    error('Cache is empty — run smp_compile_event first.');
end

fprintf('Cache loaded: %d manifest rows, %d group keys.\n\n', ...
    height(cache.manifest), numel(fieldnames(cache.stats)));

%% ── STEP 2: Flatten ──────────────────────────────────────────────────────

fprintf('--- Flattening stats ---\n');
T = smp_flatten_stats(cache, EVENT_NAME);

% Remove id column if present
if ismember('id', T.Properties.VariableNames)
    T = removevars(T, 'id');
end

if isempty(T) || height(T) == 0
    error('Flatten produced no rows.');
end

fprintf('\nPreview (first 3 rows):\n');
disp(T(1:min(3,height(T)), {'event','session','team','driver','manufacturer','lap_number','lap_time'}));

%% ── STEP 3: Upload to PocketBase ─────────────────────────────────────────

import matlab.net.http.*
import matlab.net.http.io.*

endpoint     = [PB_URL '/api/collections/lap_stats/records'];
col_names    = T.Properties.VariableNames;
n_rows       = height(T);
n_uploaded   = 0;
n_failed     = 0;
n_skipped    = 0;

% ── Overwrite: delete existing rows for this event + session ──
if OVERWRITE && ~DRY_RUN
    fprintf('Overwrite mode: deleting existing rows...\n');
    events   = unique(T.event);
    sessions = unique(T.session);
    for ei = 1:numel(events)
        for si = 1:numel(sessions)
            ev = events{ei}; se = sessions{si};
            if isempty(ev) || isempty(se), continue; end
            % PocketBase filter delete — get IDs then delete each
            filter_url = sprintf('%s?filter=(event="%s"%%26%%26session="%s")&perPage=500', ...
                endpoint, ev, se);
            get_req  = RequestMessage('GET', []);
            get_resp = get_req.send(filter_url);
            if double(get_resp.StatusCode) == 200
                items = get_resp.Body.Data.items;
                if ~isempty(items)
                    for k = 1:numel(items)
                        del_url = sprintf('%s/%s', endpoint, items(k).id);
                        del_req = RequestMessage('DELETE', []);
                        del_req.send(del_url);
                    end
                    fprintf('  Deleted %d rows for %s / %s\n', numel(items), ev, se);
                end
            end
        end
    end
end

% ── Upload rows ──────────────────────────────────────────────
if DRY_RUN
    fprintf('\n[DRY RUN] First row JSON:\n');
    s = build_struct(T, col_names, 1);
    fprintf('%s\n', jsonencode(s));
    return;
end

fprintf('\nUploading %d rows to PocketBase...\n', n_rows);
t_start = tic;

for ri = 1:n_rows
    s        = build_struct(T, col_names, ri);
    json_str = jsonencode(s);
    body     = StringProvider(json_str);
    req      = RequestMessage('POST', HeaderField('Content-Type','application/json'), body);
    resp     = req.send(endpoint);
    status   = double(resp.StatusCode);

    if status == 200 || status == 201
        n_uploaded = n_uploaded + 1;
    else
        n_failed = n_failed + 1;
        if n_failed <= 5
            fprintf('  [ERROR] Row %d: HTTP %d\n', ri, status);
        end
    end

    % Progress every 50 rows
    if mod(ri, 50) == 0
        elapsed = toc(t_start);
        rate    = ri / elapsed;
        eta     = (n_rows - ri) / rate;
        fprintf('  %d/%d  (%.0f rows/s  ETA %.0fs)\n', ri, n_rows, rate, eta);
    end
end

elapsed = toc(t_start);
fprintf('\n--- PocketBase upload complete ---\n');
fprintf('  Uploaded : %d\n', n_uploaded);
fprintf('  Failed   : %d\n', n_failed);
fprintf('  Time     : %.1fs  (%.1f rows/s)\n', elapsed, n_rows/elapsed);


% ======================================================================= %
%  HELPER
% ======================================================================= %
function s = build_struct(T, col_names, ri)
    s = struct();
    for ci = 1:numel(col_names)
        col = col_names{ci};
        val = T.(col)(ri);
        if iscell(val), val = val{1}; end
        if isstring(val), val = char(val); end
        % NaN → 0 for PocketBase number fields (PocketBase doesn't accept null in number fields)
        if isnumeric(val) && ~isempty(val) && ~isfinite(val)
            val = 0;
        end
        s.(col) = val;
    end
end
