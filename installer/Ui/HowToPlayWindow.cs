using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

namespace LotmRussianPatcher
{
    // "Как играть": installer/HowToPlay.md (resource LotmRussianPatcher.HowToPlay.md) shown as a FlowDocument.
    // Markup: "# " section, "## " subsection, "N. " step (number shown as written), "- " item, **bold**, [text](https://...),
    // ![](img/name.png) = resource LotmRussianPatcher.howto.name.png. Links outside Links.AllowedHosts stay plain text.
    public static class HowToPlayWindow
    {
        public const string XamlResource = "LotmRussianPatcher.HowToPlayWindow.xaml";
        public const string TextResource = "LotmRussianPatcher.HowToPlay.md";
        public const string ImageResourcePrefix = "LotmRussianPatcher.howto.";
        public static readonly string[] ElementNames = { "Viewer", "CloseButton" };

        private const double StepIndent = 30;
        private static readonly Regex Numbered = new Regex("^(\\d+)\\.\\s+(.*)$");
        private static readonly Regex ImageLine = new Regex("^!\\[[^\\]]*\\]\\(img/([A-Za-z0-9_.-]+)\\)$");
        private static readonly Regex InlineToken = new Regex("\\*\\*(?<b>.+?)\\*\\*|\\[(?<t>[^\\]]+)\\]\\((?<u>[^)\\s]+)\\)");

        public static void Show(Window owner)
        {
            var window = (Window)UiKit.LoadXaml(XamlResource);
            window.Owner = owner;
            if (owner != null) window.Icon = owner.Icon;
            UiKit.UseDarkTitleBar(window);
            var viewer = UiKit.Find<FlowDocumentScrollViewer>(window, "Viewer");
            UiKit.Find<Button>(window, "CloseButton").Click += (s, e) => window.Close();
            window.PreviewKeyDown += (s, e) => { if (e.Key == Key.Escape) window.Close(); };
            viewer.Document = BuildDocument(LoadText(), name => UiKit.LoadImage(ImageResourcePrefix + name));
            window.ShowDialog();
        }

        public static string LoadText()
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(TextResource))
            {
                if (s == null) return "# Как играть\n\nТекст инструкции не найден.";
                using (var reader = new StreamReader(s, Encoding.UTF8)) return reader.ReadToEnd();
            }
        }

        public static FlowDocument BuildDocument(string markdown, Func<string, ImageSource> loadImage)
        {
            var doc = new FlowDocument
            {
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 14,
                PagePadding = new Thickness(12, 8, 12, 16),
                TextAlignment = TextAlignment.Left,
                LineHeight = 21
            };
            if (Application.Current != null && Application.Current.Resources.Contains("TextBrush"))
            {
                doc.Foreground = UiKit.Brush("TextBrush");
            }

            List list = null;       // "- " items
            Section steps = null;   // "N. " items: the number is taken as written (the steps count down 9 → 0)
            var paragraph = new StringBuilder();
            Action flush = () =>
            {
                if (paragraph.Length == 0) return;
                var p = new Paragraph { Margin = new Thickness(0, 0, 0, 10) };
                AddInlines(p.Inlines, paragraph.ToString());
                doc.Blocks.Add(p);
                paragraph.Clear();
            };

            foreach (string rawLine in (markdown ?? "").Replace("\r\n", "\n").Split('\n'))
            {
                string line = rawLine.TrimEnd();
                if (line.Trim().Length == 0) { flush(); list = null; steps = null; continue; }

                if (line.StartsWith("# ") || line.StartsWith("## "))
                {
                    flush();
                    list = null;
                    steps = null;
                    bool h1 = line.StartsWith("# ");
                    var h = new Paragraph(new Run(line.Substring(h1 ? 2 : 3).Trim()))
                    {
                        Tag = h1 ? "h1" : "h2",
                        FontSize = h1 ? 19 : 15.5,
                        FontWeight = FontWeights.SemiBold,
                        Margin = new Thickness(0, doc.Blocks.Count == 0 ? 0 : (h1 ? 20 : 12), 0, 8)
                    };
                    if (h1 && Application.Current != null && Application.Current.Resources.Contains("GoldBrush")) h.Foreground = UiKit.Brush("GoldBrush");
                    doc.Blocks.Add(h);
                    continue;
                }

                Match img = ImageLine.Match(line.Trim());
                if (img.Success)
                {
                    flush();
                    list = null;
                    steps = null;
                    ImageSource source = loadImage != null ? loadImage(img.Groups[1].Value) : null;
                    if (source != null)
                    {
                        var image = new Image { Source = source, Stretch = Stretch.Uniform, MaxWidth = 340, HorizontalAlignment = HorizontalAlignment.Left };
                        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                        var frame = new Border { Child = image, CornerRadius = new CornerRadius(8), HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(6), Background = Brushes.White };
                        doc.Blocks.Add(new BlockUIContainer(frame) { Tag = "img", Margin = new Thickness(StepIndent, 2, 0, 12) });
                    }
                    continue;
                }

                Match num = Numbered.Match(line);
                if (num.Success)
                {
                    flush();
                    list = null;
                    // Hanging indent: the number sits in a fixed-width box, wrapped lines align with the text.
                    // (FlowDocument Table collapses its star column in FlowDocumentScrollViewer, List numbers only count up.)
                    if (steps == null)
                    {
                        steps = new Section { Tag = "ol", Margin = new Thickness(0, 0, 0, 10) };
                        doc.Blocks.Add(steps);
                    }
                    var number = new TextBlock { Text = num.Groups[1].Value + ".", Width = StepIndent, FontWeight = FontWeights.SemiBold, FontSize = 14, RenderTransform = new TranslateTransform(0, 2) };
                    if (Application.Current != null && Application.Current.Resources.Contains("GoldBrush")) number.Foreground = UiKit.Brush("GoldBrush");
                    var item = new Paragraph { Tag = num.Groups[1].Value, Margin = new Thickness(StepIndent, 0, 0, 6), TextIndent = -StepIndent };
                    item.Inlines.Add(new InlineUIContainer(number) { BaselineAlignment = BaselineAlignment.TextBottom });
                    AddInlines(item.Inlines, num.Groups[2].Value);
                    steps.Blocks.Add(item);
                    continue;
                }

                if (line.StartsWith("- "))
                {
                    flush();
                    steps = null;
                    if (list == null)
                    {
                        list = new List { Tag = "ul", MarkerStyle = TextMarkerStyle.Disc, Margin = new Thickness(0, 0, 0, 10), Padding = new Thickness(26, 0, 0, 0) };
                        doc.Blocks.Add(list);
                    }
                    var p = new Paragraph { Margin = new Thickness(0, 0, 0, 6) };
                    AddInlines(p.Inlines, line.Substring(2));
                    list.ListItems.Add(new ListItem(p));
                    continue;
                }

                if (paragraph.Length > 0) paragraph.Append(' ');
                paragraph.Append(line.Trim());
            }
            flush();
            return doc;
        }

        private static void AddInlines(InlineCollection inlines, string text)
        {
            int pos = 0;
            foreach (Match m in InlineToken.Matches(text))
            {
                if (m.Index > pos) inlines.Add(new Run(text.Substring(pos, m.Index - pos)));
                if (m.Groups["b"].Success)
                {
                    inlines.Add(new Bold(new Run(m.Groups["b"].Value)));
                }
                else
                {
                    string label = m.Groups["t"].Value;
                    string url = m.Groups["u"].Value;
                    if (Links.IsAllowedUrl(url))
                    {
                        var link = new Hyperlink(new Run(label)) { ToolTip = url };
                        link.Click += (s, e) => Links.Open(url);
                        inlines.Add(link);
                    }
                    else inlines.Add(new Run(label));
                }
                pos = m.Index + m.Length;
            }
            if (pos < text.Length) inlines.Add(new Run(text.Substring(pos)));
        }
    }
}
