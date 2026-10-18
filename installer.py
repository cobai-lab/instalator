"""Instalator de aplicații pentru Windows — interfață în terminal (Textual + winget).

Pornire:  python installer.py      (sau dublu-click pe porneste.bat)

Pentru a adăuga o aplicație, pune o linie nouă în lista APPS de mai jos.
ID-ul winget îl găsești cu:  winget search numele

Teme: tasta T schimbă tema, sau alege din lista „Temă” din stânga-jos.
Pentru a-ți face tema ta, copiază una din CUSTOM_THEMES și schimbă culorile.
"""
from __future__ import annotations

import asyncio
import codecs
import json
import re
from pathlib import Path
from typing import NamedTuple

from rich.text import Text
from textual import on
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.theme import Theme
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    ListItem,
    ListView,
    ProgressBar,
    RichLog,
    Select,
    Static,
)

PROFILE = Path(__file__).with_name("profil.json")
ALL = "*"


class AppInfo(NamedTuple):
    cat: str
    icon: str
    name: str
    id: str
    desc: str


CATEGORIES = {
    "Browsere": "🌐",
    "Utilitare": "🧰",
    "Dezvoltare": "💻",
    "Comunicare": "💬",
    "Jocuri": "🎮",
    "Media": "🎵",
    "Sistem": "🔧",
}

APPS = [
    # Browsere
    AppInfo("Browsere", "🌐", "Google Chrome", "Google.Chrome", "Browserul de la Google"),
    AppInfo("Browsere", "🦊", "Mozilla Firefox", "Mozilla.Firefox", "Browser open-source, axat pe confidențialitate"),
    AppInfo("Browsere", "🦁", "Brave", "Brave.Brave", "Browser cu blocare de reclame inclusă"),
    # Utilitare
    AppInfo("Utilitare", "📦", "7-Zip", "7zip.7zip", "Arhivator gratuit (zip, rar, 7z...)"),
    AppInfo("Utilitare", "🎬", "VLC", "VideoLAN.VLC", "Player pentru aproape orice format video/audio"),
    AppInfo("Utilitare", "📝", "Notepad++", "Notepad++.Notepad++", "Editor de text rapid, cu tab-uri"),
    AppInfo("Utilitare", "⚡", "PowerToys", "Microsoft.PowerToys", "Unelte avansate de la Microsoft"),
    AppInfo("Utilitare", "🔍", "Everything", "voidtools.Everything", "Căutare instantanee de fișiere"),
    AppInfo("Utilitare", "📸", "ShareX", "ShareX.ShareX", "Capturi de ecran și înregistrări"),
    AppInfo("Utilitare", "🧲", "qBittorrent", "qBittorrent.qBittorrent", "Client torrent fără reclame"),
    # Dezvoltare
    AppInfo("Dezvoltare", "💻", "VS Code", "Microsoft.VisualStudioCode", "Editor de cod de la Microsoft"),
    AppInfo("Dezvoltare", "🔀", "Git", "Git.Git", "Control de versiuni"),
    AppInfo("Dezvoltare", "🐍", "Python 3", "Python.Python.3.12", "Limbajul Python"),
    AppInfo("Dezvoltare", "🟩", "Node.js LTS", "OpenJS.NodeJS.LTS", "Runtime JavaScript (versiunea LTS)"),
    AppInfo("Dezvoltare", "🐳", "Docker Desktop", "Docker.DockerDesktop", "Containere pe Windows"),
    AppInfo("Dezvoltare", "🖥", "Windows Terminal", "Microsoft.WindowsTerminal", "Terminalul modern de la Microsoft"),
    AppInfo("Dezvoltare", "🔌", "PuTTY", "PuTTY.PuTTY", "Client SSH (ex. pentru serverul tău)"),
    # Comunicare
    AppInfo("Comunicare", "👾", "Discord", "Discord.Discord", "Chat, voce și comunități"),
    AppInfo("Comunicare", "📨", "Telegram", "Telegram.TelegramDesktop", "Mesagerie rapidă"),
    AppInfo("Comunicare", "📱", "WhatsApp", "WhatsApp.WhatsApp", "WhatsApp pentru desktop"),
    AppInfo("Comunicare", "📹", "Zoom", "Zoom.Zoom", "Videoconferințe"),
    # Jocuri
    AppInfo("Jocuri", "🚂", "Steam", "Valve.Steam", "Magazin și bibliotecă de jocuri"),
    AppInfo("Jocuri", "🛒", "Epic Games Launcher", "EpicGames.EpicGamesLauncher", "Magazin Epic, jocuri gratuite"),
    AppInfo("Jocuri", "🌌", "GOG Galaxy", "GOG.Galaxy", "Jocuri fără DRM"),
    # Media
    AppInfo("Media", "🎵", "Spotify", "Spotify.Spotify", "Muzică și podcasturi"),
    AppInfo("Media", "🎥", "OBS Studio", "OBSProject.OBSStudio", "Streaming și înregistrare ecran"),
    AppInfo("Media", "🎙", "Audacity", "Audacity.Audacity", "Editor audio"),
    AppInfo("Media", "🍍", "HandBrake", "HandBrake.HandBrake", "Convertor video"),
    # Sistem
    AppInfo("Sistem", "📊", "HWiNFO", "REALiX.HWiNFO", "Monitorizare detaliată hardware"),
    AppInfo("Sistem", "🧠", "CPU-Z", "CPUID.CPU-Z", "Informații despre procesor și RAM"),
    AppInfo("Sistem", "💽", "CrystalDiskInfo", "CrystalDewWorld.CrystalDiskInfo", "Starea de sănătate a discurilor"),
    AppInfo("Sistem", "🗑", "Revo Uninstaller", "RevoUninstaller.RevoUninstaller", "Dezinstalare curată a programelor"),
]
BY_ID = {a.id: a for a in APPS}

# Cod de ieșire winget: "deja instalat / nicio actualizare disponibilă" (0x8A15002B)
ALREADY_INSTALLED = 0x8A15002B
NOISE = re.compile(r"^[\-\\|/]$|^[\d.,]+ ?[KMG]?B ?/ ?[\d.,]+ ?[KMG]?B$|^\d+ ?%$")


# ============================================================
#  Teme
# ============================================================
DEFAULT_THEME = "wallpaper"

CUSTOM_THEMES = {
    # Culori luate din wallpaper: cărbune închis, gri-bej cald, gri-albăstrui și brun-roșcat stins
    "wallpaper": Theme(
        name="wallpaper",
        primary="#6b7f8c",      # gri-albăstrui (din pene)
        secondary="#9a867e",    # taupe cald
        accent="#c98b78",       # teracotă stinsă
        foreground="#dad4c4",   # bej deschis
        background="#1b1c1b",   # cărbune
        surface="#232324",
        panel="#2c2e2f",
        success="#8fae7e",
        warning="#d9b36c",
        error="#c8645a",
        dark=True,
    ),
    # Tema violet de la început
    "nebula": Theme(
        name="nebula",
        primary="#6d28d9",
        secondary="#a78bfa",
        accent="#22d3ee",
        foreground="#d1d5db",
        background="#0b0d17",
        surface="#11142a",
        panel="#151826",
        success="#22c55e",
        warning="#facc15",
        error="#ef4444",
        dark=True,
    ),
}

# Temele incluse în Textual care apar în listă (doar cele existente în versiunea ta)
BUILTIN_THEMES = [
    "dracula",
    "nord",
    "gruvbox",
    "tokyo-night",
    "catppuccin-mocha",
    "monokai",
    "textual-dark",
    "textual-light",
    "catppuccin-latte",
]

THEME_LABELS = {
    "wallpaper": "🖼  Wallpaper",
    "nebula": "🌌  Nebula",
    "dracula": "🧛  Dracula",
    "nord": "❄  Nord",
    "gruvbox": "🍂  Gruvbox",
    "tokyo-night": "🌃  Tokyo Night",
    "catppuccin-mocha": "🐱  Catppuccin Mocha",
    "monokai": "🎨  Monokai",
    "textual-dark": "🌑  Textual Dark",
    "textual-light": "☀  Textual Light",
    "catppuccin-latte": "☕  Catppuccin Latte",
}

# Culori de rezervă, dacă o temă nu le definește
FALLBACK = {
    "primary": "#6b7f8c",
    "accent": "#c98b78",
    "success": "#8fae7e",
    "warning": "#d9b36c",
    "error": "#c8645a",
    "foreground": "#dad4c4",
}


def palette(app: App) -> dict[str, str]:
    """Culorile temei curente, ca să se coloreze corect și textele din tabele."""
    try:
        variables = app.get_css_variables()
    except Exception:
        variables = {}
    return {k: str(variables.get(k, d)) for k, d in FALLBACK.items()}


# ============================================================
#  Ecranul de instalare
# ============================================================
class InstallScreen(Screen):
    BINDINGS = [Binding("escape", "back", "Înapoi", show=True)]

    def __init__(self, to_install: list[AppInfo]) -> None:
        super().__init__()
        self.to_install = to_install
        self.busy = True
        self.ok: list[str] = []
        self.failed: list[str] = []

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Vertical(id="install-box"):
            yield Static("🚀  Instalare în curs...", id="install-title")
            yield ProgressBar(total=len(self.to_install), show_eta=False, id="bar")
            yield DataTable(id="status", cursor_type="none", zebra_stripes=True)
            yield RichLog(id="log", wrap=True, markup=False, highlight=False)
            with Horizontal(id="install-buttons"):
                yield Button("⬅  Înapoi la listă", id="btn-back", disabled=True)
                yield Button("✖  Ieșire", id="btn-exit", variant="error", disabled=True)
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#status", DataTable)
        table.add_column("", width=3, key="icon")
        table.add_column("Aplicație", width=26, key="name")
        table.add_column("Stare", key="status")
        for a in self.to_install:
            table.add_row(a.icon, a.name, Text("⏸ în așteptare", style="dim"), key=a.id)
        self.run_worker(self.install_all(), exclusive=True)

    # ---------- instalare ----------
    async def install_all(self) -> None:
        table = self.query_one("#status", DataTable)
        log = self.query_one("#log", RichLog)
        bar = self.query_one("#bar", ProgressBar)
        p = palette(self.app)

        for a in self.to_install:
            table.update_cell(a.id, "status", Text("⏳ se instalează...", style=f"bold {p['warning']}"))
            log.write(Text(f"▶ {a.name}  ({a.id})", style=f"bold {p['accent']}"))
            code = await self.run_winget(a, log)

            if code is None:
                self.failed.append(a.name)
                table.update_cell(a.id, "status", Text("✖ winget lipsește", style=f"bold {p['error']}"))
            elif code == 0:
                self.ok.append(a.name)
                table.update_cell(a.id, "status", Text("✔ instalat", style=f"bold {p['success']}"))
            elif (code & 0xFFFFFFFF) == ALREADY_INSTALLED:
                self.ok.append(a.name)
                table.update_cell(a.id, "status", Text("✔ deja instalat", style=f"bold {p['success']}"))
            else:
                self.failed.append(a.name)
                table.update_cell(
                    a.id, "status",
                    Text(f"✖ eșuat (cod {code & 0xFFFFFFFF:#x})", style=f"bold {p['error']}"),
                )
            bar.advance(1)

        self.busy = False
        title = self.query_one("#install-title", Static)
        if self.failed:
            title.update(f"⚠  Gata: {len(self.ok)} reușite, {len(self.failed)} eșuate")
        else:
            title.update(f"🎉  Gata! Toate cele {len(self.ok)} aplicații sunt instalate")
        log.write(Text("— terminat —", style=f"bold {p['primary']}"))
        self.query_one("#btn-back", Button).disabled = False
        self.query_one("#btn-exit", Button).disabled = False
        self.query_one("#btn-back", Button).focus()

    async def run_winget(self, a: AppInfo, log: RichLog) -> int | None:
        try:
            proc = await asyncio.create_subprocess_exec(
                "winget", "install", "-e", "--id", a.id,
                "--accept-package-agreements", "--accept-source-agreements",
                "--disable-interactivity",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
        except FileNotFoundError:
            log.write(Text("winget nu a fost găsit. Instalează „App Installer” din Microsoft Store.",
                           style=f"bold {palette(self.app)['error']}"))
            return None

        decoder = codecs.getincrementaldecoder("utf-8")(errors="ignore")
        buf = ""
        assert proc.stdout is not None
        while True:
            chunk = await proc.stdout.read(512)
            if not chunk:
                break
            buf += decoder.decode(chunk)
            parts = re.split(r"[\r\n]", buf)
            buf = parts.pop()
            for line in parts:
                self.log_line(log, line)
        if buf:
            self.log_line(log, buf)
        return await proc.wait()

    @staticmethod
    def log_line(log: RichLog, line: str) -> None:
        s = line.strip()
        if not s or "█" in s or "▒" in s or NOISE.match(s):
            return
        log.write(Text(s, style="dim"))

    # ---------- acțiuni ----------
    def action_back(self) -> None:
        if not self.busy:
            self.app.pop_screen()

    @on(Button.Pressed, "#btn-back")
    def _back(self) -> None:
        self.action_back()

    @on(Button.Pressed, "#btn-exit")
    def _exit(self) -> None:
        self.app.exit()


# ============================================================
#  Aplicația principală
# ============================================================
class InstallerApp(App):
    TITLE = "📦  Instalator de aplicații"
    SUB_TITLE = "powered by winget"

    # Toate culorile vin din temă ($primary, $accent...), deci se schimbă odată cu ea.
    CSS = """
    Screen { background: $background; }
    Header { background: $primary; color: $text; text-style: bold; }
    Footer { background: $panel; }

    #sidebar { width: 32; background: $surface; border-right: heavy $primary; }
    #side-title { padding: 1 2; color: $accent; text-style: bold; }
    #cats { height: 1fr; background: transparent; }
    #cats > ListItem { height: 3; padding: 1 2; color: $foreground; background: transparent; }
    #cats > ListItem.-highlight { background: $primary; color: $text; text-style: bold; }

    #theme-box { dock: bottom; height: auto; padding: 1 2; background: $panel; }
    #theme-title { color: $accent; text-style: bold; margin-bottom: 1; }

    #main { padding: 1 2; }
    #search { margin-bottom: 1; }
    #table { height: 1fr; background: $surface; }
    #summary { height: 1; margin-top: 1; color: $accent; text-style: bold; }
    #buttons { height: 3; margin-top: 1; }
    #buttons Button { margin-right: 2; }

    #install-box { padding: 1 3; }
    #install-title { height: 3; content-align: left middle; color: $accent; text-style: bold; }
    #bar { margin-bottom: 1; }
    #status { height: auto; max-height: 14; background: $surface; margin-bottom: 1; }
    #log { height: 1fr; background: $background; border: round $primary; padding: 0 1; }
    #install-buttons { height: 3; margin-top: 1; }
    #install-buttons Button { margin-right: 2; }
    """

    BINDINGS = [
        Binding("space", "toggle", "Bifează"),
        Binding("a", "select_all", "Toate"),
        Binding("n", "select_none", "Niciuna"),
        Binding("i", "install", "Instalează"),
        Binding("s", "save", "Salvează"),
        Binding("t", "cycle_theme", "Temă"),
        Binding("/", "search", "Caută"),
        Binding("escape", "focus_list", "Listă", show=False),
        Binding("q", "quit", "Ieșire"),
    ]

    def __init__(self) -> None:
        super().__init__()
        for t in CUSTOM_THEMES.values():
            self.register_theme(t)
        self.theme_names = list(CUSTOM_THEMES) + [
            n for n in BUILTIN_THEMES if n in self.available_themes
        ]
        self.selected: set[str] = set()
        self.category = ALL
        self.search_text = ""
        self.theme_name = DEFAULT_THEME
        self.load_profile()
        if self.theme_name not in self.theme_names:
            self.theme_name = DEFAULT_THEME

    # ---------- profil salvat ----------
    @staticmethod
    def read_profile() -> dict:
        try:
            data = json.loads(PROFILE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        if isinstance(data, list):          # format vechi: doar lista de aplicații
            return {"apps": data}
        return data if isinstance(data, dict) else {}

    def write_profile(self, **changes) -> bool:
        data = self.read_profile()
        data.update(changes)
        try:
            PROFILE.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
            return True
        except OSError:
            return False

    def load_profile(self) -> None:
        data = self.read_profile()
        apps = data.get("apps", [])
        if isinstance(apps, list):
            self.selected = {i for i in apps if i in BY_ID}
        theme = data.get("theme")
        if isinstance(theme, str):
            self.theme_name = theme

    def action_save(self) -> None:
        if self.write_profile(apps=sorted(self.selected), theme=self.theme):
            self.notify(f"💾 Selecția ({len(self.selected)} aplicații) a fost salvată în profil.json")
        else:
            self.notify("Nu am putut salva profil.json", severity="error")

    # ---------- interfața ----------
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal():
            with Vertical(id="sidebar"):
                yield Static("📂  CATEGORII", id="side-title")
                yield ListView(*self.category_items(), id="cats")
                with Vertical(id="theme-box"):
                    yield Static("🎨  TEMĂ   ( T )", id="theme-title")
                    yield Select(
                        [(THEME_LABELS.get(n, n), n) for n in self.theme_names],
                        value=self.theme_name,
                        allow_blank=False,
                        id="theme-select",
                    )
            with Vertical(id="main"):
                yield Input(placeholder="🔎  Caută o aplicație...   ( / )", id="search")
                yield DataTable(id="table", cursor_type="row", zebra_stripes=True)
                yield Static(id="summary")
                with Horizontal(id="buttons"):
                    yield Button("☑  Selectează tot", id="btn-all")
                    yield Button("☐  Șterge selecția", id="btn-none")
                    yield Button("💾  Salvează", id="btn-save")
                    yield Button("🚀  Instalează", id="btn-install", variant="success")
        yield Footer()

    def category_items(self) -> list[ListItem]:
        items = [ListItem(Label(f"✨  Toate  ({len(APPS)})"), name=ALL)]
        for cat, icon in CATEGORIES.items():
            n = sum(1 for a in APPS if a.cat == cat)
            items.append(ListItem(Label(f"{icon}  {cat}  ({n})"), name=cat))
        return items

    def on_mount(self) -> None:
        self.theme = self.theme_name
        table = self.query_one("#table", DataTable)
        table.add_column("✔", width=3, key="chk")
        table.add_column("", width=3, key="icon")
        table.add_column("Aplicație", width=24, key="name")
        table.add_column("Categorie", width=12, key="cat")
        table.add_column("Descriere", key="desc")
        self.query_one("#cats", ListView).index = 0
        self.refresh_table()
        table.focus()
        # Dacă tema e schimbată din paleta de comenzi (Ctrl+P), recolorăm tabelul
        signal = getattr(self, "theme_changed_signal", None)
        if signal is not None:
            signal.subscribe(self, lambda _theme: self.call_after_refresh(self.refresh_table))

    # ---------- listă ----------
    def visible_apps(self) -> list[AppInfo]:
        q = self.search_text.lower().strip()
        out = []
        for a in APPS:
            if self.category != ALL and a.cat != self.category:
                continue
            if q and q not in f"{a.name} {a.desc} {a.id} {a.cat}".lower():
                continue
            out.append(a)
        return out

    def refresh_table(self) -> None:
        table = self.query_one("#table", DataTable)
        row = table.cursor_row
        table.clear()
        p = palette(self)
        for a in self.visible_apps():
            checked = a.id in self.selected
            mark = Text("✔", style=f"bold {p['success']}") if checked else Text("·", style="dim")
            name = Text(a.name, style="bold" if checked else "")
            table.add_row(mark, a.icon, name, a.cat, Text(a.desc, style="dim"), key=a.id)
        if table.row_count:
            table.move_cursor(row=min(row, table.row_count - 1))
        self.update_summary()

    def update_summary(self) -> None:
        n = len(self.selected)
        shown = len(self.visible_apps())
        self.query_one("#summary", Static).update(
            f"✔ {n} selectate   ·   {shown} afișate din {len(APPS)}"
        )
        btn = self.query_one("#btn-install", Button)
        btn.label = f"🚀  Instalează ({n})"
        btn.disabled = n == 0

    # ---------- teme ----------
    def set_theme_name(self, name: str) -> None:
        if name not in self.theme_names:
            return
        self.theme = name
        self.theme_name = name
        self.query_one("#theme-select", Select).value = name
        self.write_profile(theme=name)
        self.call_after_refresh(self.refresh_table)

    def action_cycle_theme(self) -> None:
        i = self.theme_names.index(self.theme) if self.theme in self.theme_names else -1
        name = self.theme_names[(i + 1) % len(self.theme_names)]
        self.set_theme_name(name)
        self.notify(f"🎨 Temă: {THEME_LABELS.get(name, name)}")

    @on(Select.Changed, "#theme-select")
    def theme_picked(self, event: Select.Changed) -> None:
        value = event.value
        if isinstance(value, str) and value != self.theme:
            self.set_theme_name(value)

    # ---------- evenimente ----------
    @on(ListView.Highlighted, "#cats")
    def category_changed(self, event: ListView.Highlighted) -> None:
        if event.item is not None and event.item.name:
            self.category = event.item.name
            self.refresh_table()

    @on(Input.Changed, "#search")
    def search_changed(self, event: Input.Changed) -> None:
        self.search_text = event.value
        self.refresh_table()

    @on(Input.Submitted, "#search")
    def search_submitted(self) -> None:
        self.query_one("#table", DataTable).focus()

    @on(DataTable.RowSelected, "#table")
    def row_selected(self, event: DataTable.RowSelected) -> None:
        self.toggle_id(event.row_key.value)

    @on(Button.Pressed, "#btn-all")
    def _all(self) -> None:
        self.action_select_all()

    @on(Button.Pressed, "#btn-none")
    def _none(self) -> None:
        self.action_select_none()

    @on(Button.Pressed, "#btn-save")
    def _save(self) -> None:
        self.action_save()

    @on(Button.Pressed, "#btn-install")
    def _install(self) -> None:
        self.action_install()

    # ---------- acțiuni ----------
    def toggle_id(self, app_id: str | None) -> None:
        if not app_id:
            return
        self.selected.symmetric_difference_update({app_id})
        self.refresh_table()

    def action_toggle(self) -> None:
        table = self.query_one("#table", DataTable)
        if table.row_count:
            key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key.value
            self.toggle_id(key)

    def action_select_all(self) -> None:
        self.selected.update(a.id for a in self.visible_apps())
        self.refresh_table()

    def action_select_none(self) -> None:
        self.selected.difference_update(a.id for a in self.visible_apps())
        self.refresh_table()

    def action_search(self) -> None:
        self.query_one("#search", Input).focus()

    def action_focus_list(self) -> None:
        self.query_one("#table", DataTable).focus()

    def action_install(self) -> None:
        chosen = [a for a in APPS if a.id in self.selected]
        if not chosen:
            self.notify("Nu ai bifat nicio aplicație.", severity="warning")
            return
        self.push_screen(InstallScreen(chosen))

    async def action_quit(self) -> None:
        screen = self.screen
        if isinstance(screen, InstallScreen) and screen.busy:
            self.notify("Instalarea e în curs — așteaptă să se termine.", severity="warning")
            return
        self.exit()


if __name__ == "__main__":
    InstallerApp().run()
