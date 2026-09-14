using System.IO;
using System.Windows;
using System.Windows.Controls;
using V8SCTiming.Core.Data;
using V8SCTiming.Viewer.Services;

namespace V8SCTiming.Viewer;

/// <summary>
/// Interaction logic for MainWindow.xaml.
///
/// The Viewer only ever READS from the shared SQLite database written by
/// V8SCTiming.Logger — it never inserts laps/passings itself. This keeps the
/// Logger as the single source of truth per the user's storage decision.
/// </summary>
public partial class MainWindow : Window
{
    private readonly TimingDb _db;
    private DbTailService? _tail;

    private record SessionItem(string Id, string Display);

    public MainWindow()
    {
        InitializeComponent();

        var dbPath = ResolveDbPath();
        _db = new TimingDb(dbPath);
        StatusText.Text = $"DB: {dbPath}";
        LoadSessions();

        foreach (ComboBoxItem item in ThemeCombo.Items)
        {
            if ((string?)item.Tag == ThemeManager.Current.ToString()) { ThemeCombo.SelectedItem = item; break; }
        }
    }

    private static string ResolveDbPath()
    {
        // Walk up from the executable looking for a v8sctiming.db next to the
        // solution root (same file the Logger writes to). Falls back to a
        // local copy next to the exe if none is found (first run).
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 6 && dir != null; i++)
        {
            var candidate = Path.Combine(dir, "v8sctiming.db");
            if (File.Exists(candidate)) return candidate;
            dir = Directory.GetParent(dir)?.FullName;
        }
        return Path.Combine(AppContext.BaseDirectory, "v8sctiming.db");
    }

    private void LoadSessions()
    {
        var selected = (SessionCombo.SelectedItem as SessionItem)?.Id;
        var sessions = _db.GetAllSessions()
            .Select(s => new SessionItem(s.Id, $"{s.TrackName} — {DateTimeOffset.FromUnixTimeMilliseconds(s.StartedAt):yyyy-MM-dd HH:mm} ({s.Status})"))
            .ToList();
        SessionCombo.ItemsSource = sessions;
        if (sessions.Count > 0)
        {
            SessionCombo.SelectedItem = sessions.FirstOrDefault(s => s.Id == selected) ?? sessions[0];
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) => LoadSessions();

    private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ThemeCombo.SelectedItem is not ComboBoxItem item || item.Tag is not string tag) return;
        if (Enum.TryParse<AppTheme>(tag, out var theme)) ThemeManager.Apply(theme);
    }

    private void SessionCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SessionCombo.SelectedItem is not SessionItem item) return;

        _tail?.Dispose();
        _tail = new DbTailService(_db);
        _tail.NewLaps += laps =>
        {
            foreach (var lap in laps)
            {
                Scoreboard.OnLap(lap);
                LapTimeChart.OnLap(lap);
                BestLap.OnLap(lap);
                Position.OnLap(lap);
                PitStops.OnLap(lap);
                Gap.OnLap(lap);
                Distribution.OnLap(lap);
                FuelCalc.OnLap(lap);
                FuelDeg.OnLap(lap);
                PitImpact.OnLap(lap);
                SectorBreakdown.OnLap(lap);
                SectorProgression.OnLap(lap);
                SectorVariance.OnLap(lap);
                SpeedTrap.OnLap(lap);
                Strategy.OnLap(lap);
                Summary.OnLap(lap);
                Undercut.OnLap(lap);
                Overtakes.OnLap(lap);
                Ants.OnLap(lap);
            }
        };
        _tail.Start(item.Id);
        StatusText.Text = $"Live-tailing session {item.Id}";
    }
}
