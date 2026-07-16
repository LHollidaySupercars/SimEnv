function result = smp_push_to_sql(T, conn, opts)
% SMP_PUSH_TO_SQL  Upload a flattened lap stats table to SQL Server via JDBC.
%
% Mirrors smp_push_to_pocketbase.m but targets SQL Server (local or Azure).
% Uses JDBC PreparedStatement with batched INSERTs for performance.
%
% Usage:
%   conn   = smp_sql_connect('azure_online');
%   result = smp_push_to_sql(T, conn)
%   result = smp_push_to_sql(T, conn, opts)
%
% Inputs:
%   T       - MATLAB table from smp_flatten_stats()
%   conn    - JDBC connection from smp_sql_connect()
%   opts    - optional struct:
%     .table      string   table name (default: 'lap_stats')
%     .batch      double   rows per batch commit (default: 100)
%     .overwrite  logical  delete existing rows for same event+session first (default: true)
%     .dry_run    logical  print first row SQL only, no writes (default: false)
%     .schema     string   SQL schema (default: 'dbo')
%
% Output:
%   result.n_uploaded   rows successfully inserted
%   result.n_failed     rows that failed
%   result.errors       cell array of error messages
%
% =========================================================

    if nargin < 3, opts = struct(); end

    table_name = get_opt(opts, 'table',     'lap_stats');
    schema     = get_opt(opts, 'schema',    'dbo');
    batch_size = get_opt(opts, 'batch',     100);
    overwrite  = get_opt(opts, 'overwrite', true);
    dry_run    = get_opt(opts, 'dry_run',   false);

    full_table = sprintf('[%s].[%s]', schema, table_name);

    result.n_uploaded = 0;
    result.n_failed   = 0;
    result.errors     = {};

    col_names = T.Properties.VariableNames;
    n_cols    = numel(col_names);
    n_rows    = height(T);

    % ── Identify text vs numeric columns ─────────────────────────────────
    txt_cols = {'event','venue','session','year','team','team_name','driver', ...
                'car_number','manufacturer','vehicle','group_key','source_file'};

    % ── Dry run: print first row only ────────────────────────────────────
    if dry_run
        fprintf('[DRY RUN] First row preview:\n');
        for ci = 1:n_cols
            val = get_val(T, col_names{ci}, 1);
            fprintf('  %-45s = %s\n', col_names{ci}, format_val(val));
        end
        return;
    end

    % ── Overwrite: delete existing rows for this event + session ─────────
    if overwrite
        events   = unique(T.event);
        sessions = unique(T.session);
        fprintf('Overwrite mode: deleting existing rows...\n');
        stmt = conn.createStatement();
        for ei = 1:numel(events)
            for si = 1:numel(sessions)
                ev = events{ei}; se = sessions{si};
                if isempty(ev) || isempty(se), continue; end
                del_sql = sprintf('DELETE FROM %s WHERE event = ''%s'' AND session = ''%s''', ...
                    full_table, ev, se);
                try
                    rows_del = stmt.executeUpdate(del_sql);
                    fprintf('  Deleted %d rows for %s / %s\n', rows_del, ev, se);
                catch ME
                    fprintf('  [WARN] Delete failed (%s/%s): %s\n', ev, se, ME.message);
                end
            end
        end
        stmt.close();
    end

    % ── Build INSERT prepared statement ───────────────────────────────────
    col_list     = strjoin(cellfun(@(c) sprintf('[%s]', c), col_names, 'UniformOutput', false), ', ');
    placeholders = strjoin(repmat({'?'}, 1, n_cols), ', ');
    insert_sql   = sprintf('INSERT INTO %s (%s) VALUES (%s)', full_table, col_list, placeholders);

    fprintf('Uploading %d rows to %s in batches of %d...\n', n_rows, full_table, batch_size);
    t_start = tic;

    % Disable auto-commit for batching
    conn.setAutoCommit(false);

    try
        pstmt = conn.prepareStatement(insert_sql);

        for ri = 1:n_rows
            % Bind each column value
            for ci = 1:n_cols
                col = col_names{ci};
                val = get_val(T, col, ri);
                is_text = ismember(col, txt_cols);

                if is_text
                    if isempty(val)
                        pstmt.setNull(ci, java.sql.Types.NVARCHAR);
                    else
                        pstmt.setString(ci, val);
                    end
                else
                    if isnan(val)
                        pstmt.setNull(ci, java.sql.Types.FLOAT);
                    else
                        pstmt.setDouble(ci, val);
                    end
                end
            end

            pstmt.addBatch();

            % Commit every batch_size rows
            if mod(ri, batch_size) == 0
                try
                    pstmt.executeBatch();
                    conn.commit();
                    result.n_uploaded = result.n_uploaded + batch_size;
                    elapsed = toc(t_start);
                    rate    = ri / elapsed;
                    eta     = (n_rows - ri) / max(rate, 0.1);
                    fprintf('  %d/%d  (%.0f rows/s  ETA %.0fs)\n', ri, n_rows, rate, eta);
                catch ME
                    conn.rollback();
                    n_fail = batch_size;
                    result.n_failed = result.n_failed + n_fail;
                    msg = sprintf('Batch ending row %d: %s', ri, ME.message);
                    result.errors{end+1} = msg;
                    fprintf('  [ERROR] %s\n', msg);
                end
                pstmt.clearBatch();
            end
        end

        % Final partial batch
        remainder = mod(n_rows, batch_size);
        if remainder > 0
            try
                pstmt.executeBatch();
                conn.commit();
                result.n_uploaded = result.n_uploaded + remainder;
            catch ME
                conn.rollback();
                result.n_failed = result.n_failed + remainder;
                msg = sprintf('Final batch: %s', ME.message);
                result.errors{end+1} = msg;
                fprintf('  [ERROR] %s\n', msg);
            end
        end

        pstmt.close();

    catch ME
        conn.rollback();
        conn.setAutoCommit(true);
        error('smp_push_to_sql: Fatal error during upload.\n%s', ME.message);
    end

    conn.setAutoCommit(true);

    elapsed = toc(t_start);
    fprintf('\n--- smp_push_to_sql complete ---\n');
    fprintf('  Uploaded : %d\n', result.n_uploaded);
    fprintf('  Failed   : %d\n', result.n_failed);
    fprintf('  Time     : %.1fs  (%.1f rows/s)\n', elapsed, n_rows / max(elapsed, 0.01));
    for i = 1:numel(result.errors)
        fprintf('  ERR: %s\n', result.errors{i});
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function val = get_val(T, col, ri)
    val = T.(col)(ri);
    if iscell(val),   val = val{1}; end
    if isstring(val), val = char(val); end
    if isnumeric(val) && ~isempty(val) && ~isfinite(val)
        val = NaN;
    end
end

function s = format_val(val)
    if ischar(val) || isstring(val)
        s = sprintf('"%s"', val);
    elseif isnumeric(val) && isnan(val)
        s = 'NULL';
    else
        s = num2str(val);
    end
end

function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end
