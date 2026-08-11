
smp_rewrite_execution_scripts({'DAR'})

function smp_rewrite_execution_scripts(track_filter)
% SMP_REWRITE_EXECUTION_SCRIPTS  Rewrite per-event/session CombineDatasets,
%   PlottingScript, and driverAlias files from the masters in 01_Master.
%
%   Single source of truth: 01_Master\SessionAlias.xlsx, columns
%   (case-insensitive header match): Event | Track | Session | Date
%   (Date as plain text 'yyyy-mm-dd'). A session is generated IF AND ONLY
%   IF it has a row here — no separate eventAlias.xlsx session list, no
%   GARAGE/ER exclusion needed (simply don't add rows for those).
%
%   For each (Event, Track) group found in SessionAlias.xlsx:
%     - one CombineDatasets.m + PlottingScript.m per session row
%       (cfg.event_date / cfg.date_from filled from that row's Date)
%     - exactly ONE driverAlias.m for the whole event/track
%       (opts.date_from filled with the EARLIEST F in the group)
%
%   Existing files are overwritten unconditionally.
%
%   USAGE:
%     smp_rewrite_execution_scripts();                % all tracks
%     smp_rewrite_execution_scripts({'SMP','AGP'});    % only these tracks
%
%   Folder layout expected:
%     D:\SimEnv\dataAcquisition\parseEventData\executionScripts\
%       01_Master\
%         ENN_RNN_XXX_CombineDatasets.m
%         ENN_RNN_XXX_PlottingScript.m
%         ENN_XXX_driverAlias.m
%         SessionAlias.xlsx
%       E01_SMP\               (must already exist — files written here)
%         E01_R01_SMP_CombineDatasets.m   (generated)
%         E01_R01_SMP_PlottingScript.m    (generated)
%         E01_SMP_driverAlias.m           (generated, one only)
%       E02_AGP\
%         ...

if nargin < 1
    track_filter = {};   % {} = touch every track
end

ROOT_DIR   = fullfile(pwd, 'dataAcquisition\parseEventData\executionScripts');
MASTER_DIR = fullfile(ROOT_DIR, '01_Master');

MASTER_COMBINE   = fullfile(MASTER_DIR, 'ENN_RNN_XXX_CombineDatasets.m');
MASTER_PLOT      = fullfile(MASTER_DIR, 'ENN_RNN_XXX_PlottingScript.m');
MASTER_UPLOAD    = fullfile(MASTER_DIR, 'ENN_XXX_UploadScript.m')
MASTER_ALIAS     = fullfile(MASTER_DIR, 'ENN_XXX_DriverAlias.m');
SessionAlias_FILE = fullfile(MASTER_DIR, 'SessionAlias.xlsx');

for f = {MASTER_COMBINE, MASTER_PLOT, MASTER_UPLOAD, MASTER_ALIAS, SessionAlias_FILE}
    if ~isfile(f{1})
        error('Required master file not found: %s', f{1});
    end
end

master_text_combine  = read_text(MASTER_COMBINE);
master_text_plot     = read_text(MASTER_PLOT);
master_upload_script = read_text(MASTER_UPLOAD);
master_text_alias    = read_text(MASTER_ALIAS);

% ---- Load SessionAlias.xlsx: the single source of truth ----
rows = load_session_rows(SessionAlias_FILE);   % struct array: event, track, session, date
if isempty(rows)
    fprintf('SessionAlias.xlsx has no usable rows — nothing to do.\n');
    return;
end

if ~isempty(track_filter)
    keep = ismember(upper({rows.track}), upper(track_filter));
    rows = rows(keep);
end

if isempty(rows)
    fprintf('No rows matched track_filter — nothing to do.\n');
    return;
end

% ---- Group rows by (Event, Track) ----
group_keys = strcat(upper({rows.event}), '|', upper({rows.track}));
[unique_groups, ~, group_idx] = unique(group_keys);

fprintf('Found %d (Event, Track) group(s) in SessionAlias.xlsx\n\n', numel(unique_groups));

n_written        = 0;
n_skipped_folder = 0;

for g = 1:numel(unique_groups)
    group_rows = rows(group_idx == g);
    event_tok  = group_rows(1).event;
    track_tok  = group_rows(1).track;

    folder_name = sprintf('%s_%s', event_tok, track_tok);
    folder      = fullfile(ROOT_DIR, folder_name);

    if ~isfolder(folder)
        fprintf('  [SKIP] %s — folder does not exist under %s.\n', folder_name, ROOT_DIR);
        n_skipped_folder = n_skipped_folder + 1;
        continue;
    end

    fprintf('--- %s  (event=%s, track=%s, %d session(s)) ---\n', ...
        folder_name, event_tok, track_tok, numel(group_rows));

    % ---- Per-session files ----
    all_dates = {};
    for s = 1:numel(group_rows)
        session_tok = group_rows(s).session;
        date_str    = group_rows(s).date;
        if ~isempty(date_str)
            all_dates{end+1} = date_str; %#ok<AGROW>
        end

        combine_text = substitute_tokens_3(master_text_combine, event_tok, session_tok, track_tok);
        plot_text    = substitute_tokens_3(master_text_plot,    event_tok, session_tok, track_tok);
        upload_text  = substitute_tokens_3(master_upload_script,    event_tok, session_tok, track_tok);

        combine_text = tok_replace(combine_text, 'SESSIONDATE_STRING',   date_string_literal(date_str));
        plot_text    = tok_replace(plot_text,    'SESSIONDATE_DATETIME', date_datetime_literal(date_str));
        upload_text  = tok_replace(upload_text,  'SESSIONDATE_DATETIME', date_datetime_literal(date_str));

        combine_name = sprintf('%s_%s_%s_CombineDatasets.m', event_tok, session_tok, track_tok);
        plot_name    = sprintf('%s_%s_%s_PlottingScript.m',  event_tok, session_tok, track_tok);
        upload_name  = sprintf('%s_%s_UploadScript.m',  event_tok, track_tok);


        write_text(fullfile(folder, combine_name), combine_text);
        write_text(fullfile(folder, plot_name),    plot_text);
        write_text(fullfile(folder, upload_name),    upload_text);

        fprintf('  session %-6s (%s) -> %s, %s\n', session_tok, date_str, combine_name, plot_name);
        n_written = n_written + 2;
    end

    % ---- One driverAlias.m per event/track — earliest date in the group ----
    earliest_date = '';
    if ~isempty(all_dates)
        dt = sort(datetime(all_dates, 'InputFormat', 'yyyy-MM-dd'));
        earliest_date = datestr(dt(1), 'yyyy-mm-dd');
    end

    alias_text = substitute_tokens_2(master_text_alias, event_tok, track_tok);
    alias_text = tok_replace(alias_text, 'SESSIONDATE_DATETIME', date_datetime_literal(earliest_date));

    alias_name = sprintf('%s_%s_driverAlias.m', event_tok, track_tok);
    write_text(fullfile(folder, alias_name), alias_text);
    fprintf('  driverAlias  -> %s  (earliest date: %s)\n', alias_name, fallback_str(earliest_date));

    n_written = n_written + 1;
    fprintf('\n');
end

fprintf('Done. %d file(s) written, %d group(s) skipped (folder missing).\n', ...
    n_written, n_skipped_folder);
end


function s = fallback_str(s)
    if isempty(s), s = '(none)'; end
end


function rows = load_session_rows(SessionAlias_xlsx)
% LOAD_SESSION_ROWS  Read SessionAlias.xlsx into a struct array with
%   fields event/track/session/date (all char, date as 'yyyy-mm-dd' or
%   '' if blank). Column headers matched case-insensitively.
    T = readtable(SessionAlias_xlsx, 'TextType', 'char', 'ReadVariableNames', true);
    req_cols = {'Event', 'Track', 'Session', 'Date'};
    actual_names = T.Properties.VariableNames;
    col_map = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for c = req_cols
        hit = actual_names(strcmpi(actual_names, c{1}));
        if isempty(hit)
            error('SessionAlias.xlsx is missing required column "%s" (columns found: %s).', ...
                c{1}, strjoin(actual_names, ', '));
        end
        col_map(c{1}) = hit{1};
    end

    rows = struct('event', {}, 'track', {}, 'session', {}, 'date', {});
    for r = 1:height(T)
        ev = strtrim(char(string(T.(col_map('Event'))(r))));
        tr = strtrim(char(string(T.(col_map('Track'))(r))));
        se = strtrim(char(string(T.(col_map('Session'))(r))));
        dt = strtrim(char(string(T.(col_map('Date'))(r))));

        if isempty(ev) || isempty(tr) || isempty(se)
            fprintf('  [SessionAlias.xlsx] row %d skipped (blank Event/Track/Session): "%s" "%s" "%s"\n', ...
                r, ev, tr, se);
            continue;
        end
        rows(end+1) = struct('event', ev, 'track', tr, 'session', se, 'date', dt); %#ok<AGROW>
    end
    fprintf('[SessionAlias.xlsx] loaded %d usable session row(s).\n', numel(rows));
end


function text = substitute_tokens_3(text, event_tok, session_tok, track_tok)
% SUBSTITUTE_TOKENS_3  Replace ENN / RNN / XXX placeholders (CombineDatasets
%   / PlottingScript masters). Underscore is excluded from the boundary
%   check so joined forms like 'ENN_XXX' still substitute correctly.
    text = tok_replace(text, 'ENN', event_tok);
    text = tok_replace(text, 'RNN', session_tok);
    text = tok_replace(text, 'XXX', track_tok);
end


function text = substitute_tokens_2(text, event_tok, track_tok)
% SUBSTITUTE_TOKENS_2  Replace ENN / XXX placeholders (driverAlias master —
%   no session token involved).
    text = tok_replace(text, 'ENN', event_tok);
    text = tok_replace(text, 'XXX', track_tok);
end


function text = tok_replace(text, tok, repl)
    text = regexprep(text, ['(?<![A-Za-z0-9])' tok '(?![A-Za-z0-9])'], repl);
end


function lit = date_string_literal(date_str)
% DATE_STRING_LITERAL  Text to drop in place of SessionAlias_STRING,
%   e.g. '2026-02-20' -> quoted char literal ''2026-02-20''.
%   Missing date -> empty char literal ''.
    if isempty(date_str)
        lit = '''''';
    else
        lit = ['''' date_str ''''];
    end
end


function lit = date_datetime_literal(date_str)
% DATE_DATETIME_LITERAL  Text to drop in place of SessionAlias_DATETIME,
%   e.g. '2026-02-20' -> 'datetime(2026, 2, 20)'. Missing date -> '[]'.
    if isempty(date_str)
        lit = '[]';
        return;
    end
    parts = strsplit(date_str, '-');
    if numel(parts) ~= 3
        warning('smp_rewrite_execution_scripts:badDateFormat', ...
            'Date "%s" is not in yyyy-mm-dd format — leaving empty.', date_str);
        lit = '[]';
        return;
    end
    lit = sprintf('datetime(%d, %d, %d)', str2double(parts{1}), str2double(parts{2}), str2double(parts{3}));
end


function text = read_text(path)
    fid = fopen(path, 'r');
    if fid == -1
        error('Could not open file for reading: %s', path);
    end
    text = fread(fid, '*char')';
    fclose(fid);
end


function write_text(path, text)
    fid = fopen(path, 'w');
    if fid == -1
        error('Could not open file for writing: %s', path);
    end
    fwrite(fid, text);
    fclose(fid);
end