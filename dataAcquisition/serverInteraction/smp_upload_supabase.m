function result = smp_upload_supabase(T, opts)
% SMP_UPLOAD_SUPABASE  Upload a flattened lap stats table to Supabase.
%
% Uses the Supabase PostgREST REST API via MATLAB webwrite.
% No toolboxes required.
%
% Usage:
%   opts.url       = 'https://xxxxxxxxxxxx.supabase.co';
%   opts.key       = 'eyJ...';     % service_role key
%   opts.table     = 'lap_stats';  % default
%   opts.batch     = 200;          % rows per POST (default 200)
%   opts.overwrite = true;         % delete existing rows for same event+session first
%   opts.dry_run   = false;        % if true: print JSON but don't POST
%   result = smp_upload_supabase(T, opts)
%
% Credentials are read from opts first, then from environment variables
% SMP_SUPABASE_URL and SMP_SUPABASE_KEY, then prompted interactively.
%
% Returns:
%   result.n_uploaded   rows successfully posted
%   result.n_failed     rows that failed
%   result.errors       cell array of error messages per failed batch

    if nargin < 2, opts = struct(); end

    % ------------------------------------------------------------------ %
    %  Credentials
    % ------------------------------------------------------------------ %
    sb_url = get_opt(opts, 'url', '');
    sb_key = get_opt(opts, 'key', '');
    table  = get_opt(opts, 'table',     'lap_stats');
    batch  = get_opt(opts, 'batch',     200);
    overwr = get_opt(opts, 'overwrite', true);
    dry    = get_opt(opts, 'dry_run',   false);

    if isempty(sb_url), sb_url = getenv('SMP_SUPABASE_URL'); end
    if isempty(sb_key), sb_key = getenv('SMP_SUPABASE_KEY'); end
    if isempty(sb_url), sb_url = strtrim(input('Supabase project URL: ', 's')); end
    if isempty(sb_key), sb_key = strtrim(input('Service role key    : ', 's')); end

    sb_url   = strtrim(regexprep(sb_url, '/$', ''));
    endpoint = sprintf('%s/rest/v1/%s', sb_url, table);

    result.n_uploaded = 0;
    result.n_failed   = 0;
    result.errors     = {};

    % ------------------------------------------------------------------ %
    %  HTTP headers for POST (using matlab.net.http)
    % ------------------------------------------------------------------ %
    import matlab.net.http.*
    post_headers = [ ...
        HeaderField('apikey',        sb_key), ...
        HeaderField('Authorization', ['Bearer ' sb_key]), ...
        HeaderField('Content-Type',  'application/json'), ...
        HeaderField('Prefer',        'return=minimal') ...
    ];

    % ------------------------------------------------------------------ %
    %  Overwrite: DELETE existing rows for the same event + session
    % ------------------------------------------------------------------ %
    if overwr && ~dry
        events   = unique(T.event);
        sessions = unique(T.session);
        fprintf('Overwrite mode: deleting existing rows...\n');
        del_headers = [ ...
            HeaderField('apikey',        sb_key), ...
            HeaderField('Authorization', ['Bearer ' sb_key]) ...
        ];
        for ei = 1:numel(events)
            for si = 1:numel(sessions)
                ev  = events{ei};  se = sessions{si};
                if isempty(ev) || isempty(se), continue; end
                del_url = sprintf('%s?event=eq.%s&session=eq.%s', ...
                    endpoint, urlencode(ev), urlencode(se));
                try
                    del_req  = RequestMessage('DELETE', del_headers);
                    del_resp = del_req.send(del_url);
                    fprintf('  Deleted: event=%s  session=%s\n', ev, se);
                catch ME
                    fprintf('  [WARN] Delete failed (%s/%s): %s\n', ev, se, ME.message);
                end
            end
        end
    end

    % ------------------------------------------------------------------ %
    %  Batch upload
    % ------------------------------------------------------------------ %
    n_rows    = height(T);
    col_names = T.Properties.VariableNames;
    n_batches = ceil(n_rows / batch);

    fprintf('Uploading %d rows in %d batch(es)...\n', n_rows, n_batches);

    for bi = 1:n_batches
        i_start = (bi-1)*batch + 1;
        i_end   = min(bi*batch, n_rows);
        batch_T = T(i_start:i_end, :);

        json_str = table_to_json(batch_T, col_names);

        if dry
            fprintf('[DRY RUN] Batch %d/%d  rows %d-%d  (%d chars)\n', ...
                bi, n_batches, i_start, i_end, numel(json_str));
            if numel(json_str) < 600
                disp(json_str);
            else
                fprintf('%s...\n', json_str(1:600));
            end
            result.n_uploaded = result.n_uploaded + (i_end - i_start + 1);
            continue;
        end

        try
            req  = RequestMessage('POST', post_headers, MessageBody(json_str));
            resp = req.send(endpoint);
            status = double(resp.StatusCode);
            if status == 200 || status == 201
                result.n_uploaded = result.n_uploaded + (i_end - i_start + 1);
                fprintf('  [%d/%d]  rows %d-%d  OK\n', bi, n_batches, i_start, i_end);
            else
                n_fail = i_end - i_start + 1;
                result.n_failed = result.n_failed + n_fail;
                try
                    body = resp.Body.Data;
                    if isstruct(body)
                        msg = sprintf('Batch %d rows %d-%d: HTTP %d — %s', ...
                            bi, i_start, i_end, status, body.message);
                    else
                        msg = sprintf('Batch %d rows %d-%d: HTTP %d', bi, i_start, i_end, status);
                    end
                catch
                    msg = sprintf('Batch %d rows %d-%d: HTTP %d', bi, i_start, i_end, status);
                end
                result.errors{end+1} = msg;
                fprintf('  [ERROR] %s\n', msg);
            end
        catch ME
            n_fail = i_end - i_start + 1;
            result.n_failed = result.n_failed + n_fail;
            msg = sprintf('Batch %d rows %d-%d: %s', bi, i_start, i_end, ME.message);
            result.errors{end+1} = msg;
            fprintf('  [ERROR] %s\n', msg);
        end
    end

    % ------------------------------------------------------------------ %
    %  Summary
    % ------------------------------------------------------------------ %
    fprintf('\n--- smp_upload_supabase ---\n');
    fprintf('  Uploaded : %d\n', result.n_uploaded);
    fprintf('  Failed   : %d\n', result.n_failed);
    for i = 1:numel(result.errors)
        fprintf('  ERR: %s\n', result.errors{i});
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function json_str = table_to_json(T, col_names)
% Convert table rows to a JSON array of objects.
% NaN and Inf become JSON null (empty [] in struct → null via jsonencode).

    n = height(T);
    structs = cell(1, n);

    for ri = 1:n
        s = struct();
        for ci = 1:numel(col_names)
            col = col_names{ci};
            val = T.(col)(ri);

            % Unwrap cell
            if iscell(val), val = val{1}; end

            % String types
            if isstring(val), val = char(val); end

            % NaN / Inf → null
            if isnumeric(val) && ~isempty(val) && (~isfinite(val))
                val = [];
            end

            s.(col) = val;
        end
        structs{ri} = s;
    end

    json_str = jsonencode([structs{:}]);
end


function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end
