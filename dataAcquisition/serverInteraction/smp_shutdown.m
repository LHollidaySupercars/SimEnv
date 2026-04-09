%% SMP_SHUTDOWN
% V8SC Pit Wall — shutdown script
% Kills PocketBase and ngrok processes
% =========================================================

fprintf('Shutting down V8SC Pit Wall...\n');

[~, pb_check] = system('tasklist /FI "IMAGENAME eq pocketbase.exe" /NH');
if contains(pb_check, 'pocketbase.exe')
    system('taskkill /F /IM pocketbase.exe');
    fprintf('  PocketBase stopped.\n');
else
    fprintf('  PocketBase was not running.\n');
end

[~, ng_check] = system('tasklist /FI "IMAGENAME eq ngrok.exe" /NH');
if contains(ng_check, 'ngrok.exe')
    system('taskkill /F /IM ngrok.exe');
    fprintf('  ngrok stopped.\n');
else
    fprintf('  ngrok was not running.\n');
end

fprintf('\nPit Wall shut down.\n');
