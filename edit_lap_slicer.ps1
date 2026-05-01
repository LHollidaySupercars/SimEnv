$f = 'c:\SimEnv\dataAcquisition\parseEventData\lap_slicer.m'
$c = [IO.File]::ReadAllText($f)
$n = $c.Length
Write-Host "Original length: $n"

# ---- Edit 1: add br2_proto_in opts parsing after br2_ch_name ----
$old1 = "    br2_ch_name     = get_opt(opts, 'br2_channel',    'BR2_Beacon_Number');"
$new1 = "    br2_ch_name     = get_opt(opts, 'br2_channel',    'BR2_Beacon_Number');`r`n    br2_proto_in    = get_opt(opts, 'br2_protocol',   'standard');"
if ($c.Contains($old1)) {
    $c = $c.Replace($old1, $new1)
    Write-Host "Edit 1 OK"
} else { Write-Host "Edit 1 NOT FOUND" }

# ---- Edit 2: add proto resolution after br2_field_orig ----
$old2 = "        br2_field_orig = br2_field;   % preserve for plot even if detection falls back to Mode C`r`n        % ---- MODE B: BR2_Beacon_Number S/F transition detection ----"
$new2 = "        br2_field_orig = br2_field;   % preserve for plot even if detection falls back to Mode C`r`n        if ischar(br2_proto_in)`r`n            br2_proto = br2_protocol_get(br2_proto_in);`r`n        else`r`n            br2_proto = br2_proto_in;`r`n        end`r`n        % ---- MODE B: BR2_Beacon_Number S/F transition detection ----"
if ($c.Contains($old2)) {
    $c = $c.Replace($old2, $new2)
    Write-Host "Edit 2 OK"
} else { Write-Host "Edit 2 NOT FOUND" }

# ---- Edit 3a: add simple_pulse branch + else header before standard detection ----
$old3a = "        br2_sf_times    = [];   % session time of each S/F crossing`r`n        br2_pitin_t     = [];   % session time of each pit-in line crossing`r`n        br2_pit900_prev = [];   % value before each garage run`r`n        br2_pit900_t0   = [];   % start time of each garage run`r`n        br2_pit900_t1   = [];   % end   time of each garage run`r`n`r`n        n_br2_zoh = numel(br2_zoh);"
$new3a = "        br2_sf_times    = [];   % session time of each S/F crossing`r`n        br2_pitin_t     = [];   % session time of each pit-in line crossing`r`n        br2_pitout_t    = [];   % session time of each pit-out event`r`n`r`n        if strcmp(br2_proto.variant, 'simple_pulse')`r`n            % --- Simple-pulse protocol detection (e.g. TAS2025) ---`r`n            % S/F:     idle -> sf_pulse -> idle   time = start of sf_pulse`r`n            % Pit-in:  idle -> pitin             time = start of pitin state`r`n            % Pit-out: pitin -> idle             time = return to idle`r`n            for i = 2:numel(br2_zoh)`r`n                prev_v = br2_zoh(i-1);`r`n                cur_v  = br2_zoh(i);`r`n                if prev_v == br2_proto.idle && cur_v == br2_proto.sf_pulse`r`n                    br2_sf_times(end+1) = br2_zoh_t(i);   %#ok<AGROW>`r`n                elseif prev_v == br2_proto.idle && cur_v == br2_proto.pitin`r`n                    br2_pitin_t(end+1)  = br2_zoh_t(i);   %#ok<AGROW>`r`n                elseif prev_v == br2_proto.pitin && cur_v == br2_proto.idle`r`n                    br2_pitout_t(end+1) = br2_zoh_t(i);   %#ok<AGROW>`r`n                end`r`n            end`r`n        else`r`n            % --- Standard protocol detection (999->1500->996 sequences) ---`r`n            br2_pit900_prev = [];   % value before each garage run`r`n            br2_pit900_t0   = [];   % start time of each garage run`r`n            br2_pit900_t1   = [];   % end   time of each garage run`r`n`r`n            n_br2_zoh = numel(br2_zoh);"
if ($c.Contains($old3a)) {
    $c = $c.Replace($old3a, $new3a)
    Write-Host "Edit 3a OK"
} else { Write-Host "Edit 3a NOT FOUND" }

# ---- Edit 3b: close else block before boundary check ----
# The unique sequence is: closing end of pit-exit for loop, empty line, then if isempty
$old3b = "        end`r`n`r`n        if isempty(br2_sf_times)"
$new3b = "        end`r`n        end  % if strcmp(br2_proto.variant, 'simple_pulse') / else`r`n`r`n        if isempty(br2_sf_times)"
if ($c.Contains($old3b)) {
    $c = $c.Replace($old3b, $new3b)
    Write-Host "Edit 3b OK"
} else { Write-Host "Edit 3b NOT FOUND" }

[IO.File]::WriteAllText($f, $c)
Write-Host "Done. New length: $($c.Length)"
