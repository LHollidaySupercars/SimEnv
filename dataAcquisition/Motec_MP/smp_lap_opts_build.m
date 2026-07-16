function lap_opts = smp_lap_opts_build(season, track, opts)
% SMP_LAP_OPTS_BUILD  Single source of truth for lap_slicer() options.
%
% Builds the lap_opts struct passed to lap_slicer from a track/season lookup
% plus an opts-like struct (e.g. compile_opts or vch_opts). Both
% smp_compile_event and smp_recompute_vch must call this — it exists so a
% fix or new field never has to be hand-mirrored between the two paths.
%
% Usage:
%   lap_opts = smp_lap_opts_build(season, track, opts)
%
% Inputs:
%   season   struct from smp_season_load() — pass [] to use defaults
%   track    track acronym, e.g. 'TAS' — pass '' to use defaults
%   opts     struct that may contain any of the fields below. Unset
%            fields fall back to the documented defaults. Typically
%            this is compile_opts or vch_opts as already used at the
%            call site — no new struct needs to be built by hand.
%
%     .verbose         (default: false)
%     .detect_pitlane  (default: false)
%     .fcy_channel     (default: 'FCY_Flag')   — matches smp_compile_event default.
%                       execute_main_report.m always overrides this to
%                       'Sw_State_SC' explicitly, so this default is rarely hit
%                       in practice, but it must match the authoritative
%                       function (smp_compile_event) rather than the previous
%                       ad-hoc default ('Sw_State_SC') that smp_recompute_vch
%                       used to fall back to on its own.
%     .br2_channel     (default: 'BR2_Beacon_Number')
%     .br2_protocol    (default: 'standard')
%     .beacon_check    (default: false) — passed through onto lap_opts.beacon_check.
%                       NOTE: as of this helper's creation, smp_compile_event's
%                       process_stream did NOT wire opts.beacon_check into
%                       lap_opts at all (it was parsed and silently dropped).
%                       This helper now sets it for real. If lap_slicer doesn't
%                       recognise lap_opts.beacon_check, this is a harmless
%                       extra field; if it does, behaviour now matches what
%                       callers (e.g. execute_main_report.m Section 5c) already
%                       assumed was happening.
%     .min_lap_time    optional — if BOTH .min_lap_time and .max_lap_time are
%     .max_lap_time     supplied, they are used directly and the season/track
%                       lookup (and its "no track specified" warning) is
%                       skipped entirely. Use this when the caller has already
%                       resolved limits via smp_season_get and just needs the
%                       rest of lap_opts assembled consistently (e.g.
%                       smp_compile_event's process_stream, which receives
%                       min_lt/max_lt as already-resolved positional args).
%
% Output:
%   lap_opts   struct ready to pass directly into lap_slicer(session, lap_opts)
%
% Lap time limits (.min_lap_time / .max_lap_time) come from
% smp_season_get(season, track) when both season and track are supplied
% and opts.min_lap_time/.max_lap_time are NOT both supplied. If neither
% path resolves limits, defaults of 10s/600s are used and a warning is
% printed — the same fallback both call sites previously implemented
% separately.
%
% NOT covered by this helper (intentionally out of scope):
%   lap_opts.mylaps_channel, .save_beacon_pdf, .beacon_pdf_dir,
%   .beacon_check_pause, .beacon_pdf_name, .beacon_check_label
%   These remain hardcoded/per-group inside smp_compile_event's
%   process_stream and are not yet part of the shared opts contract.

    if nargin < 3 || isempty(opts), opts = struct(); end

    % ------------------------------------------------------------------
    %  Lap time limits
    % ------------------------------------------------------------------
    opt_min_lt = get_opt(opts, 'min_lap_time', []);
    opt_max_lt = get_opt(opts, 'max_lap_time', []);

    if ~isempty(opt_min_lt) && ~isempty(opt_max_lt)
        % Caller already resolved limits (e.g. via smp_season_get upstream) —
        % use them directly, no lookup, no warning.
        min_lt = opt_min_lt;
        max_lt = opt_max_lt;
    elseif ~isempty(track) && ~isempty(season)
        [min_lt, max_lt] = smp_season_get(season, track);
    else
        min_lt = 10;
        max_lt = 600;
        fprintf('[WARN] smp_lap_opts_build: no track/season supplied — using default lap time limits (10s / 600s).\n');
    end

    lap_opts.min_lap_time   = min_lt;
    lap_opts.max_lap_time   = max_lt;
    lap_opts.verbose        = get_opt(opts, 'verbose',        false);
    lap_opts.detect_pitlane = get_opt(opts, 'detect_pitlane', false);
    lap_opts.fcy_channel    = get_opt(opts, 'fcy_channel',    'FCY_Flag');
    lap_opts.br2_channel    = get_opt(opts, 'br2_channel',    'BR2_Beacon_Number');
    lap_opts.br2_protocol   = get_opt(opts, 'br2_protocol',   'standard');
    lap_opts.beacon_check   = get_opt(opts, 'beacon_check',   false);
    lap_opts.mylaps_channel = get_opt(opts, 'mylaps_channel', 'MyLaps_X2TRA_DeviceShortId');
end


% ======================================================================= %
function val = get_opt(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end