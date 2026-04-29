function startingValue = startingValues(requestChannels, excelFiltering, session)
% STARTINGVALUES  Filter session channels based on Excel-defined bounds.
%
% Inputs:
%   requestChannels  - cell array of newChannelName strings to process
%   excelFiltering   - path to filteringRequest.xlsx
%   session          - struct of channel vectors (plain doubles)
%
% Output:
%   startingValue    - struct where each field is a newChannelName
%                      containing the filtered values of filteredChannel

    startingValue = struct();

    % --- Read both sheets ---
    T_filt   = readtable(excelFiltering, 'Sheet', 'filtering');
    T_bounds = readtable(excelFiltering, 'Sheet', 'channel_bounds');

    % --- Discover max filter index once from channel_bounds headers ---
    vn = T_bounds.Properties.VariableNames;
    nums = zeros(1, numel(vn));
    for v = 1:numel(vn)
        tokens = regexp(vn{v}, '\d+', 'match');
        if ~isempty(tokens)
            nums(v) = str2double(tokens{end});
        end
    end
    maxFilters = max(nums);

    % --- Extract bounds sheet key columns by index (col 1 = case, col 2 = filterChannel) ---
    case_col_vals = T_bounds{:,1};
    if ~iscell(case_col_vals)
        case_col_vals = cellstr(string(case_col_vals));
    end
    fc_col_vals = T_bounds{:,2};
    if ~iscell(fc_col_vals)
        fc_col_vals = cellstr(string(fc_col_vals));
    end

    for i = 1:numel(requestChannels)
        caseName = requestChannels{i};

        % --- Find row in filtering sheet by newChannelName ---
        % --- Find row in filtering sheet by filteredChannel ---
        filt_row = find(strcmp(T_filt.filteredChannel, requestChannels{i}));
        if isempty(filt_row)
            warning('startingValues: "%s" not found in filteredChannel column. Skipping.', requestChannels{i});
            continue;
        end
        filt_row = filt_row(1);

        % --- Derive both names from the row ---
        caseName        = strtrim(T_filt.newChannelName{filt_row});
        filteredChannel = strtrim(T_filt.filteredChannel{filt_row});
        if ~isfield(session, filteredChannel)
            warning('startingValues: filteredChannel "%s" not found in session. Skipping.', filteredChannel);
            continue;
        end
        chanData = session.(filteredChannel).data;
        n    = numel(session.(filteredChannel).data);
        mask = true(n, 1);

        % --- Get filter channels from filtering sheet, skip empty and 'temp' ---
        filterChannelCols = {'filterChannel_1','filterChannel_2','filterChannel_3'};
        filterChannels = {};
        for fc = 1:numel(filterChannelCols)
            col = filterChannelCols{fc};
            if ismember(col, T_filt.Properties.VariableNames)
                val = strtrim(T_filt.(col){filt_row});
                if ~isempty(val) && ~strcmpi(val, 'temp')
                    filterChannels{end+1} = val; %#ok
                end
            end
        end

        % --- For each filter channel apply its bounds ---
        % --- For each filter channel apply its bounds ---
        outer_mask = true(n, 1);

        for fc = 1:numel(filterChannels)
            fcName = filterChannels{fc};

            bounds_row = find(strcmp(case_col_vals, caseName) & ...
                              strcmp(fc_col_vals, fcName));
            if isempty(bounds_row)
                warning('startingValues: No bounds row found for case "%s" / filterChannel "%s". Skipping.', caseName, fcName);
                continue;
            end
            bounds_row = bounds_row(1);

            if ~isfield(session, fcName)
                warning('startingValues: filterChannel "%s" not found in session. Skipping.', fcName);
                continue;
            end
            % --- Align filterVec to whichever channel has higher frequency ---
            if numel(session.(fcName).data) >= n
                % filter channel is higher freq — resample filteredChannel up to it
                filterVec = session.(fcName).data;
                chanData  = align_to(session.(filteredChannel), session.(fcName));
                n         = numel(chanData);
                outer_mask = true(n, 1);
                fc_mask    = true(n, 1);
            else
                % filtered channel is higher freq — resample filterChannel up to it
                filterVec = align_to(session.(fcName), session.(filteredChannel));
            end

            if numel(filterVec) ~= n
                warning('startingValues: filterChannel "%s" length (%d) does not match filteredChannel length (%d). Skipping.', fcName, numel(filterVec), n);
                continue;
            end

            fc_mask = true(n, 1);

            for b = 1:maxFilters
                blf_col = sprintf('BLF_%d', b);
                bl_col  = sprintf('boundLower_%d', b);
                buf_col = sprintf('BUF_%d', b);
                bu_col  = sprintf('boundUpper_%d', b);

                % Lower bound
                if ismember(blf_col, vn) && ismember(bl_col, vn)
                    blf = strtrim(T_bounds.(blf_col){bounds_row});
                    bl  = T_bounds.(bl_col)(bounds_row);
                    if ~strcmp(blf, '~') && ~isnan(bl)
                        fc_mask = fc_mask & apply_op(filterVec, blf, bl);
                    end
                end

                % Upper bound
                if ismember(buf_col, vn) && ismember(bu_col, vn)
                    buf = strtrim(T_bounds.(buf_col){bounds_row});
                    bu  = T_bounds.(bu_col)(bounds_row);
                    if ~strcmp(buf, '~') && ~isnan(bu)
                        fc_mask = fc_mask & apply_op(filterVec, buf, bu);
                    end
                end
            end

            outer_mask = outer_mask & fc_mask;
        end

        % --- Apply mask and store under newChannelName ---
        startingValue.(caseName) = chanData(outer_mask);
        fprintf('startingValues: "%s" -> %d / %d samples kept.\n', caseName, sum(outer_mask), n);

        % --- Apply mask and store under newChannelName ---
%         startingValue.(caseName) = session.(filteredChannel)(mask);
        startingValue.(caseName) = chanData(mask);
        fprintf('startingValues: "%s" -> %d / %d samples kept.\n', caseName, sum(mask), n);
    end
end


% ======================================================================= %
function result = apply_op(vec, op, val)
% APPLY_OP  Apply a comparison operator to a vector.
    switch strtrim(op)
        case '='
            result = vec == val;
        case '!='
            result = vec ~= val;
        case '<'
            result = vec < val;
        case '>'
            result = vec > val;
        case '<='
            result = vec <= val;
        case '>='
            result = vec >= val;
        otherwise
            warning('apply_op: Unknown operator "%s". Returning all-true mask.', op);
            result = true(size(vec));
    end
end