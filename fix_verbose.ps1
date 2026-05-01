$f = 'c:\SimEnv\dataAcquisition\parseEventData\lap_slicer.m'
$c = [IO.File]::ReadAllText($f)

$old = "            if verbose`r`n                fprintf('\n  Boundary mode       : Mode B — BR2 999→996 S/F transitions\n');`r`n                fprintf('  S/F crossings       : %d\n', numel(br2_sf_times));`r`n                fprintf('  Pit-in (996→999)    : %d\n', numel(br2_pitin_t));`r`n                fprintf('  Garage runs (0/900) : %d\n', numel(br2_pit900_t0));`r`n            end"
$new = "            if verbose`r`n                fprintf('\n  Boundary mode       : Mode B — BR2 S/F transitions (%s)\n', br2_proto.name);`r`n                fprintf('  S/F crossings       : %d\n', numel(br2_sf_times));`r`n                fprintf('  Pit-in events       : %d\n', numel(br2_pitin_t));`r`n                fprintf('  Pit-out events      : %d\n', numel(br2_pitout_t));`r`n                if exist('br2_pit900_t0', 'var')`r`n                    fprintf('  Garage runs (0/900) : %d\n', numel(br2_pit900_t0));`r`n                end`r`n            end"

if ($c.Contains($old)) {
    $c = $c.Replace($old, $new)
    [IO.File]::WriteAllText($f, $c)
    Write-Host "OK"
} else {
    # Try finding the block by unique substring
    $idx = $c.IndexOf("Garage runs (0/900) : %d")
    Write-Host "Garage runs index: $idx"
    if ($idx -ge 0) { $c.Substring($idx - 200, 300) | Format-Hex }
}
