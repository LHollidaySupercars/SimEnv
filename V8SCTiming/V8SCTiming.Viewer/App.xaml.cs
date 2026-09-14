using System.IO;
using System.Windows;
using V8SCTiming.Viewer.Services;

namespace V8SCTiming.Viewer;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    private static readonly string ThemePrefPath = Path.Combine(AppContext.BaseDirectory, "theme.pref");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Apply the last-used theme (default Dark) before showing any window,
        // then create MainWindow manually since StartupUri is no longer used.
        var saved = File.Exists(ThemePrefPath) ? File.ReadAllText(ThemePrefPath).Trim() : "Dark";
        var theme = Enum.TryParse<AppTheme>(saved, out var t) ? t : AppTheme.Dark;
        ThemeManager.Apply(theme);
        ThemeManager.ThemeChanged += th =>
        {
            try { File.WriteAllText(ThemePrefPath, th.ToString()); } catch { /* non-fatal */ }
        };

        var window = new MainWindow();
        window.Show();
    }
}

