%% EXECUTE_WRITE_VCH
%  Write virtual channels (from smp_custom_channels) back into .ld files.
%
%  WORKFLOW:
%    1. Set SOURCE_FILES to one or more .ld paths
%    2. In smp_custom_channels.m, mark channels to write with:
%         data.myVCH.write_to_ld = true;
%         data.myVCH.dec_places  = 2;     % decimal places in i2 Pro
%       Those are the only entries needed — no list to maintain here.
%    3. Run — each source file gets a corresponding _vch.ld output
%
%  OUTPUT_SUFFIX: appended before .ld extension  (e.g. '_vch')
%  OVERWRITE:     false = skip if output already exists

clear; clc;

%% =========================================================
%  CONFIG
%% =========================================================

SOURCE_FILES = {
    'E:\2026\T01_QLR\COM\20260505-156890016_combined.ld';
};

OUTPUT_SUFFIX = '_vch';
OVERWRITE     = true;

% Add paths
repo_root = 'C:\SimEnv';
addpath(fullfile(repo_root, 'dataAcquisition', 'Motec_MP'));
addpath(fullfile(repo_root, 'dataAcquisition', 'Motec_MP', 'channelAdd'));
addpath(fullfile(repo_root, 'dataAcquisition', 'parseEventData'));

%% =========================================================
%  PROCESS FILES
%% =========================================================

n_ok   = 0;
n_skip = 0;
n_fail = 0;

for fi = 1:numel(SOURCE_FILES)
    src = SOURCE_FILES{fi};

    [d, base, ext] = fileparts(src);
    out = fullfile(d, [base OUTPUT_SUFFIX ext]);

    fprintf('\n[%d/%d] %s\n', fi, numel(SOURCE_FILES), base);

    % --- Skip check ---
    if ~OVERWRITE && exist(out, 'file')
        fprintf('  SKIP — output exists: %s\n', out);
        n_skip = n_skip + 1;
        continue;
    end
    if ~exist(src, 'file')
        fprintf('  SKIP — source not found\n');
        n_skip = n_skip + 1;
        continue;
    end

    try
        % --- Read source ---
        fprintf('  Reading...\n');
        data = motec_ld_reader(src);

        % --- Populate data.info so smp_custom_channels has manufacturer/driver ---
        try
            data.info = motec_ld_info(src, false);
        catch
            data.info = struct();
        end

        % --- Compute VCHs ---
        fprintf('  Computing VCHs...\n');
        data = smp_custom_channels(data);

        % --- Collect channels flagged write_to_ld = true ---
        ch_list = {};
        fields  = fieldnames(data);
        for fi2 = 1:numel(fields)
            f  = fields{fi2};
            ch = data.(f);
            if ~isstruct(ch),           continue; end
            if ~isfield(ch, 'write_to_ld') || ~ch.write_to_ld
                continue;
            end

            ld_ch.name        = ch.raw_name;
            ld_ch.units       = ch.units;
            ld_ch.sample_rate = ch.sample_rate;
            ld_ch.value       = ch.data(:);
            ld_ch.dec_places  = ch.dec_places;
            ld_ch.mul         = 1;
            ld_ch.scale       = 1;
            ld_ch.offset      = 0;
            % Float16 (datatype=1) is inherently signed — use it for channels
            % with negative values so i2 reads the sign bit correctly.
            % Int16 (datatype=2) is read by i2 as unsigned uint16, so negative
            % raw bytes appear as large positive values.
            vals = ld_ch.value(isfinite(ld_ch.value));
if ~isempty(vals) && min(vals) < 0
    ld_ch.offset = floor(min(vals)) - 1;  % shift so raw > 0 always
else
    ld_ch.offset = 0;
end

            ch_list{end+1} = ld_ch; %#ok<AGROW>
            fprintf('  [+] "%s"  %d Hz  %d samples\n', ld_ch.name, ld_ch.sample_rate, numel(ld_ch.value));
        end

        if isempty(ch_list)
            fprintf('  No channels flagged write_to_ld — skipping output\n');
            n_skip = n_skip + 1;
            continue;
        end

        % --- Write ---
        fprintf('  Writing %d channel(s) → %s\n', numel(ch_list), [base OUTPUT_SUFFIX ext]);
        ld_add_channel(src, out, ch_list);
        n_ok = n_ok + 1;

    catch ME
        fprintf('  ERROR: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
end

fprintf('\n============================================================\n');
fprintf('  Done.  OK=%d  Skipped=%d  Failed=%d\n', n_ok, n_skip, n_fail);
fprintf('============================================================\n');
