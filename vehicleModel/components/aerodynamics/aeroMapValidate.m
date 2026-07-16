% aeroMapValidate  Visual validation of an aeroMap struct.
%
%   aeroMapValidate(MAP)
%
%   For each unique roll value in the data, produces a 3x3 figure showing
%   all 9 aero outputs as surf plots vs FRH_mm / RRH_mm.
%   Uses griddata on the raw scatter, consistent with visualize.m.

function aeroMapValidate(map)
    out_channels = {'CDa_SCx','CLa_SCz','CLf_SCzF','CLr_SCzR', ...
                    'AB_FRT','EFF','CSa_Scy','CSf_SCyF','CSr_SCyR'};

    out_labels = {'CDa\_SCx (drag)',       'CLa\_SCz (total lift)',  'CLf\_SCzF (front lift)', ...
                  'CLr\_SCzR (rear lift)', 'AB\_FRT (balance)',      'EFF (efficiency)', ...
                  'CSa\_Scy (side force)', 'CSf\_SCyF (front side)', 'CSr\_SCyR (rear side)'};

    tbl       = map.raw;
    roll_vals = sort(unique(tbl.roll_deg), 'ascend');

    nPts = 40;

    for wi = 1:numel(roll_vals)
        roll_val = roll_vals(wi);
        rows = abs(tbl.roll_deg - roll_val) < 0.01;
        sub  = tbl(rows, :);

        if height(sub) < 3
            fprintf('aeroMapValidate: skipping roll=%.2f (only %d rows)\n', roll_val, height(sub));
            continue;
        end

        % Build query grid from this slice's actual data range
        [Xq, Yq] = meshgrid(linspace(min(sub.FRH_mm), max(sub.FRH_mm), nPts), ...
                             linspace(min(sub.RRH_mm), max(sub.RRH_mm), nPts));

        figure('Name', sprintf('Aero Map  Roll=%.2fdeg', roll_val), ...
               'NumberTitle', 'off', 'Position', [50 50 1400 900]);

        for k = 1:numel(out_channels)
            ch = out_channels{k};
            Zq = griddata(sub.FRH_mm, sub.RRH_mm, sub.(ch), Xq, Yq);

            subplot(3, 3, k);
            if isequal(size(Zq), size(Xq))
                surf(Xq, Yq, Zq, 'EdgeColor', 'none');
            else
                % Fallback: scatter when griddata can't triangulate
                scatter3(sub.FRH_mm, sub.RRH_mm, sub.(ch), 40, sub.(ch), 'filled');
            end
            xlabel('FRH [mm]', 'FontSize', 8);
            ylabel('RRH [mm]', 'FontSize', 8);
            title(out_labels{k}, 'Interpreter', 'tex', 'FontSize', 9);
            colorbar;
            view(45, 30);
        end

        annotation('textbox', [0 0.96 1 0.04], ...
            'String', sprintf('Aero Map  |  Roll = %.2f deg  |  n=%d runs', roll_val, height(sub)), ...
            'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
            'FontSize', 11, 'FontWeight', 'bold');
    end

end

