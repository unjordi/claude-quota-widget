using System.Drawing;
using System.Drawing.Drawing2D;
using Microsoft.Win32;

namespace ClaudeQuota;

/// <summary>
/// The click-to-open breakdown, a borderless transient form. Mirrors the
/// plasmoid's fullRepresentation and the mac popover: a vertical tab rail on the
/// left (Límites / Resumen / Modelos / Proyectos / Cerebro), a 1px separator, and
/// the tab content on the right. Everything is owner-drawn with GDI+ so it stays a
/// single control tree and honors the FelixDes look (orange accent, red past 90%).
/// </summary>
public sealed class PopupForm : Form
{
    private readonly QuotaService _svc;
    private readonly Action _onRefresh;
    private int _tab;
    private int _hoverRail = -1;

    // Scroll vertical SOLO de la pestaña Cerebro (owner-draw): desplazamiento
    // actual y altura total dibujada en el último paint (para acotar el scroll).
    private int _cerebroScroll;
    private int _cerebroContentH;

    // logical → device scale (PerMonitorV2); all metrics below are in logical px.
    private float S => DeviceDpi / 96f;

    private const int WLogical = 520, HLogical = 420, RailWLogical = 132;

    // theme
    private Color _bg, _fg;
    private readonly Color _accent = Fmt.Hex(Fmt.Accent);

    private readonly Panel _rail = new();
    private readonly Panel _content = new();

    private static readonly string[] TabNames = { "Límites", "Resumen", "Modelos", "Proyectos", "Cerebro" };

    public PopupForm(QuotaService svc, Action onRefresh)
    {
        _svc = svc;
        _onRefresh = onRefresh;

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.Dpi;
        DoubleBuffered = true;
        KeyPreview = true;

        ApplyTheme();

        _rail.Dock = DockStyle.Left;
        _rail.Width = Sc(RailWLogical);
        _rail.BackColor = Blend(_bg, _fg, 0.03);
        _rail.Paint += RailPaint;
        _rail.MouseDown += RailMouseDown;
        _rail.MouseMove += RailMouseMove;
        _rail.MouseLeave += (_, _) => { _hoverRail = -1; _rail.Invalidate(); };

        _content.Dock = DockStyle.Fill;
        _content.BackColor = _bg;
        _content.Paint += ContentPaint;

        // 1px separator between rail and content.
        var sep = new Panel { Dock = DockStyle.Left, Width = 1, BackColor = Blend(_bg, _fg, 0.12) };

        Controls.Add(_content);
        Controls.Add(sep);
        Controls.Add(_rail);

        ClientSize = new Size(Sc(WLogical), Sc(HLogical));

        foreach (Control c in new Control[] { _rail, _content })
            EnableDoubleBuffer(c);
    }

    /// When set (dev `--shot` mode) the popup stays visible so its real paint
    /// path can be captured; normal runtime leaves it false.
    public bool ShotMode;

    // Close when focus leaves (transient popover behavior).
    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        if (!ShotMode) Hide();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape) Hide();
        base.OnKeyDown(e);
    }

    /// <summary>Refresh in-memory data and repaint (called before showing).</summary>
    public void RefreshData()
    {
        ApplyTheme();
        _rail.BackColor = Blend(_bg, _fg, 0.03);
        _content.BackColor = _bg;
        Invalidate(true);
        _rail.Invalidate();
        _content.Invalidate();
    }

    public void SelectTab(int t) { _tab = t; _cerebroScroll = 0; _rail.Invalidate(); _content.Invalidate(); }

    // Rueda del ratón: solo scrollea la pestaña Cerebro (las demás caben en el
    // alto fijo del popup). El form tiene el foco mientras el popover está
    // visible, así que recibe WM_MOUSEWHEEL aquí.
    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        if (_tab != 4) return;
        int max = Math.Max(0, _cerebroContentH - _content.Height);
        if (max <= 0) return;
        int step = (e.Delta / 120) * Sc(48);
        _cerebroScroll = Math.Clamp(_cerebroScroll - step, 0, max);
        _content.Invalidate();
    }

    // ================= Rail =================

    private void RailPaint(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        int pad = Sc(6);
        int btnH = Sc(34);
        using var font = Px(12.5f, FontStyle.Regular);
        using var fontB = Px(12.5f, FontStyle.Bold);

        for (int i = 0; i < TabNames.Length; i++)
        {
            var r = new Rectangle(pad, pad + i * (btnH + Sc(4)), _rail.Width - pad * 2, btnH);
            bool active = _tab == i;
            if (active)
                using (var b = new SolidBrush(Color.FromArgb(46, _accent)))
                    FillRounded(g, b, r, Sc(6));
            else if (_hoverRail == i)
                using (var b = new SolidBrush(Blend(_bg, _fg, 0.08)))
                    FillRounded(g, b, r, Sc(6));

            var col = active ? _accent : _fg;
            using var brush = new SolidBrush(col);
            var sf = new StringFormat { LineAlignment = StringAlignment.Center, Alignment = StringAlignment.Near };
            g.DrawString(TabNames[i], active ? fontB : font, brush,
                new RectangleF(r.X + Sc(10), r.Y, r.Width - Sc(12), r.Height), sf);
        }

        // bottom row: refresh + quit
        using var iconFont = Px(13f, FontStyle.Regular);
        var (refreshR, quitR) = BottomButtons();
        using (var b1 = new SolidBrush(Blend(_bg, _fg, 0.7)))
            g.DrawString("⟳", Px(15f, FontStyle.Regular), b1, refreshR, Center());
        using (var b2 = new SolidBrush(Blend(_bg, _fg, 0.45)))
            g.DrawString("⏻", Px(13f, FontStyle.Regular), b2, quitR, Center());
    }

    private (RectangleF refresh, RectangleF quit) BottomButtons()
    {
        int sz = Sc(30);
        int y = _rail.Height - sz - Sc(6);
        var refresh = new RectangleF(Sc(8), y, sz, sz);
        var quit = new RectangleF(Sc(8) + sz + Sc(6), y, sz, sz);
        return (refresh, quit);
    }

    private void RailMouseDown(object? sender, MouseEventArgs e)
    {
        int pad = Sc(6), btnH = Sc(34);
        for (int i = 0; i < TabNames.Length; i++)
        {
            var r = new Rectangle(pad, pad + i * (btnH + Sc(4)), _rail.Width - pad * 2, btnH);
            if (r.Contains(e.Location)) { SelectTab(i); return; }
        }
        var (refreshR, quitR) = BottomButtons();
        if (refreshR.Contains(e.Location)) { _onRefresh(); return; }
        if (quitR.Contains(e.Location)) { Application.Exit(); }
    }

    private void RailMouseMove(object? sender, MouseEventArgs e)
    {
        int pad = Sc(6), btnH = Sc(34), was = _hoverRail;
        _hoverRail = -1;
        for (int i = 0; i < TabNames.Length; i++)
        {
            var r = new Rectangle(pad, pad + i * (btnH + Sc(4)), _rail.Width - pad * 2, btnH);
            if (r.Contains(e.Location)) { _hoverRail = i; break; }
        }
        if (was != _hoverRail) _rail.Invalidate();
    }

    // ================= Content =================

    private void ContentPaint(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        int pad = Sc(16);
        switch (_tab)
        {
            case 0: PaintLimites(g, pad); break;
            case 1: PaintResumen(g, pad); break;
            case 2: PaintModelos(g, pad); break;
            case 3: PaintProyectos(g, pad); break;
            default:
                // Cerebro: contenido alto y scrolleable → se dibuja bajo un
                // desplazamiento; lo que queda fuera del panel lo recorta el clip.
                var state = g.Save();
                g.TranslateTransform(0, -_cerebroScroll);
                _cerebroContentH = PaintCerebro(g, pad);
                g.Restore(state);
                break;
        }
    }

    // ----- Tab 0: Límites -----

    private void PaintLimites(Graphics g, int pad)
    {
        int y = pad;
        using (var h = Px(15f, FontStyle.Bold))
        using (var b = new SolidBrush(_fg))
            g.DrawString("Límites de uso", h, b, pad, y);
        y += Sc(34);

        y = UsageSection(g, pad, y, "Sesión (5 h)", _svc.Snapshot?.FiveHour);
        y += Sc(14);
        y = UsageSection(g, pad, y, "Semanal (7 d)", _svc.Snapshot?.Weekly);

        // footer at the bottom (red when the pinned account doesn't match)
        bool mismatch = _svc.Snapshot?.AccountMismatch == true;
        using var fFont = Px(10f, mismatch ? FontStyle.Bold : FontStyle.Regular);
        using var fBrush = new SolidBrush(mismatch ? Fmt.Hex(Fmt.Danger) : Blend(_bg, _fg, 0.5));
        var fr = new RectangleF(pad, _content.Height - Sc(24), _content.Width - pad * 2, Sc(20));
        g.DrawString(_svc.FooterText, fFont, fBrush, fr);
    }

    private int UsageSection(Graphics g, int pad, int y, string title, Bucket? bucket)
    {
        int w = _content.Width - pad * 2;
        double? pct = bucket?.Percent;

        using (var tFont = Px(12.5f, FontStyle.Bold))
        using (var tBrush = new SolidBrush(_fg))
            g.DrawString(title, tFont, tBrush, pad, y);

        string pctTxt = pct is double p ? p.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "%" : "—";
        using (var pFont = Px(12.5f, FontStyle.Bold))
        using (var pBrush = new SolidBrush(Fmt.PctColor(pct)))
        {
            var sz = g.MeasureString(pctTxt, pFont);
            g.DrawString(pctTxt, pFont, pBrush, pad + w - sz.Width, y);
        }
        y += Sc(24);

        // progress bar
        int barH = Sc(9);
        using (var track = new SolidBrush(Blend(_bg, _fg, 0.12)))
            FillRounded(g, track, new Rectangle(pad, y, w, barH), barH / 2f);
        if (pct is double pv)
        {
            int fw = (int)(w * Math.Clamp(pv / 100.0, 0, 1));
            if (fw > 1)
                using (var fill = new SolidBrush(Fmt.PctColor(pct)))
                    FillRounded(g, fill, new Rectangle(pad, y, fw, barH), barH / 2f);
        }
        y += barH + Sc(8);

        // caption
        using (var cFont = Px(10f, FontStyle.Regular))
        using (var cBrush = new SolidBrush(Blend(_bg, _fg, 0.65)))
            g.DrawString(Caption(bucket), cFont, cBrush, pad, y);
        return y + Sc(20);
    }

    private static string Caption(Bucket? bucket)
    {
        if (bucket == null) return "";
        string s = $"Se restablece {Rel.Relative(bucket.ResetsAt)}";
        if (bucket.CostUsd is double c)
            s += $" · ≈ ${c.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)} (API equiv local)";
        return s;
    }

    // ----- Tab 1: Resumen -----

    private void PaintResumen(Graphics g, int pad)
    {
        var s = _svc.Stats?.Summary;
        var streaks = StatsCompute.Streaks(_svc.Stats);
        int y = pad;
        using (var h = Px(15f, FontStyle.Bold))
        using (var b = new SolidBrush(_fg))
            g.DrawString("Resumen", h, b, pad, y);
        y += Sc(32);

        (string, string)[] cards =
        {
            ("Sesiones",        s != null ? Fmt.Int(s.Sessions) : "—"),
            ("Mensajes",        s != null ? Fmt.Int(s.Messages) : "—"),
            ("Tokens totales",  s != null ? Fmt.Tok(s.TotalTokens) : "—"),
            ("Días activos",    s != null ? s.ActiveDays.ToString() : "—"),
            ("Racha actual",    $"{streaks.cur}d"),
            ("Racha más larga", $"{streaks.max}d"),
            ("Hora pico",       s != null ? Fmt.Hour(s.PeakHour) : "—"),
            ("Modelo favorito", s != null ? Fmt.PrettyModel(s.FavoriteModel) : "—"),
            ("Costo API-equiv", s?.TotalCost is double tc ? "$" + ((long)Math.Round(tc)) : "—"),
        };

        int cols = 3, gapc = Sc(6);
        int cardW = (_content.Width - pad * 2 - gapc * (cols - 1)) / cols;
        int cardH = Sc(50);
        for (int i = 0; i < cards.Length; i++)
        {
            int cx = pad + (i % cols) * (cardW + gapc);
            int cy = y + (i / cols) * (cardH + gapc);
            StatCard(g, new Rectangle(cx, cy, cardW, cardH), cards[i].Item1, cards[i].Item2);
        }
        y += 3 * (cardH + gapc) + Sc(6);

        using (var cFont = Px(10f, FontStyle.Regular))
        using (var cBrush = new SolidBrush(Blend(_bg, _fg, 0.6)))
            g.DrawString("Actividad diaria (local)", cFont, cBrush, pad, y);
        y += Sc(18);

        Heatmap(g, pad, y);
    }

    private void StatCard(Graphics g, Rectangle r, string label, string value)
    {
        using (var bg = new SolidBrush(Blend(_bg, _fg, 0.06)))
            FillRounded(g, bg, r, Sc(6));
        int ipad = Sc(8);
        using (var lFont = Px(9f, FontStyle.Regular))
        using (var lBrush = new SolidBrush(Blend(_bg, _fg, 0.6)))
            g.DrawString(label, lFont, lBrush, r.X + ipad, r.Y + Sc(6));
        using (var vFont = Px(13.5f, FontStyle.Bold))
        using (var vBrush = new SolidBrush(_fg))
        {
            var sf = new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
            g.DrawString(value, vFont, vBrush,
                new RectangleF(r.X + ipad, r.Y + Sc(24), r.Width - ipad * 2, Sc(20)), sf);
        }
    }

    private void Heatmap(Graphics g, int pad, int y)
    {
        var cells = StatsCompute.HeatmapCells(_svc.Stats);
        if (cells.Count == 0) return;
        double maxTok = StatsCompute.MaxDayTokens(_svc.Stats);
        int cell = Sc(12), gap = Sc(3);
        var empty = Blend(_bg, _fg, 0.08);
        for (int i = 0; i < cells.Count; i++)
        {
            int col = i / 7, row = i % 7;
            int x = pad + col * (cell + gap);
            int cy = y + row * (cell + gap);
            if (x + cell > _content.Width - pad) break; // clip overflow columns
            Color c;
            if (cells[i] <= 0) c = empty;
            else
            {
                double a = 0.25 + 0.75 * Math.Min(1, cells[i] / maxTok);
                c = Color.FromArgb((int)(a * 255), _accent);
            }
            using var b = new SolidBrush(c);
            FillRounded(g, b, new Rectangle(x, cy, cell, cell), Sc(3));
        }
    }

    // ----- Tab 2: Modelos -----

    private void PaintModelos(Graphics g, int pad)
    {
        int y = pad;
        using (var h = Px(15f, FontStyle.Bold))
        using (var b = new SolidBrush(_fg))
            g.DrawString("Uso por modelo", h, b, pad, y);
        y += Sc(32);

        int chartH = Sc(110);
        StackedChart(g, new Rectangle(pad, y, _content.Width - pad * 2, chartH));
        y += chartH + Sc(12);

        var models = _svc.Stats?.Models ?? new List<StatsModel>();
        using var nameFont = Px(11.5f, FontStyle.Bold);
        using var subFont = Px(10.5f, FontStyle.Regular);
        int rowH = Sc(22);
        foreach (var m in models)
        {
            if (y + rowH > _content.Height - pad) break;
            var col = StatsCompute.ModelColor(_svc.Stats, m.Model);
            using (var sw = new SolidBrush(col))
                FillRounded(g, sw, new Rectangle(pad, y + Sc(4), Sc(10), Sc(10)), Sc(2));
            using (var nb = new SolidBrush(_fg))
                g.DrawString(Fmt.PrettyModel(m.Model), nameFont, nb, pad + Sc(16), y);

            string sub = $"{Fmt.Tok(m.InTok)} in · {Fmt.Tok(m.OutTok)} out";
            string pctT = m.Pct.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "%";
            using (var pb = new SolidBrush(col))
            {
                var pf = new StringFormat { Alignment = StringAlignment.Far };
                g.DrawString(pctT, nameFont, pb,
                    new RectangleF(pad, y, _content.Width - pad * 2, rowH), pf);
            }
            using (var sb = new SolidBrush(Blend(_bg, _fg, 0.7)))
            {
                var sf = new StringFormat { Alignment = StringAlignment.Far };
                g.DrawString(sub, subFont, sb,
                    new RectangleF(pad, y, _content.Width - pad * 2 - Sc(52), rowH), sf);
            }
            y += rowH;
        }
    }

    private void StackedChart(Graphics g, Rectangle area)
    {
        var days = _svc.Stats?.Days ?? new List<StatsDay>();
        if (days.Count == 0) return;
        double maxTok = StatsCompute.MaxDayTokens(_svc.Stats);
        int gap = Sc(2);
        float barW = Math.Max(1f, (area.Width - gap * (days.Count - 1f)) / days.Count);
        for (int i = 0; i < days.Count; i++)
        {
            float x = area.X + i * (barW + gap);
            float yTop = area.Bottom;
            foreach (var seg in days[i].Models ?? new List<DayModel>())
            {
                float h = (float)(area.Height * (seg.Tokens / maxTok));
                if (h <= 0) continue;
                yTop -= h;
                using var b = new SolidBrush(StatsCompute.ModelColor(_svc.Stats, seg.Model));
                g.FillRectangle(b, x, yTop, barW, h);
            }
        }
    }

    // ----- Tab 3: Proyectos -----

    private void PaintProyectos(Graphics g, int pad)
    {
        int y = pad;
        using (var h = Px(15f, FontStyle.Bold))
        using (var b = new SolidBrush(_fg))
            g.DrawString("Uso por proyecto", h, b, pad, y);
        y += Sc(32);

        int chartH = Sc(110);
        StackedProjectChart(g, new Rectangle(pad, y, _content.Width - pad * 2, chartH));
        y += chartH + Sc(12);

        var projects = _svc.Stats?.Projects ?? new List<StatsProject>();
        using var nameFont = Px(11.5f, FontStyle.Bold);
        using var subFont = Px(10.5f, FontStyle.Regular);
        int rowH = Sc(22);
        foreach (var p in projects)
        {
            if (y + rowH > _content.Height - pad) break;
            var col = StatsCompute.ProjectColor(_svc.Stats, p.Project);
            using (var sw = new SolidBrush(col))
                FillRounded(g, sw, new Rectangle(pad, y + Sc(4), Sc(10), Sc(10)), Sc(2));
            using (var nb = new SolidBrush(_fg))
            {
                var nf = new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
                g.DrawString(p.Project ?? "—", nameFont, nb,
                    new RectangleF(pad + Sc(16), y, _content.Width - pad * 2 - Sc(180), rowH), nf);
            }

            string sub = $"{Fmt.Tok(p.InTok)} in · {Fmt.Tok(p.OutTok)} out";
            string pctT = p.Pct.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "%";
            using (var pb = new SolidBrush(col))
            {
                var pf = new StringFormat { Alignment = StringAlignment.Far };
                g.DrawString(pctT, nameFont, pb,
                    new RectangleF(pad, y, _content.Width - pad * 2, rowH), pf);
            }
            using (var sb = new SolidBrush(Blend(_bg, _fg, 0.7)))
            {
                var sf = new StringFormat { Alignment = StringAlignment.Far };
                g.DrawString(sub, subFont, sb,
                    new RectangleF(pad, y, _content.Width - pad * 2 - Sc(52), rowH), sf);
            }
            y += rowH;
        }
    }

    private void StackedProjectChart(Graphics g, Rectangle area)
    {
        var days = _svc.Stats?.Days ?? new List<StatsDay>();
        if (days.Count == 0) return;
        double maxTok = StatsCompute.MaxDayTokens(_svc.Stats);
        int gap = Sc(2);
        float barW = Math.Max(1f, (area.Width - gap * (days.Count - 1f)) / days.Count);
        for (int i = 0; i < days.Count; i++)
        {
            float x = area.X + i * (barW + gap);
            float yTop = area.Bottom;
            foreach (var seg in days[i].Projects ?? new List<DayProject>())
            {
                float h = (float)(area.Height * (seg.Tokens / maxTok));
                if (h <= 0) continue;
                yTop -= h;
                using var b = new SolidBrush(StatsCompute.ProjectColor(_svc.Stats, seg.Project));
                g.FillRectangle(b, x, yTop, barW, h);
            }
        }
    }

    // ----- Tab 4: Cerebro -----
    //
    // Infografía del cerebro global de Claude Code, réplica de la pestaña macOS
    // (PopoverView.swift, `cerebroTab`). Contenido 100% ESTÁTICO: refleja `brain/`
    // (hooks / norms / skills) y se mantiene a mano cuando cambian las piezas; no
    // depende de datos en vivo. Jerarquía de más DURO (arriba) a más LEVE (abajo).
    // Devuelve la altura total dibujada, que ContentPaint usa para acotar el scroll.
    private int PaintCerebro(Graphics g, int pad)
    {
        int right = _content.Width - pad;      // borde derecho útil del contenido
        int y = pad;

        // Encabezado de marca: destello acento + 🧠 Cerebro global.
        using (var spFont = Px(12f, FontStyle.Bold))
        using (var spBrush = new SolidBrush(_accent))
            g.DrawString("✦", spFont, spBrush, pad, y + Sc(1));
        int hx = pad + Sc(16);
        using (var emj = PxFont("Segoe UI Emoji", 13f, FontStyle.Regular))
        using (var b = new SolidBrush(_fg))
            g.DrawString("🧠", emj, b, hx, y);
        hx += Sc(22);
        using (var h = Px(13.5f, FontStyle.Bold))
        using (var b = new SolidBrush(_fg))
            g.DrawString("Cerebro global", h, b, hx, y + Sc(1));
        y += Sc(24);

        // Subtítulo tenue (envuelve a varias líneas).
        const string subtitle =
            "Guardarraíles + gobernanza + normas de Claude Code. Viaja por git, " +
            "aplica en toda máquina. De más duro (arriba) a más leve (abajo).";
        using (var sf = Px(9.5f, FontStyle.Regular))
        using (var b = new SolidBrush(Blend(_bg, _fg, 0.6)))
        {
            var sz = g.MeasureString(subtitle, sf, right - pad);
            g.DrawString(subtitle, sf, b, new RectangleF(pad, y, right - pad, sz.Height + Sc(2)));
            y += (int)Math.Ceiling(sz.Height) + Sc(10);
        }

        foreach (var tier in BrainTiers)
            y = PaintTier(g, pad, right, y, tier);

        // Pie tenue.
        const string footer =
            "Instalado por install-brain.sh · probado por test-brain.sh · sin jq " +
            "los hooks fallan ABIERTO (no bloquean).";
        using (var ff = Px(9.5f, FontStyle.Regular))
        using (var b = new SolidBrush(Blend(_bg, _fg, 0.45)))
        {
            var sz = g.MeasureString(footer, ff, right - pad);
            g.DrawString(footer, ff, b, new RectangleF(pad, y + Sc(2), right - pad, sz.Height + Sc(2)));
            y += (int)Math.Ceiling(sz.Height) + Sc(4);
        }
        return y + pad;
    }

    /// Un nivel del cerebro: espina de color a la izquierda + encabezado
    /// (emoji + TÍTULO en el color del nivel + subtítulo tenue) + hojas con
    /// conectores de árbol monoespaciados. Devuelve la nueva `y`.
    private int PaintTier(Graphics g, int pad, int right, int y, BrainTier tier)
    {
        int spineW = Sc(3), spineGap = Sc(10);
        int tx = pad + spineW + spineGap;   // x del texto del nivel
        int top = y;

        // Encabezado del nivel.
        using (var emj = PxFont("Segoe UI Emoji", 12.5f, FontStyle.Regular))
        using (var b = new SolidBrush(_fg))
            g.DrawString(tier.Emoji, emj, b, tx, y);
        using (var tf = Px(12f, FontStyle.Bold))
        using (var tb = new SolidBrush(tier.Color))
            g.DrawString(tier.Title, tf, tb, tx + Sc(22), y + Sc(1));
        y += Sc(20);

        using (var subF = Px(9.5f, FontStyle.Regular))
        using (var subB = new SolidBrush(Blend(_bg, _fg, 0.6)))
        {
            var sz = g.MeasureString(tier.Subtitle, subF, right - tx);
            g.DrawString(tier.Subtitle, subF, subB, new RectangleF(tx, y, right - tx, sz.Height + Sc(2)));
            y += (int)Math.Ceiling(sz.Height) + Sc(5);
        }

        // Hojas: conector ├─ salvo la última, que lleva └─.
        for (int i = 0; i < tier.Items.Length; i++)
            y = PaintLeaf(g, tx, right, y, tier.Items[i], i == tier.Items.Length - 1, tier.Color);

        // Espina de color: se dibuja al final, cuando ya se conoce el alto del nivel.
        int bottom = y - Sc(3);
        using (var sp = new SolidBrush(tier.Color))
            FillRounded(g, sp, new Rectangle(pad, top, spineW, Math.Max(spineW, bottom - top)), spineW / 2f);

        return y + Sc(12); // separación entre niveles
    }

    /// Una hoja del árbol: conector monoespaciado (color del nivel, tenue) +
    /// emoji + nombre en mono; la descripción tenue envuelve debajo del nombre.
    private int PaintLeaf(Graphics g, int tx, int right, int y, BrainItem item, bool last, Color color)
    {
        using (var cf = PxFont("Consolas", 10.5f, FontStyle.Regular))
        using (var cb = new SolidBrush(Blend(_bg, color, 0.55)))
            g.DrawString(last ? "└─" : "├─", cf, cb, tx, y);

        int ex = tx + Sc(20);               // tras el conector: emoji
        using (var emj = PxFont("Segoe UI Emoji", 10f, FontStyle.Regular))
        using (var b = new SolidBrush(_fg))
            g.DrawString(item.Emoji, emj, b, ex, y);

        int nx = ex + Sc(18);               // tras el emoji: nombre (mono)
        using (var nf = PxFont("Consolas", 10.5f, FontStyle.Bold))
        using (var nb = new SolidBrush(_fg))
            g.DrawString(item.Name, nf, nb, nx, y);

        // Descripción tenue, envuelta bajo el nombre.
        using var df = Px(9f, FontStyle.Regular);
        using var db = new SolidBrush(Blend(_bg, _fg, 0.62));
        int descY = y + Sc(15);
        var descSz = g.MeasureString(item.Desc, df, right - nx);
        g.DrawString(item.Desc, df, db, new RectangleF(nx, descY, right - nx, descSz.Height + Sc(2)));
        return descY + (int)Math.Ceiling(descSz.Height) + Sc(6);
    }

    /// Datos ESTÁTICOS del cerebro (reflejan `brain/hooks`, `brain/norms`,
    /// `brain/skills`). Espejo 1:1 del array `brainTiers` de la GUI macOS.
    private BrainTier[] BrainTiers =>
    [
        new("🔒", "INVIOLABLE", Fmt.Hex("#dc3545"), "hooks que BLOQUEAN (deny) — no negociables",
        [
            new("🚧", "git-branch-guard", "push/merge a develop·main → denegado, te redirige a ramita→MR"),
            new("🔗", "merge-squash-guard", "MR a develop sin --squash → denegado (1 commit limpio)"),
            new("✋", "confirmar-merge-develop", "merge a develop sin tu OK → denegado; a main exige OK súper-explícito"),
            new("✅", "dod-verificar", "declarar “listo” sin build+tests+memoria → denegado"),
            new("💸", "delegacion-gate", "reclutar agente con costo → pide tu consentimiento (puede negar)"),
        ]),
        new("🔔", "AUTOMÁTICO", _accent, "hooks que inyectan / recuerdan — no bloquean",
        [
            new("🧭", "sesion-inicio", "al abrir/retomar reinyecta rama + norma de git + orden de leer memoria"),
            new("💾", "precompact-volcar-estado", "antes de compactar, vuelca avance/decisiones/pendientes a memoria"),
            new("📊", "recordar-dashboard", "antes de un push, recuerda actualizar el dashboard del cerebro"),
            new("📝", "delegacion-registrar", "registra el consentimiento (materializa el “pregunta 1×”)"),
        ]),
        new("📜", "NORMAS", Fmt.Hex("#4a90d9"), "reglas que Claude se autoimpone (CLAUDE.md)",
        [
            new("🎯", "Definición de LISTO", "verde técnico ≠ listo; exige tu QA o tu OK expreso"),
            new("🪞", "Doc = realidad", "cambió algo → actualiza su doc en la misma tanda, sin preguntar"),
            new("🌿", "Flujo de git", "ramita → MR → develop (squash); main es release-only"),
            new("💰", "Costo de delegación", "gratis / incluido / con costo — window-aware, lee tu cuota"),
        ]),
        new("💡", "SKILLS", Fmt.Hex("#3aa76d"), "herramientas opt-in — las invocas tú",
        [
            new("📦", "cerrar-slice", "build+tests+memoria al día + MR con resumen curado por slice"),
        ]),
    ];

    /// Un nivel del cerebro (tier) con sus hojas — datos estáticos de la pestaña.
    private sealed record BrainTier(string Emoji, string Title, Color Color, string Subtitle, BrainItem[] Items);

    /// Una hoja del árbol del cerebro (un hook / norma / skill).
    private sealed record BrainItem(string Emoji, string Name, string Desc);

    // ================= helpers =================

    private int Sc(float logical) => (int)Math.Round(logical * S);
    private Font Px(float logicalPt, FontStyle style) =>
        new("Segoe UI", logicalPt * S, style, GraphicsUnit.Pixel);
    // Como Px pero con una familia explícita (Consolas para mono/conectores,
    // Segoe UI Emoji para que los emojis rendericen a color en GDI+).
    private Font PxFont(string family, float logicalPt, FontStyle style) =>
        new(family, logicalPt * S, style, GraphicsUnit.Pixel);
    private static StringFormat Center() =>
        new() { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };

    private void ApplyTheme()
    {
        bool light = IsLightTheme();
        _bg = light ? Color.FromArgb(0xFA, 0xFA, 0xFA) : Color.FromArgb(0x22, 0x22, 0x22);
        _fg = light ? Color.FromArgb(0x1A, 0x1A, 0x1A) : Color.FromArgb(0xE6, 0xE6, 0xE6);
        BackColor = _bg;
    }

    private static bool IsLightTheme()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (k?.GetValue("AppsUseLightTheme") is int v) return v != 0;
        }
        catch { }
        return false; // default dark
    }

    /// Blend `over` onto `baseC` at the given alpha (0..1); GDI+ alpha over an
    /// opaque surface, matching SwiftUI's Color.opacity() usage.
    private static Color Blend(Color baseC, Color over, double a)
    {
        a = Math.Clamp(a, 0, 1);
        return Color.FromArgb(
            (int)(baseC.R + (over.R - baseC.R) * a),
            (int)(baseC.G + (over.G - baseC.G) * a),
            (int)(baseC.B + (over.B - baseC.B) * a));
    }

    private static void FillRounded(Graphics g, Brush b, Rectangle r, float radius) =>
        FillRounded(g, b, new RectangleF(r.X, r.Y, r.Width, r.Height), radius);

    private static void FillRounded(Graphics g, Brush b, RectangleF r, float radius)
    {
        if (r.Width <= 0 || r.Height <= 0) return;
        float rad = Math.Min(radius, Math.Min(r.Width, r.Height) / 2f);
        using var path = new GraphicsPath();
        float d = rad * 2f;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(b, path);
    }

    private static void EnableDoubleBuffer(Control c)
    {
        typeof(Control).GetProperty("DoubleBuffered",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(c, true, null);
    }
}
