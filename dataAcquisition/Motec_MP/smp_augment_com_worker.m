% function smp_augment_com_worker(worker_id, tmp_dir)
% %% SMP_AUGMENT_COM_WORKER  Phase 6 parallel worker — augment a chunk of COM files.
% %
% % Loads its assigned file chunk, runs smp_custom_channels + smp_gated_channels
% % on each .ld file, and writes the new channels back in-place.
% %
% % Called via:
% %   matlab -batch "addpath(genpath('...')); smp_augment_com_worker(N, 'tmp_path')"
% %
% % Writes done_N.flag to tmp_dir after all files are processed.
% 
% fprintf('=== smp_augment_com_worker  (worker %d) ===\n', worker_id);
% fprintf('    TMP : %s\n\n', tmp_dir);
% 
% % ---- Load shared cfg ----
% cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
% if ~isfile(cfg_file)
%     error('smp_augment_com_worker: worker_cfg.mat not found:\n  %s', cfg_file);
% end
% loaded_cfg    = load(cfg_file, 'aug_worker_cfg');
% channels_file = loaded_cfg.aug_worker_cfg.channels_file;
% 
% % ---- Load this worker's file chunk ----
% chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
% if ~isfile(chunk_file)
%     error('smp_augment_com_worker: chunk_%d.mat not found:\n  %s', worker_id, chunk_file);
% end
% chunk        = load(chunk_file, 'worker_files');
% worker_files = chunk.worker_files;
% 
% if isempty(worker_files)
%     fprintf('Worker %d: no files assigned — exiting.\n', worker_id);
%     write_flag(tmp_dir, worker_id, 0, 0);
%     return;
% end
% 
% % ---- Load gated channels table once ----
% try
%     T_gated_w = readtable(channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');
% catch
%     T_gated_w = table();
%     fprintf('  [WARN] Could not load gatedChannels sheet — skipping gated channels.\n');
% end
% 
% fprintf('Worker %d: %d file(s) assigned\n\n', worker_id, numel(worker_files));
% 
% n_ok   = 0;
% n_fail = 0;
% 
% for fi = 1:numel(worker_files)
%     com_path = worker_files{fi};
%     [~, fname] = fileparts(com_path);
%     fprintf('  [%d/%d] %s\n', fi, numel(worker_files), fname);
% 
%     if ~isfile(com_path)
%         fprintf('    SKIP — file not found\n');
%         n_fail = n_fail + 1;
%         continue;
%     end
% 
%     try
%         % Load all channels
%         aug_data      = motec_ld_reader(com_path, {});
%         aug_data.info = motec_ld_info(com_path, false);
% 
%         % Compute derived channels
%         aug_data = smp_custom_channels(aug_data, ...
%             'manufacturer', aug_data.info.manufacturer, ...
%             'driver',       aug_data.info.driver);
%         [aug_data, ~] = smp_gated_channels(aug_data, T_gated_w);
% 
%         % Collect channels flagged write_to_ld=true
%         % (set by make_channel and smp_gated_channels — not present on
%         % channels read back from file, so works on first run and re-runs)
%         all_fields   = fieldnames(aug_data);
%         ch_list = {};
%         for ci = 1:numel(all_fields)
%             fn = all_fields{ci};
%             ch = aug_data.(fn);
%             if ~isstruct(ch) || ~isfield(ch, 'write_to_ld') || ~ch.write_to_ld
%                 continue;
%             end
%             ld_ch.name        = ch.raw_name;
%             ld_ch.units       = ch.units;
%             ld_ch.sample_rate = ch.sample_rate;
%             ld_ch.value       = ch.data(:);
%             if isfield(ch, 'dec_places')
%                 ld_ch.dec_places = ch.dec_places;
%             else
%                 ld_ch.dec_places = 2;
%             end
%             ld_ch.mul         = 1;
%             ld_ch.scale       = 1;
%             vals = ld_ch.value(isfinite(ld_ch.value));
%             if ~isempty(vals) && min(vals) < 0
%                 ld_ch.offset = floor(min(vals)) - 1;
%             else
%                 ld_ch.offset = 0;
%             end
%             ch_list{end+1} = ld_ch; %#ok<SAGROW>
%         end
% 
%         if isempty(ch_list)
%             fprintf('    No new channels computed — skipping write.\n');
%             n_ok = n_ok + 1;
%             continue;
%         end
% 
%         % Write to temp then replace original
%         tmp_path = [com_path '.aug_tmp'];
%         ld_add_channel(com_path, tmp_path, ch_list);
%         movefile(tmp_path, com_path, 'f');
%         fprintf('    Written %d channel(s)\n', numel(ch_list));
%         n_ok = n_ok + 1;
% 
%     catch ME
%         fprintf('    [ERROR] %s\n', ME.message);
%         n_fail = n_fail + 1;
%         tmp_path = [com_path '.aug_tmp'];
%         if exist(tmp_path, 'file'), delete(tmp_path); end
%     end
%     clear aug_data ch_list;
% end
% 
% fprintf('\nWorker %d: OK=%d  Failed=%d\n', worker_id, n_ok, n_fail);
% 
% % ---- Signal done ----
% write_flag(tmp_dir, worker_id, n_ok, n_fail);
% fprintf('=== Worker %d complete ===\n', worker_id);
% end
% 
% % -----------------------------------------------------------------------
% function write_flag(tmp_dir, worker_id, n_ok, n_fail)
%     flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
%     fid = fopen(flag_file, 'w');
%     if fid ~= -1
%         fprintf(fid, 'Worker %d completed: OK=%d Failed=%d  %s\n', ...
%             worker_id, n_ok, n_fail, datestr(now));
%         fclose(fid);
%     end
% end

function smp_augment_com_worker(worker_id, tmp_dir)
%% SMP_AUGMENT_COM_WORKER  Phase 6 parallel worker — augment a chunk of COM files.
fprintf('=== smp_augment_com_worker  (worker %d) ===\n', worker_id);
fprintf('    TMP : %s\n\n', tmp_dir);

% ---- Load shared cfg ----
cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
if ~isfile(cfg_file)
    error('smp_augment_com_worker: worker_cfg.mat not found:\n  %s', cfg_file);
end
loaded_cfg    = load(cfg_file, 'aug_worker_cfg');
cfg           = loaded_cfg.aug_worker_cfg;
channels_file = cfg.channels_file;
if isfield(cfg, 'driver_map')
    driver_map = cfg.driver_map;
else
    driver_map = [];
end

% ---- Load this worker's file chunk ----
chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
if ~isfile(chunk_file)
    error('smp_augment_com_worker: chunk_%d.mat not found:\n  %s', worker_id, chunk_file);
end
chunk        = load(chunk_file, 'worker_files');
worker_files = chunk.worker_files;

if isempty(worker_files)
    fprintf('Worker %d: no files assigned — exiting.\n', worker_id);
    write_flag(tmp_dir, worker_id, 0, 0);
    return;
end

% ---- Load gated channels table once ----
try
    T_gated_w = readtable(channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');
catch
    T_gated_w = table();
    fprintf('  [WARN] Could not load gatedChannels sheet — skipping gated channels.\n');
end

fprintf('Worker %d: %d file(s) assigned\n\n', worker_id, numel(worker_files));

n_ok   = 0;
n_fail = 0;

for fi = 1:numel(worker_files)
    com_path = worker_files{fi};
    [~, fname] = fileparts(com_path);
    fprintf('  [%d/%d] %s\n', fi, numel(worker_files), fname);

    if ~isfile(com_path)
        fprintf('    SKIP — file not found\n');
        n_fail = n_fail + 1;
        continue;
    end

    try
        % Load all channels
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

        % Compute derived channels
        aug_data = smp_custom_channels(aug_data, ...
            'manufacturer', aug_data.info.manufacturer, ...
            'driver',       aug_data.info.driver, ...
            'session',      aug_data.info.session, ...
            'patchRH',      cfg.PatchRH);
        [aug_data, ~] = smp_gated_channels(aug_data, T_gated_w);

        % Collect channels flagged write_to_ld=true
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
            n_ok = n_ok + 1;
            continue;
        end

        % Write to temp then replace original
        tmp_path = [com_path '.aug_tmp'];
        ld_add_channel(com_path, tmp_path, ch_list);
        movefile(tmp_path, com_path, 'f');
        fprintf('    Written %d channel(s)\n', numel(ch_list));
        n_ok = n_ok + 1;

    catch ME
        fprintf('    [ERROR] %s\n', ME.message);
        n_fail = n_fail + 1;
        tmp_path = [com_path '.aug_tmp'];
        if exist(tmp_path, 'file'), delete(tmp_path); end
    end
    clear aug_data ch_list;
end

fprintf('\nWorker %d: OK=%d  Failed=%d\n', worker_id, n_ok, n_fail);

% ---- Signal done ----
write_flag(tmp_dir, worker_id, n_ok, n_fail);
fprintf('=== Worker %d complete ===\n', worker_id);
end

% -----------------------------------------------------------------------
function write_flag(tmp_dir, worker_id, n_ok, n_fail)
    flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
    fid = fopen(flag_file, 'w');
    if fid ~= -1
        fprintf(fid, 'Worker %d completed: OK=%d Failed=%d  %s\n', ...
            worker_id, n_ok, n_fail, datestr(now));
        fclose(fid);
    end
end

% -----------------------------------------------------------------------
function tla = resolve_driver_tla(raw_driver, driver_map)
% Resolve a raw driver string to its canonical TLA via the alias map.
    tla = '';
    if isempty(driver_map) || isempty(raw_driver), return; end
    raw_lower = lower(raw_driver);
    keys = fieldnames(driver_map);
    for ki = 1:numel(keys)
        entry = driver_map.(keys{ki});
        if any(strcmp(raw_lower, entry.aliases))
            if ~isempty(entry.tla)
                tla = entry.tla;
            elseif ~isempty(entry.canonical)
                tla = entry.canonical;
            end
            return;
        end
    end
end

% -----------------------------------------------------------------------
function mfr = local_resolve_manufacturer_by_tla(tla, driver_map)
% Resolve manufacturer for a driver given their already-resolved TLA.
    mfr = '';
    if isempty(driver_map) || isempty(tla), return; end
    keys = fieldnames(driver_map);
    for ki = 1:numel(keys)
        entry = driver_map.(keys{ki});
        if isfield(entry, 'tla') && strcmp(entry.tla, tla)
            if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
                mfr = entry.manufacturer;
            end
            return;
        end
    end
end