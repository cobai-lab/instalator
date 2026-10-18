# ============================================================
#  get.ps1 - pornire cu o singura comanda, pe orice PC Windows
#
#  1. Schimba $Repo mai jos cu "utilizatorul-tau/numele-repo-ului" de pe GitHub
#  2. Pune in acel repo: installer.py, get.ps1 (si optional profil.json)
#  3. Pe orice PC, intr-un terminal PowerShell:
#
#     irm https://raw.githubusercontent.com/UTILIZATOR/REPO/main/get.ps1 | iex
#
#  Ce face: gaseste sau instaleaza Python, descarca installer.py, isi face
#  un mediu izolat (venv) cu Textual si porneste interfata.
#  Totul sta in %LOCALAPPDATA%\instalator - nu atinge restul sistemului.
# ============================================================

$Repo   = 'UTILIZATOR/REPO'     # <-- SCHIMBA ASTA
$Branch = 'main'

$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$Dir  = Join-Path $env:LOCALAPPDATA 'instalator'
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Say($msg, $color = 'Cyan') { Write-Host "  $msg" -ForegroundColor $color }
function Fail($msg) { Write-Host "`n  EROARE: $msg" -ForegroundColor Red; return }

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function Find-Python {
    foreach ($name in 'py', 'python') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        # ignoram "stub-ul" din WindowsApps, care doar deschide Microsoft Store
        if ($cmd -and $cmd.Source -notlike '*\WindowsApps\*') { return $cmd.Source }
    }
    $guess = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
    if (Test-Path $guess) { return $guess }
    return $null
}

Write-Host ""
Write-Host "  === INSTALATOR DE APLICATII ===" -ForegroundColor Magenta
Write-Host ""

if ($Repo -eq 'UTILIZATOR/REPO') { Fail 'Editeaza get.ps1 si pune in $Repo numele repo-ului tau de pe GitHub.'; return }

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

# --- 1. Python ---
$py = Find-Python
if (-not $py) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Fail 'Nu am gasit nici Python, nici winget. Instaleaza "App Installer" din Microsoft Store si ruleaza din nou.'
        return
    }
    Say 'Python nu e instalat - il instalez cu winget...' Yellow
    winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent
    Refresh-Path
    $py = Find-Python
    if (-not $py) { Fail 'Python s-a instalat, dar nu l-am gasit. Inchide terminalul, deschide-l din nou si ruleaza comanda.'; return }
}

# --- 2. Descarcare fisiere ---
Say 'Descarc instalatorul...'
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/installer.py" -OutFile (Join-Path $Dir 'installer.py')
} catch {
    Fail "Nu pot descarca $Base/installer.py  (repo-ul trebuie sa fie public si fisierul sa existe)."
    return
}
# profilul tau (aplicatiile bifate + tema), doar daca exista in repo si nu ai deja unul local
$profile = Join-Path $Dir 'profil.json'
if (-not (Test-Path $profile)) {
    try { Invoke-WebRequest -UseBasicParsing -Uri "$Base/profil.json" -OutFile $profile } catch { }
}

# --- 3. Mediu izolat + Textual ---
$venvPy = Join-Path $Dir 'venv\Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    Say 'Creez mediul Python (o singura data)...'
    & $py -m venv (Join-Path $Dir 'venv')
}
& $venvPy -c "import textual.theme" 2>$null
if ($LASTEXITCODE -ne 0) {
    Say 'Instalez interfata Textual (o singura data)...'
    & $venvPy -m pip install --quiet --disable-pip-version-check --upgrade textual
    if ($LASTEXITCODE -ne 0) { Fail 'Nu am putut instala Textual (verifica conexiunea la internet).'; return }
}

# --- 4. Pornire ---
Say 'Pornesc...' Green
& $venvPy (Join-Path $Dir 'installer.py')
