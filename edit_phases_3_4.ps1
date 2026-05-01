$fc = 'c:\SimEnv\dataAcquisition\parseEventData\smp_compile_event.m'
$fl = 'c:\SimEnv\dataAcquisition\parseEventData\LiftAndCoast.m'
$cc = [IO.File]::ReadAllText($fc, [Text.Encoding]::UTF8)
$cl = [IO.File]::ReadAllText($fl, [Text.Encoding]::UTF8)

# === smp_compile_event.m ===

# Edit CE-1: add br2_protocol to outer opts parsing
$old = "    br2_channel    = get_opt(opts, 'br2_channel',      'BR2_Beacon_Number');"
$new = "    br2_channel    = get_opt(opts, 'br2_channel',      'BR2_Beacon_Number');" + [char]13 + [char]10 +
       "    br2_protocol   = get_opt(opts, 'br2_protocol',     'standard');"
if ($cc.Contains($old)) { $cc = $cc.Replace($old, $new); Write-Host "CE-1 OK" } else { Write-Host "CE-1 NOT FOUND" }

# Edit CE-2: add br2_channel + br2_protocol to process_stream call
$old = "                               detect_pitlane, fcy_channel, ..." + [char]13 + [char]10 +
       "                               unique_fp, show_report, concat_csv_dir);"
$new = "                               detect_pitlane, fcy_channel, ..." + [char]13 + [char]10 +
       "                               br2_channel, br2_protocol, ..." + [char]13 + [char]10 +
       "                               unique_fp, show_report, concat_csv_dir);"
if ($cc.Contains($old)) { $cc = $cc.Replace($old, $new); Write-Host "CE-2 OK" } else { Write-Host "CE-2 NOT FOUND" }

# Edit CE-3: add br2_channel + br2_protocol to process_stream signature + nargin defaults
$old = "                                 detect_pitlane, fcy_channel, ..." + [char]13 + [char]10 +
       "                                 unique_fp, show_report, concat_csv_dir)" + [char]13 + [char]10 +
       "    if nargin < 11, channel_rules  = [];        end" + [char]13 + [char]10 +
       "    if nargin < 12, detect_pitlane = false;     end" + [char]13 + [char]10 +
       "    if nargin < 13, fcy_channel    = 'FCY_Flag'; end" + [char]13 + [char]10 +
       "    if nargin < 14, unique_fp      = false;     end" + [char]13 + [char]10 +
       "    if nargin < 15, show_report    = false;     end" + [char]13 + [char]10 +
       "    if nargin < 16, concat_csv_dir = '';        end"
$new = "                                 detect_pitlane, fcy_channel, ..." + [char]13 + [char]10 +
       "                                 br2_channel, br2_protocol, ..." + [char]13 + [char]10 +
       "                                 unique_fp, show_report, concat_csv_dir)" + [char]13 + [char]10 +
       "    if nargin < 11, channel_rules  = [];                  end" + [char]13 + [char]10 +
       "    if nargin < 12, detect_pitlane = false;               end" + [char]13 + [char]10 +
       "    if nargin < 13, fcy_channel    = 'FCY_Flag';          end" + [char]13 + [char]10 +
       "    if nargin < 14, br2_channel    = 'BR2_Beacon_Number'; end" + [char]13 + [char]10 +
       "    if nargin < 15, br2_protocol   = 'standard';          end" + [char]13 + [char]10 +
       "    if nargin < 16, unique_fp      = false;               end" + [char]13 + [char]10 +
       "    if nargin < 17, show_report    = false;               end" + [char]13 + [char]10 +
       "    if nargin < 18, concat_csv_dir = '';                  end"
if ($cc.Contains($old)) { $cc = $cc.Replace($old, $new); Write-Host "CE-3 OK" } else { Write-Host "CE-3 NOT FOUND" }

# Edit CE-4: add lap_opts.br2_* after lap_opts.fcy_channel
$old = "    lap_opts.fcy_channel     = fcy_channel;" + [char]13 + [char]10 +
       "    lap_opts.mylaps_channel  = MYLAPS_CH_DEFAULT;"
$new = "    lap_opts.fcy_channel     = fcy_channel;" + [char]13 + [char]10 +
       "    lap_opts.br2_channel     = br2_channel;" + [char]13 + [char]10 +
       "    lap_opts.br2_protocol    = br2_protocol;" + [char]13 + [char]10 +
       "    lap_opts.mylaps_channel  = MYLAPS_CH_DEFAULT;"
if ($cc.Contains($old)) { $cc = $cc.Replace($old, $new); Write-Host "CE-4 OK" } else { Write-Host "CE-4 NOT FOUND" }

# Edit CE-5: inject br2_channel into required_ch
$old = "        if ~isempty(fcy_channel)" + [char]13 + [char]10 +
       "            required_ch{end+1} = fcy_channel;" + [char]13 + [char]10 +
       "        end"
$new = "        if ~isempty(fcy_channel)" + [char]13 + [char]10 +
       "            required_ch{end+1} = fcy_channel;" + [char]13 + [char]10 +
       "        end" + [char]13 + [char]10 +
       "        if ~isempty(br2_channel)" + [char]13 + [char]10 +
       "            required_ch{end+1} = br2_channel;" + [char]13 + [char]10 +
       "        end"
if ($cc.Contains($old)) { $cc = $cc.Replace($old, $new); Write-Host "CE-5 OK" } else { Write-Host "CE-5 NOT FOUND" }

[IO.File]::WriteAllText($fc, $cc, [Text.Encoding]::UTF8)
Write-Host "smp_compile_event done."

# === LiftAndCoast.m ===

# Edit LC-1: add addParameter for br2_protocol
$old = "addParameter(p, 'concat_csv_dir','',                    @ischar);"
$new = "addParameter(p, 'concat_csv_dir','',                    @ischar);" + [char]13 + [char]10 +
       "addParameter(p, 'br2_protocol', 'standard',             @ischar);"
if ($cl.Contains($old)) { $cl = $cl.Replace($old, $new); Write-Host "LC-1 OK" } else { Write-Host "LC-1 NOT FOUND" }

# Edit LC-2: extract br2_protocol from r
$old = "concat_csv_dir = r.concat_csv_dir;"
$new = "concat_csv_dir = r.concat_csv_dir;" + [char]13 + [char]10 +
       "br2_protocol   = r.br2_protocol;"
if ($cl.Contains($old)) { $cl = $cl.Replace($old, $new); Write-Host "LC-2 OK" } else { Write-Host "LC-2 NOT FOUND" }

# Edit LC-3: pass br2_protocol into c_opts in compile block
$old = "    c_opts.detect_pitlane   = true;"
$new = "    c_opts.detect_pitlane   = true;" + [char]13 + [char]10 +
       "    c_opts.br2_protocol     = br2_protocol;"
if ($cl.Contains($old)) { $cl = $cl.Replace($old, $new); Write-Host "LC-3 OK" } else { Write-Host "LC-3 NOT FOUND" }

[IO.File]::WriteAllText($fl, $cl, [Text.Encoding]::UTF8)
Write-Host "LiftAndCoast done."
