using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// StrategyPanel — Gantt-style stint chart, one horizontal bar row per car,
/// segmented by outing (stint). Simplified from the original canvas-drawn
/// ui/views/panels/panel_strategy.js (tyre/fuel entry popups not yet ported).
/// </summary>
public partial class StrategyPanel : UserControl
{
    private sealed class Stint
    {
        public int Outing;
        public int StartLap;
        public int EndLap;
    }

    private readonly Dictionary<string, List<Stint>> _stints = new();
    private readonly List<string> _carOrder = new();

    public StrategyPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Stint Strategy");
        Plot.Plot.XLabel("Lap");
    }

    public void OnLap(Lap lap)
    {
        if (!_stints.TryGetValue(lap.CarNumber, out var list))
        {
            _stints[lap.CarNumber] = list = new();
            _carOrder.Add(lap.CarNumber);
        }

        var current = list.LastOrDefault(s => s.Outing == lap.Outing);
        if (current == null)
        {
            current = new Stint { Outing = lap.Outing, StartLap = lap.LapNumber, EndLap = lap.LapNumber };
            list.Add(current);
        }
        else
        {
            current.EndLap = Math.Max(current.EndLap, lap.LapNumber);
        }
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        for (var i = 0; i < _carOrder.Count; i++)
        {
            var car = _carOrder[i];
            foreach (var stint in _stints[car])
            {
                var bar = new Bar
                {
                    Position = i,
                    ValueBase = stint.StartLap,
                    Value = stint.EndLap + 1,
                    Orientation = ScottPlot.Orientation.Horizontal,
                };
                Plot.Plot.Add.Bars(new[] { bar });
            }
        }
        var ticks = _carOrder.Select((c, i) => new Tick(i, c)).ToArray();
        Plot.Plot.Axes.Left.TickGenerator = new ScottPlot.TickGenerators.NumericManual(ticks);
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
