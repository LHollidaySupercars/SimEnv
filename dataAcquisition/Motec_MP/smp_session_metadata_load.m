function meta = smp_session_metadata_load(xlsx_file, dash_file)
%SMP_SESSION_METADATA_LOAD  Load session environmental/mass data from Excel.
%
%   meta = smp_session_metadata_load(xlsx_file, dash_file)
%
%   Reads session_metadata.xlsx and returns a struct for the row whose
%   DASH_FILE column matches dash_file.  Returns empty struct if no match.
%
%   Expected columns (row 1 = headers):
%     DASH_FILE, ECU_FILE,
%     Temperature_C, Wind_Direction_deg, Wind_Speed_kph,
%     Pressure_hPa, Humidity_pct, Density,
%     Start_Mass_kg, Finish_Mass_kg

    meta = struct();

    if ~exist(xlsx_file, 'file')
        warning('smp_session_metadata_load: file not found: %s', xlsx_file);
        return;
    end

    % Read all as cell array so mixed text/number is handled correctly
    [~, ~, raw] = xlsread(xlsx_file, 'Sheet1');

    if size(raw, 1) < 2
        warning('smp_session_metadata_load: no data rows in %s', xlsx_file);
        return;
    end

    % Row 1 = headers
    headers = raw(1, :);

    % Find DASH_FILE column
    dash_col = find(strcmpi(headers, 'DASH_FILE'));
    if isempty(dash_col)
        warning('smp_session_metadata_load: DASH_FILE column not found.');
        return;
    end

    % Find row matching dash_file (case-insensitive, normalise separators + whitespace)
    norm = @(s) strtrim(lower(strrep(strrep(s, '/', '\'), '//', '\')));
    target = norm(dash_file);
    row_idx = 0;
    for r = 2 : size(raw, 1)
        cell_val = raw{r, dash_col};
        if ischar(cell_val) && strcmp(norm(cell_val), target)
            row_idx = r;
            break;
        end
    end

    if row_idx == 0
        warning(['smp_session_metadata_load: no row found matching DASH_FILE:\n' ...
                 '  %s\n  in %s'], dash_file, xlsx_file);
        return;
    end

    % Column name → struct field mapping
    col_map = { ...
        'Temperature_C',       'temperature';  ...
        'Wind_Direction_deg',  'wind_direction'; ...
        'Wind_Speed_kph',      'wind_speed'; ...
        'Pressure_hPa',        'pressure'; ...
        'Humidity_pct',        'humidity'; ...
        'Density',             'density'; ...
        'Start_Mass_kg',       'start_mass'; ...
        'Finish_Mass_kg',      'finish_mass'; ...
    };

    % Channel display names and units (parallel to col_map)
    ch_info = { ...
        'Temperature',     'C';   ...
        'Wind Direction',  'deg'; ...
        'Wind Speed',      'kph'; ...
        'Pressure',        'hPa'; ...
        'Humidity',        '%';   ...
        'Density',         'kg/m3'; ...
        'Start Mass',      'kg';  ...
        'Finish Mass',     'kg';  ...
    };

    for k = 1 : size(col_map, 1)
        col_name  = col_map{k, 1};
        field_name = col_map{k, 2};

        col_idx = find(strcmpi(headers, col_name));
        if isempty(col_idx)
            warning('smp_session_metadata_load: column "%s" not found — skipped.', col_name);
            continue;
        end

        val = raw{row_idx, col_idx};
        if ~isnumeric(val) || isnan(val)
            warning('smp_session_metadata_load: non-numeric value for "%s" — skipped.', col_name);
            continue;
        end

        meta.(field_name).value = val;
        meta.(field_name).name  = ch_info{k, 1};
        meta.(field_name).units = ch_info{k, 2};
    end

    fprintf('  Session metadata loaded: %d field(s) from row %d.\n', ...
        numel(fieldnames(meta)), row_idx - 1);
end
