$f = 'c:\SimEnv\dataAcquisition\parseEventData\lap_slicer.m'
$full = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)

# Use ASCII-only anchors to locate the block
$anchor1 = "run_idx  = find(abs(br2_pit900_t0 - t_s) < 0.1, 1);"
$anchor2 = "                if ~isempty(run_idx)" + [char]13 + [char]10 +
           "                    pit_exit_t = br2_pit900_t1(run_idx);" + [char]13 + [char]10 +
           "                end"

$idx1 = $full.IndexOf($anchor1)
Write-Host "anchor1 at: $idx1"
if ($idx1 -lt 0) { exit 1 }

# Replace just the 3 lines: the find + if/end block
$oldSnip = $anchor1 + [char]13 + [char]10 + $anchor2
$newSnip = "if exist('br2_pit900_t0', 'var') && ~isempty(br2_pit900_t0)" + [char]13 + [char]10 +
           "                    run_idx  = find(abs(br2_pit900_t0 - t_s) < 0.1, 1);" + [char]13 + [char]10 +
           "                    if ~isempty(run_idx)" + [char]13 + [char]10 +
           "                        pit_exit_t = br2_pit900_t1(run_idx);" + [char]13 + [char]10 +
           "                    end" + [char]13 + [char]10 +
           "                end"

if ($full.Contains($oldSnip)) {
    $full = $full.Replace($oldSnip, $newSnip)
    [IO.File]::WriteAllText($f, $full, [Text.Encoding]::UTF8)
    Write-Host "Fix 1 OK. Length: $($full.Length)"
} else {
    Write-Host "Fix 1 still NOT FOUND"
    $full.Substring($idx1 - 5, 200)
}
