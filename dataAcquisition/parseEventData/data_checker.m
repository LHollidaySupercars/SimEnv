function data_checker(varargin)
% DATA_CHECKER  Visual channel quality check for MoTeC .ld files.
%
%   Reads a channel list from Excel, loads the corresponding .ld file,
%   then plots every channel grouped by datatype (one figure per datatype),
%   4 channels per figure as a 2x2 subplot grid.
%
%   Channel names in Excel may contain spaces — these are converted to
%   underscores for MATLAB field lookup before searching the data struct.
%
% Usage:
%   data_checker()                              % prompts for files via GUI
%   data_checker('ExcelPath', 'channels.xlsx')
%   data_checker('ExcelPath', 'channels.xlsx', 'LDPath', 'run.ld')
%   data_checker('ExcelPath', 'channels.xlsx', 'SheetName', 'Sheet2')
%   data_checker('ExcelPath', 'channels.xlsx', 'ChannelCol', 'ChannelName')
%   data_checker('ExcelPath', 'channels.xlsx', 'DatatypeCol', 'DataType')
%   data_checker('ExcelPath', 'channels.xlsx', 'SaveFigs', true, 'OutputDir', 'C:\figs')
%   data_checker('ExcelPath', 'channels.xlsx', 'XAxis', 'time')
%
% Excel format (sheet: 'channels'):
%   CHANNEL NAME     check
%   Corr Speed         1       <- plotted
%   Engine Speed       1       <- plotted
%   Throttle Pedal     0       <- skipped
%   Brake Pressure              <- skipped (empty = skip)
%
% Parameters (all optional, defaults shown):
%   'ExcelPath'   - path to Excel file   (default: GUI prompt)
%   'LDPath'      - path to .ld file     (default: GUI prompt)
%   'SheetName'   - Excel sheet to read  (default: 'channels')
%   'ChannelCol'  - channel name column  (default: 'CHANNEL NAME')
%   'CheckCol'    - check flag column    (default: 'check')
%   'DatatypeCol' - datatype column      (default: 'DataType')
%   'XAxis'       - 'time' or 'distance' (default: 'time')
%   'SaveFigs'    - save figures as PNG  (default: false)
%   'OutputDir'   - where to save figs   (default: same folder as .ld file)
%   'PlotWidth'   - figure width px      (default: 1400)
%   'PlotHeight'  - figure height px     (default: 900)
%   'FontSize'    - base font size       (default: 10)
%
% Notes:
%   - Only rows where 'check' == 1 are plotted; 0 or empty are skipped.
%   - Channels not found in the .ld data are reported as warnings and skipped.
%   - Channels are grouped by DataType; 4 per figure on a 2x2 subplot grid.
%   - Colour cycles through a fixed palette per subplot position.

    % ------------------------------------------------------------------ %
    %  Parse inputs via inputParser / addParameter
    % ------------------------------------------------------------------ %
    p = inputParser();
    p.FunctionName = 'data_checker';

    addParameter(p, 'ExcelPath',   '',              @ischar);
    addParameter(p, 'LDPath',      '',              @ischar);
    addParameter(p, 'SheetName',   'channels',      @ischar);
    addParameter(p, 'ChannelCol',  'CHANNEL_NAME',  @ischar);
    addParameter(p, 'CheckCol',    'check',         @ischar);
    addParameter(p, 'DatatypeCol', 'DataType',      @ischar);
    addParameter(p, 'XAxis',       'time',          @ischar);
    addParameter(p, 'SaveFigs',    false,           @islogical);
    addParameter(p, 'OutputDir',   '',              @ischar);
    addParameter(p, 'PlotWidth',   1400,            @isnumeric);
    addParameter(p, 'PlotHeight',  900,             @isnumeric);
    addParameter(p, 'FontSize',    10,              @isnumeric);

    parse(p, varargin{:});
    opts = p.Results;

    % ------------------------------------------------------------------ %
    %  File selection — GUI fallback if paths not supplied
    % ------------------------------------------------------------------ %
    if isempty(opts.ExcelPath)
        [f, d] = uigetfile({'*.xlsx;*.xls','Excel Files'}, 'Select channel list Excel');
        if isequal(f, 0), fprintf('Cancelled.\n'); return; end
        opts.ExcelPath = fullfile(d, f);
    end

    if isempty(opts.LDPath)
        [f, d] = uigetfile({'*.ld','MoTeC LD Files'}, 'Select .ld file');
        if isequal(f, 0), fprintf('Cancelled.\n'); return; end
        opts.LDPath = fullfile(d, f);
    end

    if isempty(opts.OutputDir)
        [d, ~, ~] = fileparts(opts.LDPath);
        opts.OutputDir = d;
    end

    % ------------------------------------------------------------------ %
    %  Read channel list from Excel
    % ------------------------------------------------------------------ %
    fprintf('\n=== DATA CHECKER ===\n');
    fprintf('Excel : %s\n', opts.ExcelPath);
    fprintf('LD    : %s\n\n', opts.LDPath);

    T = readtable(opts.ExcelPath, 'Sheet', opts.SheetName);
%                   'VariableNamingRule', 'preserve');

    % Locate required columns
    ch_col = find_col(T, opts.ChannelCol);
    if isempty(ch_col)
        error('data_checker: Cannot find channel column "%s".\nAvailable columns: %s', ...
              opts.ChannelCol, strjoin(T.Properties.VariableNames, ', '));
    end

    check_col = find_col(T, opts.CheckCol);
    if isempty(check_col)
        error('data_checker: Cannot find check column "%s".\nAvailable columns: %s', ...
              opts.CheckCol, strjoin(T.Properties.VariableNames, ', '));
    end

    dt_col       = find_col(T, opts.DatatypeCol);
    has_datatype = ~isempty(dt_col);

    % Extract raw columns
    ch_names_raw = T.(ch_col);
    if ~iscell(ch_names_raw)
        ch_names_raw = cellstr(string(ch_names_raw));
    end

    check_vals = T.(check_col);
    if ~isnumeric(check_vals)
        check_vals = str2double(string(check_vals));
    end

    % Keep only rows where check == 1 AND channel name is non-empty
    has_name  = ~cellfun(@(x) isempty(strtrim(x)), ch_names_raw);
    is_active = (check_vals == 1);
    keep      = has_name & is_active;

    fprintf('Total rows in Excel : %d\n', height(T));
    fprintf('Rows with check = 1 : %d\n\n', sum(keep));

    ch_names_raw = ch_names_raw(keep);

    if has_datatype
        dt_vals = T.(dt_col);
        if isnumeric(dt_vals)
            dt_vals = dt_vals(keep);
        else
            dt_vals = str2double(string(dt_vals(keep)));
        end
    else
        dt_vals = ones(sum(keep), 1);
        fprintf('[WARN] No DataType column found — all channels plotted in one group.\n');
    end

    n_channels = numel(ch_names_raw);
    if n_channels == 0
        fprintf('No channels selected (check column has no 1s). Exiting.\n');
        return;
    end
    fprintf('Channels to plot: %d\n\n', n_channels);

    % ------------------------------------------------------------------ %
    %  Load .ld file
    % ------------------------------------------------------------------ %
    fprintf('Loading .ld file...\n');
    ld_data = motec_ld_reader(opts.LDPath);
    ld_fields = fieldnames(ld_data);
    fprintf('\n');

    % ------------------------------------------------------------------ %
    %  Match Excel channel names → .ld struct fields
    % ------------------------------------------------------------------ %
    %  Excel names may have spaces. Spaces between words → underscores.
    % ------------------------------------------------------------------ %
    matched_field    = cell(n_channels, 1);
    matched_raw_name = cell(n_channels, 1);
    not_found        = {};

    for i = 1:n_channels
        raw_name  = strtrim(ch_names_raw{i});
        % Replace spaces with underscores for field lookup
        san_name  = regexprep(raw_name, '\s+', '_');
        % Also apply the same sanitisation as the reader
        san_name2 = sanitise_fieldname(san_name);

        found = '';
        % 1. Exact match on sanitised name
        if isfield(ld_data, san_name2)
            found = san_name2;
        end
        % 2. Case-insensitive scan
        if isempty(found)
            for fi = 1:numel(ld_fields)
                if strcmpi(ld_fields{fi}, san_name2)
                    found = ld_fields{fi};
                    break;
                end
            end
        end
        % 3. Partial match fallback (raw_name contained in raw_name field)
        if isempty(found)
            for fi = 1:numel(ld_fields)
                if isfield(ld_data.(ld_fields{fi}), 'raw_name')
                    if strcmpi(ld_data.(ld_fields{fi}).raw_name, raw_name)
                        found = ld_fields{fi};
                        break;
                    end
                end
            end
        end

        if isempty(found)
            not_found{end+1} = raw_name; %#ok
            matched_field{i}    = '';
            matched_raw_name{i} = raw_name;
        else
            matched_field{i}    = found;
            matched_raw_name{i} = raw_name;
        end
    end

    % Report missing channels
    if ~isempty(not_found)
        fprintf('[WARN] The following channels were NOT found in the .ld file:\n');
        for i = 1:numel(not_found)
            fprintf('  - "%s"\n', not_found{i});
        end
        fprintf('\n');
    end

    % ------------------------------------------------------------------ %
    %  Group channels by datatype
    % ------------------------------------------------------------------ %
    unique_dt = unique(dt_vals(~isnan(dt_vals)));
    unique_dt = sort(unique_dt);

    % Colour palette (cycles within each group)
    palette = [
        0.12  0.47  0.71;   % blue
        0.90  0.33  0.05;   % orange
        0.20  0.63  0.17;   % green
        0.84  0.15  0.16;   % red
        0.58  0.40  0.74;   % purple
        0.55  0.34  0.29;   % brown
        0.89  0.47  0.76;   % pink
        0.74  0.74  0.13;   % yellow-green
        0.09  0.75  0.81;   % cyan
    ];

    % ------------------------------------------------------------------ %
    %  Plot — one figure per datatype, 4 channels per figure (2x2 subplot)
    % ------------------------------------------------------------------ %
    fig_handles = [];
    fig_titles  = {};

    for di = 1:numel(unique_dt)
        dt = unique_dt(di);

        % Channels in this datatype group that were successfully matched
        in_group = find(dt_vals == dt & ~cellfun(@isempty, matched_field));
        if isempty(in_group), continue; end

        % Page through them 4 at a time
        page = 1;
        for start_idx = 1:4:numel(in_group)
            chunk = in_group(start_idx : min(start_idx+3, numel(in_group)));
            n_plots = numel(chunk);

            fig_title = sprintf('DataType %d  —  Page %d', dt, page);
            fig = figure('Visible', 'on', ...
                         'Color',   'white', ...
                         'Name',    fig_title, ...
                         'Position',[50 50 opts.PlotWidth opts.PlotHeight]);
            sgtitle(fig_title, 'FontSize', opts.FontSize+2, 'FontWeight', 'bold');

            for sp = 1:n_plots
                row_idx   = chunk(sp);
                field     = matched_field{row_idx};
                disp_name = matched_raw_name{row_idx};
                ch        = ld_data.(field);

                ax = subplot(2, 2, sp, 'Parent', fig);
                hold(ax, 'on');
                grid(ax, 'on');
                box(ax, 'on');
                set(ax, 'FontSize', opts.FontSize, ...
                        'FontName', 'Arial', ...
                        'GridAlpha', 0.3, ...
                        'GridLineStyle', '--', ...
                        'Color', [0.97 0.97 0.97]);

                % Determine x axis
                if strcmpi(opts.XAxis, 'distance') && isfield(ch, 'dist_data')
                    x_vec = ch.dist_vec;
                    y_vec = ch.dist_data;
                    x_lbl = 'Distance (m)';
                else
                    x_vec = ch.time;
                    y_vec = ch.data;
                    x_lbl = 'Time (s)';
                end

                col = palette(mod(sp-1, size(palette,1))+1, :);

                plot(ax, x_vec, y_vec, '-', ...
                    'Color',     col, ...
                    'LineWidth', 1.2);

                title(ax, disp_name, ...
                    'FontSize',   opts.FontSize, ...
                    'FontWeight', 'bold', ...
                    'Interpreter','none');
                xlabel(ax, x_lbl, 'FontSize', opts.FontSize-1);

                units_str = '';
                if isfield(ch, 'units') && ~isempty(ch.units)
                    units_str = ch.units;
                end
                ylabel(ax, units_str, 'FontSize', opts.FontSize-1);

                % Annotation: sample rate + n samples
                sr  = ch.sample_rate;
                n_s = numel(y_vec);
                ann = sprintf('%g Hz  |  %d samples', sr, n_s);
                text(ax, 0.01, 0.97, ann, ...
                    'Units',              'normalized', ...
                    'VerticalAlignment',  'top', ...
                    'HorizontalAlignment','left', ...
                    'FontSize',           opts.FontSize-2, ...
                    'Color',              [0.4 0.4 0.4], ...
                    'Interpreter',        'none');
            end

            % Hide unused subplot panels
            for sp = n_plots+1 : 4
                ax_empty = subplot(2, 2, sp, 'Parent', fig);
                set(ax_empty, 'Visible', 'off');
            end

            fig_handles(end+1) = fig;   %#ok
            fig_titles{end+1}  = fig_title; %#ok
            page = page + 1;
        end
    end

    % ------------------------------------------------------------------ %
    %  Save figures if requested
    % ------------------------------------------------------------------ %
    if opts.SaveFigs && ~isempty(fig_handles)
        if ~isfolder(opts.OutputDir)
            mkdir(opts.OutputDir);
        end
        fprintf('\nSaving figures to: %s\n', opts.OutputDir);
        for fi = 1:numel(fig_handles)
            safe_title = regexprep(fig_titles{fi}, '[^\w\s-]', '');
            safe_title = strtrim(regexprep(safe_title, '\s+', '_'));
            out_path   = fullfile(opts.OutputDir, [safe_title '.png']);
            exportgraphics(fig_handles(fi), out_path, ...
                'Resolution', 150, 'BackgroundColor', 'white');
            fprintf('  Saved: %s\n', out_path);
        end
    end

    fprintf('\ndata_checker: Done. %d figure(s) created.\n', numel(fig_handles));
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function col_name = find_col(T, target)
% Case-insensitive column name lookup. Returns empty string if not found.
    col_name = '';
    vars = T.Properties.VariableNames;
    for i = 1:numel(vars)
        if strcmpi(vars{i}, target)
            col_name = vars{i};
            return;
        end
    end
    % Partial match fallback
    for i = 1:numel(vars)
        if contains(lower(vars{i}), lower(target))
            col_name = vars{i};
            return;
        end
    end
end


function name = sanitise_fieldname(raw)
% Mirror the sanitisation logic in motec_ld_reader so lookups always match.
    if isempty(raw), name = ''; return; end
    name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '_$', '');
    if isempty(name), return; end
    if ~isletter(name(1)), name = ['ch_' name]; end
    name = name(1:min(end, 63));
end