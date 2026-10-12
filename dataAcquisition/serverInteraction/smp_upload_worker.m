function smp_upload_worker(data_file, conn)
% SMP_UPLOAD_WORKER  Detached, one-shot: load a buffered table, push to SQL.
% Launched via `matlab -batch "smp_upload_worker('path')"` from flush_buffer,
% OR called directly with an already-open connection (conn) to reuse it
% instead of authenticating again. Writes its own .log and .done flag
% files — the launching process never waits on either.
%
% Usage:
%   smp_upload_worker(data_file)         % opens its own connection
%   smp_upload_worker(data_file, conn)   % reuses an existing connection —
%                                         % no smp_sql_connect() call, no
%                                         % repeated Azure AD/MFA prompt

    if nargin < 2, conn = []; end

    s = load(data_file, 'T', 'upload_opts');
    T    = s.T;
    opts = s.upload_opts;

    diary(opts.log_file);
    fprintf('[%s] smp_upload_worker starting — %d rows -> %s\n', ...
        datestr(now, 'HH:MM:SS'), height(T), upper(opts.target));

    try
        switch lower(opts.target)
            case 'pocketbase'
                opts_pb           = struct();
                opts_pb.batch     = opts.batch;
                opts_pb.overwrite = opts.overwrite;
                opts_pb.dry_run   = false;
                result = smp_push_to_pocketbase(T, opts_pb);

            case {'azure_local', 'azure_online'}
                if isempty(conn)
                    conn = smp_sql_connect(opts.target);
                end
                opts_sql           = struct();
                opts_sql.batch     = opts.batch;
                opts_sql.overwrite = opts.overwrite;
                opts_sql.mode      = '';
                if isfield(opts, 'mode'),     opts_sql.mode     = opts.mode;     end
                opts_sql.channels  = {};
                if isfield(opts, 'channels'), opts_sql.channels = opts.channels; end
                opts_sql.dry_run   = false;
                result = smp_push_to_sql(T, conn, opts_sql);

            otherwise
                error('Unknown upload target: %s', opts.target);
        end

        fprintf('[%s] Complete: %d uploaded, %d failed.\n', ...
            datestr(now, 'HH:MM:SS'), result.n_uploaded, result.n_failed);

        fid = fopen(opts.flag_file, 'w');
        fprintf(fid, 'ok\nuploaded=%d\nfailed=%d\n', result.n_uploaded, result.n_failed);
        fclose(fid);

    catch ME
        fprintf('[%s] [ERROR] %s\n', datestr(now, 'HH:MM:SS'), ME.message);
        fid = fopen(opts.flag_file, 'w');
        fprintf(fid, 'error\n%s\n', ME.message);
        fclose(fid);
    end

    diary off;
end