function smp_filter_summary(SMP, varargin)
% SMP_FILTER_SUMMARY  Print a readable summary of an SMP struct.
%
% Usage:
%   smp_filter_summary(SMP)
%   smp_filter_summary(SMP, 'ShowPaths', true)

    p = inputParser();
    addParameter(p, 'ShowPaths', false);
    parse(p, varargin{:});
    opts = p.Results;

    team_keys = fieldnames(SMP);
    if isempty(team_keys)
        fprintf('smp_filter_summary: SMP struct is empty.\n');
        return;
    end

    total_runs = 0;
    fprintf('\n========================================\n');
    fprintf(' SMP Struct Summary\n');
    fprintf('========================================\n');

    for t = 1:numel(team_keys)
        tk   = team_keys{t};
        T    = SMP.(tk).meta;
        n    = height(T);
        total_runs = total_runs + n;

        fprintf('\n  [%s]  %d runs\n', tk, n);

        for r = 1:n
            load_flag = '';
            if ismember('LoadOK', T.Properties.VariableNames) && ~T.LoadOK(r)
                load_flag = ' [FAILED]';
            end

            parts = {};
            for col = {'Venue','Session','Driver','CarNumber','Manufacturer','Year'}
                if ismember(col{1}, T.Properties.VariableNames)
                    val = strtrim(char(string(T.(col{1}){r})));
                    if ~isempty(val) && ~strcmpi(val,'NaN')
                        parts{end+1} = val; %#ok
                    end
                end
            end

            [~, fname] = fileparts(T.Path{r});
            fprintf('    %s   %s%s\n', fname, strjoin(parts, '  |  '), load_flag);

            if opts.ShowPaths
                fprintf('      → %s\n', T.Path{r});
            end
        end
    end

    fprintf('\n--- Total: %d runs across %d team(s) ---\n\n', total_runs, numel(team_keys));
end
