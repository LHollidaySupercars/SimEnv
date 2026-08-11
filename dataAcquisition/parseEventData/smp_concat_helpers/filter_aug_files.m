function paths = filter_aug_files(paths, cfg)
% FILTER_AUG_FILES  Apply driver alias + session filter to a list of .ld paths.
%
%   Session filter: if cfg.session_filter is set, reads each file header and
%     keeps only files whose event/session string matches.
%   Driver filter:  if cfg.fix_filter is non-empty, loads the driver alias map
%     and keeps only files whose driver resolves to a listed TLA/car number.

    if isempty(paths), return; end

    % ---- Build driver alias map (once) ----
    driver_map = [];
    has_driver_filter = isfield(cfg, 'fix_filter') && ~isempty(cfg.fix_filter);
    if has_driver_filter && isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
        try
            driver_map = smp_driver_alias_load(cfg.driver_alias_file);
        catch
            fprintf('  [WARN] filter_aug_files: could not load driver alias — skipping driver filter.\n');
            has_driver_filter = false;
        end
    end

    % ---- Session strings to accept ----
    has_session_filter = isfield(cfg, 'session_filter') && ~isempty(cfg.session_filter);
    accepted_sessions  = {};
    if has_session_filter
        accepted_sessions = lower(cfg.session_filter);
    end

    if ~has_driver_filter && ~has_session_filter
        return;   % nothing to filter
    end

    keep = true(size(paths));
    for i = 1:numel(paths)
        try
            info = motec_ld_info(paths{i}, false);
        catch
            fprintf('  [WARN] filter_aug_files: could not read header of %s — keeping.\n', paths{i});
            continue;
        end

        % ---- Session check ----
        if has_session_filter
            file_session = '';
            if isfield(info, 'event'),   file_session = lower(strtrim(info.event));   end
            if isfield(info, 'session'), file_session = lower(strtrim(info.session)); end
            if ~any(contains(file_session, accepted_sessions))
                keep(i) = false;
                continue;
            end
        end

        % ---- Driver check ----
        if has_driver_filter
            raw_drv = '';
            if isfield(info, 'driver'), raw_drv = strtrim(info.driver); end
            tla = resolve_driver_tla(raw_drv, driver_map);
            if isempty(tla), tla = raw_drv; end
            % cfg.fix_filter may contain TLAs or car numbers
            if ~any(strcmpi(tla, cfg.fix_filter)) && ~any(strcmpi(raw_drv, cfg.fix_filter))
                keep(i) = false;
            end
        end
    end

    n_removed = sum(~keep);
    if n_removed > 0
        fprintf('  filter_aug_files: removed %d file(s) that did not match driver/session filter.\n', n_removed);
    end
    paths = paths(keep);
end

