% debug_br2_detection.m
% Standalone BR2 Mode B detection debugger.
%
% 1. Loads c:\SimEnv\debug_session.mat (auto-discovers session variable).
% 2. Runs Pass 1 (S/F + pit-in) and Pass 2 (garage runs) inline,
%    printing a diagnostic table of every 999-run decision.
% 3. Calls lap_slicer(session, opts) with beacon_check=true to generate
%    the full diagnostic plot using the current production code.

clear; clc;

% -----------------------------------------------------------------------
% Add path to lap_slicer
% -----------------------------------------------------------------------
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', '..', 'dataAcquisition', 'parseEventData'));

% -----------------------------------------------------------------------
% Load debug_session.mat — discover session variable
% -----------------------------------------------------------------------
MAT_PATH = 'c:\SimEnv\debug_session.mat';
fprintf('Loading %s ...\n', MAT_PATH);
S = load(MAT_PATH);
vars = fieldnames(S);

session = [];
session_var_name = '';
for vi = 1:numel(vars)
    v = S.(vars{vi});
    if isstruct(v) && ~isempty(fieldnames(v))
        f = fieldnames(v);
        if isstruct(v.(f{1})) && isfield(v.(f{1}), 'data') && isfield(v.(f{1}), 'time')
            session = v;
            session_var_name = vars{vi};
            break;
        end
    end
end
if isempty(session)
    error('No session struct found in %s.\nVariables present: %s', MAT_PATH, strjoin(vars, ', '));
end
fprintf('Session variable : ''%s''  (%d channels)\n\n', session_var_name, numel(fieldnames(session)));

% -----------------------------------------------------------------------
% Constants — must match lap_slicer.m exactly
% -----------------------------------------------------------------------
BR2_CHANNEL_NAME  = 'BR2_Beacon_Number';
BR2_SF_LOOKBACK_S = 2.0;
BR2_PIT_MIN_S     = 1.0;
BR2_MIN_HOLD_S    = 0.05;

% -----------------------------------------------------------------------
% Find BR2 channel
% -----------------------------------------------------------------------
ch_names  = fieldnames(session);
br2_field = '';
br2_san   = regexprep(BR2_CHANNEL_NAME, '[^a-zA-Z0-9_]', '_');
for ci = 1:numel(ch_names)
    if strcmpi(ch_names{ci}, BR2_CHANNEL_NAME) || strcmpi(ch_names{ci}, br2_san)
        br2_field = ch_names{ci};
        break;
    end
end
if isempty(br2_field)
    error('BR2 channel ''%s'' not found.\nAvailable: %s', BR2_CHANNEL_NAME, strjoin(ch_names, ', '));
end
fprintf('BR2 field        : %s\n', br2_field);

% -----------------------------------------------------------------------
% Build raw + ZOH arrays
% -----------------------------------------------------------------------
br2_raw  = round(session.(br2_field).data(:));
br2_time = session.(br2_field).time(:);
[br2_zoh, br2_zoh_t] = local_beacon_to_zoh(br2_raw, br2_time, BR2_MIN_HOLD_S);

fprintf('BR2 samples      : %d\n', numel(br2_raw));
fprintf('ZOH steps        : %d\n', numel(br2_zoh));
fprintf('Unique ZOH vals  : %s\n\n', mat2str(unique(br2_zoh)'));

% -----------------------------------------------------------------------
% PASS 1 -- S/F crossings + pit-in detection
% -----------------------------------------------------------------------
% ZOH finds the 999 transition; raw signal used for forward discriminator
% scan so sub-50ms 1500 pulses (at race speed) are not missed.
%   S/F  : ANY -> 999 -> 1500 -> 900 -> 996   (1500 = discriminator)
%   Pit-in: 996 -> 999 -> 900/0               (no 1500, pred must be 996)
% -----------------------------------------------------------------------
br2_sf_times = [];
br2_pitin_t  = [];
n_br2_zoh    = numel(br2_zoh);

fprintf('--- Pass 1: 999-run entries ---\n');
fprintf('  %-9s  %-8s  %-12s  %-12s  %s\n', ...
    't(s)', 'pred_zoh', 'first_non999', 'action', 'reason');
fprintf('  %s\n', repmat('-', 1, 72));

for i = 2:n_br2_zoh
    if br2_zoh(i) == 999 && br2_zoh(i-1) ~= 999
        t_999    = br2_zoh_t(i);
        pred_996 = (br2_zoh(i-1) == 996);

        raw_after   = br2_raw(br2_time >= t_999);
        raw_t_after = br2_time(br2_time >= t_999);
        fn_idx      = find(raw_after ~= 999, 1);
        if isempty(fn_idx)
            fprintf('  t=%-7.2f  %-8d  %-12s  %-12s  no non-999 found\n', ...
                t_999, br2_zoh(i-1), 'N/A', 'skipped');
            continue;
        end
        first_non999 = raw_after(fn_idx);

        if first_non999 == 1500
            action = 'SF-cross';
            raw_from_1500 = raw_after(fn_idx:end);
            raw_t_1500    = raw_t_after(fn_idx:end);
            idx996 = find(raw_from_1500 == 996, 1);
            if ~isempty(idx996)
                sf_t = raw_t_1500(idx996);
                br2_sf_times(end+1) = sf_t;  %#ok<AGROW>
                reason = sprintf('-> SF boundary t=%.2f', sf_t);
            else
                reason = '1500 found but no 996 after';
            end
        elseif (first_non999 == 900 || first_non999 == 0) && pred_996
            action = 'PIT-IN  <=';
            reason = sprintf('pred=996 first_non999=%d', first_non999);
            br2_pitin_t(end+1) = t_999;  %#ok<AGROW>
        else
            action = 'ignored';
            reason = sprintf('pred=%d first_non999=%d', br2_zoh(i-1), first_non999);
        end

        fprintf('  t=%-7.2f  %-8d  %-12d  %-12s  %s\n', ...
            t_999, br2_zoh(i-1), first_non999, action, reason);
    end
end

% -----------------------------------------------------------------------
% PASS 2 — Garage runs (val == 0 or 900, duration > BR2_PIT_MIN_S)
% -----------------------------------------------------------------------
n_br2          = numel(br2_raw);
br2_pit900_t0  = [];
br2_pit900_t1  = [];
br2_pit900_dur = [];
br2_pit900_val = [];

i = 1;
while i <= n_br2
    if br2_raw(i) == 900 || br2_raw(i) == 0
        gval      = br2_raw(i);
        run_start = i;
        while i <= n_br2 && (br2_raw(i) == 900 || br2_raw(i) == 0)
            i = i + 1;
        end
        run_end  = i - 1;
        run_dur  = br2_time(run_end) - br2_time(run_start);
        if run_dur > BR2_PIT_MIN_S
            br2_pit900_t0(end+1)  = br2_time(run_start);  %#ok<AGROW>
            br2_pit900_t1(end+1)  = br2_time(run_end);    %#ok<AGROW>
            br2_pit900_dur(end+1) = run_dur;               %#ok<AGROW>
            br2_pit900_val(end+1) = gval;                  %#ok<AGROW>
        end
    else
        i = i + 1;
    end
end

fprintf('\nGarage runs (>%.1fs) : %d\n', BR2_PIT_MIN_S, numel(br2_pit900_t0));
for gi = 1:numel(br2_pit900_t0)
    fprintf('  run %d : val=%d  t0=%.2f  t1=%.2f  dur=%.1fs\n', ...
        gi, br2_pit900_val(gi), br2_pit900_t0(gi), br2_pit900_t1(gi), br2_pit900_dur(gi));
end

% -----------------------------------------------------------------------
% Full lap_slicer run — generates beacon_check_plot automatically
% -----------------------------------------------------------------------
fprintf('\n--- Running lap_slicer (beacon_check=true) ---\n\n');
opts                    = struct();
opts.beacon_check       = true;
opts.beacon_check_label = 'debug session';
opts.verbose            = true;

laps = lap_slicer(session, opts);

fprintf('\n%-6s  %-10s  %-10s  %-12s  %s\n', 'Lap', 't_start', 't_end', 'Duration', 'Type');
fprintf('%s\n', repmat('-', 1, 55));
for k = 1:numel(laps)
    fprintf('%-6d  %-10.2f  %-10.2f  %-12.3f  %s\n', ...
        laps(k).lap_number, laps(k).t_start, laps(k).t_end, ...
        laps(k).lap_time, laps(k).lap_type);
end

% -----------------------------------------------------------------------
% Local functions
% -----------------------------------------------------------------------
function [data_out, time_out] = local_beacon_to_zoh(data, time, min_hold_s)
% Exact copy of beacon_to_zoh logic from lap_slicer.m
    data = data(:);
    time = time(:);
    data_out = zeros(0, 1, 'like', data);
    time_out = zeros(0, 1, 'like', time);
    n = numel(data);
    if n == 0, return; end
    run_start = 1;
    for idx = 2:n
        at_end = (idx == n);
        if data(idx) ~= data(idx-1) || at_end
            run_end  = idx - 1;
            if at_end && data(idx) == data(idx-1), run_end = n; end
            hold_dur = time(run_end) - time(run_start);
            if hold_dur >= min_hold_s || run_start == 1
                data_out(end+1) = data(run_start); %#ok<AGROW>
                time_out(end+1) = time(run_start); %#ok<AGROW>
            end
            run_start = idx;
        end
    end
    if isempty(time_out) || time_out(end) ~= time(run_start)
        data_out(end+1) = data(run_start); %#ok<AGROW>
        time_out(end+1) = time(run_start); %#ok<AGROW>
    end
end

