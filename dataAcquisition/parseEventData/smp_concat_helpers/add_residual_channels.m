function add_residual_channels(com_dir, ch_a_name, ch_b_name, out_ch_name, resample_hz)
% ADD_RESIDUAL_CHANNELS  Compute per-sample residual (A − B) for all .ld files
%   in com_dir and append the result as a new channel back into each file.
%
%   Both channels are resampled to a common grid at resample_hz before
%   subtraction, so the output is a time-series aligned to channel A's
%   time base.
%
%   Arguments:
%     com_dir       - folder containing combined .ld files
%     ch_a_name     - minuend channel name   (e.g. 'ecu_Engine_Speed')
%     ch_b_name     - subtrahend channel name (e.g. 'Engine_Speed')
%     out_ch_name   - name for the residual channel written to file
%     resample_hz   - common sample rate for interpolation

files = dir(fullfile(com_dir, '*.ld'));
if isempty(files)
    fprintf('  [residual] No .ld files found in: %s\n', com_dir);
    return;
end

dt = 1 / resample_hz;

for fi = 1 : numel(files)
    fpath = fullfile(files(fi).folder, files(fi).name);
    fprintf('  [residual] %s  (%s − %s)\n', files(fi).name, ch_a_name, ch_b_name);

    % ---- Load both channels ----
    try
        da = motec_ld_reader(fpath, {ch_a_name}, false);
        db = motec_ld_reader(fpath, {ch_b_name}, false);
    catch ME
        fprintf('    WARNING: could not load channels — %s\n', ME.message);
        continue;
    end
    fn_a = fieldnames(da); fn_b = fieldnames(db);
    if isempty(fn_a) || isempty(fn_b)
        fprintf('    WARNING: one or both channels missing, skipping.\n');
        continue;
    end
    ch_a = da.(fn_a{1}); ch_b = db.(fn_b{1});

    % ---- Resample to common time grid ----
    t_start = max(ch_a.time(1),   ch_b.time(1));
    t_end   = min(ch_a.time(end), ch_b.time(end));
    if t_end <= t_start
        fprintf('    WARNING: no overlapping time range, skipping.\n');
        continue;
    end
    t_grid = (t_start : dt : t_end)';
    v_a = interp1(ch_a.time(:), double(ch_a.data(:)), t_grid, 'linear', NaN);
    v_b = interp1(ch_b.time(:), double(ch_b.data(:)), t_grid, 'linear', NaN);

    % ---- Compute residual ----
    resid = single(v_a - v_b);

    % ---- Build channel struct for ld_add_channel ----
    resid_ch.name        = char(out_ch_name);
    resid_ch.value       = resid;
    resid_ch.sample_rate = resample_hz;
    if ischar(ch_a.units) || isstring(ch_a.units)
        resid_ch.units = char(ch_a.units);
    else
        resid_ch.units = '';
    end
    tmp_file = [fpath '.residtmp'];
    try
        ld_add_channel(fpath, tmp_file, resid_ch);
        movefile(tmp_file, fpath, 'f');
        % Delete the original file's stale .ldx index so i2 Pro rebuilds it
        ldx_path = [fpath(1:end-2) 'ldx'];
        if exist(ldx_path, 'file'), delete(ldx_path); end
        fprintf('    Written: %s  (%.0f Hz, %.1f s)\n', ...
            out_ch_name, resample_hz, t_end - t_start);
    catch ME
        if exist(tmp_file, 'file'), delete(tmp_file); end
        fprintf('    WARNING: write failed — %s\n', ME.message);
    end
end
end

