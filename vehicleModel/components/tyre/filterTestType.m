function filteredData = filterTestType(allData, testNames, varargin)
% FILTERTESTTYPE Extract specific fields from struct, keeping longest matching names
%
%   filteredData = filterTestType(allData, testNames)
%   filteredData = filterTestType(allData, testNames, 'Name', Value, ...)
%
%   Inputs:
%       allData   - Struct with field names like A_1792run10, A_1792run10_Thermal
%       testNames - Cell array of base test names like '10', '11', '12'
%                   Will be converted to match field name format
%
%   Optional Name-Value Pairs:
%       'Prefix' - String to prepend to all testNames (default: '')
%                  Example: 'A-1792-' converts '10' -> 'A-1792-10'
%
%   Outputs:
%       filteredData - Struct containing only the specified fields
%                      If multiple matches exist (e.g., A_1792run10 and A_1792run10_Thermal),
%                      keeps the longest field name (most specific test)
%
%   Examples:
%       allData = calspanTyre(path, 'run');
%       testNames = {'10', '11', '12'};
%       filteredData = filterTestType(allData, testNames, 'Prefix', 'A-1792-');

    % Parse inputs
    p = inputParser;
    addRequired(p, 'allData', @isstruct);
    addRequired(p, 'testNames', @iscell);
    addParameter(p, 'Prefix', '', @ischar);
    parse(p, allData, testNames, varargin{:});
    
    opts = p.Results;
    
    filteredData = struct();
    
    % Get all field names from allData
    allFields = fieldnames(allData);
    
    % Loop through requested test names
    for i = 1:length(testNames)
        % Add prefix if specified
        fullTestName = [opts.Prefix, testNames{i}];
        
        % Convert test name format: A-1792-10 -> A_1792run10
        baseName = strrep(fullTestName, '-', '_');
        baseName = regexprep(baseName, '_(\d+)$', 'run$1'); % Replace last _## with run##
        
        % Find all fields that match this base name exactly
        % Must match: baseName OR baseName_SomethingSuffix (but not baseName#)
        matchingFields = {};
        for j = 1:length(allFields)
            field = allFields{j};
            % Check if field starts with baseName and next char is either:
            % - end of string
            % - underscore (for suffixes like _Thermal)
            if startsWith(field, baseName)
                % Get what comes after baseName
                remainder = field(length(baseName)+1:end);
                % Valid if empty OR starts with underscore
                if isempty(remainder) || startsWith(remainder, '_')
                    matchingFields{end+1} = field; %#ok<AGROW>
                end
            end
        end
        
        if isempty(matchingFields)
            warning('No field found matching base name "%s". Skipping.', baseName);
            continue;
        end
        
        % Keep the longest matching field name (most specific test)
        [~, longestIdx] = max(cellfun(@length, matchingFields));
        selectedField = matchingFields{longestIdx};
        
        % Add to filtered data
        filteredData.(selectedField) = allData.(selectedField);
        
        if length(matchingFields) > 1
            fprintf('Found %d matches for "%s", kept: %s\n', ...
                length(matchingFields), fullTestName, selectedField);
        end
    end
    
    fprintf('\nExtracted %d/%d requested tests\n', length(fieldnames(filteredData)), length(testNames));
end