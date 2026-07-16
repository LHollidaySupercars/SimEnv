function data_out = smp_excel_filter(data, varargin)
% SMP_EXCEL_FILTER  Filter an smp_read_excel data struct down to matching rows.
%
% Mirrors the logic of smp_filter but operates on pre-processed Excel data
% rather than raw MoTeC .ld files.
%
% Usage:
%   data2 = smp_excel_filter(data)
%   data2 = smp_excel_filter(data, 'Manufacturer', 'Ford')
%   data2 = smp_excel_filter(data, 'Manufacturer', {'Ford','Toyota'})
%   data2 = smp_excel_filter(data, 'Driver',       'T. Mostert')
%   data2 = smp_excel_filter(data, 'Session',      'Race 1')
%   data2 = smp_excel_filter(data, 'Car',          {'97','888'})
%   data2 = smp_excel_filter(data, 'Manufacturer', 'Ford', 'Session', 'R1')
%
% All filters are AND'd.  Multiple values within one filter are OR'd.
% Matching is case-insensitive partial string match.
%
% Output is the same struct shape as smp_read_excel but with .table
% narrowed to matching rows, and convenience lists refreshed.

    p = inputParser();
    p.FunctionName = 'smp_excel_filter';
    addParameter(p, 'Manufacturer', {});
    addParameter(p, 'Driver',       {});
    addParameter(p, 'Car',          {});
    addParameter(p, 'Session',      {});
    addParameter(p, 'Event',        {});
    addParameter(p, 'Venue',        {});
    addParameter(p, 'Year',         {});
    parse(p, varargin{:});
    opts = p.Results;

    T    = data.table;
    cols = data.cols;
    mask = true(height(T), 1);

    % ------------------------------------------------------------------ %
    %  Apply each active filter
    % ------------------------------------------------------------------ %
    mask = apply_filter(mask, T, cols.manufacturer, to_cell(opts.Manufacturer));
    mask = apply_filter(mask, T, cols.driver,       to_cell(opts.Driver));
    mask = apply_filter(mask, T, cols.car,          to_cell(opts.Car));
    mask = apply_filter(mask, T, cols.session,      to_cell(opts.Session));
    mask = apply_filter(mask, T, cols.event,        to_cell(opts.Event));
    mask = apply_filter(mask, T, cols.venue,        to_cell(opts.Venue));
    mask = apply_filter(mask, T, cols.year,         to_cell(opts.Year));

    n_in  = height(T);
    n_out = sum(mask);
    fprintf('smp_excel_filter: %d / %d rows match.\n', n_out, n_in);

    % ------------------------------------------------------------------ %
    %  Build output struct
    % ------------------------------------------------------------------ %
    data_out      = data;           % copy everything, then overwrite table
    data_out.table = T(mask, :);

    % Refresh convenience lists
    Tf = data_out.table;
    if ~isempty(cols.car)          && ismember(cols.car,          Tf.Properties.VariableNames), data_out.cars          = unique(Tf.(cols.car));          end
    if ~isempty(cols.driver)       && ismember(cols.driver,       Tf.Properties.VariableNames), data_out.drivers       = unique(Tf.(cols.driver));       end
    if ~isempty(cols.manufacturer) && ismember(cols.manufacturer, Tf.Properties.VariableNames), data_out.manufacturers = unique(Tf.(cols.manufacturer)); end
end


% ======================================================================= %
function mask = apply_filter(mask, T, col, keywords)
% Apply one category filter.  Empty keywords = no constraint.

    if isempty(keywords) || isempty(col) || ~ismember(col, T.Properties.VariableNames)
        return;
    end

    raw_col = T.(col);
    if isnumeric(raw_col)
        raw_col = arrayfun(@num2str, raw_col, 'UniformOutput', false);
    elseif iscell(raw_col)
        raw_col = cellfun(@(x) strtrim(char(string(x))), raw_col, 'UniformOutput', false);
    else
        raw_col = cellstr(string(raw_col));
    end

    row_match = false(height(T), 1);
    for k = 1:numel(keywords)
        kw = lower(strtrim(keywords{k}));
        hit = cellfun(@(v) contains(lower(v), kw), raw_col);
        row_match = row_match | hit;
    end
    mask = mask & row_match;
end


function c = to_cell(v)
    if isempty(v),       c = {}; return; end
    if ischar(v),        c = {v}; return; end
    if isstring(v),      c = cellstr(v); return; end
    c = v;
end
