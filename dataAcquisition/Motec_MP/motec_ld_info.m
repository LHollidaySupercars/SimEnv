function info = motec_ld_info(filepath)
% MOTEC_LD_INFO  Read metadata from a MoTeC .ld file.
%
% Fixed offsets confirmed from hex analysis of Supercars Control Dash files:
%   0x004A  device_code   char[8]   — contains car number e.g. "C185"
%   0x005E  date          char[16]  "DD/MM/YYYY"
%   0x007E  time          char[16]  "HH:MM:SS"
%   0x009E  driver        char[64]
%   0x00DE  vehicle       char[64]  e.g. "Mustang Supercar"
%   0x011E  engine_id     char[64]  e.g. "TEP-005"
%   0x015E  venue         char[64]  e.g. "Sydney Motorsport Park"
%   0x05E4  session       char[32]  e.g. "Qualifying 2", "Morning Session"
%   0x0624  run           char[32]  e.g. "Run 2.1", "Run 1"
%   0x0694  team_name     char[64]  e.g. "Triple Eight Race Engineering"

    info.driver     = '';
    info.vehicle    = '';
    info.vehicle_id = '';
    info.engine_id  = '';
    info.car_number = '';
    info.car_number_raw = '';
    info.team_name  = '';
    info.venue      = '';
    info.session    = '';
    info.run        = '';
    info.event      = '';   % not at a fixed offset — populate via alias config
    info.date       = '';
    info.time       = '';
    info.year       = '';

    % Filename-derived fields
    [~, fname, ~] = fileparts(filepath);
    info.filename = fname;
    tok = regexp(fname, '^(\d{8})-(\d+)(?:_(\d+))?$', 'tokens');
    if ~isempty(tok)
        t = tok{1};
        ds = t{1};
        info.log_date   = [ds(1:4) '-' ds(5:6) '-' ds(7:8)];
        info.serial     = t{2};
        info.run_number = '';
        if numel(t) >= 3 && ~isempty(t{3}), info.run_number = t{3}; end
    else
        info.log_date = ''; info.serial = ''; info.run_number = '';
    end

    % ------------------------------------------------------------------ %
    %  Read file header — enough to cover all fixed offsets
    %  Furthest field is team_name at 0x0694 + 64 bytes = 0x06D4
    % ------------------------------------------------------------------ %
    fid = fopen(char(filepath), 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    fseek(fid, 0, 'bof');
    hdr = fread(fid, 0x06D4 + 64, 'uint8=>double')';
    fclose(fid);

    % ------------------------------------------------------------------ %
    %  Fixed metadata fields
    % ------------------------------------------------------------------ %
    info.date       = fstr(hdr, 0x5E,   16);
    info.time       = fstr(hdr, 0x7E,   16);
    info.driver     = fstr(hdr, 0x9E,   64);
    info.vehicle    = fstr(hdr, 0xDE,   64);
    info.engine_id  = fstr(hdr, 0x11E,  64);
    info.venue      = fstr(hdr, 0x15E,  64);
    info.session    = fstr(hdr, 0x5E4,  32);
    info.run        = fstr(hdr, 0x624,  32);
    info.team_name  = fstr(hdr, 0x694,  64);

    % Car number — stored in device code field as e.g. "C185", strip the C
    raw_dev = fstr(hdr, 0x4A, 8);
    info.car_number_raw = raw_dev;
    tok_car = regexp(raw_dev, '^[A-Za-z]*(\d+)', 'tokens');
    if ~isempty(tok_car)
        info.car_number = tok_car{1}{1};
    else
        info.car_number = raw_dev;
    end

    % Vehicle ID = first word of vehicle string
    if ~isempty(info.vehicle)
        tok2 = regexp(info.vehicle, '^(\S+)', 'tokens');
        if ~isempty(tok2), info.vehicle_id = tok2{1}{1}; end
    end

    % Manufacturer — inferred from vehicle string
    info.manufacturer = infer_manufacturer(info.vehicle);

    % Year from date field
    if ~isempty(info.date)
        yt = regexp(info.date, '(\d{4})', 'tokens');
        if ~isempty(yt), info.year = yt{1}{1}; end
    end

    % ------------------------------------------------------------------ %
    fprintf('=== MoTeC Log File Info ===\n');
    fprintf('Filename:     %s\n', info.filename);
    fprintf('Date:         %s  %s\n', info.date, info.time);
    fprintf('Driver:       %s\n', info.driver);
    fprintf('Car Number:   %s\n', info.car_number);
    fprintf('Team:         %s\n', info.team_name);
    fprintf('Vehicle:      %s\n', info.vehicle);
    fprintf('Manufacturer: %s\n', info.manufacturer);
    fprintf('Engine ID:    %s\n', info.engine_id);
    fprintf('Venue:        %s\n', info.venue);
    fprintf('Session:      %s\n', info.session);
    fprintf('Run:          %s\n', info.run);
    fprintf('Year:         %s\n', info.year);
end


% ======================================================================= %
function str = fstr(raw, offset, len)
% Read null-terminated printable ASCII string from raw bytes at absolute offset.
    idx  = offset + 1;
    last = min(idx + len - 1, numel(raw));
    if idx > numel(raw), str = ''; return; end
    seg = raw(idx:last);
    nul = find(seg == 0, 1);
    if ~isempty(nul), seg = seg(1:nul-1); end
    if isempty(seg) || any(seg < 32 | seg > 126)
        str = '';
    else
        str = strtrim(char(seg));
    end
end


% ======================================================================= %
function mfr = infer_manufacturer(vehicle_str)
% Infer manufacturer from vehicle string.
% Extend this list as needed.
    v = lower(vehicle_str);
    if contains(v, 'mustang') || contains(v, 'ford')
        mfr = 'Ford';
    elseif contains(v, 'camaro') || contains(v, 'chev') || contains(v, 'holden')
        mfr = 'Chev';
    elseif contains(v, 'camry') || contains(v, 'toyota') || contains(v, 'supra')
        mfr = 'Toyota';
    else
        mfr = '';
    end
end
