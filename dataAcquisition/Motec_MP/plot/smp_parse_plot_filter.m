function groups = smp_parse_plot_filter(filter_str)
% SMP_PARSE_PLOT_FILTER  Parse a per-plot filter string into filter groups.
%
% Filter string format:
%   'key=value,key=value;key=value,key=value'
%
%   Semicolons  (;)  separate independent filter GROUPS  (OR between groups)
%   Commas      (,)  separate key=value pairs within one group  (AND within group)
%
% Supported keys:
%   mfr=Ford            manufacturer match (partial, case-insensitive)
%   drv=MST,SVG         driver TLA or name (comma-separated within value)
%   team=T8R            team acronym
%   session=Race1       session name
%   n=2                 top N runs by best lap time within this group
%
% Examples:
%   'mfr=Ford'                      all Ford runs
%   'mfr=Ford,n=1'                  fastest Ford run only
%   'mfr=Ford,n=1;mfr=Toyota'       fastest Ford + all Toyotas
%   'drv=MST,SVG'                   two specific drivers
%   'mfr=Ford,drv=MST'              Ford AND MST
%   'mfr=Ford,n=2;mfr=Toyota,n=3'   top 2 Fords + top 3 Toyotas
%
% Returns:
%   groups  - struct array, one per semicolon-separated group
%     .mfr        cell    manufacturer values (OR'd)
%     .drv        cell    driver TLA/names (OR'd)
%     .team       cell    team acronyms (OR'd)
%     .session    cell    session names (OR'd)
%     .n          double  top-N limit (0 = no limit)

    groups = struct('mfr',{}, 'drv',{}, 'team',{}, 'session',{}, 'n',{});

    if isempty(filter_str) || strcmpi(strtrim(filter_str), 'none') || ...
       strcmpi(strtrim(filter_str), 'NaN')
        return;
    end

    % Split into groups on semicolon
    group_strs = strsplit(strtrim(filter_str), ';');

    for g = 1:numel(group_strs)
        gs = strtrim(group_strs{g});
        if isempty(gs), continue; end

        grp.mfr     = {};
        grp.drv     = {};
        grp.team    = {};
        grp.session = {};
        grp.n       = 0;    % 0 = no limit

        % Split on commas — but be careful: drv=MST,SVG uses comma inside value
        % Strategy: split on comma only when followed by a known key=
        % Safer: split on ',' then re-join any that don't contain '='
        parts = strsplit(gs, ',');
        parts = merge_value_parts(parts);   % re-join multi-value entries

        for k = 1:numel(parts)
            part = strtrim(parts{k});
            if isempty(part), continue; end

            eq_idx = strfind(part, '=');
            if isempty(eq_idx)
                fprintf('[smp_parse_plot_filter] WARN: ignoring malformed part "%s"\n', part);
                continue;
            end

            key = lower(strtrim(part(1:eq_idx(1)-1)));
            val = strtrim(part(eq_idx(1)+1:end));

            switch key
                case 'mfr'
                    grp.mfr = parse_values(val);
                case 'drv'
                    grp.drv = parse_values(val);
                case 'team'
                    grp.team = parse_values(val);
                case 'session'
                    grp.session = parse_values(val);
                case 'n'
                    grp.n = str2double(val);
                    if isnan(grp.n), grp.n = 0; end
                otherwise
                    fprintf('[smp_parse_plot_filter] WARN: unknown key "%s"\n', key);
            end
        end

        groups(end+1) = grp; %#ok
    end

    % Print summary
    fprintf('smp_parse_plot_filter: %d group(s)\n', numel(groups));
    for g = 1:numel(groups)
        grp = groups(g);
        parts = {};
        if ~isempty(grp.mfr),     parts{end+1} = ['mfr='     strjoin(grp.mfr,   '|')]; end %#ok
        if ~isempty(grp.drv),     parts{end+1} = ['drv='     strjoin(grp.drv,   '|')]; end %#ok
        if ~isempty(grp.team),    parts{end+1} = ['team='    strjoin(grp.team,  '|')]; end %#ok
        if ~isempty(grp.session), parts{end+1} = ['session=' strjoin(grp.session,'|')]; end %#ok
        if grp.n > 0,             parts{end+1} = sprintf('n=%d', grp.n);                end %#ok
        fprintf('  Group %d: %s\n', g, strjoin(parts, '  AND  '));
    end
end


% ======================================================================= %
function parts = merge_value_parts(raw_parts)
% Re-join comma-split pieces that belong to multi-value entries like drv=MST,SVG.
% A part belongs to the previous entry if it contains no '=' sign.
    parts = {};
    for i = 1:numel(raw_parts)
        p = strtrim(raw_parts{i});
        if contains(p, '=')
            parts{end+1} = p; %#ok
        elseif ~isempty(parts)
            % Append to previous entry's value
            parts{end} = [parts{end} ',' p];
        end
    end
end


function vals = parse_values(val_str)
% Split a value string on pipe | or comma , into a cell of trimmed strings.
    if contains(val_str, '|')
        vals = cellfun(@strtrim, strsplit(val_str,'|'), 'UniformOutput', false);
    elseif contains(val_str, ',')
        vals = cellfun(@strtrim, strsplit(val_str,','), 'UniformOutput', false);
    else
        vals = {strtrim(val_str)};
    end
    vals = vals(~cellfun(@isempty, vals));
end
