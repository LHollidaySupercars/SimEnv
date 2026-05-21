%% plot_from_excel_plots_sheet.m
% Reads the 'PLOTS' sheet from an already-open Excel instance and plots
% all data columns coloured by the 'Run num' column.
%
% Assumptions:
%   - Column A = X axis (header in A1, data from A2)
%   - Row 1 starting B1 = column headers
%   - One header is 'Run num' (case-insensitive); used for colouring
%   - Data starts in row 2

%% Connect to open Excel instance
try
    xl = actxGetRunningServer('Excel.Application');
catch
    error('No running Excel instance found. Open Excel first.');
end

wb = xl.ActiveWorkbook;
ws = wb.Sheets.Item('PLOTS');

%% Read used range
used = ws.UsedRange;
data = used.Value;   % cell array: rows x cols

if isempty(data)
    error('PLOTS sheet appears empty.');
end

%% Parse headers
xHeader   = strtrim(num2str(data{1,1}));          % col A header (x axis)
headerRow = data(1, 2:end);                        % col B onward
headers   = cellfun(@(x) strtrim(num2str(x)), headerRow, 'UniformOutput', false);

%% Locate 'Run num' column (relative to headers, i.e. within col B onward)
runColIdx = find(strcmpi(headers, 'Outing Num'), 1);
if isempty(runColIdx)
    error('"Run num" header not found. Found: %s', strjoin(headers, ', '));
end

%% Convert all data cells to doubles (handles both numeric and text from Excel)
nDataRows = size(data,1) - 1;
nDataCols = size(data,2);

allNum = NaN(nDataRows, nDataCols);
for r = 1:nDataRows
    for c = 1:nDataCols
        v = data{r+1, c};
        if isnumeric(v)
            allNum(r,c) = v;
        elseif ischar(v) || isstring(v)
            allNum(r,c) = str2double(v);
        end
    end
end

xData   = allNum(:, 1);          % col A = x axis
numData = allNum(:, 2:end);      % col B onward = channel data

%% Build colour map keyed on unique run numbers
runNums    = numData(:, runColIdx);
uniqueRuns = unique(runNums(~isnan(runNums)));
nRuns      = numel(uniqueRuns);
if nRuns == 0
    error('No valid numeric values found in "Run num" column.');
end
cmap = lines(nRuns);

%% Plot each channel (skip Run num column)
plotCols  = setdiff(1:numel(headers), runColIdx);
nPlotCols = numel(plotCols);
nFigRows  = ceil(nPlotCols / 2);
nFigCols  = min(nPlotCols, 2);

figure('Name', 'PLOTS sheet', 'NumberTitle', 'off');

for pi = 1:nPlotCols
    ci  = plotCols(pi);
    ax  = subplot(nFigRows, nFigCols, pi);
    hold(ax, 'on');

    for ri = 1:nRuns
        mask = runNums == uniqueRuns(ri);
        plot(ax, xData(mask), numData(mask, ci), ...
             'o-', 'Color', cmap(ri,:), ...
             'DisplayName', sprintf('Run %g', uniqueRuns(ri)));
    end

    title(ax, headers{ci}, 'Interpreter', 'none');
    xlabel(ax, xHeader, 'Interpreter', 'none');
    xlim([2, 6])
    if plotCols(pi) == 10;
        ylim([0.5, 2.5])
    end
    grid(ax, 'on');
    hold(ax, 'off');
end

%% Legend on last subplot
lgd              = legend(ax, 'show');
lgd.Title.String = 'Outing num';
