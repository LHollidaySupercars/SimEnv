$f = 'c:\SimEnv\dataAcquisition\parseEventData\lap_slicer.m'
$full = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)

# Find the unique ASCII anchor
$anchor = "Garage runs (0/900) : %d"
$idx = $full.IndexOf($anchor)
if ($idx -lt 0) { Write-Host "NOT FOUND"; exit 1 }

# Walk back to find "if verbose" before this position
$start = $full.LastIndexOf("            if verbose", $idx)
if ($start -lt 0) { Write-Host "if verbose NOT FOUND"; exit 1 }

# The closing end of the if verbose block is the next 'end' after the anchor
$endSearch = $full.IndexOf("end", $idx + $anchor.Length)
# include the newline after 'end'
$blockEnd = $endSearch + 3  # length of "end"

Write-Host "start=$start  blockEnd=$blockEnd"
Write-Host "OLD:"
Write-Host $full.Substring($start, $blockEnd - $start)
Write-Host "---"

# Build replacement (no Unicode needed)
$newBlock = "            if verbose" + [char]13 + [char]10 +
            "                fprintf('\n  Boundary mode       : Mode B - BR2 S/F transitions (%s)\n', br2_proto.name);" + [char]13 + [char]10 +
            "                fprintf('  S/F crossings       : %d\n', numel(br2_sf_times));" + [char]13 + [char]10 +
            "                fprintf('  Pit-in events       : %d\n', numel(br2_pitin_t));" + [char]13 + [char]10 +
            "                fprintf('  Pit-out events      : %d\n', numel(br2_pitout_t));" + [char]13 + [char]10 +
            "                if exist('br2_pit900_t0', 'var')" + [char]13 + [char]10 +
            "                    fprintf('  Garage runs (0/900) : %d\n', numel(br2_pit900_t0));" + [char]13 + [char]10 +
            "                end" + [char]13 + [char]10 +
            "            end"

$oldBlock = $full.Substring($start, $blockEnd - $start)
$newFull = $full.Substring(0, $start) + $newBlock + $full.Substring($blockEnd)

[IO.File]::WriteAllText($f, $newFull, [Text.Encoding]::UTF8)
Write-Host "Done. Length: $($newFull.Length)"
