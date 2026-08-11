function augment_com_files_serial(com_dir, channels_file, cfg, driver_map)
% AUGMENT_COM_FILES_SERIAL  Serial Phase 6 — augment every .ld in com_dir.
%   Recursively scans com_dir, applies driver alias + session filters,
%   then runs smp_custom_channels + smp_gated_channels on each file.
    if nargin < 3, cfg = struct(); end
    if nargin < 4, driver_map = []; end

    try
        T_gated_vcs = readtable(channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');
    catch
        T_gated_vcs = table();
        fprintf('  [WARN] Could not load gatedChannels sheet — skipping gated channels.\n');
    end

    % Recursive .ld scan
    all_paths = recursive_find_ld(com_dir);
    if isempty(all_paths)
        fprintf('  [WARN] No .ld files found (recursive) in %s\n', com_dir);
        return;
    end

    % Apply driver + session filter
    all_paths = filter_aug_files(all_paths, cfg);
    if isempty(all_paths)
        fprintf('  [WARN] No files remain after driver/session filter.\n');
        return;
    end

    n_aug_ok   = 0;
    n_aug_fail = 0;

    for fi = 1:numel(all_paths)
        com_path = all_paths{fi};
        [~, fname] = fileparts(com_path);
        fprintf('  [%d/%d] %s\n', fi, numel(all_paths), fname);
        try
    aug_data      = motec_ld_reader(com_path, {});
    aug_data.info = motec_ld_info(com_path, false);

    % ---- Manufacturer fallback via driver alias lookup ----
            if (~isfield(aug_data.info, 'manufacturer') || isempty(aug_data.info.manufacturer)) && ...
               isfield(aug_data.info, 'driver') && ~isempty(aug_data.info.driver) && ...
               ~isempty(driver_map)
                tla = resolve_driver_tla(aug_data.info.driver, driver_map);
                mfr = local_resolve_manufacturer_by_tla(tla, driver_map);
                if ~isempty(mfr)
                    aug_data.info.manufacturer = mfr;
                    fprintf('    Manufacturer resolved via alias: %s\n', mfr);
                else
                    fprintf('    [WARN] Manufacturer not found via alias for driver "%s"\n', aug_data.info.driver);
                end
            end
        
            aug_data = smp_custom_channels(aug_data, ...
                'manufacturer', aug_data.info.manufacturer, ...
                'driver',       aug_data.info.driver, ...
                'session',      aug_data.info.session, ...
                'patchRH',      cfg.PatchRH);
        
            [aug_data, ~] = smp_gated_channels(aug_data, T_gated_vcs);
    % ... rest of the try block (the ld_ch collection loop etc.) stays unchanged ...
            % Collect channels flagged write_to_ld=true
            % (set by make_channel and smp_gated_channels — not present on
            % channels read back from file, so works on first run and re-runs)
            all_fields = fieldnames(aug_data);
            ch_list = {};
            for ci = 1:numel(all_fields)
                fn = all_fields{ci};
                ch = aug_data.(fn);
                if ~isstruct(ch) || ~isfield(ch, 'write_to_ld') || ~ch.write_to_ld
                    continue;
                end
                ld_ch.name        = ch.raw_name;
                ld_ch.units       = ch.units;
                ld_ch.sample_rate = ch.sample_rate;
                ld_ch.value       = ch.data(:);
                if isfield(ch, 'dec_places')
                    ld_ch.dec_places = ch.dec_places;
                else
                    ld_ch.dec_places = 2;
                end
                if isfield(ch, 'overwrite')
                    ld_ch.overwrite = ch.overwrite;
                else
                    ld_ch.overwrite = false;
                end

                ld_ch.mul         = 1;
                ld_ch.scale       = 1;
                vals = ld_ch.value(isfinite(ld_ch.value));
                if ~isempty(vals) && min(vals) < 0
                    ld_ch.offset = floor(min(vals)) - 1;
                else
                    ld_ch.offset = 0;
                end
                ch_list{end+1} = ld_ch; %#ok<SAGROW>
            end

            if isempty(ch_list)
                fprintf('    No new channels computed — skipping write.\n');
                n_aug_ok = n_aug_ok + 1;
            else
                tmp_path = [com_path '.aug_tmp'];
                ld_add_channel(com_path, tmp_path, ch_list);
                movefile(tmp_path, com_path, 'f');
                fprintf('    Written %d channel(s)\n', numel(ch_list));
                n_aug_ok = n_aug_ok + 1;
            end
        catch ME
            fprintf('    [ERROR] %s\n', ME.message);
            n_aug_fail = n_aug_fail + 1;
            tmp_path = [com_path '.aug_tmp'];
            if exist(tmp_path, 'file'), delete(tmp_path); end
        end
        clear aug_data ch_list;
    end
    fprintf('  Phase 6 complete — OK: %d  Failed: %d\n', n_aug_ok, n_aug_fail);
end