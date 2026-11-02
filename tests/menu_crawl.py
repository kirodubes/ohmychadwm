#!/usr/bin/env python3
"""Click through every row of the ohmychadwm system menu like a user and report what breaks."""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKEL = REPO / "etc/skel"
OHM = SKEL / ".config/ohmychadwm"
MENU = OHM / "menu/ohmychadwm-menu.sh"
# Hostile-user settings, changed by --home and --lang.
SETTINGS = {"home_prefix": "home-", "lang": "C.UTF-8"}

# Real tools the menu may run inside the sandbox. Everything else is a recorder stub or "command not found".
REAL_TOOLS = [
    "bash",
    "sh",
    "env",
    "sed",
    "grep",
    "awk",
    "gawk",
    "cat",
    "ls",
    "cp",
    "mv",
    "mkdir",
    "rm",
    "rmdir",
    "date",
    "head",
    "tail",
    "sort",
    "uniq",
    "tr",
    "cut",
    "printf",
    "basename",
    "dirname",
    "find",
    "wc",
    "python3",
    "make",
    "cc",
    "gcc",
    "as",
    "ld",
    "ld.bfd",
    "bc",
    "fc-list",
    "xargs",
    "sleep",
    "touch",
    "timeout",
    "tee",
    "id",
    "stat",
    "readlink",
    "realpath",
    "mktemp",
    "chmod",
    "ln",
    "md5sum",
    "sha256sum",
    "expr",
    "seq",
    "true",
    "false",
    "test",
    "comm",
    "diff",
    "cmp",
    "od",
    "tput",
    "gettext",
    "gettext.sh",
    "envsubst",
    "nproc",
    "install",
    "tac",
    "rev",
    "paste",
    "echo",
    "flock",
    "df",
]

# Commands that change the system, talk to X or need a person. They only record that they were called.
RECORDERS = [
    "sudo",
    "pacman",
    "yay",
    "systemctl",
    "pkill",
    "killall",
    "kill",
    "slop",
    "xclip",
    "xcolor",
    "redshift",
    "xautolock",
    "betterlockscreen",
    "slock",
    "i3lock",
    "picom",
    "fastcompmgr",
    "sxhkd",
    "slstatus",
    "feh",
    "xrdb",
    "xdotool",
    "setxkbmap",
    "nomacs",
    "arandr",
    "nm-connection-editor",
    "nmtui",
    "octopi",
    "pamac",
    "pamac-manager",
    "journalctl",
    "dmesg",
    "man",
    "mandb",
    "inxi",
    "btop",
    "ncdu",
    "sensors",
    "tzselect",
    "timedatectl",
    "mise",
    "curl",
    "npm",
    "rustup",
    "simplescreenrecorder",
    "kiro-keybindings",
    "xdg-open",
    "firefox",
    "chromium",
    "brave",
    "qutebrowser",
    "vivaldi",
    "code",
    "nvim",
    "vim",
    "emacs",
    "gedit",
    "ghostty",
    "kitty",
    "xterm",
    "urxvt",
    "nano",
    "node",
    "python",
    "ruby",
    "ohmychadwm",
]

GENERIC_STUB = """#!/bin/bash
echo "$(basename "$0") $*" >> "$CRAWL_DIR/actions.log"
"""

SPECIAL_STUBS = {
    # Nothing of ours is running, so every toggle starts it.
    "pgrep": "#!/bin/bash\nexit 1\n",
    "notify-send": '#!/bin/bash\necho "notify-send $*" >> "$CRAWL_DIR/actions.log"\n',
    "swapon": '#!/bin/bash\necho "/swapfile file 4G 0B -2"\n',
    "upower": '#!/bin/bash\n[[ "$1" == -e ]] && echo /org/freedesktop/UPower/devices/battery_BAT0\nexit 0\n',
    "xrandr": '#!/bin/bash\nif [[ $# -eq 0 ]]; then echo "eDP-1 connected primary"; echo "HDMI-1 connected"; '
    'else echo "xrandr $*" >> "$CRAWL_DIR/actions.log"; fi\n',
    "localectl": '#!/bin/bash\ncase "$1" in list-x11-keymap-layouts) printf "be\\nus\\n";; '
    '*) echo "localectl $*" >> "$CRAWL_DIR/actions.log";; esac\n',
    "less": "#!/bin/bash\ncat >/dev/null\n",
    # maim writes the screenshot it was asked for, or PNG bytes to stdout.
    "maim": '#!/bin/bash\necho "maim $*" >> "$CRAWL_DIR/actions.log"\n'
    'last="${!#}"; if [[ "$last" == *.png ]]; then printf "PNG" > "$last"; else printf "PNG"; fi\n',
    "fzf": '#!/bin/bash\necho "fzf $*" >> "$CRAWL_DIR/actions.log"\nhead -1\n',
    # setsid starts its argument, which is itself a stub or a real tool.
    "setsid": '#!/bin/bash\nexec "$@"\n',
    # rofi without -dmenu is the app launcher.
    "rofi": "#!/usr/bin/python3 -I\n"
    + """
import os, sys
d = os.environ["CRAWL_DIR"]
args = sys.argv[1:]
if "-dmenu" not in args:
    open(os.path.join(d, "actions.log"), "a").write("rofi " + " ".join(args) + "\\n")
    sys.exit(0)
rows = [r.split("\\0")[0] for r in sys.stdin.read().split("\\n") if r != ""]
seq = [int(x) for x in os.environ.get("CRAWL_SEQ", "").split()]
counter = os.path.join(d, "rofi.count")
k = int(open(counter).read()) if os.path.exists(counter) else 0
open(counter, "w").write(str(k + 1))
keyed = "-format" in args and args[args.index("-format") + 1] == "i"
if k < len(seq):
    i = seq[k]
    print(i if keyed else rows[i])
    sys.exit(0)
menu = os.path.join(d, "menu.txt")
if not os.path.exists(menu):
    open(menu, "w").write(("keyed" if keyed else "plain") + "\\n" + "\\n".join(rows) + "\\n")
sys.exit(1)
""",
    # The terminal runs what the menu hands it, answering "y" to prompts, and logs everything.
    "alacritty": "#!/bin/bash\n"
    + """
mkdir -p "$CRAWL_DIR/running"; touch "$CRAWL_DIR/running/$$"
echo "alacritty $*" >> "$CRAWL_DIR/actions.log"
while [[ $# -gt 0 && "$1" != -e ]]; do shift; done
if [[ $# -gt 0 ]]; then
    shift
    if [[ "${1:-}" == bash && "${2:-}" == -c ]]; then
        cmd="${3//; exec bash/}"
        yes y 2>/dev/null | timeout 120 bash -c "$cmd" >> "$CRAWL_DIR/term.log" 2>&1
    else
        yes y 2>/dev/null | timeout 120 "$@" >> "$CRAWL_DIR/term.log" 2>&1
    fi
    echo "exit=$?" >> "$CRAWL_DIR/term.log"
fi
rm -f "$CRAWL_DIR/running/$$"
""",
}

ERROR_MARKERS = (
    "command not found",
    "syntax error",
    "unbound variable",
    "bad substitution",
    "No such file or directory",
    "error:",
    "make: ***",
    "Traceback",
    "Permission denied",
)


def build_bin(root: Path) -> Path:
    """Create the PATH directory: real allowlisted tools plus stubs."""
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for tool in REAL_TOOLS:
        real = shutil.which(tool)
        if real:
            (bin_dir / tool).symlink_to(real)
    (bin_dir / "yes").symlink_to(shutil.which("yes"))
    for name in RECORDERS:
        (bin_dir / name).write_text(GENERIC_STUB)
    for name, body in SPECIAL_STUBS.items():
        (bin_dir / name).write_text(body)
    for f in bin_dir.iterdir():
        if not f.is_symlink():
            f.chmod(0o755)
    return bin_dir


def make_home(root: Path) -> Path:
    """Fresh user home: the repo skel (two wallpapers only) plus a Kiro-like alacritty config."""
    home = Path(tempfile.mkdtemp(dir=root, prefix=SETTINGS["home_prefix"]))
    shutil.copytree(SKEL, home, dirs_exist_ok=True, symlinks=True, ignore=shutil.ignore_patterns("wallpapers"))
    walls = home / ".config/ohmychadwm/wallpapers"
    walls.mkdir(parents=True, exist_ok=True)
    for wp in sorted((OHM / "wallpapers").glob("*.jpg"))[:2]:
        shutil.copy(wp, walls)
    host_alacritty = Path("/etc/skel/.config/alacritty")
    if host_alacritty.is_dir():
        shutil.copytree(host_alacritty, home / ".config/alacritty", dirs_exist_ok=True)
    return home


def _sources(home: Path) -> dict[str, bytes]:
    """The config sources a rebuild compiles (generated config.h excluded)."""
    base = home / ".config/ohmychadwm"
    files = [p for p in (base / "chadwm").rglob("*.h") if p.name != "config.h"]
    files += [p for p in (base / "slstatus").glob("*.h") if p.name != "config.h"]
    return {str(p): p.read_bytes() for p in files}


def run_path(root: Path, bin_dir: Path, seq: list[int], timeout: int, home: Path | None = None) -> dict:
    """Run the menu once with a list of row choices; return what happened. A given home is reused and kept."""
    keep_home = home is not None
    home = home or make_home(root)
    before = _sources(home)
    crawl = Path(tempfile.mkdtemp(dir=root, prefix="crawl-"))
    (crawl / "actions.log").touch()
    env = {
        "PATH": str(bin_dir),
        "HOME": str(home),
        "CRAWL_DIR": str(crawl),
        "CRAWL_SEQ": " ".join(map(str, seq)),
        "TERMINAL": "alacritty",
        "EDITOR": "nano",
        "BROWSER": "firefox",
        "LANG": SETTINGS["lang"],
        "LC_ALL": SETTINGS["lang"],
        "OHMYCHADWM_SKEL": str(OHM),
    }
    menu = home / ".config/ohmychadwm/menu/ohmychadwm-menu.sh"
    try:
        proc = subprocess.run(
            ["bash", str(menu)], env=env, cwd=home, capture_output=True, text=True, check=False, timeout=timeout
        )
        out, rc = proc.stdout + proc.stderr, proc.returncode
    except subprocess.TimeoutExpired:
        out, rc = "TIMEOUT in menu", 124
    # Terminals and browsers start in the background after the menu exits: wait until they appear and finish.
    deadline = time.time() + timeout
    quiet_since = time.time()
    while time.time() < deadline:
        busy = (crawl / "running").exists() and any((crawl / "running").iterdir())
        if busy:
            quiet_since = time.time()
        elif time.time() - quiet_since > 1.0:
            break
        time.sleep(0.1)
    term = (crawl / "term.log").read_text(errors="replace") if (crawl / "term.log").exists() else ""
    result = {
        "seq": seq,
        "rc": rc,
        "out": out,
        "term": term,
        "actions": (crawl / "actions.log").read_text(errors="replace"),
        "menu": None,
        "changed": _sources(home) != before,
    }
    if (crawl / "menu.txt").exists():
        kind, *rows = (crawl / "menu.txt").read_text().rstrip("\n").split("\n")
        result["menu"] = (kind, rows)
    if not keep_home:
        shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(crawl, ignore_errors=True)
    return result


def _define(home: Path, name: str) -> str:
    """Value of a THEME_* define in the active theme of a home (or of the skel when home is OHM's parent)."""
    base = home / ".config/ohmychadwm/chadwm" if home != SKEL else OHM / "chadwm"
    config = (base / "config.def.h").read_text()
    theme = re.search(r'^#include "themes/([^"]+)\.h"', config, re.MULTILINE).group(1)
    m = re.search(rf"^#define {name}\s+(\S+)", (base / f"themes/{theme}.h").read_text(), re.MULTILINE)
    return m.group(1) if m else ""


def _autostart(home: Path) -> str:
    """Which compositor run.sh starts at login."""
    run = (home / ".config/ohmychadwm/scripts/run.sh").read_text()
    started = [c for c in ("picom", "fastcompmgr") if re.search(rf"^run {c}\b", run, re.MULTILINE)]
    return ",".join(started) or "none"


# Things a user does over several menu trips, and what must be true afterwards.
SCENARIOS = [
    (
        "Border 10, then Appearance › Back to default restores the border",
        [("Appearance", "Windows", "Border", "10"), ("Appearance", "Back to default")],
        lambda h: (
            _define(h, "THEME_BORDER") == _define(SKEL, "THEME_BORDER")
            or f"border is {_define(h, 'THEME_BORDER')}, shipped is {_define(SKEL, 'THEME_BORDER')}"
        ),
    ),
    (
        "Tags › Purpose, then Back to default restores the tag style",
        [("Appearance", "Tags", "Purpose (home, chat, surf…)"), ("Appearance", "Back to default")],
        lambda h: _define(h, "THEME_TAGS") == _define(SKEL, "THEME_TAGS") or f"tags are {_define(h, 'THEME_TAGS')}",
    ),
    (
        "Update › Process › Picom makes run.sh start picom at login",
        [("Update", "Process", "Picom")],
        lambda h: _autostart(h) == "picom" or f"run.sh starts {_autostart(h)}",
    ),
    (
        "…and Fastcompmgr switches run.sh back",
        [("Update", "Process", "Picom"), ("Update", "Process", "Fastcompmgr")],
        lambda h: _autostart(h) == "fastcompmgr" or f"run.sh starts {_autostart(h)}",
    ),
    (
        "Keybinding set AZERTY, then Back to default gives QWERTY config and cheatsheet",
        [("Setup", "Keybinding set", "AZERTY (Belgian)"), ("Appearance", "Back to default")],
        lambda h: _qwerty_again(h),
    ),
    (
        "Net download speed uses this machine's network interface",
        [("Appearance", "Bar", "Status modules", "✗ Net download speed")],
        lambda h: _netspeed_iface(h),
        # A name no machine has, so the test proves the menu writes the real one.
        lambda h: _set_netspeed_iface(h, "bogus0"),
    ),
]


def _set_netspeed_iface(home: Path, iface: str) -> None:
    conf = home / ".config/ohmychadwm/slstatus/config.def.h"
    conf.write_text(re.sub(r'(netspeed_[rt]x,[^"]*"[^"]*",\s*)"[^"]*"', rf'\1"{iface}"', conf.read_text()))


def _qwerty_again(home: Path) -> bool | str:
    base = home / ".config/ohmychadwm"
    if re.search(r"^#define KIRO_AZERTY\s+true", (base / "chadwm/config.def.h").read_text(), re.MULTILINE):
        return "config.def.h is still AZERTY"
    if (base / "keybindings.txt").read_text() != (OHM / "keybindings.txt").read_text():
        return "keybindings.txt is not the shipped (QWERTY) cheatsheet"
    return True


def _netspeed_iface(home: Path) -> bool | str:
    route = Path("/proc/net/route").read_text().splitlines()[1:]
    iface = next((f.split()[0] for f in route if f.split()[1] == "00000000"), None)
    text = (home / ".config/ohmychadwm/slstatus/config.def.h").read_text()
    line = re.search(r"^\s*\{ netspeed_rx,.*", text, re.MULTILINE)
    if not line:
        return "netspeed_rx was not switched on"
    return iface is None or f'"{iface}"' in line.group(0) or f"uses {line.group(0).split(',')[2].strip()}, not {iface}"


def run_scenarios(root: Path, bin_dir: Path, timeout: int, by_label: dict[tuple, tuple]) -> int:
    """Run each scenario in one shared home; return the number that failed."""
    failed = 0
    for title, steps, check, *setup in SCENARIOS:
        home = make_home(root)
        for prepare in setup:
            prepare(home)
        problems_found = []
        for step in steps:
            seq = by_label.get(step)
            if seq is None:
                problems_found.append(f"menu path not found: {' › '.join(step)}")
                break
            res = run_path(root, bin_dir, list(seq), timeout, home=home)
            problems_found += [p for p in problems(res) if p != "nothing happened"]
        if not problems_found:
            verdict = check(home)
            if verdict is not True:
                problems_found.append(str(verdict))
        shutil.rmtree(home, ignore_errors=True)
        if problems_found:
            failed += 1
            print(f"FAIL  scenario: {title}")
            for p in dict.fromkeys(problems_found):
                print(f"        {p}")
        else:
            print(f"ok    scenario: {title}")
    return failed


def problems(res: dict, toggled: bool | None = None) -> list[str]:
    """List what went wrong in one leaf run; toggled says whether a ✓/✗ row flipped (None: not a toggle row)."""
    found = []
    text = res["out"] + "\n" + res["term"]
    for marker in ERROR_MARKERS:
        for line in text.splitlines():
            if marker in line:
                found.append(line.strip()[:160])
                break
    if "TIMEOUT" in text or "exit=124" in res["term"]:
        found.append("timed out")
    for line in res["actions"].splitlines():
        if line.startswith("notify-send -u critical"):
            found.append(line[:160])
    if toggled is False:
        found.append("row did not switch between ✓ and ✗")
    elif toggled is None and not res["actions"].strip():
        found.append("nothing happened")
    return found


def _norm(rows: list[str]) -> list[str]:
    return [r.lstrip("✓✗ ").strip() for r in rows]


def crawl(jobs: int, timeout: int, max_depth: int) -> int:
    """Walk the menu tree breadth-first, running each level in parallel."""
    root = Path(tempfile.mkdtemp(prefix="ohmychadwm-crawl-"))
    bin_dir = build_bin(root)
    names: dict[tuple, str] = {(): "ohmychadwm"}
    parent_rows: dict[tuple, list[str]] = {}
    rebuilds: dict[tuple, list[bool]] = {}
    level, leaves, failures = [()], 0, 0
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            while level:
                results = list(pool.map(lambda s: run_path(root, bin_dir, list(s), timeout), level))
                next_level = []
                for seq, res in zip(level, results):
                    seq = tuple(seq)
                    menu = res["menu"]
                    looped = menu and seq and _norm(menu[1]) == _norm(parent_rows.get(seq[:-1], []))
                    if menu and not looped and len(seq) < max_depth:
                        kind, rows = menu
                        parent_rows[seq] = rows
                        picks = range(len(rows)) if kind == "keyed" else sorted({0, len(rows) - 1})
                        for i in picks:
                            names[seq + (i,)] = rows[i].strip()
                            next_level.append(seq + (i,))
                        continue
                    if not seq:
                        continue
                    leaves += 1
                    label = " › ".join(names[seq[:n]] for n in range(1, len(seq) + 1))
                    toggled = None
                    before = parent_rows.get(seq[:-1], [])
                    if looped and before[seq[-1]].lstrip()[:1] in ("✓", "✗"):
                        toggled = menu[1][seq[-1]].lstrip()[:1] != before[seq[-1]].lstrip()[:1]
                    # Picking the current value rebuilds without a change; a menu where no choice changes anything
                    # is a silent no-op. Collected per menu and judged after the crawl.
                    if "rebuild.sh" in res["actions"]:
                        rebuilds.setdefault(seq[:-1], []).append(res["changed"])
                    bad = problems(res, toggled)
                    if bad:
                        failures += 1
                        print(f"FAIL  {label}")
                        for b in dict.fromkeys(bad):
                            print(f"        {b}")
                    else:
                        print(f"ok    {label}")
                    sys.stdout.flush()
                level = next_level
        for parent, changes in rebuilds.items():
            if len(changes) >= 2 and not any(changes):
                failures += 1
                label = " › ".join(names[parent[:n]] for n in range(1, len(parent) + 1))
                print(f"FAIL  {label}\n        no choice in this menu changes any setting before the rebuild")
        by_label = {tuple(names[s[:n]] for n in range(1, len(s) + 1)): s for s in names if s}
        failures += run_scenarios(root, bin_dir, timeout, by_label)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"\n{leaves} menu actions tried, {failures} failed")
    return 1 if failures else 0


def main() -> int:
    """Parse arguments and crawl."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--max-depth", type=int, default=6)
    ap.add_argument("--home", default="home-", help='home folder name prefix, e.g. "my home " (with a space)')
    ap.add_argument("--lang", default="C.UTF-8", help="locale to run the menu in, e.g. de_DE.UTF-8")
    args = ap.parse_args()
    if not MENU.exists():
        print(f"menu not found: {MENU}", file=sys.stderr)
        return 2
    SETTINGS.update(home_prefix=args.home, lang=args.lang)
    return crawl(args.jobs, args.timeout, args.max_depth)


if __name__ == "__main__":
    sys.exit(main())
