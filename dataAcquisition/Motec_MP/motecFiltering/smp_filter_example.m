%% SMP FILTER EXAMPLE

%% 1. Load
alias = smp_alias_load('C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx');
[SMP, cache] = smp_load_teams('C:\LOCAL_DATA\01 - SMP\_Team Data', {'XMP'});

%% 2. Inspect full struct
smp_filter_summary(SMP);

%% 3. Filter examples
SMP2 = smp_filter(SMP, alias, 'Session',   'RA1');
%%
SMP2 = smp_filter(SMP, alias, 'Session',   {'RA1', 'QU1'});
%%
SMP2 = smp_filter(SMP, alias, 'Session',   'FP1');
%%
SMP2 = smp_filter(SMP, alias, 'Manufacturer', 'Ford');
%%
SMP2 = smp_filter(SMP, alias,   'Session',  'Race 1');   % no alias file needed  using T8R's own naming convention

%% 4. Check result
smp_filter_summary(SMP2);

%% 5. Iterate
team_keys = fieldnames(SMP2);
for t = 1:numel(team_keys)
    tk   = team_keys{t};
    node = SMP2.(tk);
    for r = 1:height(node.meta)
        ch   = node.channels{r};   % struct: ch.Corr_Speed, ch.Engine_Speed ...
        info = node.info{r};
        fprintf('%s | %s | %s | %s\n', tk, ...
            node.meta.Driver{r}, node.meta.Session{r}, node.meta.Manufacturer{r});
    end
end
