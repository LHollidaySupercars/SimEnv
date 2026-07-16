%% SMP_MIGRATE_PB_TO_SQL
% One-time migration: read all data from PocketBase, save .mat backup,
% then insert 1 row to Azure SQL to verify the connection works.
%
% After successful verification, run smp_push_to_sql.m with the full
% table to push all data properly via the compiled cache.
%
% Usage: Run section by section
% =========================================================

%% ── CONFIG ──────────────────────────────────────────────────────────────

PB_URL      = 'http://127.0.0.1:8090';
BACKUP_DIR  = 'C:\PocketBase\backups';       % where to save the .mat backup
BACKUP_FILE = fullfile(BACKUP_DIR, 'pb_backup_AGP.mat');

SQL_TARGET  = 'azure_online';   % 'azure_local' | 'azure_online'

PER_PAGE    = 500;              % PocketBase max per page

%% ── STEP 1: Pull all rows from PocketBase ────────────────────────────────

fprintf('=== SMP PocketBase → SQL Migration ===\n\n');
fprintf('[1/4] Reading all rows from PocketBase...\n');

import matlab.net.http.*

endpoint = [PB_URL '/api/collections/lap_stats/records'];

% ── Get first page to find total count ───────────────────────────────────
url_p1   = sprintf('%s?page=1&perPage=%d', endpoint, PER_PAGE);
req      = RequestMessage('GET', []);
resp     = req.send(url_p1);

if double(resp.StatusCode) ~= 200
    error('Could not reach PocketBase at %s\nStatus: %d\nIs PocketBase running?', ...
        PB_URL, double(resp.StatusCode));
end

total_items = resp.Body.Data.totalItems;
total_pages = resp.Body.Data.totalPages;

fprintf('  Found %d rows across %d page(s).\n', total_items, total_pages);

% ── Collect all pages ─────────────────────────────────────────────────────
all_items = resp.Body.Data.items;

for pg = 2:total_pages
    url_pg   = sprintf('%s?page=%d&perPage=%d', endpoint, pg, PER_PAGE);
    resp_pg  = req.send(url_pg);
    if double(resp_pg.StatusCode) == 200
        page_items = resp_pg.Body.Data.items;
        all_items  = [all_items; page_items]; %#ok
        fprintf('  Page %d/%d fetched (%d rows so far)\n', pg, total_pages, numel(all_items));
    else
        fprintf('  [WARN] Page %d failed with HTTP %d — skipping.\n', pg, double(resp_pg.StatusCode));
    end
end

fprintf('  Total rows retrieved: %d\n', numel(all_items));

%% ── STEP 2: Convert to MATLAB table and save backup ──────────────────────

fprintf('\n[2/4] Converting to MATLAB table and saving backup...\n');

% Convert struct array to table
T_pb = struct2table(all_items);

% Remove PocketBase system columns
pb_system_cols = {'id','collectionId','collectionName','created','updated'};
for ci = 1:numel(pb_system_cols)
    if ismember(pb_system_cols{ci}, T_pb.Properties.VariableNames)
        T_pb = removevars(T_pb, pb_system_cols{ci});
    end
end

fprintf('  Table size: %d rows x %d columns\n', height(T_pb), width(T_pb));

% Save backup
if ~exist(BACKUP_DIR, 'dir')
    mkdir(BACKUP_DIR);
end
save(BACKUP_FILE, 'T_pb', '-v7');
fprintf('  Backup saved: %s\n', BACKUP_FILE);

% Preview
fprintf('\n  Preview (first row, identity columns):\n');
id_cols = {'event','session','team','driver','manufacturer','lap_number','lap_time'};
id_cols_present = id_cols(ismember(id_cols, T_pb.Properties.VariableNames));
disp(T_pb(1, id_cols_present));

%% ── STEP 3: Connect to SQL ───────────────────────────────────────────────

fprintf('\n[3/4] Connecting to SQL (%s)...\n', SQL_TARGET);
fprintf('  >> If a browser window appears, complete MFA authentication.\n\n');

conn = smp_sql_connect(SQL_TARGET);

%% ── STEP 4: Insert 1 row as connectivity test ────────────────────────────

fprintf('\n[4/4] Inserting 1 test row into SQL...\n');

T_test = T_pb(1, :);   % just the first row

% Fix any type issues from PocketBase JSON parsing
% (PocketBase returns numbers as doubles but sometimes as strings)
txt_cols = {'event','venue','session','year','team','team_name','driver', ...
            'car_number','manufacturer','vehicle','group_key','source_file'};
col_names = T_test.Properties.VariableNames;

for ci = 1:numel(col_names)
    col = col_names{ci};
    val = T_test.(col);
    if iscell(val), val = val{1}; end
    if isstring(val), val = char(val); end

    is_text = ismember(col, txt_cols);
    if ~is_text && ischar(val)
        % PocketBase returned a numeric column as string — convert
        num_val = str2double(val);
        if isnan(num_val)
            T_test.(col) = {NaN};
        else
            T_test.(col) = num_val;
        end
    end
end

opts_test            = struct();
opts_test.overwrite  = false;   % don't delete anything for a test
opts_test.batch      = 1;
opts_test.dry_run    = false;

result = smp_push_to_sql(T_test, conn, opts_test);

fprintf('\n=== Migration Test Complete ===\n');
if result.n_uploaded == 1 && result.n_failed == 0
    fprintf('  SUCCESS: 1 row inserted into [dbo].[lap_stats].\n');
    fprintf('  Check in VS Code: right-click lap_stats → Select Top 1000 Rows\n');
    fprintf('\n  When ready to push ALL %d rows, run:\n', height(T_pb));
    fprintf('    opts.overwrite = true;\n');
    fprintf('    result = smp_push_to_sql(T_pb, conn, opts);\n');
else
    fprintf('  FAILED: %d uploaded, %d failed.\n', result.n_uploaded, result.n_failed);
    for i = 1:numel(result.errors)
        fprintf('  ERR: %s\n', result.errors{i});
    end
end

% Keep connection open — you can reuse conn for the full push
% Call conn.close() when completely done
