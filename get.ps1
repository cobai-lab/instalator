# ============================================================
#  get.ps1 - Instalator de aplicatii, direct in PowerShell
#  Fara Python, fara fisiere descarcate: se incarca in memorie.
#
#  Comanda (pe orice PC Windows 10/11, in PowerShell):
#
#     irm https://raw.githubusercontent.com/cobai-lab/instalator/main/get.ps1 | iex
#
#  Taste:  Sus/Jos navigare | Stanga/Dreapta categorie | Spatiu bifeaza
#          / cauta | A toate | N niciuna | T tema | S salveaza
#          Enter instaleaza | Q iesire
#
#  Ca sa adaugi o aplicatie: pune o linie noua in lista $apps de mai jos.
#  ID-ul il gasesti cu:  winget search numele
# ============================================================

& {
    $Repo   = 'cobai-lab/instalator'   # de aici se citeste profil.json (optional)
    $Branch = 'main'

    $ESC = [char]27
    $CSI = "$ESC["

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'winget nu este instalat. Instaleaza "App Installer" din Microsoft Store si ruleaza din nou.' -ForegroundColor Red
        return
    }

    # --- terminal: UTF-8 + culori ANSI (Windows Terminal le are deja) ---
    $oldEnc = $null
    try { $oldEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    if (-not $env:WT_SESSION) {
        try {
            if (-not ('Win32.ConVT' -as [type])) {
                Add-Type -Namespace Win32 -Name ConVT -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);
'@
            }
            $hnd = [Win32.ConVT]::GetStdHandle(-11)
            $mode = 0
            [void][Win32.ConVT]::GetConsoleMode($hnd, [ref]$mode)
            [void][Win32.ConVT]::SetConsoleMode($hnd, ($mode -bor 4))
        } catch { }
    }

    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    # --------------------------------------------------------
    #  Ajutoare
    # --------------------------------------------------------
    function U([int]$cp) { [char]::ConvertFromUtf32($cp) }
    function Fg($c) { "${CSI}38;2;$($c[0]);$($c[1]);$($c[2])m" }
    function Bg($c) { "${CSI}48;2;$($c[0]);$($c[1]);$($c[2])m" }
    function At([int]$r, [int]$c) { "${CSI}${r};${c}H" }
    function Spaces([int]$n) { if ($n -gt 0) { ' ' * $n } else { '' } }
    function Fit([string]$s, [int]$n) {
        if ($n -le 0) { return '' }
        if ($s.Length -gt $n) { return $s.Substring(0, $n) }
        return $s.PadRight($n)
    }

    # --------------------------------------------------------
    #  Teme (culori RGB)
    # --------------------------------------------------------
    $themeOrder = @('wallpaper', 'nebula', 'dracula', 'nord', 'gruvbox', 'light')
    $themes = @{
        wallpaper = @{ label = 'Wallpaper'; bg = @(27, 28, 27);   panel = @(35, 35, 36);   fg = @(218, 212, 196); dim = @(140, 134, 125); primary = @(107, 127, 140); hlfg = @(18, 20, 20);    accent = @(201, 139, 120); ok = @(143, 174, 126); warn = @(217, 179, 108); err = @(200, 100, 90) }
        nebula    = @{ label = 'Nebula';    bg = @(11, 13, 23);   panel = @(17, 20, 42);   fg = @(209, 213, 219); dim = @(107, 114, 128); primary = @(109, 40, 217);  hlfg = @(255, 255, 255); accent = @(34, 211, 238);  ok = @(34, 197, 94);   warn = @(250, 204, 21);  err = @(239, 68, 68) }
        dracula   = @{ label = 'Dracula';   bg = @(40, 42, 54);   panel = @(33, 34, 44);   fg = @(248, 248, 242); dim = @(98, 114, 164);  primary = @(189, 147, 249); hlfg = @(40, 42, 54);    accent = @(255, 121, 198); ok = @(80, 250, 123);  warn = @(241, 250, 140); err = @(255, 85, 85) }
        nord      = @{ label = 'Nord';      bg = @(46, 52, 64);   panel = @(59, 66, 82);   fg = @(216, 222, 233); dim = @(129, 140, 160); primary = @(136, 192, 208); hlfg = @(46, 52, 64);    accent = @(235, 203, 139); ok = @(163, 190, 140); warn = @(235, 203, 139); err = @(191, 97, 106) }
        gruvbox   = @{ label = 'Gruvbox';   bg = @(40, 40, 40);   panel = @(50, 48, 47);   fg = @(235, 219, 178); dim = @(146, 131, 116); primary = @(250, 189, 47);  hlfg = @(40, 40, 40);    accent = @(254, 128, 25);  ok = @(184, 187, 38);  warn = @(250, 189, 47);  err = @(251, 73, 52) }
        light     = @{ label = 'Light';     bg = @(250, 248, 244); panel = @(236, 232, 224); fg = @(50, 50, 50);    dim = @(130, 130, 130); primary = @(60, 100, 160);  hlfg = @(255, 255, 255); accent = @(190, 80, 60);   ok = @(40, 140, 70);   warn = @(180, 120, 20);  err = @(190, 40, 40) }
    }

    # --------------------------------------------------------
    #  Aplicatii
    # --------------------------------------------------------
    function New-App($cat, $cp, $name, $id, $desc) {
        [pscustomobject]@{ Cat = $cat; Icon = (U $cp); Name = $name; Id = $id; Desc = $desc }
    }

    $catIcons = [ordered]@{
        'Browsere'   = 0x1F310
        'Utilitare'  = 0x1F9F0
        'Dezvoltare' = 0x1F4BB
        'Comunicare' = 0x1F4AC
        'Jocuri'     = 0x1F3AE
        'Media'      = 0x1F3B5
        'Sistem'     = 0x1F527
    }

    $apps = @(
        (New-App 'Browsere'   0x1F310 'Google Chrome'       'Google.Chrome'                    'Browserul de la Google'),
        (New-App 'Browsere'   0x1F98A 'Mozilla Firefox'     'Mozilla.Firefox'                  'Browser open-source, axat pe confidentialitate'),
        (New-App 'Browsere'   0x1F981 'Brave'               'Brave.Brave'                      'Browser cu blocare de reclame inclusa'),

        (New-App 'Utilitare'  0x1F4E6 '7-Zip'               '7zip.7zip'                        'Arhivator gratuit (zip, rar, 7z...)'),
        (New-App 'Utilitare'  0x1F3AC 'VLC'                 'VideoLAN.VLC'                     'Player pentru aproape orice format video/audio'),
        (New-App 'Utilitare'  0x1F4DD 'Notepad++'           'Notepad++.Notepad++'              'Editor de text rapid, cu tab-uri'),
        (New-App 'Utilitare'  0x26A1  'PowerToys'           'Microsoft.PowerToys'              'Unelte avansate de la Microsoft'),
        (New-App 'Utilitare'  0x1F50D 'Everything'          'voidtools.Everything'             'Cautare instantanee de fisiere'),
        (New-App 'Utilitare'  0x1F4F8 'ShareX'              'ShareX.ShareX'                    'Capturi de ecran si inregistrari'),
        (New-App 'Utilitare'  0x1F9F2 'qBittorrent'         'qBittorrent.qBittorrent'          'Client torrent fara reclame'),

        (New-App 'Dezvoltare' 0x1F4BB 'VS Code'             'Microsoft.VisualStudioCode'       'Editor de cod de la Microsoft'),
        (New-App 'Dezvoltare' 0x1F500 'Git'                 'Git.Git'                          'Control de versiuni'),
        (New-App 'Dezvoltare' 0x1F40D 'Python 3'            'Python.Python.3.12'               'Limbajul Python'),
        (New-App 'Dezvoltare' 0x1F7E9 'Node.js LTS'         'OpenJS.NodeJS.LTS'                'Runtime JavaScript (versiunea LTS)'),
        (New-App 'Dezvoltare' 0x1F433 'Docker Desktop'      'Docker.DockerDesktop'             'Containere pe Windows'),
        (New-App 'Dezvoltare' 0x1F5A5 'Windows Terminal'    'Microsoft.WindowsTerminal'        'Terminalul modern de la Microsoft'),
        (New-App 'Dezvoltare' 0x1F50C 'PuTTY'               'PuTTY.PuTTY'                      'Client SSH (ex. pentru serverul tau)'),

        (New-App 'Comunicare' 0x1F47E 'Discord'             'Discord.Discord'                  'Chat, voce si comunitati'),
        (New-App 'Comunicare' 0x1F4E8 'Telegram'            'Telegram.TelegramDesktop'         'Mesagerie rapida'),
        (New-App 'Comunicare' 0x1F4F1 'WhatsApp'            'WhatsApp.WhatsApp'                'WhatsApp pentru desktop'),
        (New-App 'Comunicare' 0x1F4F9 'Zoom'                'Zoom.Zoom'                        'Videoconferinte'),

        (New-App 'Jocuri'     0x1F682 'Steam'               'Valve.Steam'                      'Magazin si biblioteca de jocuri'),
        (New-App 'Jocuri'     0x1F6D2 'Epic Games Launcher' 'EpicGames.EpicGamesLauncher'      'Magazin Epic, jocuri gratuite'),
        (New-App 'Jocuri'     0x1F30C 'GOG Galaxy'          'GOG.Galaxy'                       'Jocuri fara DRM'),

        (New-App 'Media'      0x1F3B5 'Spotify'             'Spotify.Spotify'                  'Muzica si podcasturi'),
        (New-App 'Media'      0x1F3A5 'OBS Studio'          'OBSProject.OBSStudio'             'Streaming si inregistrare ecran'),
        (New-App 'Media'      0x1F399 'Audacity'            'Audacity.Audacity'                'Editor audio'),
        (New-App 'Media'      0x1F34D 'HandBrake'           'HandBrake.HandBrake'              'Convertor video'),

        (New-App 'Sistem'     0x1F4CA 'HWiNFO'              'REALiX.HWiNFO'                    'Monitorizare detaliata hardware'),
        (New-App 'Sistem'     0x1F9E0 'CPU-Z'               'CPUID.CPU-Z'                      'Informatii despre procesor si RAM'),
        (New-App 'Sistem'     0x1F4BD 'CrystalDiskInfo'     'CrystalDewWorld.CrystalDiskInfo'  'Starea de sanatate a discurilor'),
        (New-App 'Sistem'     0x1F5D1 'Revo Uninstaller'    'RevoUninstaller.RevoUninstaller'  'Dezinstalare curata a programelor')
    )

    $byId = @{}
    foreach ($a in $apps) { $byId[$a.Id] = $a }

    $catList  = @('*') + @($catIcons.Keys)
    $catCount = @{ '*' = $apps.Count }
    foreach ($c in $catIcons.Keys) { $catCount[$c] = @($apps | Where-Object { $_.Cat -eq $c }).Count }

    # --------------------------------------------------------
    #  Stare + profil salvat
    # --------------------------------------------------------
    $S = @{
        theme = 'wallpaper'; cat = 0; cursor = 0; top = 0
        search = ''; typing = $false; msg = ''
        quit = $false; alt = $false; w = 0; h = 0
        sel = @{}
    }

    $dataDir     = Join-Path $env:LOCALAPPDATA 'instalator'
    $profilePath = Join-Path $dataDir 'profil.json'

    function Load-Profile {
        $json = $null
        if (Test-Path $profilePath) {
            try { $json = Get-Content -Path $profilePath -Raw -Encoding UTF8 } catch { }
        } elseif ($Repo) {
            try { $json = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 -Uri "https://raw.githubusercontent.com/$Repo/$Branch/profil.json").Content } catch { }
        }
        if (-not $json) { return }
        try {
            $p = $json | ConvertFrom-Json
            $ids = @()
            if ($p -is [array]) { $ids = @($p) } elseif ($p.apps) { $ids = @($p.apps) }
            foreach ($id in $ids) { if ($byId.ContainsKey([string]$id)) { $S.sel[[string]$id] = $true } }
            if ($p.theme -and $themes.ContainsKey([string]$p.theme)) { $S.theme = [string]$p.theme }
        } catch { }
    }

    function Save-Profile {
        try {
            $null = New-Item -ItemType Directory -Force -Path $dataDir
            $obj = [ordered]@{ apps = @($S.sel.Keys | Sort-Object); theme = $S.theme }
            ($obj | ConvertTo-Json) | Set-Content -Path $profilePath -Encoding UTF8
            return $true
        } catch { return $false }
    }

    function Get-Visible {
        $q = $S.search.ToLower().Trim()
        $c = $catList[$S.cat]
        @($apps | Where-Object {
            ($c -eq '*' -or $_.Cat -eq $c) -and
            ($q -eq '' -or ("$($_.Name) $($_.Desc) $($_.Id) $($_.Cat)".ToLower().Contains($q)))
        })
    }

    # --------------------------------------------------------
    #  Desenare
    # --------------------------------------------------------
    function Render {
        $t   = $themes[$S.theme]
        $w   = [Console]::WindowWidth - 1
        $hgt = [Console]::WindowHeight
        $S.w = $w + 1
        $S.h = $hgt
        if ($w -lt 64 -or $hgt -lt 16) {
            [Console]::Write("${CSI}0m${CSI}2J${CSI}H" + 'Mareste fereastra terminalului (minim 65x16).')
            return
        }

        $sideW   = 26
        $mx      = $sideW + 3
        $listW   = $w - $mx + 2
        $visible = $hgt - 9

        $vis = @(Get-Visible)
        $n = $vis.Count
        if ($S.cursor -ge $n) { $S.cursor = [Math]::Max(0, $n - 1) }
        if ($S.cursor -lt $S.top) { $S.top = $S.cursor }
        if ($S.cursor -ge $S.top + $visible) { $S.top = $S.cursor - $visible + 1 }
        if ($S.top -lt 0) { $S.top = 0 }

        $sb = New-Object System.Text.StringBuilder
        $null = $sb.Append("${CSI}?25l")

        # fundal: sidebar + zona principala
        for ($r = 1; $r -le $hgt; $r++) {
            $null = $sb.Append((At $r 1)).Append((Bg $t.panel)).Append((Spaces $sideW)).Append((Bg $t.bg)).Append((Spaces ($w - $sideW)))
        }

        # bara de titlu
        $null = $sb.Append((At 1 1)).Append((Bg $t.primary)).Append((Fg $t.hlfg)).Append("${CSI}1m").Append((Spaces $w))
        $null = $sb.Append((At 1 3)).Append((U 0x1F4E6)).Append('  INSTALATOR DE APLICATII')
        $right = 'tema: ' + $t.label + '  (T)'
        if (-not $isAdmin) { $right = '! fara Administrator    ' + $right }
        $null = $sb.Append((At 1 ([Math]::Max(30, $w - $right.Length - 1)))).Append($right).Append("${CSI}22m")

        # mesaj (rand 2)
        if ($S.msg) {
            $null = $sb.Append((At 2 ($mx - 1))).Append((Bg $t.bg)).Append((Fg $t.ok)).Append((Fit $S.msg ($listW - 2)))
        }

        # sidebar: categorii
        $null = $sb.Append((At 3 3)).Append((Bg $t.panel)).Append((Fg $t.accent)).Append("${CSI}1m").Append('CATEGORII').Append("${CSI}22m")
        for ($i = 0; $i -lt $catList.Count; $i++) {
            $c   = $catList[$i]
            $row = 5 + $i
            if ($c -eq '*') { $icon = U 0x2728; $label = 'Toate' } else { $icon = U $catIcons[$c]; $label = $c }
            if ($i -eq $S.cat) { $bgc = Bg $t.primary; $fgc = Fg $t.hlfg; $bold = "${CSI}1m" } else { $bgc = Bg $t.panel; $fgc = Fg $t.fg; $bold = '' }
            $null = $sb.Append((At $row 1)).Append($bgc).Append((Spaces $sideW))
            $null = $sb.Append((At $row 3)).Append($bgc).Append($fgc).Append($bold).Append($icon)
            $null = $sb.Append((At $row 6)).Append(('{0} ({1})' -f $label, $catCount[$c])).Append("${CSI}22m")
        }

        # sidebar: tema
        $null = $sb.Append((At ($hgt - 3) 3)).Append((Bg $t.panel)).Append((Fg $t.accent)).Append("${CSI}1m").Append('TEMA  [T]').Append("${CSI}22m")
        $null = $sb.Append((At ($hgt - 2) 3)).Append((Bg $t.panel)).Append((Fg $t.fg)).Append($t.label)

        # cautare (rand 3)
        $null = $sb.Append((At 3 ($mx - 1))).Append((Bg $t.panel)).Append((Spaces $listW))
        $null = $sb.Append((At 3 $mx)).Append((Fg $t.accent)).Append('/ ')
        if ($S.search -eq '' -and -not $S.typing) {
            $null = $sb.Append((Fg $t.dim)).Append('cauta o aplicatie... (apasa /)')
        } else {
            $st = $S.search
            if ($st.Length -gt ($listW - 8)) { $st = $st.Substring($st.Length - ($listW - 8)) }
            $null = $sb.Append((Fg $t.fg)).Append($st)
            if ($S.typing) { $null = $sb.Append((Fg $t.accent)).Append([string][char]0x258F) }
        }

        # lista
        if ($n -eq 0) {
            $null = $sb.Append((At 6 $mx)).Append((Bg $t.bg)).Append((Fg $t.dim)).Append('Nicio aplicatie gasita.')
        }
        $showCat  = ($w - $mx - 32) -gt 12
        $descW    = $w - $mx - 44
        for ($i = 0; $i -lt $visible; $i++) {
            $idx = $S.top + $i
            if ($idx -ge $n) { break }
            $a   = $vis[$idx]
            $row = 5 + $i
            $cur = ($idx -eq $S.cursor)
            $checked = $S.sel.ContainsKey($a.Id)

            if ($cur) { $rbg = Bg $t.primary; $txt = Fg $t.hlfg; $dim = Fg $t.hlfg } else { $rbg = Bg $t.bg; $txt = Fg $t.fg; $dim = Fg $t.dim }
            if ($checked -and -not $cur) { $chk = Fg $t.ok } else { $chk = $txt }

            $null = $sb.Append((At $row ($mx - 1))).Append($rbg).Append((Spaces $listW))
            $ptr = ' '; if ($cur) { $ptr = [string][char]0x25B8 }
            $null = $sb.Append((At $row $mx)).Append($rbg).Append($txt).Append($ptr)
            if ($checked) { $box = '[' + [char]0x2714 + ']' } else { $box = '[ ]' }
            $null = $sb.Append((At $row ($mx + 2))).Append($rbg).Append($chk).Append("${CSI}1m").Append($box).Append("${CSI}22m")
            $null = $sb.Append((At $row ($mx + 6))).Append($rbg).Append($txt).Append($a.Icon)
            if ($checked) { $null = $sb.Append("${CSI}1m") }
            $null = $sb.Append((At $row ($mx + 9))).Append($rbg).Append($txt).Append((Fit $a.Name 22)).Append("${CSI}22m")
            if ($showCat) { $null = $sb.Append((At $row ($mx + 32))).Append($rbg).Append($dim).Append((Fit $a.Cat 11)) }
            if ($descW -gt 8) { $null = $sb.Append((At $row ($mx + 44))).Append($rbg).Append($dim).Append((Fit $a.Desc $descW)) }
        }

        # bara de derulare
        if ($n -gt $visible) {
            $thumb = [Math]::Max(1, [int]([Math]::Floor($visible * $visible / $n)))
            $pos   = [int]([Math]::Floor($S.top * ($visible - $thumb) / ($n - $visible)))
            for ($i = 0; $i -lt $visible; $i++) {
                if ($i -ge $pos -and $i -lt $pos + $thumb) { $ch = [char]0x2588; $col = $t.primary } else { $ch = [char]0x2502; $col = $t.dim }
                $null = $sb.Append((At (5 + $i) $w)).Append((Bg $t.bg)).Append((Fg $col)).Append($ch)
            }
        }

        # sumar
        $count = $S.sel.Count
        $sum = '{0} {1} selectate  {2}  {3} afisate din {4}' -f [char]0x2714, $count, [char]0xB7, $n, $apps.Count
        $null = $sb.Append((At ($hgt - 3) ($mx - 1))).Append((Bg $t.bg)).Append((Fg $t.accent)).Append("${CSI}1m").Append((Fit $sum ($listW - 2))).Append("${CSI}22m")

        # ajutor (2 randuri, cu rupere automata)
        $helpItems = @(
            @('Sus/Jos', 'navigare'), @('Stanga/Dreapta', 'categorie'), @('Spatiu', 'bifeaza'), @('/', 'cauta'),
            @('A', 'toate'), @('N', 'niciuna'), @('T', 'tema'), @('S', 'salveaza'), @('Enter', 'instaleaza'), @('Q', 'iesire')
        )
        $hr = $hgt - 2
        $hc = $mx - 1
        foreach ($it in $helpItems) {
            $len = $it[0].Length + 1 + $it[1].Length + 3
            if ($hc + $len -gt $w) { $hr++; $hc = $mx - 1 }
            if ($hr -ge $hgt) { break }
            $null = $sb.Append((At $hr $hc)).Append((Bg $t.bg)).Append((Fg $t.accent)).Append($it[0]).Append((Fg $t.dim)).Append(' ' + $it[1])
            $hc += $len
        }

        $null = $sb.Append("${CSI}0m")
        [Console]::Write($sb.ToString())
    }

    function Enter-Alt { [Console]::Write("${CSI}?1049h${CSI}?25l"); $S.alt = $true }
    function Leave-Alt { [Console]::Write("${CSI}0m${CSI}?25h${CSI}?1049l"); $S.alt = $false }

    # --------------------------------------------------------
    #  Instalare
    # --------------------------------------------------------
    function Invoke-Install {
        $chosen = @($apps | Where-Object { $S.sel.ContainsKey($_.Id) })
        if ($chosen.Count -eq 0) { $S.msg = 'Nu ai bifat nicio aplicatie.'; return }

        Leave-Alt
        $t = $themes[$S.theme]
        $ok = @(); $fail = @()
        $total = $chosen.Count
        $i = 0
        [Console]::Write("`n")
        foreach ($a in $chosen) {
            $i++
            $filled = [int][Math]::Floor(($i - 1) * 20 / $total)
            $bar = ((U 0x2588) * $filled) + ((U 0x2591) * (20 - $filled))
            [Console]::Write("`n" + (Fg $t.primary) + $bar + (Fg $t.accent) + "${CSI}1m  [$i/$total]  Instalez $($a.Name) ...${CSI}0m`n")
            $code = -1
            try {
                $proc = Start-Process -FilePath 'winget' -ArgumentList @('install', '-e', '--id', $a.Id, '--accept-package-agreements', '--accept-source-agreements') -NoNewWindow -Wait -PassThru
                $code = $proc.ExitCode
            } catch { $code = -1 }
            # 0 = instalat, -1978335189 (0x8A15002B) = deja instalat / fara update
            if ($code -eq 0 -or $code -eq -1978335189) { $ok += $a.Name } else { $fail += ('{0} (cod {1})' -f $a.Name, $code) }
        }

        [Console]::Write("`n" + (Fg $t.primary) + ((U 0x2588) * 20) + (Fg $t.accent) + "${CSI}1m  GATA${CSI}0m`n")
        if ($ok.Count)   { [Console]::Write((Fg $t.ok)  + "  " + [char]0x2714 + " Reusit ($($ok.Count)): " + ($ok -join ', ') + "${CSI}0m`n") }
        if ($fail.Count) { [Console]::Write((Fg $t.err) + "  " + [char]0x2716 + " Esuat ($($fail.Count)): " + ($fail -join ', ') + "${CSI}0m`n") }
        [Console]::Write("`n" + (Fg $t.dim) + "  Apasa orice tasta ca sa revii la lista, sau Q pentru iesire." + "${CSI}0m`n")

        $k = [Console]::ReadKey($true)
        if ("$($k.KeyChar)".ToLower() -eq 'q') { $S.quit = $true; return }
        Enter-Alt
    }

    # --------------------------------------------------------
    #  Bucla principala
    # --------------------------------------------------------
    Load-Profile

    try {
        Enter-Alt
        Render

        while (-not $S.quit) {
            while (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 40
                if ([Console]::WindowWidth -ne $S.w -or [Console]::WindowHeight -ne $S.h) { Render }
            }
            $k   = [Console]::ReadKey($true)
            $key = [string]$k.Key
            $S.msg = ''
            $vis = @(Get-Visible)
            $n   = $vis.Count

            if ($S.typing) {
                # --- mod cautare: literele se scriu in caseta ---
                if ($key -eq 'Enter') { $S.typing = $false }
                elseif ($key -eq 'Escape') { $S.typing = $false; $S.search = ''; $S.cursor = 0; $S.top = 0 }
                elseif ($key -eq 'Backspace') {
                    if ($S.search.Length -gt 0) { $S.search = $S.search.Substring(0, $S.search.Length - 1); $S.cursor = 0; $S.top = 0 }
                }
                elseif ($key -eq 'UpArrow')   { if ($S.cursor -gt 0) { $S.cursor-- } }
                elseif ($key -eq 'DownArrow') { if ($S.cursor -lt $n - 1) { $S.cursor++ } }
                elseif (-not [char]::IsControl($k.KeyChar)) { $S.search += [string]$k.KeyChar; $S.cursor = 0; $S.top = 0 }
            } else {
                switch ($key) {
                    'UpArrow'    { if ($S.cursor -gt 0) { $S.cursor-- } elseif ($n -gt 0) { $S.cursor = $n - 1 } }
                    'DownArrow'  { if ($S.cursor -lt $n - 1) { $S.cursor++ } else { $S.cursor = 0 } }
                    'PageUp'     { $S.cursor = [Math]::Max(0, $S.cursor - 10) }
                    'PageDown'   { $S.cursor = [Math]::Max(0, [Math]::Min($n - 1, $S.cursor + 10)) }
                    'Home'       { $S.cursor = 0 }
                    'End'        { $S.cursor = [Math]::Max(0, $n - 1) }
                    'LeftArrow'  { $S.cat = ($S.cat - 1 + $catList.Count) % $catList.Count; $S.cursor = 0; $S.top = 0 }
                    'RightArrow' { $S.cat = ($S.cat + 1) % $catList.Count; $S.cursor = 0; $S.top = 0 }
                    'Spacebar'   {
                        if ($n -gt 0) {
                            $id = $vis[$S.cursor].Id
                            if ($S.sel.ContainsKey($id)) { $S.sel.Remove($id) } else { $S.sel[$id] = $true }
                        }
                    }
                    'Enter'      { Invoke-Install }
                    'Escape'     { if ($S.search -ne '') { $S.search = ''; $S.cursor = 0; $S.top = 0 } }
                    default {
                        $ch = "$($k.KeyChar)".ToLower()
                        if ($ch -eq 'q') { $S.quit = $true }
                        elseif ($ch -eq '/') { $S.typing = $true }
                        elseif ($ch -eq 'a') { foreach ($x in $vis) { $S.sel[$x.Id] = $true } }
                        elseif ($ch -eq 'n') { foreach ($x in $vis) { $S.sel.Remove($x.Id) } }
                        elseif ($ch -eq 't') {
                            $i = [Array]::IndexOf($themeOrder, $S.theme)
                            $S.theme = $themeOrder[($i + 1) % $themeOrder.Count]
                        }
                        elseif ($ch -eq 's') {
                            if (Save-Profile) { $S.msg = "Salvat: $profilePath" } else { $S.msg = 'Nu am putut salva profilul.' }
                        }
                    }
                }
            }

            if (-not $S.quit -and $S.alt) { Render }
        }
    }
    finally {
        if ($S.alt) { Leave-Alt } else { [Console]::Write("${CSI}0m${CSI}?25h") }
        if ($oldEnc) { try { [Console]::OutputEncoding = $oldEnc } catch { } }
    }
}
