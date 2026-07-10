using System.Drawing;

namespace ClaudeQuota;

/// <summary>
/// Diálogo modal minimal para renombrar (proyecto/sesión). Un TextBox precargado + Guardar/Cancelar,
/// espejo del <c>.alert { TextField … }</c> de la vista macOS (PopoverView.swift). Devuelve el texto
/// (posiblemente VACÍO = "restaurar original") o <c>null</c> si se canceló. La semántica de vacío la
/// aplica quien llama vía <see cref="QuotaService.RenameProject"/>/<see cref="QuotaService.RenameSession"/>.
/// </summary>
internal static class RenameDialog
{
    public static string? Show(IWin32Window owner, string title, string prompt, string current)
    {
        using var form = new Form
        {
            Text = title,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterParent,
            MinimizeBox = false,
            MaximizeBox = false,
            ShowInTaskbar = false,
            AutoScaleMode = AutoScaleMode.Dpi,
            ClientSize = new Size(380, 138),
        };

        var lbl = new Label { Left = 14, Top = 14, Width = 352, Height = 44, Text = prompt };
        var box = new TextBox { Left = 14, Top = 62, Width = 352, Text = current };
        var ok = new Button { Text = "Guardar", DialogResult = DialogResult.OK, Width = 84, Height = 28, Left = 198, Top = 98 };
        var cancel = new Button { Text = "Cancelar", DialogResult = DialogResult.Cancel, Width = 84, Height = 28, Left = 288, Top = 98 };

        form.Controls.AddRange(new Control[] { lbl, box, ok, cancel });
        form.AcceptButton = ok;   // Enter → Guardar
        form.CancelButton = cancel;   // Esc → Cancelar
        form.Shown += (_, _) => { box.Focus(); box.SelectAll(); };

        return form.ShowDialog(owner) == DialogResult.OK ? box.Text : null;
    }
}
