function plots = smp_plot_config_load(filepath, sheet)
% SMP_PLOT_CONFIG_LOAD  Read a plot configuration Excel sheet.
%
% Expected columns (order flexible, names matched case-insensitively):
%   plotName | plotType | mathFunction | xAxis | yAxis1-4 | zAxis |
%   colours | differentiator | useSecondary | plotFilter |
%   figure | plotOrganization | plotPos |
%   xLim | yLim | outliers | outlierMethod | outlierThreshold |
%   alignChannel | alignWindow | alignMethod | alignMaxOffset
%
%   For timeseries_align: yAxis2 is the alignment channel; yAxis1/3/4 are plotted.

    if nargin < 2 || isempty(sheet)
        sheet = 1;
    end

    if ~exist(filepath, 'file')
        error('smp_plot_config_load: File not found: %s', filepath);
    end

    T = readtable(filepath, 'Sheet', sheet);
    fprintf('smp_plot_config_load: %d plot definition(s) found.\n', height(T));

    vn = T.Properties.VariableNames;

    % ---- Column detection ----
    col_name  = find_col(vn, {'plotName','plot name','name'});
    col_type  = find_col(vn, {'plotType','plotTye','plot type','type'});
    col_math  = find_col(vn, {'mathFunction','math function','math','function'});
    col_x     = find_col(vn, {'xAxis','x axis','x'});
    col_y1    = find_col(vn, {'yAxis1','y axis1','y1','yAxis'});
    col_y2    = find_col(vn, {'yAxis2','y axis2','y2'});
    col_y3    = find_col(vn, {'yAxis3','y axis3','y3'});
    col_y4    = find_col(vn, {'yAxis4','y axis4','y4'});
    col_z     = find_col(vn, {'zAxis','z axis','z'});
    col_col   = find_col(vn, {'colours','colors','colour','color','colourMode'});
    col_diff  = find_col(vn, {'differentiator','diff','differentiate'});
    col_sec   = find_col(vn, {'useSecondary','secondary','secondaryAxis','use secondary'});
    col_filt  = find_col(vn, {'plotFilter','filter','plotfilter'});
    col_xlim  = find_col(vn, {'xLim','xlim','x lim','XLim','xLimit','x limit'});
    col_ylim  = find_col(vn, {'yLim','ylim','y lim','YLim','yLimit','y limit'});
    col_outl  = find_col(vn, {'outliers','Outliers','highlightOutliers'});
    col_ometh  = find_col(vn, {'outlierMethod','outlier method','OutlierMethod'});
    col_othr   = find_col(vn, {'outlierThreshold','outlier threshold','OutlierThreshold'});
    col_oscope = find_col(vn, {'outlierScope','outlier scope','OutlierScope'});
    % Align columns — alignChannel can also come from yAxis2 for timeseries_align
    col_ach   = find_col(vn, {'alignChannel','align channel','alignCh'});
    col_awin  = find_col(vn, {'alignWindow','align window','alignWin'});
    col_ameth = find_col(vn, {'alignMethod','align method','alignMeth'});
    col_amax  = find_col(vn, {'alignMaxOffset','align max offset','alignMax'});
    % Figure grouping — 'figure' is a reserved word; readtable may rename to 'figure_1'
    col_fig   = find_col(vn, {'figure_1','figure','figNum','fig_num','fig'});
    col_lay   = find_col(vn, {'plotOrganization','plotOrg','plotLayout','organization','layout','fig_layout'});
    col_pos   = find_col(vn, {'plotPos','plotPosition','position','pos','fig_pos'});
    col_pptx  = find_col(vn, {'pptxTitle','pptx_title','pptxtitle','pptx title','slideTitle'});

    plots = struct('name',{}, 'type',{}, 'math_fn',{}, 'x_axis',{}, ...
                   'y_channels',{}, 'z_axis',{}, 'colour_mode',{}, ...
                   'differentiator',{}, 'use_secondary',{}, 'plot_filter',{}, ...
                   'x_lim',{}, 'y_lim',{}, ...
                   'highlight_outliers',{}, 'outlier_method',{}, 'outlier_threshold',{}, 'outlier_scope',{}, ...
                   'align_channel',{}, 'align_window',{}, 'align_method',{}, 'align_max_offset',{}, ...
                   'fig_num',{}, 'fig_layout',{}, 'fig_pos',{}, 'pptx_title',{});

    for r = 1:height(T)
        p.name           = get_str(T, r, col_name);
        p.type           = lower(strtrim(get_str(T, r, col_type)));
        p.math_fn        = lower(strtrim(get_str(T, r, col_math)));
        p.x_axis         = strtrim(get_str(T, r, col_x));
        p.z_axis         = strtrim(get_str(T, r, col_z));
        p.differentiator = lower(strtrim(get_str(T, r, col_diff)));

        % useSecondary
        sec_str = lower(strtrim(get_str(T, r, col_sec)));
        p.use_secondary = any(strcmpi(sec_str, {'true','yes','1'}));

        % plotFilter
        p.plot_filter = strtrim(get_str(T, r, col_filt));

        % Axis limits
        p.x_lim = parse_vec(get_str(T, r, col_xlim));
        p.y_lim = parse_vec(get_str(T, r, col_ylim));

        % Outlier highlighting
        outl_str = lower(strtrim(get_str(T, r, col_outl)));
        p.highlight_outliers = any(strcmpi(outl_str, {'true','yes','1'}));

        % Outlier method
        meth = lower(strtrim(get_str(T, r, col_ometh)));
        if isempty(meth) || ~ismember(meth, {'iqr','mad'}), meth = 'mad'; end
        p.outlier_method = meth;

        % Outlier threshold
        thr_str = get_str(T, r, col_othr);
        thr = str2double(thr_str);
        if isnan(thr)
            if strcmp(meth,'iqr'), thr = 1.5; else, thr = 3.0; end
        end
        p.outlier_threshold = thr;

        % Outlier scope: 'manufacturer' (default) or 'global'
        scope_str = lower(strtrim(get_str(T, r, col_oscope)));
        if ismember(scope_str, {'global','all'})
            p.outlier_scope = 'global';
        else
            p.outlier_scope = 'manufacturer';
        end

        % Alignment channel:
        %   1. Explicit alignChannel column takes priority
        %   2. For timeseries_align, fall back to yAxis2
        ach = strtrim(get_str(T, r, col_ach));
        if isempty(ach) && strcmpi(p.type, 'timeseries_align') && ~isempty(col_y2)
            v = strtrim(get_str(T, r, col_y2));
            if ~isempty(v) && ~strcmpi(v,'none') && ~strcmpi(v,'NaN')
                ach = v;
            end
        end
        p.align_channel = ach;

        % Alignment window, method, max offset
        p.align_window = parse_vec(get_str(T, r, col_awin));
        ameth = lower(strtrim(get_str(T, r, col_ameth)));
        if isempty(ameth) || ~ismember(ameth, {'peaks','xcorr'}), ameth = 'peaks'; end
        p.align_method = ameth;
        amax = str2double(get_str(T, r, col_amax));
        if isnan(amax), amax = 60; end
        p.align_max_offset = amax;

        % Figure grouping — use get_num to handle numeric column correctly
        p.fig_num    = get_num(T, r, col_fig);
        p.fig_layout = parse_vec(get_str(T, r, col_lay));
        p.fig_pos    = parse_vec(get_str(T, r, col_pos));
        p.pptx_title = strtrim(get_str(T, r, col_pptx));

        % Colour mode
        cm = lower(strtrim(get_str(T, r, col_col)));
        if isempty(cm) || strcmpi(cm,'none') || strcmpi(cm,'NaN')
            cm = 'manufacturer';
        end
        p.colour_mode = cm;

        % Y channels — for timeseries_align, yAxis2 is the align channel so skip it
        if strcmpi(p.type, 'timeseries_align')
            ycols = {col_y1, col_y3, col_y4};
        else
            ycols = {col_y1, col_y2, col_y3, col_y4};
        end
        ych = {};
        for i = 1:numel(ycols)
            if ~isempty(ycols{i})
                v = strtrim(get_str(T, r, ycols{i}));
                if ~isempty(v) && ~strcmpi(v,'none') && ~strcmpi(v,'NaN')
                    ych{end+1} = v; %#ok
                end
            end
        end
        p.y_channels = ych;

        plots(r) = p;

        fprintf('  [%d] "%-20s"  type=%-14s  math=%-10s  colour=%-14s  fig=%-4s  pos=%-8s  y={%s}\n', ...
            r, p.name, p.type, p.math_fn, p.colour_mode, ...
            num2str(p.fig_num), mat2str(p.fig_pos), strjoin(p.y_channels,', '));
    end
end


% ======================================================================= %
function col = find_col(var_names, candidates)
    col = '';
    for i = 1:numel(candidates)
        idx = find(strcmpi(var_names, candidates{i}), 1);
        if ~isempty(idx), col = var_names{idx}; return; end
    end
    for i = 1:numel(candidates)
        for j = 1:numel(var_names)
            if contains(lower(var_names{j}), lower(candidates{i}))
                col = var_names{j}; return;
            end
        end
    end
end

function s = get_str(T, r, col)
    if isempty(col) || ~ismember(col, T.Properties.VariableNames)
        s = ''; return;
    end
    v = T.(col)(r);
    if iscell(v),    s = strtrim(char(string(v{1}))); return; end
    if isstring(v),  s = strtrim(char(v));            return; end
    if isnumeric(v), s = '';                          return; end
    s = strtrim(char(string(v)));
end

function n = get_num(T, r, col)
% Read a numeric cell directly — handles integer columns that get_str would drop.
    n = NaN;
    if isempty(col) || ~ismember(col, T.Properties.VariableNames), return; end
    v = T.(col)(r);
    if iscell(v), v = v{1}; end
    if isnumeric(v) && isscalar(v) && isfinite(v)
        n = v;
    elseif ischar(v) || isstring(v)
        num = str2double(strtrim(char(v)));
        if isfinite(num), n = num; end
    end
end

function vec = parse_vec(s)
% Parse '[3,1]' / '3,1' / '3 1' into numeric row vector. Returns [] if blank/invalid.
    vec = [];
    if isempty(s), return; end
    s = strtrim(s);
    if strcmpi(s,'nan') || strcmpi(s,'none'), return; end
    s = regexprep(s, '[\[\]\(\)]', '');
    s = regexprep(s, '[,;]', ' ');
    nums = str2num(s); %#ok<ST2NM>
    if ~isempty(nums) && isnumeric(nums)
        vec = nums(:)';
    end
end