using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace LotmRussianPatcher
{
    // Shared WPF helpers: theme, XAML from resources, icons, dark title bar, own dialogs (no system MessageBox).
    public static class UiKit
    {
        public const string ThemeResource = "LotmRussianPatcher.Theme.xaml";
        public const string IconResource = "LotmRussianPatcher.app.ico";

        public static Application EnsureApplication()
        {
            Application app = Application.Current ?? new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            if (!app.Resources.Contains("BgBrush"))
            {
                app.Resources.MergedDictionaries.Add((ResourceDictionary)LoadXaml(ThemeResource));
            }
            return app;
        }

        public static object LoadXaml(string resourceName)
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
            {
                if (s == null) throw new InvalidOperationException("Нет ресурса " + resourceName);
                return XamlReader.Load(s);
            }
        }

        // T for FindName with a clear error instead of a null reference later.
        public static T Find<T>(FrameworkElement root, string name) where T : class
        {
            T element = root.FindName(name) as T;
            if (element == null) throw new InvalidOperationException("В разметке нет элемента " + name + " (" + typeof(T).Name + ")");
            return element;
        }

        public static Brush Brush(string key)
        {
            return (Brush)Application.Current.Resources[key];
        }

        public static ImageSource LoadImage(string resourceName)
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
                {
                    if (s == null) return null;
                    var ms = new MemoryStream();
                    s.CopyTo(ms);
                    ms.Position = 0;
                    BitmapDecoder decoder = BitmapDecoder.Create(ms, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                    BitmapFrame best = decoder.Frames[0];
                    foreach (BitmapFrame f in decoder.Frames) if (f.PixelWidth > best.PixelWidth) best = f;
                    best.Freeze();
                    return best;
                }
            }
            catch { return null; }
        }

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        // Dark caption on Windows 10 2004+ / 11 (attribute 20; 19 on older 10 builds). Ignored elsewhere.
        public static void UseDarkTitleBar(Window window)
        {
            window.SourceInitialized += (s, e) =>
            {
                try
                {
                    IntPtr hwnd = new WindowInteropHelper(window).Handle;
                    int on = 1;
                    if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
                }
                catch { }
            };
        }

        public static void Message(Window owner, string title, string text, bool error)
        {
            ShowDialog(owner, title, text, "OK", null, error ? "ErrorBrush" : "GoldBrush", false);
        }

        public static bool Confirm(Window owner, string title, string text, string okText, string cancelText, bool danger)
        {
            return ShowDialog(owner, title, text, okText, cancelText, danger ? "ErrorBrush" : "GoldBrush", danger);
        }

        private static bool ShowDialog(Window owner, string title, string text, string okText, string cancelText, string accentKey, bool danger)
        {
            var dlg = new Window
            {
                Title = title,
                Owner = owner,
                WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
                Width = 460,
                SizeToContent = SizeToContent.Height,
                ResizeMode = ResizeMode.NoResize,
                ShowInTaskbar = false,
                Background = Brush("BgBrush"),
                Foreground = Brush("TextBrush"),
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 13,
                UseLayoutRounding = true
            };
            if (owner != null) dlg.Icon = owner.Icon;
            UseDarkTitleBar(dlg);

            var panel = new StackPanel { Margin = new Thickness(24, 20, 24, 20) };
            panel.Children.Add(new TextBlock { Text = title, FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush(accentKey), TextWrapping = TextWrapping.Wrap });
            panel.Children.Add(new TextBlock { Text = text, Margin = new Thickness(0, 10, 0, 0), TextWrapping = TextWrapping.Wrap, Foreground = Brush("TextBrush") });

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 20, 0, 0) };
            bool result = false;
            if (cancelText != null)
            {
                var cancel = new Button { Content = cancelText, IsCancel = true, MinWidth = 100, IsDefault = danger };
                cancel.Click += (s, e) => dlg.Close();
                buttons.Children.Add(cancel);
            }
            var ok = new Button { Content = okText, MinWidth = 100, Margin = new Thickness(10, 0, 0, 0), IsDefault = !danger, IsCancel = cancelText == null };
            ok.Style = (Style)Application.Current.Resources[danger ? "DangerButton" : "PrimaryButton"];
            ok.Padding = new Thickness(18, 7, 18, 7);
            ok.FontSize = 13;
            ok.Click += (s, e) => { result = true; dlg.Close(); };
            buttons.Children.Add(ok);
            panel.Children.Add(buttons);
            dlg.Content = panel;
            dlg.ShowDialog();
            return result;
        }
    }
}
