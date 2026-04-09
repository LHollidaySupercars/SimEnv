% function channels = smp_channel_config_load(filepath)
% % SMP_CHANNEL_CONFIG_LOAD  Load the list of channels to extract from .ld files.
% %
% % Reads channels.xlsx which has a 1 or 0 next to each channel name.
% % Only channels marked with 1 are returned.
% %
% % The following channels are ALWAYS included regardless of the check value,
% % because they are required for lap slicing, lap time filtering, and
% % distance interpolation:
% %   Lap_Number, Lap_Time, Odometer
% %
% % Expected Excel columns (case-insensitive):
% %   CHANNEL_NAME   - MoTeC channel name string
% %   check          - 1 to include, 0 to exclude
% %
% % Usage:
% %   channels = smp_channel_config_load('C:\...\channels.xlsx')
% %
% % Output:
% %   channels  - cell array of channel name strings to extract
% 
%     ALWAYS_INCLUDE = {'Lap_Number', 'Lap_Time', 'Odometer'};
% 
%     if ~exist(filepath, 'file')
%         error('smp_channel_config_load: File not found: %s', filepath);
%     end
% 
%     fprintf('Loading channel config: %s\n', filepath);
%     T = readtable(filepath);
% 
%     % ------------------------------------------------------------------
%     %  Detect column names (case-insensitive)
%     % ------------------------------------------------------------------
%     cols = T.Properties.VariableNames;
%     name_col  = find_col(cols, {'CHANNEL_NAME','Channel_Name','channel_name','ChannelName','Name','name'});
%     check_col = find_col(cols, {'check','Check','CHECK','include','Include','INCLUDE'});
% 
%     if isempty(name_col)
%         error('smp_channel_config_load: Cannot find channel name column. Found: %s', ...
%             strjoin(cols, ', '));
%     end
%     if isempty(check_col)
%         error('smp_channel_config_load: Cannot find check column. Found: %s', ...
%             strjoin(cols, ', '));
%     end
% 
%     % ------------------------------------------------------------------
%     %  Extract enabled channels
%     % ------------------------------------------------------------------
%     channels = {};
% 
%     for i = 1:height(T)
%         raw_name = strtrim(char(string(T.(name_col)(i))));
%         if isempty(raw_name), continue; end
% 
%         check_val = T.(check_col)(i);
%         if isnumeric(check_val)
%             enabled = check_val == 1;
%         elseif islogical(check_val)
%             enabled = check_val;
%         else
%             % Handle string '1'/'0' or 'true'/'false'
%             enabled = strcmpi(strtrim(char(string(check_val))), '1') || ...
%                       strcmpi(strtrim(char(string(check_val))), 'true');
%         end
% 
%         if enabled
%             channels{end+1} = raw_name; %#ok
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Always include mandatory channels (append if not already present)
%     % ------------------------------------------------------------------
%     for i = 1:numel(ALWAYS_INCLUDE)
%         required = ALWAYS_INCLUDE{i};
%         already_in = any(strcmpi(channels, required));
%         if ~already_in
%             channels{end+1} = required; %#ok
%             fprintf('  [AUTO] Adding required channel: %s\n', required);
%         end
%     end
% 
%     channels = channels(:);   % ensure column cell array
% 
%     fprintf('  %d channel(s) selected for extraction.\n', numel(channels));
%     for i = 1:numel(channels)
%         fprintf('    %s\n', channels{i});
%     end
%     fprintf('\n');
% end
% 
% 
% % ======================================================================= %
% function col = find_col(all_cols, candidates)
%     col = '';
%     for i = 1:numel(candidates)
%         if ismember(candidates{i}, all_cols)
%             col = candidates{i};
%             return;
%         end
%     end
% end


function [channels, channel_rules] = smp_channel_config_load(filepath)
% SMP_CHANNEL_CONFIG_LOAD  Load the list of channels to extract from .ld files.
%
% Reads channels.xlsx which has a 1 or 0 next to each channel name.
% Only channels marked with 1 are returned.
%
% The following channels are ALWAYS included regardless of the check value,
% because they are required for lap slicing, lap time filtering, and
% distance interpolation:
%   Lap_Number, Lap_Time, Odometer
%
% Expected Excel columns (case-insensitive):
%   CHANNEL_NAME     - MoTeC channel name string
%   check            - 1 to include, 0 to exclude
%   min_valid        - minimum valid sample value  (leave blank or -Inf = no lower bound)
%   max_valid        - maximum valid sample value  (leave blank or  Inf = no upper bound)
%   sentinel_values  - pipe-separated list of invalid sentinel values  e.g. 296.796|0
%                      leave blank = no sentinel check
%
% Usage:
%   channels = smp_channel_config_load('C:\...\channels.xlsx')
%   [channels, channel_rules] = smp_channel_config_load('C:\...\channels.xlsx')
%
% Outputs:
%   channels       - cell array of channel name strings to extract (unchanged)
%   channel_rules  - struct array, one entry per channel that has at least
%                    one filter rule defined. Fields:
%                      .channel    char     exact channel name
%                      .min_valid  double   lower bound  (-Inf if not set)
%                      .max_valid  double   upper bound  (+Inf if not set)
%                      .sentinels  double   row vector of sentinel values ([] if none)

    ALWAYS_INCLUDE = {'Lap_Number', 'Lap_Time', 'Odometer'};
    SENTINEL_TOL   = 1e-4;   % tolerance for floating-point sentinel comparison

    if ~exist(filepath, 'file')
        error('smp_channel_config_load: File not found: %s', filepath);
    end

    fprintf('Loading channel config: %s\n', filepath);
    T = readtable(filepath);

    % ------------------------------------------------------------------
    %  Detect column names (case-insensitive)
    % ------------------------------------------------------------------
    cols      = T.Properties.VariableNames;
    name_col  = find_col(cols, {'CHANNEL_NAME','Channel_Name','channel_name','ChannelName','Name','name'});
    check_col = find_col(cols, {'check','Check','CHECK','include','Include','INCLUDE'});
    min_col   = find_col(cols, {'min_valid','MinValid','min_Valid','minvalid','min'});
    max_col   = find_col(cols, {'max_valid','MaxValid','max_Valid','maxvalid','max'});
    sent_col  = find_col(cols, {'sentinel_values','SentinelValues','sentinel','sentinels'});

    if isempty(name_col)
        error('smp_channel_config_load: Cannot find channel name column. Found: %s', ...
            strjoin(cols, ', '));
    end
    if isempty(check_col)
        error('smp_channel_config_load: Cannot find check column. Found: %s', ...
            strjoin(cols, ', '));
    end

    % ------------------------------------------------------------------
    %  Extract enabled channels + build filter rules
    % ------------------------------------------------------------------
    channels     = {};
    channel_rules = struct('channel',{}, ...
                           'min_valid',{}, ...
                           'max_valid',{}, ...
                           'sentinels',{}, ...
                           'sentinel_tol', {});

    for i = 1:height(T)
        raw_name = strtrim(char(string(T.(name_col)(i))));
        if isempty(raw_name), continue; end

        % --- check flag ---
        check_val = T.(check_col)(i);
        if isnumeric(check_val)
            enabled = check_val == 1;
        elseif islogical(check_val)
            enabled = check_val;
        else
            enabled = strcmpi(strtrim(char(string(check_val))), '1') || ...
                      strcmpi(strtrim(char(string(check_val))), 'true');
        end

        if enabled
            channels{end+1} = raw_name; %#ok
        end

        % --- filter rule (built for all rows, enabled or not, in case
        %     an always-include channel needs filtering too) ---
        mn  = read_num(T, i, min_col, -Inf);
        mx  = read_num(T, i, max_col, +Inf);
        snt = read_sentinels(T, i, sent_col);

        has_range    = isfinite(mn) || isfinite(mx);
        has_sentinel = ~isempty(snt);

        if has_range || has_sentinel
            rule.channel   = raw_name;
            rule.min_valid = mn;
            rule.max_valid = mx;
            rule.sentinels = snt;
            rule.sentinel_tol = SENTINEL_TOL;
            channel_rules(end+1) = rule; %#ok
        end
    end

    % ------------------------------------------------------------------
    %  Always include mandatory channels
    % ------------------------------------------------------------------
    for i = 1:numel(ALWAYS_INCLUDE)
        required = ALWAYS_INCLUDE{i};
        if ~any(strcmpi(channels, required))
            channels{end+1} = required; %#ok
            fprintf('  [AUTO] Adding required channel: %s\n', required);
        end
    end

    channels = channels(:);

    fprintf('  %d channel(s) selected for extraction.\n', numel(channels));
    for i = 1:numel(channels)
        fprintf('    %s\n', channels{i});
    end

    if ~isempty(channel_rules)
        fprintf('  %d channel(s) have filter rules:\n', numel(channel_rules));
        for i = 1:numel(channel_rules)
            r = channel_rules(i);
            mn_str = num2str(r.min_valid);  if isinf(r.min_valid),  mn_str = '-Inf'; end
            mx_str = num2str(r.max_valid);  if isinf(r.max_valid),  mx_str = '+Inf'; end
            if isempty(r.sentinels)
                snt_str = 'none';
            else
                snt_str = strjoin(arrayfun(@num2str, r.sentinels, 'UniformOutput', false), ' | ');
            end
            fprintf('    %-35s  range=[%s, %s]  sentinels=[%s]\n', ...
                r.channel, mn_str, mx_str, snt_str);
        end
    end

    fprintf('\n');
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function col = find_col(all_cols, candidates)
    col = '';
    for i = 1:numel(candidates)
        if ismember(candidates{i}, all_cols)
            col = candidates{i};
            return;
        end
    end
end


function val = read_num(T, row, col, default)
% Read a numeric cell; return default if column missing, empty, or NaN text.
    val = default;
    if isempty(col), return; end
    v = T.(col)(row);
    if iscell(v), v = v{1}; end
    if ischar(v) || isstring(v)
        s = lower(strtrim(char(v)));
        if isempty(s) || strcmp(s,'nan'), return; end
        if strcmp(s,'-inf') || strcmp(s,'-infinity'), val = -Inf; return; end
        if strcmp(s,'inf')  || strcmp(s,'infinity'),  val = +Inf; return; end
        n = str2double(s);
        if isfinite(n), val = n; end
    elseif isnumeric(v) && isscalar(v)
        if isnan(v), return; end
        val = v;
    end
end


function snt = read_sentinels(T, row, col, ~)
% Parse pipe-separated sentinel string into a numeric row vector.
    snt = [];
    if isempty(col), return; end
    v = T.(col)(row);
    if iscell(v), v = v{1}; end
    if isnumeric(v)
        if isfinite(v), snt = v; end
        return;
    end
    s = strtrim(char(string(v)));
    if isempty(s) || strcmpi(s,'nan') || strcmpi(s,'none'), return; end
    parts = strsplit(s, '|');
    for i = 1:numel(parts)
        n = str2double(strtrim(parts{i}));
        if isfinite(n)
            snt(end+1) = n; %#ok
        end
    end
end