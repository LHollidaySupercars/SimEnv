function result = smp_push_to_sql(T, conn, opts)
% SMP_PUSH_TO_SQL  Upload a flattened lap stats table to SQL Server via JDBC,
% storing it in the narrow/long schema (dbo.Channels/Sessions/Drivers/LapStats)
% instead of a wide one-column-per-channel-stat table.
%
% Replaces the old wide-table approach: no more dynamic ALTER TABLE, no
% more INSERT/UPDATE splitting for SQL Server's 2100-parameter limit — the
% narrow LapStats row is only 8 columns wide, so a single INSERT statement
% comfortably covers a full batch regardless of channel count.
%
% Usage:
%   conn   = smp_sql_connect('azure_online');
%   result = smp_push_to_sql(T, conn)
%   result = smp_push_to_sql(T, conn, opts)
%
% Inputs:
%   T       - MATLAB table from smp_flatten_stats() (wide, one row per lap,
%             one column per "<channel>_<stat>") — melted internally via
%             smp_melt_lap_stats.m before upload.
%   conn    - JDBC connection from smp_sql_connect()
%   opts    - optional struct:
%     .batch      double   rows per batch commit (default: 5000)
%     .mode       char     what to do with lap+channel rows already stored
%                          for a session+driver (checked on the server):
%                            'add_missing'      (default) insert only new
%                                               lap+channel rows, leave stored ones alone
%                            'replace_channels' insert new rows and overwrite
%                                               stored lap+channel rows; other
%                                               channels on the lap are kept
%                            'replace_all'      wipe the session+driver, then insert
%     .channels   cellstr  replace_channels only: restrict overwrite to these
%                          channel names (default: all channels in the upload)
%     .overwrite  logical  legacy: true = mode 'replace_all', false = 'add_missing'
%                          (ignored when .mode is set)
%     .dry_run    logical  print first row preview only, no writes (default: false)
%
% Output:
%   result.n_uploaded   rows successfully inserted
%   result.n_failed     rows that failed
%   result.errors       cell array of error messages
%
% =========================================================

    if nargin < 3, opts = struct(); end

    batch_size = get_opt(opts, 'batch',     5000);
    overwrite  = get_opt(opts, 'overwrite', false);
    dry_run    = get_opt(opts, 'dry_run',   false);
    append_only = get_opt(opts, 'append_only', false);  % replace_all only: an earlier chunk already wiped this session+driver
    only_channels = get_opt(opts, 'channels', {});

    % Legacy callers only set overwrite: true meant wipe-and-replace, false now means add-only.
    mode = get_opt(opts, 'mode', '');
    if isempty(mode)
        if overwrite, mode = 'replace_all'; else, mode = 'add_missing'; end
    end
    mode = lower(char(mode));
    if ~ismember(mode, {'add_missing', 'replace_channels', 'replace_all'})
        error('smp_push_to_sql:mode', 'Unknown opts.mode ''%s''.', mode);
    end

    result.n_uploaded = 0;
    result.n_failed   = 0;
    result.n_replaced = 0;   % lap+channel combos overwritten (replace_channels)
    result.n_skipped  = 0;   % rows left untouched because they were already stored
    result.pairs      = zeros(0, 2);   % [SessionID DriverID] written; used when the LapSeries rebuild is deferred
    result.errors     = {};

    % ── 1. Unpivot the wide per-lap table into narrow LapStats rows ──────
    % T may already be narrow (e.g. smp_compile_event_upload.m now melts
    % each file's stats before buffering) — detect that and skip re-melting,
    % so both narrow-buffer callers and legacy wide-table callers (e.g.
    % smp_migrate_lap_stats_to_narrow.m) work unchanged.
    already_narrow = all(ismember({'ChannelName','StatType'}, T.Properties.VariableNames));
    if already_narrow
        L = T;
    else
        L = smp_melt_lap_stats(T);
    end
    if isempty(L) || height(L) == 0
        fprintf('smp_push_to_sql: nothing to upload (melt produced 0 rows).\n');
        return;
    end
    n_rows = height(L);

    if dry_run
        fprintf('[DRY RUN] First row preview:\n');
        row1 = L(1, :);
        for ci = 1:width(row1)
            fprintf('  %-15s = %s\n', row1.Properties.VariableNames{ci}, format_val(row1{1, ci}));
        end
        fprintf('  ... %d row(s) total after unpivot.\n', n_rows);
        return;
    end

    % ── Single transaction for the WHOLE operation ───────────────────────
    % Resolve-IDs, version-check deletes, AND inserts must all succeed or
    % all roll back together — autocommit is disabled here, BEFORE any
    % writes happen (previously this was only disabled right before the
    % INSERT phase, so the version-check DELETEs ran under the
    % connection's default autocommit=true and were committed permanently
    % the instant they executed, with no relationship to whether the
    % subsequent INSERT phase succeeded. A failed insert's rollback could
    % not undo an already-autocommitted delete, so a bad insert after a
    % delete would silently wipe data with nothing to replace it — this
    % is what emptied the table previously. Now nothing is durable until
    % the single commit at the end of the chunk (see below), and any
    % exception anywhere in resolve/delete/insert rolls back
    % everything not yet committed.
    conn.setAutoCommit(false);
    t_start = tic;
    tm = struct('resolve', 0, 'version', 0, 'marshal', 0, 'execute', 0, 'series', 0);
    t_stage = tic;

    try
        % LapStats v2 (see sql/migrate_lapstats_v2.sql) keeps MathVersion/SourceFile in
        % dbo.SessionDriverUpload instead of on every stat row; this works with either layout.
        has_meta_cols = lapstats_has_meta_cols(conn);

        % ── 2. Resolve Channels / Sessions / Drivers (lookup-or-insert) ──
        fprintf('[%s] Resolving lookup IDs...\n', datestr(now, 'HH:MM:SS'));
        channel_keys = unique_rows(table(L.ChannelName, 'VariableNames', {'Name'}));
        channel_map  = smp_resolve_ids(conn, 'Channels', 'ChannelID', {'Name'}, channel_keys);

        session_keys = unique_rows(table(L.EventName, L.Venue, L.SessionName, L.Year, ...
            'VariableNames', {'EventName','Venue','SessionName','Year'}));
        session_map  = smp_resolve_ids(conn, 'Sessions', 'SessionID', ...
            {'EventName','Venue','SessionName','Year'}, session_keys);

        driver_keys = unique_rows(table(L.DriverName, L.Team, L.Year, L.CarNumber, L.Manufacturer, ...
            'VariableNames', {'DriverName','Team','Year','CarNumber','Manufacturer'}));
        driver_map_ids = smp_resolve_ids(conn, 'Drivers', 'DriverID', {'DriverName','Team','Year'}, ...
            driver_keys, {'CarNumber','Manufacturer'});
        % Commit the lookup rows now so parallel workers don't block on this transaction's locks for the whole upload; they are idempotent, so they never need rolling back.
        conn.commit();
        tm.resolve = toc(t_stage); t_stage = tic;
        fprintf('[%s] Resolved %d channel(s), %d session(s), %d driver(s) in %.1fs.\n', datestr(now, 'HH:MM:SS'), ...
            height(channel_keys), height(session_keys), height(driver_keys), tm.resolve);

        % ── 3. Decide per (lap, channel) what to insert / replace / skip ──
        % Existence is checked on the server per session+driver, at lap+channel level:
        %   add_missing      insert rows whose lap+channel isn't stored; leave stored ones alone
        %   replace_channels insert new rows AND overwrite stored lap+channel rows (opts.channels
        %                    limits the overwrite; unlisted stored channels are left alone)
        %   replace_all      delete the whole session+driver first, then insert everything
        sid_v = map_ids(L, {'EventName','Venue','SessionName','Year'}, session_map);
        did_v = map_ids(L, {'DriverName','Team','Year'}, driver_map_ids);
        cid_v = map_ids(L, {'ChannelName'}, channel_map);

        sess_driver_pairs = unique_rows(table(L.EventName, L.Venue, L.SessionName, L.Year, ...
            L.DriverName, L.Team, 'VariableNames', ...
            {'EventName','Venue','SessionName','Year','DriverName','Team'}));

        stmt = conn.createStatement();
        if strcmp(mode, 'replace_all')
            % append_only: an earlier chunk of this pair already wiped it, don't wipe that chunk's rows.
            if ~append_only
                for pi = 1:height(sess_driver_pairs)
                    sid = lookup_id(session_map, {sess_driver_pairs.EventName{pi}, sess_driver_pairs.Venue{pi}, ...
                        sess_driver_pairs.SessionName{pi}, sess_driver_pairs.Year{pi}});
                    did = lookup_id(driver_map_ids, {sess_driver_pairs.DriverName{pi}, sess_driver_pairs.Team{pi}, sess_driver_pairs.Year{pi}});
                    if isnan(sid) || isnan(did), continue; end
                    rows_del = stmt.executeUpdate(sprintf( ...
                        'DELETE FROM [dbo].[LapStats] WHERE SessionID = %d AND DriverID = %d', sid, did));
                    fprintf('  Staged delete of %d row(s) for SessionID=%d DriverID=%d (replace_all)\n', rows_del, sid, did);
                end
            end
        else
            % Existing lap+channel keys for every pair in this upload.
            existing_keys = strings(0, 1);
            for pi = 1:height(sess_driver_pairs)
                sid = lookup_id(session_map, {sess_driver_pairs.EventName{pi}, sess_driver_pairs.Venue{pi}, ...
                    sess_driver_pairs.SessionName{pi}, sess_driver_pairs.Year{pi}});
                did = lookup_id(driver_map_ids, {sess_driver_pairs.DriverName{pi}, sess_driver_pairs.Team{pi}, sess_driver_pairs.Year{pi}});
                if isnan(sid) || isnan(did), continue; end
                rs = stmt.executeQuery(sprintf(['SELECT DISTINCT LapNumber, ChannelID FROM [dbo].[LapStats] ' ...
                    'WHERE SessionID = %d AND DriverID = %d'], sid, did));
                while rs.next()
                    existing_keys(end+1, 1) = sprintf('%d|%d|%d|%d', sid, did, rs.getInt(1), rs.getInt(2)); %#ok<AGROW>
                end
                rs.close();
            end

            row_keys    = compose("%d|%d|%d|%d", sid_v, did_v, double(L.LapNumber), cid_v);
            is_existing = ismember(row_keys, existing_keys);

            if strcmp(mode, 'add_missing')
                keep_mask = ~is_existing;
            else  % replace_channels
                if isempty(only_channels)
                    in_scope = true(height(L), 1);
                else
                    in_scope = ismember(string(L.ChannelName), string(only_channels));
                end
                keep_mask  = ~is_existing | in_scope;      % stored + out of scope -> leave alone
                to_replace = is_existing & in_scope;
                if any(to_replace)
                    % Delete only the lap+channel combos being re-uploaded; other channels on the lap stay.
                    [~, first_idx] = unique(row_keys(to_replace), 'stable');
                    rep_rows = find(to_replace);
                    rep_rows = rep_rows(first_idx);
                    dstmt = conn.prepareStatement(['DELETE FROM [dbo].[LapStats] ' ...
                        'WHERE SessionID = ? AND DriverID = ? AND LapNumber = ? AND ChannelID = ?']);
                    for k = 1:numel(rep_rows)
                        ri = rep_rows(k);
                        dstmt.setInt(1, sid_v(ri));
                        dstmt.setInt(2, did_v(ri));
                        dstmt.setInt(3, double(L.LapNumber(ri)));
                        dstmt.setInt(4, cid_v(ri));
                        dstmt.addBatch();
                    end
                    dstmt.executeBatch();
                    dstmt.close();
                    result.n_replaced = numel(rep_rows);
                    fprintf('  Staged replace of %d lap+channel combo(s).\n', numel(rep_rows));
                end
            end

            result.n_skipped = sum(~keep_mask);
            if result.n_skipped > 0
                fprintf('  %d row(s) left as stored (already on server) — excluded from this upload.\n', result.n_skipped);
            end
            L     = L(keep_mask, :);
            sid_v = sid_v(keep_mask);
            did_v = did_v(keep_mask);
            cid_v = cid_v(keep_mask);
            n_rows = height(L);
        end
        stmt.close();

        if n_rows == 0
            % Commit pending resolve-id inserts so the connection isn't left mid-transaction.
            conn.commit();
            conn.setAutoCommit(true);
            fprintf('smp_push_to_sql: everything already up to date — nothing to insert.\n');
            return;
        end

        tm.version = toc(t_stage); t_stage = tic;

        % ── 4. Batched INSERT into dbo.LapStats ──────────────────────────
        if has_meta_cols
            insert_sql = ['INSERT INTO [dbo].[LapStats] ' ...
                '(SessionID, DriverID, LapNumber, ChannelID, StatType, Value, MathVersion, SourceFile) ' ...
                'VALUES (?, ?, ?, ?, ?, ?, ?, ?)'];
        else
            insert_sql = ['INSERT INTO [dbo].[LapStats] ' ...
                '(SessionID, DriverID, LapNumber, ChannelID, StatType, Value) ' ...
                'VALUES (?, ?, ?, ?, ?, ?)'];
        end

        fprintf('Uploading %d row(s) to [dbo].[LapStats] in batches of %d...\n', n_rows, batch_size);

        pstmt = conn.prepareStatement(insert_sql);

        % sid_v/did_v/cid_v were resolved (and filtered alongside L) in step 3.
        bad   = isnan(sid_v) | isnan(did_v) | isnan(cid_v);
        bad_idx = find(bad);
        result.n_failed = result.n_failed + numel(bad_idx);
        for k = 1:min(numel(bad_idx), 20)
            ri = bad_idx(k);
            result.errors{end+1} = sprintf('Row %d: unresolved ID (session=%d, driver=%d, channel=%d)', ...
                ri, sid_v(ri), did_v(ri), cid_v(ri));
        end
        good = find(~bad);
        n_good = numel(good);

        lap_v  = double(L.LapNumber);
        stat_v = cellstr(L.StatType);
        val_v  = double(L.Value);
        if has_meta_cols
            mv_v = cellstr(L.MathVersion);
            sf_v = cellstr(L.SourceFile);
        end

        n_pending = 0;
        for gi = 1:n_good
            ri = good(gi);
            pstmt.setInt(1, sid_v(ri));
            pstmt.setInt(2, did_v(ri));
            pstmt.setInt(3, lap_v(ri));
            pstmt.setInt(4, cid_v(ri));
            pstmt.setString(5, stat_v{ri});
            if isnan(val_v(ri))
                pstmt.setNull(6, java.sql.Types.FLOAT);
            else
                pstmt.setDouble(6, val_v(ri));
            end
            if has_meta_cols
                set_nullable_string(pstmt, 7, mv_v{ri});
                set_nullable_string(pstmt, 8, sf_v{ri});
            end
            pstmt.addBatch();
            n_pending = n_pending + 1;

            if n_pending == batch_size || gi == n_good
                t_exec = tic;
                execute_batch(pstmt, n_pending);
                tm.execute = tm.execute + toc(t_exec);
                result.n_uploaded = result.n_uploaded + n_pending;
                n_pending = 0;
                elapsed = toc(t_start);
                rate    = gi / elapsed;
                eta     = (n_good - gi) / max(rate, 0.1);
                fprintf('  %d/%d  (%.0f rows/s  ETA %.0fs)\n', gi, n_good, rate, eta);
            end
        end
        tm.marshal = toc(t_stage) - tm.execute;

        pstmt.close();

        % v2 layout: record MathVersion/SourceFile once per session+driver.
        if ~has_meta_cols
            fprintf('[%s] Recording upload metadata...\n', datestr(now, 'HH:MM:SS'));
            upsert_session_driver_upload(conn, L, session_map, driver_map_ids);
        end
        % Mark touched pairs unbuilt so the dashboard falls back to LapStats until BuildLapSeries re-runs.
        touched = lapseries_pairs(L, session_map, driver_map_ids);
        if ~isempty(touched)
            inv = conn.prepareStatement(['IF OBJECT_ID(''dbo.LapSeriesLaps'', ''U'') IS NOT NULL ' ...
                'DELETE FROM [dbo].[LapSeriesLaps] WHERE SessionID = ? AND DriverID = ?']);
            for k = 1:size(touched, 1)
                inv.setInt(1, touched(k, 1));
                inv.setInt(2, touched(k, 2));
                inv.addBatch();
            end
            inv.executeBatch();
            inv.close();
        end
        % One commit for the whole chunk (deletes + inserts + upsert): all-or-nothing.
        fprintf('[%s] Committing %d row(s)...\n', datestr(now, 'HH:MM:SS'), result.n_uploaded);
        t_commit = tic;
        conn.commit();
        fprintf('[%s] Committed in %.1fs.\n', datestr(now, 'HH:MM:SS'), toc(t_commit));
    catch ME
        % A dead connection makes rollback throw too, which would hide the original error.
        try, conn.rollback(); conn.setAutoCommit(true); catch, end %#ok<NOCOM>
        error('smp_push_to_sql: Fatal error during upload — all deletes and inserts in this batch were rolled back.\n%s', ME.message);
    end
    conn.setAutoCommit(true);

    t_stage = tic;
    result.pairs = lapseries_pairs(L, session_map, driver_map_ids);
    if get_opt(opts, 'skip_lapseries', false)
        % Parallel workers share the server's write capacity; the orchestrator rebuilds once they are all done.
        fprintf('[%s] LapSeries rebuild deferred for %d session+driver pair(s).\n', datestr(now, 'HH:MM:SS'), size(result.pairs, 1));
    else
        fprintf('[%s] Rebuilding LapSeries (dashboard read layout)...\n', datestr(now, 'HH:MM:SS'));
        rebuild_lap_series(conn, L, session_map, driver_map_ids);
    end
    tm.series = toc(t_stage);

    elapsed = toc(t_start);
    fprintf('\n--- smp_push_to_sql complete ---\n');
    fprintf('  Stages   : resolve %.1fs | version-check %.1fs | marshal %.1fs | execute %.1fs | series %.1fs\n', ...
        tm.resolve, tm.version, tm.marshal, tm.execute, tm.series);
    fprintf('  Uploaded : %d\n', result.n_uploaded);
    fprintf('  Failed   : %d\n', result.n_failed);
    fprintf('  Time     : %.1fs  (%.1f rows/s)\n', elapsed, n_rows / max(elapsed, 0.01));
    for i = 1:numel(result.errors)
        fprintf('  ERR: %s\n', result.errors{i});
    end
end


function pairs_ids = lapseries_pairs(L, session_map, driver_map_ids)
% [SessionID DriverID] for every session+driver present in L.
    pairs = unique_rows(table(L.EventName, L.Venue, L.SessionName, L.Year, L.DriverName, L.Team, ...
        'VariableNames', {'EventName','Venue','SessionName','Year','DriverName','Team'}));
    pairs_ids = zeros(0, 2);
    for pi = 1:height(pairs)
        sid = lookup_id(session_map, {pairs.EventName{pi}, pairs.Venue{pi}, pairs.SessionName{pi}, pairs.Year{pi}});
        did = lookup_id(driver_map_ids, {pairs.DriverName{pi}, pairs.Team{pi}, pairs.Year{pi}});
        if ~isnan(sid) && ~isnan(did), pairs_ids(end+1, :) = [sid did]; end %#ok<AGROW>
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function rebuild_lap_series(conn, L, session_map, driver_map_ids)
% Refreshes dbo.LapSeries (the dashboard's read layout) for every session+driver just written.
% A failure only warns: the dashboard falls back to dbo.LapStats for unbuilt sessions.
    try
        pairs = unique_rows(table(L.EventName, L.Venue, L.SessionName, L.Year, L.DriverName, L.Team, ...
            'VariableNames', {'EventName','Venue','SessionName','Year','DriverName','Team'}));
        stmt = conn.createStatement();
        for pi = 1:height(pairs)
            sid = lookup_id(session_map, {pairs.EventName{pi}, pairs.Venue{pi}, pairs.SessionName{pi}, pairs.Year{pi}});
            did = lookup_id(driver_map_ids, {pairs.DriverName{pi}, pairs.Team{pi}, pairs.Year{pi}});
            if isnan(sid) || isnan(did), continue; end
            fprintf('[%s]   BuildLapSeries %d/%d (SessionID=%d DriverID=%d)...\n', ...
                datestr(now, 'HH:MM:SS'), pi, height(pairs), sid, did);
            t_ls = tic;
            stmt.execute(sprintf('EXEC dbo.BuildLapSeries @SessionID = %d, @DriverID = %d', sid, did));
            fprintf('[%s]   BuildLapSeries %d/%d done in %.1fs\n', datestr(now, 'HH:MM:SS'), pi, height(pairs), toc(t_ls));
        end
        stmt.close();
        fprintf('  LapSeries rebuilt for %d session+driver pair(s).\n', height(pairs));
    catch ME
        warning('smp_push_to_sql:lapseries', ...
            'LapSeries rebuild failed (dashboard falls back to LapStats for these sessions): %s', ME.message);
    end
end


function tf = lapstats_has_meta_cols(conn)
% True when dbo.LapStats still has the per-row SourceFile column (pre-v2 layout).
% Cached per connection object: the schema doesn't change mid-run.
    persistent cached_hash cached_val
    h = conn.hashCode();
    if ~isempty(cached_hash) && cached_hash == h
        tf = cached_val;
        return;
    end
    st = conn.createStatement();
    rs = st.executeQuery(['SELECT COUNT(*) FROM sys.columns WHERE ' ...
        'object_id = OBJECT_ID(''dbo.LapStats'') AND name = ''SourceFile''']);
    rs.next();
    tf = rs.getInt(1) > 0;
    rs.close();
    st.close();
    cached_hash = h;
    cached_val  = tf;
end

function upsert_session_driver_upload(conn, L, session_map, driver_map_ids)
% One MERGE per session+driver present in L (v2 layout only).
    pairs = unique_rows(table(L.EventName, L.Venue, L.SessionName, L.Year, L.DriverName, L.Team, ...
        'VariableNames', {'EventName','Venue','SessionName','Year','DriverName','Team'}));
    ps = conn.prepareStatement(['MERGE [dbo].[SessionDriverUpload] AS t ' ...
        'USING (SELECT ? AS SessionID, ? AS DriverID, ? AS MathVersion, ? AS SourceFile) AS s ' ...
        'ON t.SessionID = s.SessionID AND t.DriverID = s.DriverID ' ...
        'WHEN MATCHED THEN UPDATE SET MathVersion = s.MathVersion, SourceFile = s.SourceFile ' ...
        'WHEN NOT MATCHED THEN INSERT (SessionID, DriverID, MathVersion, SourceFile) ' ...
        'VALUES (s.SessionID, s.DriverID, s.MathVersion, s.SourceFile);']);
    for pi = 1:height(pairs)
        sid = lookup_id(session_map, {pairs.EventName{pi}, pairs.Venue{pi}, pairs.SessionName{pi}, pairs.Year{pi}});
        did = lookup_id(driver_map_ids, {pairs.DriverName{pi}, pairs.Team{pi}, pairs.Year{pi}});
        if isnan(sid) || isnan(did), continue; end
        mask = strcmp(L.EventName, pairs.EventName{pi}) & strcmp(L.Venue, pairs.Venue{pi}) & ...
               strcmp(L.SessionName, pairs.SessionName{pi}) & strcmp(L.Year, pairs.Year{pi}) & ...
               strcmp(L.DriverName, pairs.DriverName{pi}) & strcmp(L.Team, pairs.Team{pi});
        ri = find(mask, 1, 'first');
        ps.setInt(1, sid);
        ps.setInt(2, did);
        set_nullable_string(ps, 3, L.MathVersion{ri});
        set_nullable_string(ps, 4, L.SourceFile{ri});
        ps.executeUpdate();
    end
    ps.close();
end

function execute_batch(pstmt, batch_len)
% A failure propagates: the caller's catch rolls back the whole chunk.
    try
        pstmt.executeBatch();
    catch ME
        pstmt.clearBatch();
        error('smp_push_to_sql:batch', 'Batch of %d row(s): %s', batch_len, ME.message);
    end
    pstmt.clearBatch();
end

function ids = map_ids(L, cols, id_map)
% Vectorised lookup: build one key per row, resolve each unique key once.
    k = string(L.(cols{1}));
    for c = 2:numel(cols)
        k = k + "||" + string(L.(cols{c}));
    end
    k(ismissing(k)) = "";
    [u, ~, ic] = unique(k);
    uid = nan(numel(u), 1);
    for j = 1:numel(u)
        key = char(u(j));
        if isKey(id_map, key), uid(j) = id_map(key); end
    end
    ids = uid(ic);
end

function set_nullable_string(pstmt, idx, val)
    if isempty(val)
        pstmt.setNull(idx, java.sql.Types.VARCHAR);
    else
        pstmt.setString(idx, val);
    end
end

function id = lookup_id(id_map, key_vals)
    nat_key = strjoin(cellfun(@char_safe, key_vals, 'UniformOutput', false), '||');
    if isKey(id_map, nat_key)
        id = id_map(nat_key);
    else
        id = NaN;
    end
end

function s = char_safe(v)
    if isempty(v), s = ''; else, s = char(v); end
end

function U = unique_rows(T)
% Row-unique a small key table (order doesn't matter, dup keys just waste
% a lookup query — this only trims obviously duplicate rows for speed).
    if height(T) <= 1
        U = T;
        return;
    end
    keys = cell(height(T), 1);
    for ri = 1:height(T)
        parts = cell(1, width(T));
        for ci = 1:width(T)
            v = T{ri, ci};
            if iscell(v), v = v{1}; end
            parts{ci} = char(v);
        end
        keys{ri} = strjoin(parts, '||');
    end
    [~, idx] = unique(keys, 'stable');
    U = T(idx, :);
end

function s = format_val(val)
    if iscell(val), val = val{1}; end
    if isnumeric(val)
        s = num2str(val);
    else
        s = char(string(val));
    end
end

function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end
