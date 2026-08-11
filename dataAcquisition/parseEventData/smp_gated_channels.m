function [data, new_names] = smp_gated_channels(data, T)
% SMP_GATED_CHANNELS  Inject Excel-defined gated channels into a session struct.
%
% T is the pre-loaded gatedChannels table (read once in load_and_concat).
% Each row defines one output channel via an element-wise MATLAB expression
% over existing channels in data.
%
% Table columns:
%   CHANNEL_MATH   e.g.  brakingGateVCH.*RL_SlipVCH
%   CHANNEL_NAME   e.g.  RL_SlipVCH_BrakeGate
%
% Binary channels (unique finite values subset of {0,1}) are resampled
% with 'nearest' to preserve square-wave shape. All others use 'linear'.
%
% Returns:
%   data       - session struct with new channels appended
%   new_names  - cell array of successfully added channel names
%                (append to channels_to_extract before filter_channels)

    new_names = {};

    if isempty(T)
        fprintf('smp_gated_channels: table is empty, skipping.\n');
        return;
    end

    % Locate required columns (case-insensitive)
    cols = lower(T.Properties.VariableNames);
    math_col = find_col(cols, {'channel_math','channelmath','math'});
    name_col = find_col(cols, {'channel_name','channelname','name'});

    if isempty(math_col) || isempty(name_col)
        error('smp_gated_channels: cannot find CHANNEL_MATH / CHANNEL_NAME columns. Found: %s', ...
              strjoin(T.Properties.VariableNames, ', '));
    end

    fprintf('smp_gated_channels: processing %d row(s)...\n', height(T));

    % ------------------------------------------------------------------
    %  Process each row
    % ------------------------------------------------------------------
    for i = 1:height(T)
        expr     = strtrim(char(string(T.(math_col)(i))));
        out_name = strtrim(char(string(T.(name_col)(i))));

        if isempty(expr) || isempty(out_name), continue; end

        % --- Tokenise: find all MATLAB identifiers in the expression ---
        tokens = regexp(expr, '[A-Za-z][A-Za-z0-9_]*', 'match');
        tokens = unique(tokens, 'stable');

        % --- Check all tokens resolve to channels in data --------------
        % Exclude known MATLAB builtins from the channel lookup
        BUILTINS = {'abs','sqrt','sin','cos','tan','exp','log','log2','log10', ...
                    'floor','ceil','round','mod','rem','sign','min','max', ...
                    'mean','sum','cumsum','diff','interp1','isfinite','isnan'};
        channel_tokens = tokens(~cellfun(@(t) ismember(t, BUILTINS), tokens));
        missing = channel_tokens(~cellfun(@(t) isfield(data, t), channel_tokens));
        if ~isempty(missing)
            fprintf('  [!] %s skipped — missing channel(s): %s\n', ...
                    out_name, strjoin(missing, ', '));
            continue;
        end

        % --- Pick reference channel (first non-gate, non-builtin token) ---
        ref_name = '';
        for k = 1:numel(channel_tokens)
            if ~contains(lower(channel_tokens{k}), 'gate')
                ref_name = channel_tokens{k};
                break;
            end
        end
        if isempty(ref_name)
            ref_name = channel_tokens{1};
        end
        ref_ch = data.(ref_name);

        % --- Build local workspace: align channel tokens to reference ------
        ws = struct();
        ok = true;
        for k = 1:numel(channel_tokens)
            src_ch = data.(channel_tokens{k});
            try
                ws.(channel_tokens{k}) = align_to(src_ch, ref_ch);
            catch ME
                fprintf('  [!] %s skipped — align_to failed for %s: %s\n', ...
                        out_name, tokens{k}, ME.message);
                ok = false;
                break;
            end
        end
        if ~ok, continue; end

        % --- Evaluate expression in local workspace --------------------
        % Replace each token in expr with ws.(token) by building an
        % eval string that assigns workspace vars, then evaluates.
        try
            result = eval_in_ws(ws, channel_tokens, expr);
        catch ME
            fprintf('  [!] %s skipped — expression eval failed: %s\n', out_name, ME.message);
            continue;
        end

        % --- Resolve output units --------------------------------------
        unit_str = '';
        for k = 1:numel(channel_tokens)
            if ~contains(lower(channel_tokens{k}), 'gate')
                if isfield(data.(channel_tokens{k}), 'units')
                    unit_str = data.(channel_tokens{k}).units;
                end
                break;
            end
        end
        % If all tokens were gates, output is also boolean
        if isempty(unit_str) && all(cellfun(@(t) contains(lower(t),'gate'), channel_tokens))
            unit_str = 'bool';
        end

         % --- Build output channel struct --------------------------------
        ch             = struct();
        ch.data        = result(:);
        ch.time        = ref_ch.time;
        ch.units       = unit_str;
        ch.sample_rate = ref_ch.sample_rate;
        ch.raw_name    = out_name;
        ch.write_to_ld = true;
        ch.overwrite   = true;
        ch.dec_places  = gated_auto_dec_places(ch.data);
        % Gate output if result is strictly 0/1
        if all(ismember(unique(ch.data(isfinite(ch.data))), [0; 1]))
            ch.interp_method = 'nearest';
        end

        data.(out_name) = ch;
        new_names{end+1} = out_name; %#ok
        fprintf('  [+] %s  (%s)\n', out_name, expr);
    end

    fprintf('smp_gated_channels: done — %d channel(s) added.\n', numel(new_names));
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function idx = find_col(col_list, candidates)
    idx = '';
    for i = 1:numel(candidates)
        match = find(strcmp(col_list, candidates{i}), 1);
        if ~isempty(match)
            idx = match;
            return;
        end
    end
end

function result = eval_in_ws(ws, tokens, expr)
    for k = 1:numel(tokens)
        eval(sprintf('%s = ws.(%s);', tokens{k}, sprintf('''%s''', tokens{k})));
    end
    % Ensure builtins are not shadowed by ws variables
    builtin_names = {'abs','sqrt','sin','cos','tan','exp','log','log2','log10', ...
                     'floor','ceil','round','mod','rem','sign','min','max', ...
                     'mean','sum','cumsum','diff','interp1','isfinite','isnan'};
    for k = 1:numel(builtin_names)
        if exist(builtin_names{k}, 'var')
            clear(builtin_names{k});
        end
    end
    result = eval(expr);
end

function dec = gated_auto_dec_places(values)
% GATED_AUTO_DEC_PLACES  Same logic as smp_custom_channels' auto_dec_places,
% duplicated locally since that one is a private local function and not
% callable across files. Keep in sync if the original changes.
finite_vals = values(isfinite(values));
if isempty(finite_vals)
    dec = 2;
    return;
end
data_range = max(finite_vals) - min(finite_vals);
if data_range == 0
    dec = 2;
    return;
end
dec = 0;
for d = 4:-1:0
    if data_range * 10^d <= 32767
        dec = d;
        break;
    end
end
end