function [merged, report] = concat_sessions(sessions, opts)
% CONCAT_SESSIONS  Concatenate a cell array of session structs along their
%                  time axes.
%
% Each subsequent file is straight-appended with a one-sample-period gap.
% No overlap trimming is performed — beacon-60 boundary detection in
% lap_slicer identifies true lap boundaries directly from channel data.
%
% Lap_Number data in each subsequent session is renumbered so it continues
% monotonically from the end of the preceding session, preventing the lap
% collision that would otherwise cause lap_slicer's unique() call to merge
% laps across the file boundary.
%
% INPUT
%   sessions  - {1 x N} cell array of session structs.
%               Each struct has fields named after channels;
%               each field is a struct with .data (double vector) and
%               .time (double vector, seconds from file start).
%   opts      - (optional) struct:
%       .uniqueFingerprint  bool  Detect and skip duplicate/superset sessions.
%                                 Primary method: GPS_Time point lookup.
%                                 Fallback: start+end speed fingerprint.
%                                 Default: false.
%
% OUTPUT
%   merged    - single session struct with all channels concatenated.
%
% Duplicate detection (opts.uniqueFingerprint = true):
%   PRIMARY — GPS_Time point lookup:
%     Takes N_PROBE interior samples from session S's GPS_Time channel,
%     looks each up in session R by wall-clock time, and cross-checks a
%     speed/acceleration channel value at that moment.  Trim-immune because
%     probes are drawn from the interior of S and matched by absolute time.
%     Requires GPS_Time channel to be present in both sessions.
%
%   FALLBACK — start+end speed fingerprint (used when GPS_Time absent):
%     Requires both the first AND last K samples to match.  Degenerate
%     (near-zero variance) fingerprints are never considered a match.

    if nargin < 2, opts = struct(); end
    unique_fp = false;
    if isfield(opts, 'uniqueFingerprint'), unique_fp = opts.uniqueFingerprint; end
    verbose = false;
    if isfield(opts, 'verbose'), verbose = opts.verbose; end

    % ---- GPS lookup parameters ----
    GPS_CHANNEL   = 'GPS_Time';
    GPS_TOL       = 0.5;    % seconds — max GPS_Time difference to count as same moment
    VAL_CANDIDATES = {'Ground_Speed','Speedkmh','Speed','Lateral_Acc','Longitudinal_Acc'};
    VAL_TOL        = 2.0;   % km/h (or m/s²) — max value difference at matched timestamp
    N_PROBE        = 7;     % number of interior probe points
    MATCH_THRESH   = 5;     % minimum matching probes out of N_PROBE to call duplicate

    % ---- Fallback fingerprint parameters ----
    FPRINT_CANDIDATES = {'Ground_Speed', 'Speedkmh', 'Speed', 'Lateral_Acc', 'Longitudinal_Acc'};
    FPRINT_K     = 50;
    FPRINT_TOL   = 0.01;

    % ---- Distributed sample parameters (Method 4) ----
    DIST_N      = 200;    % evenly-spaced samples across full channel
    DIST_TOL    = 0.01;   % per-sample tolerance (same units as channel)
    DIST_THRESH = 0.99;   % fraction of samples that must match
    build_report = nargout > 1;

    n_sessions = numel(sessions);
    fp_start   = cell(n_sessions, 1);
    fp_end     = cell(n_sessions, 1);

    if unique_fp || build_report
        for s = 1:n_sessions
            [fp_start{s}, fp_end{s}] = make_fingerprint(sessions{s}, FPRINT_CANDIDATES, FPRINT_K);
        end
    end

    % Initialise report struct (one entry per input session).
    if build_report
        report = struct('session_idx', num2cell((1:n_sessions)'), ...
                        'status',      repmat({'kept'},    n_sessions, 1), ...
                        'reason',      repmat({''},        n_sessions, 1), ...
                        'matched_idx', num2cell(zeros(n_sessions, 1)), ...
                        'tag',         repmat({''},        n_sessions, 1), ...
                        'fp_start',    fp_start, ...
                        'fp_end',      fp_end);
    else
        report = [];
    end

    % Determine which sessions to keep (duplicate/superset check).
    % Rule: if all of session S's data exists inside session R, drop S.
    % Three methods tried in order:
    %   1. GPS_Time point lookup  — trim-immune, wall-clock based
    %   2. Lap-time subset check  — all of S's lap durations found in R
    %   3. Start+end fingerprint  — final fallback (exact duplicate only)
    keep = true(n_sessions, 1);
    if unique_fp
        for s = 2:n_sessions
            if isempty(fp_start{s}), continue; end
            for r = 1:s-1
                if ~keep(r), continue; end

                is_dup  = false;
                method  = '';
                n_match = [];

                % ---- METHOD 1: GPS_Time point lookup (S probes inside R) ----
                [is_dup, n_match, gps_method] = gps_lookup_match( ...
                    sessions{s}, sessions{r}, ...
                    GPS_CHANNEL, GPS_TOL, VAL_CANDIDATES, VAL_TOL, ...
                    N_PROBE, MATCH_THRESH);
                if is_dup
                    method = sprintf('GPS lookup (%d/%d probes)', n_match, N_PROBE);
                end
                if verbose
                    fprintf('  S%d vs R%d | M1-GPS: method=%s  n_match=%d  is_dup=%d\n', ...
                        s, r, gps_method, n_match, is_dup);
                end

                % ---- METHOD 2: Lap-time subset check ----
                % Tried when GPS is absent OR when GPS was present but didn't match
                % (GPS partial match may indicate different session, so require
                %  corroboration from lap-time subset before dropping)
                if ~is_dup
                    [is_dup_lt, lap_info] = lap_time_subset(sessions{s}, sessions{r});
                    if verbose
                        fprintf('  S%d vs R%d | M2-LapTime: is_dup=%d  info=%s\n', ...
                            s, r, is_dup_lt, lap_info);
                    end
                    if is_dup_lt
                        % Only override GPS 'not a dup' if GPS was also absent/unreliable
                        if strcmp(gps_method, 'no_gps') || is_dup_lt
                            is_dup = true;
                            method = sprintf('lap-time subset (%s)', lap_info);
                        end
                    end
                end

                % ---- METHOD 3: Start+end speed fingerprint (universal fallback) ----
                % Runs regardless of GPS presence — handles identical sessions where
                % GPS lookup failed (non-monotonic GPS, ld quantization noise, etc.).
                if ~is_dup
                    if ~isempty(fp_start{r})
                        sm = fingerprints_match(fp_start{s}, fp_start{r}, FPRINT_TOL);
                        em = fingerprints_match(fp_end{s},   fp_end{r},   FPRINT_TOL);
                        if verbose
                            fprintf('  S%d vs R%d | M3-Fprint: start_match=%d  end_match=%d\n', ...
                                s, r, sm, em);
                        end
                        if sm && em
                            is_dup = true;
                            method = 'start+end fingerprint';
                        end
                    end
                end

                % ---- METHOD 4: Distributed channel sample comparison ----
                % Samples DIST_N points evenly across the full channel.  Conclusive
                % for files sharing identical data (e.g. _combined vs _combined_vch).
                if ~is_dup
                    [is_dup_d, frac_d, dist_ch] = distributed_match( ...
                        sessions{s}, sessions{r}, FPRINT_CANDIDATES, DIST_N, DIST_TOL, DIST_THRESH);
                    if verbose
                        fprintf('  S%d vs R%d | M4-Dist: ch=%s  frac=%.3f  is_dup=%d\n', ...
                            s, r, dist_ch, frac_d, is_dup_d);
                    end
                    if is_dup_d
                        is_dup = true;
                        method = sprintf('distributed sample (%.0f%% match, ch=%s)', frac_d*100, dist_ch);
                    end
                end

                if ~is_dup, continue; end

                reason = sprintf('Duplicate — %s', method);
                warning('concat_sessions: session %d is a duplicate/subset of session %d — dropping. (%s)', ...
                    s, r, method);
                keep(s) = false;
                if build_report
                    report(s).status      = 'dropped';
                    report(s).matched_idx = r;
                    report(s).tag         = method;
                    report(s).reason      = reason;
                end
                break;
            end
        end
    end
    sessions = sessions(keep);

    merged    = sessions{1};
    ch_fields = fieldnames(merged);

    for s = 2:numel(sessions)
        s2 = sessions{s};

        % t_last: max end time across ALL channels (prevents time overlap
        %         when channels have different lengths, e.g. 1 Hz vs 100 Hz).
        % dt_gap: from the highest-rate channel so the inter-session gap is
        %         one high-res sample, not one slow-channel period.
        t_last = -Inf;
        dt_min = Inf;
        dt_gap = 0.02;   % fallback: 50 Hz
        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
               numel(merged.(fn).time) > 1
                t_last = max(t_last, merged.(fn).time(end));
                dt_c   = median(diff(merged.(fn).time));
                if dt_c < dt_min
                    dt_min = dt_c;
                    dt_gap = dt_c;
                end
            end
        end
        t_offset = t_last + dt_gap;

        % Renumber Lap_Number in s2 so it continues from merged with no
        % collisions. Formula: lap_offset = max(merged) + 1 - min(s2)
        % so s2's lowest lap maps directly to max_merged + 1, regardless
        % of whether file 2 starts at 0 or 1.
        if isfield(merged, 'Lap_Number') && isfield(s2, 'Lap_Number') && ...
           ~isempty(merged.Lap_Number.data) && ~isempty(s2.Lap_Number.data)
            lap_max    = max(round(merged.Lap_Number.data));
            lap_min2   = min(round(s2.Lap_Number.data));
            lap_offset = lap_max + 1 - lap_min2;
            s2.Lap_Number.data = s2.Lap_Number.data + lap_offset;
        end

        % Straight append — no trimming.
%         for c = 1:numel(ch_fields)
%             fn = ch_fields{c};
%             if ~isfield(s2, fn), continue; end
%             merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
%             merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
%         end
for c = 1:numel(ch_fields)
    fn = ch_fields{c};
    if ~isfield(s2, fn), continue; end
    if ~isfield(merged.(fn), 'data') || ~isfield(merged.(fn), 'time'), continue; end   % skip non-channel fields (e.g. .info)
    merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
    merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
end
    end
end

% -------------------------------------------------------------------------
function [fp_s, fp_e] = make_fingerprint(sess, candidates, K)
% Extract first and last K samples of the first matching candidate channel.
    fp_s = []; fp_e = [];
    fns  = fieldnames(sess);
    for ci = 1:numel(candidates)
        match = '';
        for fi = 1:numel(fns)
            if strcmpi(fns{fi}, candidates{ci}), match = fns{fi}; break; end
        end
        if isempty(match), continue; end
        d = sess.(match).data(:);
        if numel(d) < K, continue; end
        fp_s = d(1:K);
        fp_e = d(end-K+1:end);
        return;
    end
end

% -------------------------------------------------------------------------
function tf = fingerprints_match(a, b, tol)
% True when a and b are same length, max absolute difference <= tol,
% AND both fingerprints have meaningful variance.
% Degenerate fingerprints (car stationary, flat signal) are never a match.
    if isempty(a) || isempty(b) || numel(a) ~= numel(b)
        tf = false; return;
    end
    % Reject if either fingerprint is flat (peak-to-peak < 0.5 km/h)
    if (max(a) - min(a)) < 0.5 || (max(b) - min(b)) < 0.5
        tf = false; return;
    end
    tf = max(abs(a - b)) <= tol;
end

% -------------------------------------------------------------------------
function [is_dup, n_match, method] = gps_lookup_match(sess_s, sess_r, ...
        gps_ch, gps_tol, val_candidates, val_tol, n_probe, match_thresh)
% GPS_LOOKUP_MATCH  Check if sess_s is a duplicate/subset of sess_r.
%
% Takes N_PROBE interior probe points from sess_s (skipping outer 15% to
% avoid trimmed edges).  For each probe: finds the nearest GPS_Time sample
% in sess_r within gps_tol seconds, then cross-checks a value channel at
% that wall-clock moment using the session-relative time axes (handles
% different channel sample rates cleanly).
%
% Returns:
%   is_dup  - true if >= match_thresh probes matched
%   n_match - number of probes that matched ([] if GPS absent)
%   method  - 'gps_lookup' | 'no_gps' (GPS_Time absent in one/both sessions)

    is_dup  = false;
    n_match = 0;
    method  = 'gps_lookup';

    % Locate GPS_Time in both sessions (case-insensitive)
    gps_fn_s = find_field(sess_s, gps_ch);
    gps_fn_r = find_field(sess_r, gps_ch);
    if isempty(gps_fn_s) || isempty(gps_fn_r)
        method = 'no_gps';  return;
    end

    gps_t_s = sess_s.(gps_fn_s).data(:);   % wall-clock GPS seconds
    gps_t_r = sess_r.(gps_fn_r).data(:);
    rel_s   = sess_s.(gps_fn_s).time(:);   % session-relative time axis for S
    rel_r   = sess_r.(gps_fn_r).time(:);   % session-relative time axis for R

    if numel(gps_t_s) < n_probe * 3 || numel(gps_t_r) < n_probe * 3
        method = 'no_gps';  return;
    end

    % GPS quality guard: reject if GPS_Time is too non-monotonic (bad/reset signal)
    % Require at least 60% of samples to be increasing
    if mean(diff(gps_t_s) > 0) < 0.6 || mean(diff(gps_t_r) > 0) < 0.6
        method = 'no_gps';  return;
    end
    if max(gps_t_s) < min(gps_t_r) || min(gps_t_s) > max(gps_t_r)
        return;   % no overlap possible — definitely not a duplicate
    end

    % Find a value channel present in both sessions
    val_fn_s = find_field_any(sess_s, val_candidates);
    val_fn_r = find_field_any(sess_r, val_candidates);
    if isempty(val_fn_s) || isempty(val_fn_r)
        method = 'no_gps';  return;
    end

    val_data_s  = sess_s.(val_fn_s).data(:);
    val_time_s  = sess_s.(val_fn_s).time(:);
    val_data_r  = sess_r.(val_fn_r).data(:);
    val_time_r  = sess_r.(val_fn_r).time(:);

    % Probe indices: interior 70% of S (skip outer 15% each side)
    n_s   = numel(gps_t_s);
    i_lo  = max(1,   floor(0.15 * n_s));
    i_hi  = min(n_s, ceil( 0.85 * n_s));
    probes = round(linspace(i_lo, i_hi, n_probe));

    n_match = 0;
    for k = 1:n_probe
        pi_s      = probes(k);
        gps_probe = gps_t_s(pi_s);   % GPS wall-clock at this probe

        % Find nearest GPS_Time sample in R
        [dt_min, idx_r] = min(abs(gps_t_r - gps_probe));
        if dt_min > gps_tol, continue; end   % no close enough timestamp in R

        % Relative times at the matched points
        t_probe_s = rel_s(pi_s);
        t_probe_r = rel_r(idx_r);

        % Interpolate value channel at the probe's relative time in each session
        v_s = interp1(val_time_s, val_data_s, t_probe_s, 'nearest', 'extrap');
        v_r = interp1(val_time_r, val_data_r, t_probe_r, 'nearest', 'extrap');

        if abs(v_s - v_r) <= val_tol
            n_match = n_match + 1;
        end
    end

    is_dup = n_match >= match_thresh;
end

% -------------------------------------------------------------------------
function [is_subset, info] = lap_time_subset(sess_s, sess_r)
% LAP_TIME_SUBSET  True if sess_s lap durations appear as a contiguous
% ordered block within sess_r's lap durations (within LAP_TOL seconds).
% Uses contiguous subsequence to avoid false positives from coincidental
% lap time matches.  LAP_TOL=1.5 accounts for ±1s 1Hz quantisation error.
    LAP_TOL   = 0.2;   % seconds — covers ±0.1 s per boundary (0.1 s resolution)
    is_subset = false;
    info      = '';

    laps_s = extract_lap_times(sess_s);
    laps_r = extract_lap_times(sess_r);

    if isempty(laps_s) || isempty(laps_r), return; end
    if numel(laps_s) > numel(laps_r), return; end   % S has more laps — not a subset

    % Require laps_s to appear as a contiguous ordered block in laps_r
    ns = numel(laps_s);
    nr = numel(laps_r);
    found_at = 0;
    for start_k = 1:(nr - ns + 1)
        window = laps_r(start_k : start_k + ns - 1);
        if all(abs(window(:) - laps_s(:)) <= LAP_TOL)
            found_at = start_k;
            break;
        end
    end

    if found_at > 0
        is_subset = true;
        info = sprintf('%d laps matched at position %d in ref', ns, found_at);
    end
end

% -------------------------------------------------------------------------
function lap_times = extract_lap_times(sess)
% Extract completed lap durations (seconds).
% Method 1: Lap_Time / Running_Lap_Time reset detection (most accurate)
% Method 2: Engine_Run_Time delta at Lap_Number transitions
% Method 3: Lap_Number time-axis delta (fallback)
    lap_times = [];

    % --- Method 1: Lap_Time / Running_Lap_Time (1 value per lap) ---
    lt_candidates = {'Lap_Time','Running_Lap_Time','LapTime','RunningLapTime'};
    fn = find_field_any(sess, lt_candidates);
    if ~isempty(fn)
        d = sess.(fn).data(:);
        d = d(d > 5);   % discard implausibly short values
        if ~isempty(d)
            lap_times = d;
            return;
        end
    end

    % --- Method 2: Engine_Run_Time delta ---
    ert_candidates = {'Engine_Run_Time','EngineRunTime','Engine_Running_Time'};
    fn_ert = find_field_any(sess, ert_candidates);
    fn_lap = find_field_any(sess, {'Lap_Number','LapNumber'});
    if ~isempty(fn_ert) && ~isempty(fn_lap)
        ert  = sess.(fn_ert).data(:);
        lapn = round(sess.(fn_lap).data(:));
        if numel(ert) > 10 && numel(ert) == numel(lapn)
            transitions = find(diff(lapn) > 0);
            if numel(transitions) >= 2
                lap_times = diff(ert(transitions));
                lap_times = lap_times(lap_times > 5);
                if ~isempty(lap_times), return; end
            end
        end
    end

    % --- Method 3: Lap_Number time-axis ---
    if isempty(fn_lap)
        fn_lap = find_field_any(sess, {'Lap_Number','LapNumber'});
    end
    if isempty(fn_lap), return; end
    lap_data = round(sess.(fn_lap).data(:));
    lap_time = sess.(fn_lap).time(:);
    if numel(lap_data) < 10, return; end
    transitions = find(diff(lap_data) > 0);
    if numel(transitions) < 2, return; end
    lap_times = diff(lap_time(transitions));
    lap_times = lap_times(lap_times > 5);
end

% -------------------------------------------------------------------------
function fn = find_field_any(sess, candidates)
% Return first matching fieldname (case-insensitive) or ''.
    fn  = '';
    fns = fieldnames(sess);
    for ci = 1:numel(candidates)
        for fi = 1:numel(fns)
            if strcmpi(fns{fi}, candidates{ci})
                if isfield(sess.(fns{fi}), 'data') && numel(sess.(fns{fi}).data) > 10
                    fn = fns{fi}; return;
                end
            end
        end
    end
end

% -------------------------------------------------------------------------
function fn = find_field(sess, name)
% Case-insensitive field lookup. Returns matched fieldname or ''.
    fn  = '';
    fns = fieldnames(sess);
    for k = 1:numel(fns)
        if strcmpi(fns{k}, name), fn = fns{k}; return; end
    end
end

% -------------------------------------------------------------------------
% function fn = find_field_any(sess, candidates)
% % Return first candidate fieldname that exists in sess (case-insensitive).
%     fn = '';
%     for ci = 1:numel(candidates)
%         f = find_field(sess, candidates{ci});
%         if ~isempty(f) && isfield(sess.(f), 'data') && numel(sess.(f).data) > 10
%             fn = f;  return;
%         end
%     end
% end

% -------------------------------------------------------------------------
function [is_dup, frac_match, ch_used] = distributed_match(sess_s, sess_r, candidates, n_samp, tol, thresh)
% DISTRIBUTED_MATCH  Compare N evenly-distributed samples of a value channel.
% Both sessions must have equal channel length; >= thresh fraction of the
% sampled values must agree within tol.  Different stints will virtually
% always differ in length, so false-positive risk is negligible.
    is_dup     = false;
    frac_match = 0;
    ch_used    = '';

    fn_s = find_field_any(sess_s, candidates);
    fn_r = find_field_any(sess_r, candidates);
    if isempty(fn_s) || isempty(fn_r), return; end

    d_s = sess_s.(fn_s).data(:);
    d_r = sess_r.(fn_r).data(:);
    if numel(d_s) ~= numel(d_r), return; end   % different lengths → not identical

    n   = numel(d_s);
    idx = unique(round(linspace(1, n, min(n_samp, n))));
    frac_match = mean(abs(d_s(idx) - d_r(idx)) <= tol);
    ch_used    = fn_s;
    is_dup     = frac_match >= thresh;
end
