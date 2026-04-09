%% Full — date filter + xref against both alias files + export
clear opts
opts.date_from        = datetime(2026, 3, 5);
opts.alias_file       = 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
opts.event_alias_file = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
opts.xref_export      = 'C:\Reports\AGP_alias_check.xlsx';
result = smp_discover_aliases('E:\2026\02_AGP\_TeamData', opts);

% -----------------------------------------------------------------------
% Inspect raw strings (paste these into alias Excel files):
result.drivers            % -> driverAlias.xlsx          (DRV column)
result.sessions           % -> eventAlias.xlsx SESSION sheet (col A)
result.venues             % -> eventAlias.xlsx VENUE sheet   (col A)

% Inspect xref breakdown:
result.xref.drivers       % .matched / .unmatched / .n_matched / .n_unmatched
result.xref.sessions      % .matched / .unmatched / .n_matched / .n_unmatched
result.xref.venues        % .matched / .unmatched / .n_matched / .n_unmatched

% Overall status:
result.xref.ok            % true ONLY when drivers AND sessions are fully matched

% Full file manifest (one row per .ld file):
% result.manifest
% -----------------------------------------------------------------------