using System.Drawing;
using System.Globalization;

namespace ClaudeBrain;

/// <summary>
/// Pure derivations over stats.json used by the Resumen / Modelos tabs.
/// Ports streaks{}, heatmapCells(), maxDayTokens and modelColor() from
/// QuotaModel.swift / main.qml so all three surfaces agree.
/// </summary>
public static class StatsCompute
{
    public static Color ModelColor(Stats? stats, string? name)
    {
        var models = stats?.Models;
        if (models == null || name == null) return Fmt.Hex(Fmt.ModelPalette[0]);
        for (int i = 0; i < models.Count; i++)
            if (models[i].Model == name)
                return Fmt.Hex(Fmt.ModelPalette[i % Fmt.ModelPalette.Length]);
        return Fmt.Hex(Fmt.ModelPalette[0]);
    }

    public static Color ProjectColor(Stats? stats, string? name)
    {
        var projects = stats?.Projects;
        if (projects == null || name == null) return Fmt.Hex(Fmt.ModelPalette[0]);
        for (int i = 0; i < projects.Count; i++)
            if (projects[i].Project == name)
                return Fmt.Hex(Fmt.ModelPalette[i % Fmt.ModelPalette.Length]);
        return Fmt.Hex(Fmt.ModelPalette[0]);
    }

    public static double MaxDayTokens(Stats? stats)
    {
        var days = stats?.Days;
        if (days == null || days.Count == 0) return 1;
        return Math.Max(1, days.Max(d => d.Tokens));
    }

    // Máximo de la SUMA de proyectos por día — normaliza la gráfica de Proyectos con su propio eje.
    // Los tokens por-modelo (con caché) y por-proyecto (in+out crudos) difieren, así que un día puede
    // sumar más en proyectos que MaxDayTokens y la barra se saldría del viewport si se usa ese.
    public static double MaxDayProjectTokens(Stats? stats)
    {
        var days = stats?.Days;
        if (days == null || days.Count == 0) return 1;
        return Math.Max(1, days.Max(d => (d.Projects ?? new List<DayProject>()).Sum(p => p.Tokens)));
    }

    /// rachas (días consecutivos con uso).
    public static (int cur, int max) Streaks(Stats? stats)
    {
        var days = stats?.Days;
        if (days == null || days.Count == 0) return (0, 0);

        var active = new HashSet<string>();
        foreach (var d in days)
            if (d.Date != null && d.Tokens > 0) active.Add(d.Date);
        if (active.Count == 0) return (0, 0);

        var dates = active.Select(ParseDay).Where(d => d != null)
            .Select(d => d!.Value).OrderBy(d => d).ToList();

        int longest = 0, run = 0;
        DateTime? prev = null;
        foreach (var t in dates)
        {
            if (prev is DateTime p && (t - p).Days == 1) run++;
            else run = 1;
            longest = Math.Max(longest, run);
            prev = t;
        }

        int cur = 0;
        var day = DateTime.UtcNow.Date;
        if (!active.Contains(Key(day))) day = day.AddDays(-1);
        while (active.Contains(Key(day))) { cur++; day = day.AddDays(-1); }

        return (cur, longest);
    }

    /// GitHub-style heatmap: continuous range from the first day with data,
    /// week-aligned starting on the Sunday of that first week. Column-major
    /// (7 rows). Returns per-cell token counts.
    public static List<double> HeatmapCells(Stats? stats)
    {
        var days = stats?.Days;
        if (days == null || days.Count == 0) return new();

        var m = new Dictionary<string, double>();
        DateTime? minD = null, maxD = null;
        foreach (var d in days)
        {
            if (d.Date == null || ParseDay(d.Date) is not DateTime dt) continue;
            m[d.Date] = d.Tokens;
            if (minD == null || dt < minD) minD = dt;
            if (maxD == null || dt > maxD) maxD = dt;
        }
        if (minD is not DateTime min || maxD is not DateTime max) return new();

        // retroceder al domingo de la semana del primer día (Sunday = 0)
        int weekday = (int)min.DayOfWeek; // Sunday=0
        var cur = min.AddDays(-weekday);
        var cells = new List<double>();
        while (cur <= max)
        {
            cells.Add(m.GetValueOrDefault(Key(cur)));
            cur = cur.AddDays(1);
        }
        return cells;
    }

    private static string Key(DateTime d) => d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static DateTime? ParseDay(string s) =>
        DateTime.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var d) ? d : null;

    // ---- Filtro de rango {hoy·7d·30d·∞} (espeja rangedDays/rangedModels/rangedProjects de macOS) ----
    // range: 0=hoy (0 días atrás), 1=7d (6 atrás), 2=30d (29 atrás), 3=∞ (sin recorte).

    /// Días hacia atrás (incluyente) del rango; null para ∞.
    private static int? DaysBack(int range) => range switch { 0 => 0, 1 => 6, 2 => 29, _ => (int?)null };

    /// Fecha de corte "yyyy-MM-dd" (hora local) del rango; null si ∞.
    public static string? RangeCutoff(int range) =>
        DaysBack(range) is int back
            ? DateTime.Now.Date.AddDays(-back).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
            : null;

    /// Días de stats.days[] dentro del rango (todos si ∞). Compara por prefijo de fecha (orden lexicográfico).
    public static List<StatsDay> RangedDays(Stats? stats, int range)
    {
        var all = stats?.Days ?? new List<StatsDay>();
        var cut = RangeCutoff(range);
        if (cut == null) return all;
        return all.Where(d => string.CompareOrdinal(d.Date ?? "", cut) >= 0).ToList();
    }

    /// Máximo de tokens totales por día dentro del rango (para reescalar la gráfica de Modelos).
    public static double MaxDayTokens(List<StatsDay> days) =>
        days.Count == 0 ? 1 : Math.Max(1, days.Max(d => d.Tokens));

    /// Máximo de la SUMA de proyectos por día dentro del rango (eje propio de la gráfica de Proyectos).
    public static double MaxDayProjectTokens(List<StatsDay> days) =>
        days.Count == 0 ? 1 : Math.Max(1, days.Max(d => (d.Projects ?? new List<DayProject>()).Sum(p => p.Tokens)));

    /// Fila de uso agregada (modelo o proyecto) recalculada por rango: nombre + in/out/total/%.
    public sealed record UsageRow(string Name, double InTok, double OutTok, double Tot, double Pct);

    /// Uso por modelo agregado sobre los días del rango (sumando in/out por día-modelo).
    public static List<UsageRow> RangedModels(List<StatsDay> days)
    {
        var acc = new Dictionary<string, (double inTok, double outTok)>();
        foreach (var d in days)
            foreach (var m in d.Models ?? new List<DayModel>())
            {
                string k = m.Model ?? "?";
                var v = acc.GetValueOrDefault(k);
                acc[k] = (v.inTok + m.InTok, v.outTok + m.OutTok);
            }
        return UsageRows(acc);
    }

    /// Uso por proyecto agregado sobre los días del rango.
    public static List<UsageRow> RangedProjects(List<StatsDay> days)
    {
        var acc = new Dictionary<string, (double inTok, double outTok)>();
        foreach (var d in days)
            foreach (var p in d.Projects ?? new List<DayProject>())
            {
                string k = p.Project ?? "?";
                var v = acc.GetValueOrDefault(k);
                acc[k] = (v.inTok + p.InTok, v.outTok + p.OutTok);
            }
        return UsageRows(acc);
    }

    private static List<UsageRow> UsageRows(Dictionary<string, (double inTok, double outTok)> acc)
    {
        double grand = acc.Values.Sum(v => v.inTok + v.outTok);
        return acc.Select(kv =>
            {
                double tot = kv.Value.inTok + kv.Value.outTok;
                return new UsageRow(kv.Key, kv.Value.inTok, kv.Value.outTok, tot,
                    grand > 0 ? tot * 100 / grand : 0);
            })
            .OrderByDescending(r => r.Tot).ToList();
    }
}
