function rows = smp_excel_summary(data)
% SMP_EXCEL_SUMMARY  Print a readable summary of an smp_read_excel / smp_excel_filter result.
%
% Also returns a struct array of rows with fields:
%   .team  .driver  .session  .manufacturer  .car  .row_index
%
% Usage:
%   smp_excel_summary(data)
%   rows = smp_excel_summary(data)
%
% Mirrors smp_filter_summary but for Excel-sourced data.

    T    = data.table;
    cols = data.cols;
    n    = height(T);

    fprintf('\n========================================\n');
    fprintf(' SMP Excel Data Summary  (%d rows)\n', n);
    fprintf('========================================\n');

    if n == 0
        fprintf('  (no rows)\n\n');
        rows = struct([]);
        return;
    end

    % ------------------------------------------------------------------ %
    %  Column helpers
    % ------------------------------------------------------------------ %
    get_col = @(col) get_col_vals(T, col, n);

    team_vals  = get_col(cols.team);
    drv_vals   = get_col(cols.driver);
    ses_vals   = get_col(cols.session);
    mfr_vals   = get_col(cols.manufacturer);
    car_vals   = get_col(cols.car);
    lap_vals   = get_col(cols.lap);

    % ------------------------------------------------------------------ %
    %  Print grouped by manufacturer → driver
    % ------------------------------------------------------------------ %
    mfrs = unique(mfr_vals);
    for m = 1:numel(mfrs)
        mfr = mfrs{m};
        idx_m = strcmp(mfr_vals, mfr);
        fprintf('\n  [%s]\n', mfr);

        drvs = unique(drv_vals(idx_m));
        for d = 1:numel(drvs)
            drv   = drvs{d};
            idx_d = idx_m & strcmp(drv_vals, drv);
            sess  = unique(ses_vals(idx_d));
            cars  = unique(car_vals(idx_d));
            laps  = lap_vals(idx_d);
            laps_num = cellfun(@str2double, laps);
            lap_range = '';
            if ~all(isnan(laps_num))
                lap_range = sprintf('  laps %d–%d', min(laps_num(~isnan(laps_num))), max(laps_num(~isnan(laps_num))));
            end

            fprintf('    Car %-4s  %-22s  Sessions: %-20s  Teams: %-10s%s\n', ...
                strjoin(cars,'/'), drv, strjoin(sess,', '), strjoin(unique(team_vals(idx_d)),'/'), lap_range);
        end
    end

    fprintf('\n--- Total: %d rows ---\n\n', n);

    % ------------------------------------------------------------------ %
    %  Build return struct
    % ------------------------------------------------------------------ %
    if nargout > 0
        rows = struct( ...
            'team',         team_vals, ...
            'driver',       drv_vals, ...
            'session',      ses_vals, ...
            'manufacturer', mfr_vals, ...
            'car',          car_vals, ...
            'row_index',    num2cell((1:n)') );
    end
end


% ======================================================================= %
function vals = get_col_vals(T, col, n)
    if isempty(col) || ~ismember(col, T.Properties.VariableNames)
        vals = repmat({''}, n, 1);
        return;
    end
    raw = T.(col);
    if isnumeric(raw)
        vals = arrayfun(@num2str, raw, 'UniformOutput', false);
    elseif iscell(raw)
        vals = cellfun(@(x) strtrim(char(string(x))), raw, 'UniformOutput', false);
    else
        vals = cellstr(string(raw));
    end
end
