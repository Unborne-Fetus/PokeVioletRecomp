# Compact Windows startup chooser. This does not read or change game files or saves.
# Exit codes: 0 = play immediately, 2 = open native Controls editor, 3 = quit.
[CmdletBinding()]
param([switch]$ListChoices)
$ErrorActionPreference = 'Stop'

if ($ListChoices) {
    Write-Output 'play=0'
    Write-Output 'controls=2'
    Write-Output 'quit=3'
    exit 0
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Tag = 3  # Closing the window or pressing Escape cancels.
    $form.Text = 'Pokemon Violet - Start'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize = New-Object System.Drawing.Size(490, 250)
    $form.BackColor = [System.Drawing.Color]::FromArgb(16, 25, 43)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(236, 243, 250)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'POKEMON VIOLET'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 21, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(243, 225, 255)
    $title.AutoSize = $false
    $title.Location = New-Object System.Drawing.Point(28, 21)
    $title.Size = New-Object System.Drawing.Size(430, 44)
    $form.Controls.Add($title)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = 'Play now, or configure your keyboard and controller first.'
    $desc.ForeColor = [System.Drawing.Color]::FromArgb(178, 199, 218)
    $desc.AutoSize = $false
    $desc.Location = New-Object System.Drawing.Point(30, 72)
    $desc.Size = New-Object System.Drawing.Size(438, 46)
    $form.Controls.Add($desc)

    function New-LauncherButton([string]$text, [int]$x, [int]$y, [int]$width, [int]$code, [bool]$primary) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $text
        $button.Location = New-Object System.Drawing.Point($x, $y)
        $button.Size = New-Object System.Drawing.Size($width, 46)
        $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderSize = 0
        $button.UseVisualStyleBackColor = $false
        $button.BackColor = if ($primary) {
            [System.Drawing.Color]::FromArgb(114, 83, 198)
        } else {
            [System.Drawing.Color]::FromArgb(43, 61, 83)
        }
        $button.ForeColor = [System.Drawing.Color]::White
        $button.Add_Click({
            $form.Tag = $code
            $form.Close()
        }.GetNewClosure())
        $form.Controls.Add($button)
        return $button
    }

    $play = New-LauncherButton 'PLAY VIOLET' 30 129 206 0 $true
    $controls = New-LauncherButton 'CHANGE KEYBINDS' 250 129 209 2 $false
    $quit = New-LauncherButton 'Quit' 349 192 110 3 $false

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Bindings are saved by the game. You can also open Controls with F1.'
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(140, 170, 192)
    $hint.AutoSize = $false
    $hint.Location = New-Object System.Drawing.Point(30, 193)
    $hint.Size = New-Object System.Drawing.Size(309, 48)
    $form.Controls.Add($hint)

    $form.AcceptButton = $play
    $form.CancelButton = $quit
    $form.Add_Shown({ $play.Focus() })
    [void]$form.ShowDialog()
    $chosen = [int]$form.Tag
    $form.Dispose()
    exit $chosen
} catch {
    Write-Error ("Unable to open the Violet startup menu: " + $_.Exception.Message)
    exit 1
}
