using System.Windows;

namespace V8SCTiming.Viewer.Services;

public enum AppTheme { Dark, Light, HighContrast }

/// <summary>
/// Swaps the theme ResourceDictionary at runtime. ControlStyles.xaml (shared
/// flat control templates) stays merged permanently; only the colour
/// dictionary (Dark/Light/HighContrast.xaml) is swapped out.
/// </summary>
public static class ThemeManager
{
    private static ResourceDictionary? _currentThemeDict;

    public static AppTheme Current { get; private set; } = AppTheme.Dark;

    public static event Action<AppTheme>? ThemeChanged;

    public static void Apply(AppTheme theme)
    {
        var uri = theme switch
        {
            AppTheme.Dark => "Themes/Dark.xaml",
            AppTheme.Light => "Themes/Light.xaml",
            AppTheme.HighContrast => "Themes/HighContrast.xaml",
            _ => "Themes/Dark.xaml",
        };

        var dict = new ResourceDictionary { Source = new Uri(uri, UriKind.Relative) };
        var merged = Application.Current.Resources.MergedDictionaries;

        if (_currentThemeDict != null) merged.Remove(_currentThemeDict);
        merged.Insert(0, dict); // theme colours first, so ControlStyles (added at startup) can DynamicResource them
        _currentThemeDict = dict;

        Current = theme;
        ThemeChanged?.Invoke(theme);
    }
}
