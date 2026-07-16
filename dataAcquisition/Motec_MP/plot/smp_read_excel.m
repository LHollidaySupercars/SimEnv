function data = smp_read_excel(filepath)
% SMP_READ_EXCEL  Read a pre-processed race data Excel sheet.
%
% Expects the sheet to have a header row. Column names are flexible —
% the function maps common variants to standardised internal field names.
%
% Usage:
%   data = smp_read_excel('C:\Reports\SMP_R1_Data.xlsx')
%
% Output:
%   data  - struct with fields:
%     .table         - full MATLAB table as read from Excel
%     .cars          - unique car numbers
%     .drivers       - unique driver names
%     .manufacturers - unique manufacturer strings
%     .teams         - unique team names
%     .cols          - struct of detected column names for each standard field

    if ~exist(filepath, 'file')
        error('smp_read_excel: File not found: %s', filepath);
    end

    fprintf('Reading Excel: %s\n', filepath);
    T = readtable(filepath, 'VariableNamingRule', 'preserve');
    fprintf('  Rows: %d   Columns: %d\n', height(T), width(T));
    fprintf('  Columns: %s\n', strjoin(T.Properties.VariableNames, ', '));

    % ------------------------------------------------------------------ %
    %  Map flexible column names to standard fields
    % ------------------------------------------------------------------ %
    cols = detect_columns(T.Properties.VariableNames);
    data.cols  = cols;
    data.table = T;

    % ------------------------------------------------------------------ %
    %  Extract convenience lists
    % ------------------------------------------------------------------ %
    if ~isempty(cols.car)
        data.cars = unique(T.(cols.car));
    else
        data.cars = {};
        fprintf('  [WARN] No car number column detected.\n');
    end

    if ~isempty(cols.driver)
        data.drivers = unique(T.(cols.driver));
    else
        data.drivers = {};
    end

    if ~isempty(cols.manufacturer)
        data.manufacturers = unique(T.(cols.manufacturer));
    else
        data.manufacturers = {};
    end

    if ~isempty(cols.team)
        data.teams = unique(T.(cols.team));
    else
        data.teams = {};
    end

    fprintf('  Cars: %d   Drivers: %d   Manufacturers: %d   Teams: %d\n', ...
        numel(data.cars), numel(data.drivers), numel(data.manufacturers), numel(data.teams));
end


% ======================================================================= %
function cols = detect_columns(var_names)
% Attempt to map actual Excel column names to standard internal names.

    cols.car          = match_col(var_names, {'Car','Car No','Car Number','#','CarNo'});
    cols.driver       = match_col(var_names, {'Driver','Driver Name','Pilot'});
    cols.manufacturer = match_col(var_names, {'Manufacturer','Make','Mfr','Brand'});
    cols.team         = match_col(var_names, {'Team','Team Name','TeamName','Squad'});
    cols.lap          = match_col(var_names, {'Lap','Lap Number','LapNo','Lap No'});
    cols.lap_time     = match_col(var_names, {'Lap Time','LapTime','Time','Lap_Time'});
    cols.session      = match_col(var_names, {'Session','Session Type','SessionType'});
    cols.event        = match_col(var_names, {'Event','Round','Race'});
    cols.venue        = match_col(var_names, {'Venue','Track','Circuit'});
    cols.year         = match_col(var_names, {'Year','Season'});
    cols.outing       = match_col(var_names, {'Outing','Outing No','OutingNo','Run','Run No'});

    % Print what was found
    fields = fieldnames(cols);
    for i = 1:numel(fields)
        f = fields{i};
        if ~isempty(cols.(f))
            fprintf('  Col %-14s -> "%s"\n', f, cols.(f));
        end
    end
end


function match = match_col(var_names, candidates)
% Case-insensitive match of candidate names against actual column headers.
    match = '';
    for i = 1:numel(candidates)
        idx = find(strcmpi(var_names, candidates{i}), 1);
        if ~isempty(idx)
            match = var_names{idx};
            return;
        end
    end
    % Partial match fallback
    for i = 1:numel(candidates)
        for j = 1:numel(var_names)
            if contains(lower(var_names{j}), lower(candidates{i}))
                match = var_names{j};
                return;
            end
        end
    end
end
