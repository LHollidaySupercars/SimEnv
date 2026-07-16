for i = 1:length(SMP.T8R.info)
    
    fprintf('%s\n', SMP.T8R.info{i,1}.event)
    fprintf('%s\n',SMP.T8R.info{i,1}.car_number)
    fprintf('%s\n',SMP.T8R.info{i,1}.session)

end
%%

motec_ld_inspect(SMP.T8R.meta.Path(15))
%%

motec_ld_meta_dump(SMP.T8R.meta.Path(15))
%%

motec_ld_inspect(SMP.T8R.meta.Path{end})

%%
% Dump entire file to text
fid_in  = fopen(SMP.T8R.meta.Path{end}, 'rb');
fid_out = fopen('C:\temp\ldx_dump.txt', 'w');

raw = fread(fid_in, inf, 'uint8')';
n   = numel(raw);

fprintf(fid_out, 'Offset     00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
fprintf(fid_out, '%s\n', repmat('-',1,77));

for row = 0:16:n-1
    idx  = row+1;
    seg  = raw(idx:min(idx+15,n));
    hexs = sprintf('%02X ', seg);
    hexs = [hexs, repmat('   ',1,16-numel(seg))];
    asc  = seg; asc(asc<32|asc>126) = double('.');
    fprintf(fid_out, '0x%06X   %s | %s\n', row, hexs, char(asc));
end

fclose(fid_in);
fclose(fid_out);
fprintf('Done. Open C:\\temp\\ldx_dump.txt\n');
%%
fid = fopen(SMP.T8R.meta.Path{end}, 'rb');
raw = fread(fid, inf, 'uint8')';
fclose(fid);

% Find all readable strings >= 5 chars
in_run = false; run_start = 0;
for i = 1:numel(raw)
    p = raw(i) >= 32 && raw(i) <= 126;
    if p && ~in_run
        in_run = true; run_start = i;
    elseif ~p && in_run
        if i - run_start >= 5
            fprintf('0x%06X: "%s"\n', run_start-1, char(raw(run_start:i-1)));
        end
        in_run = false;
    end
end
%%
fid = fopen(SMP.T8R.meta.Path{end}, 'rb');
raw = fread(fid, inf, 'uint8')';
fclose(fid);

fid_out = fopen('C:\temp\ld_strings.txt', 'w');

in_run = false; run_start = 0;
for i = 1:numel(raw)
    p = raw(i) >= 32 && raw(i) <= 126;
    if p && ~in_run
        in_run = true; run_start = i;
    elseif ~p && in_run
        if i - run_start >= 5
            fprintf(fid_out, '0x%06X: "%s"\n', run_start-1, char(raw(run_start:i-1)));
        end
        in_run = false;
    end
end

fclose(fid_out);
fprintf('Done. Open C:\\temp\\ld_strings.txt\n');