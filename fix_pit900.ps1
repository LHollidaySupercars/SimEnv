$f = 'c:\SimEnv\dataAcquisition\parseEventData\lap_slicer.m'
$full = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)

# Fix 1: outlap pit_exit_t lookup (lines ~896-899)
$old1 = "            elseif br2_starts_at_pitout_v(k)" + [char]13 + [char]10 +
        "                % Starts at beacon->900 transition -> outlap" + [char]13 + [char]10 +
        "                % pit_exit_t = end of the garage run that began at t_s" + [char]13 + [char]10 +
        "                lap_type = 'outlap';" + [char]13 + [char]10 +
        "                run_idx  = find(abs(br2_pit900_t0 - t_s) < 0.1, 1);" + [char]13 + [char]10 +
        "                if ~isempty(run_idx)" + [char]13 + [char]10 +
        "                    pit_exit_t = br2_pit900_t1(run_idx);" + [char]13 + [char]10 +
        "                end"
$new1 = "            elseif br2_starts_at_pitout_v(k)" + [char]13 + [char]10 +
        "                % Starts at beacon->900 transition -> outlap" + [char]13 + [char]10 +
        "                % pit_exit_t = end of the garage run that began at t_s" + [char]13 + [char]10 +
        "                lap_type = 'outlap';" + [char]13 + [char]10 +
        "                if exist('br2_pit900_t0', 'var') && ~isempty(br2_pit900_t0)" + [char]13 + [char]10 +
        "                    run_idx  = find(abs(br2_pit900_t0 - t_s) < 0.1, 1);" + [char]13 + [char]10 +
        "                    if ~isempty(run_idx)" + [char]13 + [char]10 +
        "                        pit_exit_t = br2_pit900_t1(run_idx);" + [char]13 + [char]10 +
        "                    end" + [char]13 + [char]10 +
        "                end"

if ($full.Contains($old1)) {
    $full = $full.Replace($old1, $new1)
    Write-Host "Fix 1 OK"
} else { Write-Host "Fix 1 NOT FOUND" }

# Fix 2: garage run overlap loop (lines ~906-914)
$old2 = "            % Check for garage run (900-hold) overlapping this lap window" + [char]13 + [char]10 +
        "            % to populate pit_entry_t / pit_exit_t fields where not already set." + [char]13 + [char]10 +
        "            % Use strict > t_s so the outlap (which starts at t_s=pit_exit) is" + [char]13 + [char]10 +
        "            % not re-attributed with the run that just ended." + [char]13 + [char]10 +
        "            for pi = 1:numel(br2_pit900_t0)"
$new2 = "            % Check for garage run (900-hold) overlapping this lap window" + [char]13 + [char]10 +
        "            % to populate pit_entry_t / pit_exit_t fields where not already set." + [char]13 + [char]10 +
        "            % Use strict > t_s so the outlap (which starts at t_s=pit_exit) is" + [char]13 + [char]10 +
        "            % not re-attributed with the run that just ended." + [char]13 + [char]10 +
        "            if ~exist('br2_pit900_t0', 'var'), br2_pit900_t0 = []; br2_pit900_t1 = []; end" + [char]13 + [char]10 +
        "            for pi = 1:numel(br2_pit900_t0)"

if ($full.Contains($old2)) {
    $full = $full.Replace($old2, $new2)
    Write-Host "Fix 2 OK"
} else { Write-Host "Fix 2 NOT FOUND" }

[IO.File]::WriteAllText($f, $full, [Text.Encoding]::UTF8)
Write-Host "Done. Length: $($full.Length)"
