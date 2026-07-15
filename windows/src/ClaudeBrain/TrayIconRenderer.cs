using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace ClaudeBrain;

/// <summary>
/// Draws the two-row tray indicator (the Windows analogue of the plasmoid's
/// compactRepresentation / the mac menu-bar pill): a "5h" mini-bar over a "7d"
/// mini-bar, each filled by its % and colored by pctColor (accent, or red past
/// 90%) so it reads on both light and dark taskbars.
///
/// The Windows notification area renders a *square* icon (unlike the
/// variable-width macOS status item / KDE panel), so the numeric %, the
/// "5h"/"7d" labels and the ⟳reset text — which can't fit legibly beside a bar
/// at 16-24px — move to the tooltip and the popup. The two bar lengths are the
/// glanceable signal; hover or click for the exact figures.
/// </summary>
public static class TrayIconRenderer
{
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public readonly record struct Row(double? Pct);

    /// <summary>Build the tray icon at the given square size (px). Caller must
    /// call <see cref="Release"/> on the returned handle once the icon is
    /// swapped out, or the GDI icon handle leaks.</summary>
    public static (Icon icon, IntPtr handle) Render(Row five, Row week, bool hasError, int size)
    {
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Color.Transparent);

            // Two rows split vertically; centers at 1/4 and 3/4 height.
            DrawRow(g, five, hasError, size, centerY: size * 0.27f);
            DrawRow(g, week, hasError, size, centerY: size * 0.73f);
        }

        IntPtr h = bmp.GetHicon();
        // Clone off the handle so the returned Icon owns an independent copy;
        // we still return the handle so the caller can DestroyIcon it.
        return (Icon.FromHandle(h), h);
    }

    public static void Release(IntPtr handle)
    {
        if (handle != IntPtr.Zero) DestroyIcon(handle);
    }

    private static void DrawRow(Graphics g, Row r, bool hasError, int size, float centerY)
    {
        float margin = MathF.Max(1f, size * 0.10f);
        float barW = size - margin * 2f;
        float barH = MathF.Max(3f, size * 0.30f);
        float barX = margin;
        float barY = centerY - barH / 2f;
        float radius = barH / 2f;

        // track
        using (var track = new SolidBrush(Color.FromArgb(hasError ? 60 : 90, 128, 128, 128)))
            FillRounded(g, track, barX, barY, barW, barH, radius);

        // fill
        if (r.Pct is double p)
        {
            float fillW = barW * (float)Math.Clamp(p / 100.0, 0, 1);
            if (fillW > 1)
                using (var fb = new SolidBrush(Fmt.PctColor(r.Pct)))
                    FillRounded(g, fb, barX, barY, fillW, barH, radius);
        }
        else if (hasError)
        {
            // no data: a small centered danger nub so the icon still signals.
            float nub = MathF.Max(2f, barH);
            using var eb = new SolidBrush(Fmt.Hex(Fmt.Danger));
            FillRounded(g, eb, barX + (barW - nub) / 2f, barY, nub, barH, radius);
        }
    }

    private static void FillRounded(Graphics g, Brush b, float x, float y, float w, float h, float r)
    {
        if (w <= 0 || h <= 0) return;
        r = Math.Min(r, Math.Min(w, h) / 2f);
        using var path = new GraphicsPath();
        var d = r * 2f;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + w - d, y, d, d, 270, 90);
        path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        path.AddArc(x, y + h - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(b, path);
    }
}
