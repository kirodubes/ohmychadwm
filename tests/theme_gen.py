#!/usr/bin/env python3
"""Create themes with generate-chadwm-theme.sh in throwaway homes, build chadwm with each and keep the results."""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OHM = REPO / "etc/skel/.config/ohmychadwm"
GENERATOR = OHM / "scripts/generate-chadwm-theme.sh"
PREVIEWS = OHM / "scripts/generate-theme-previews.sh"
DEFAULT_OUT = Path.home() / ".cache/ohmychadwm/theme-gen"
ASK = "\033[1;33m"  # generate-chadwm-theme.sh prints every question in this colour, right before its read

# Same order as the generator's menus: answer N picks entry N.
LAYOUTS = ["DWINDLE", "TILE", "SPIRAL", "DECK", "BSTACK", "BSTACKH", "GRID", "NROWGRID",
           "HORIZGRID", "GAPLESS", "CENTER", "CFLOAT", "FLOAT"]
TAGS = ["NERD", "ARABIC", "ROMAN", "POWERLINE", "WEBDINGS", "JAPANESE", "ALPHA", "EMOJI",
        "GEOMETRIC", "CHINESE", "PURPOSE"]

# Synthetic wallpapers for the edge cases a photo library rarely covers: name -> magick arguments.
# All 8-bit except "deep": a 16-bit PNG, which prints 12-digit hex colours in magick's txt: output.
SYNTHETIC = {
    "dark": ["-size", "1920x1080", "gradient:#000000-#1c2433", "-depth", "8"],
    "bright": ["-size", "1920x1080", "gradient:#ffffff-#d0d8e0", "-depth", "8"],
    "grey": ["-size", "1920x1080", "gradient:#5a5a5a-#767676", "-depth", "8"],
    "neon": ["-seed", "7", "-size", "1920x1080", "plasma:fractal", "-depth", "8"],
    "deep": ["-size", "1920x1080", "gradient:#000000-#1c2433", "-depth", "16"],
}
# One colour cannot make a palette: the generator must refuse it cleanly.
SOLID = ["-size", "1920x1080", "xc:#336699"]

STUBS = {
    "feh": "#!/bin/sh\nexit 0\n",
    "fzf": '#!/bin/sh\necho "fzf $*" >> "$HOME/fzf-called"\nexit 1\n',
    "sudo": "#!/bin/sh\necho 'sudo is not allowed in theme_gen' >&2\nexit 1\n",
    "notify-send": "#!/bin/sh\nexit 0\n",
    "xdotool": "#!/bin/sh\nexit 0\n",
}


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:24]


def _lum(hexcol: str) -> float:
    def chan(c: int) -> float:
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hexcol[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)


def contrast(a: str, b: str) -> float:
    """WCAG contrast ratio between two #rrggbb colours."""
    la, lb = sorted((_lum(a), _lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def make_stubs(root: Path) -> Path:
    """Directory put in front of PATH: tools that would touch the real session or system."""
    stub_dir = root / "stubs"
    stub_dir.mkdir()
    for name, body in STUBS.items():
        (stub_dir / name).write_text(body)
        (stub_dir / name).chmod(0o755)
    return stub_dir


def make_home(root: Path, name: str, wallpaper: Path) -> Path:
    """Throwaway home with the repo's ohmychadwm config and a .fehbg pointing at the wallpaper."""
    home = root / f"home-{name}"
    shutil.copytree(OHM, home / ".config/ohmychadwm", symlinks=True,
                    ignore=shutil.ignore_patterns("wallpapers", "previews"))
    (home / ".config/ohmychadwm/wallpapers").mkdir()
    wall = home / f"wall{wallpaper.suffix}"
    shutil.copy(wallpaper, wall)
    (home / ".fehbg").write_text(f"#!/bin/sh\nfeh --no-fehbg --bg-fill '{wall}'\n")
    return home


def answers(idx: int, name: str) -> list[tuple[str, list[str]]]:
    """Question pattern -> answers in order of asking. Unknown questions get Enter (the default)."""
    first_name = ["dracula", name] if idx == 0 else [name]
    return [
        ("Theme name", first_name),
        ("already exists. Overwrite", ["y"]),
        ("Continue with these colors", ["y"]),
        ("Bar position", ["b" if idx % 2 else "t"]),
        ("Gap size", [str(idx % 21)]),
        ("Default layout", [str(idx % len(LAYOUTS))]),
        ("Tag style", [str(idx % len(TAGS))]),
        ("Font not installed|Continue\\? \\[Y/n\\]", ["y"]),
        ("Fix this wallpaper", ["y"]),
        ("Run ./rebuild.sh", ["n"]),
    ]


def drive(home: Path, path: str, script: list[tuple[str, list[str]]], timeout: int) -> tuple[int, str, bool]:
    """Run the generator, answering each question as it appears. Returns (exit code, output, timed out)."""
    env = {"HOME": str(home), "PATH": path, "LANG": "C.UTF-8", "TERM": "dumb"}
    proc = subprocess.Popen(["bash", str(GENERATOR)], cwd=home, env=env, text=True,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    timed_out = threading.Event()

    def _kill() -> None:
        timed_out.set()
        proc.kill()

    timer = threading.Timer(timeout, _kill)
    timer.start()
    queue = {pat: list(vals) for pat, vals in script}
    out = []
    try:
        for line in proc.stdout:
            out.append(line)
            if ASK not in line:
                continue
            reply = ""
            for pat, vals in queue.items():
                if re.search(pat, line):
                    reply = vals.pop(0) if len(vals) > 1 else vals[0]
                    break
            out.append(f"[theme_gen answered: {reply!r}]\n")
            try:
                proc.stdin.write(reply + "\n")
                proc.stdin.flush()
            except BrokenPipeError:
                break
        proc.wait()
    finally:
        timer.cancel()
    return proc.returncode, "".join(out), timed_out.is_set()


def theme_values(text: str) -> tuple[dict[str, str], dict[str, str]]:
    """(defines, colours) of a theme header."""
    defines = dict(re.findall(r"^#define\s+(THEME_\w+)\s+(.+?)\s*$", text, re.MULTILINE))
    colours = dict(re.findall(r'static const char (\w+)\[\]\s*=\s*"([^"]*)"', text))
    return defines, colours


def check_theme(idx: int, name: str, home: Path, rc: int, log: str) -> list[str]:
    """Everything that is wrong with one generated theme."""
    cfg = home / ".config/ohmychadwm"
    theme = cfg / f"chadwm/themes/{name}.h"
    problems = []
    if rc != 0:
        return [f"generator exited {rc}"]
    if not theme.is_file():
        return ["no theme file written"]
    if idx == 0:
        if "is a built-in theme" not in log:
            problems.append("built-in name 'dracula' was not refused")
        if (cfg / "chadwm/themes/dracula.h").read_bytes() != (OHM / "chadwm/themes/dracula.h").read_bytes():
            problems.append("built-in dracula.h was changed")
    if (home / "fzf-called").exists():
        problems.append("generator fell back to an fzf picker: " + (home / "fzf-called").read_text().strip())

    active = re.findall(r'^#include "themes/([^"]+)\.h"', (cfg / "chadwm/config.def.h").read_text(), re.MULTILINE)
    if active != [name]:
        problems.append(f"active theme includes in config.def.h: {active}, expected [{name}]")
    if not list((cfg / "wallpapers").glob(f"{name}.*")):
        problems.append("wallpaper not saved next to the theme")

    defines, colours = theme_values(theme.read_text())
    expect = {
        "THEME_LAYOUT": f"LAYOUT_{LAYOUTS[idx % len(LAYOUTS)]}",
        "THEME_TAGS": f"TAGS_{TAGS[idx % len(TAGS)]}",
        "THEME_GAPS": str(idx % 21),
    }
    for key, want in expect.items():
        if defines.get(key) != want:
            problems.append(f"{key} = {defines.get(key)}, answered {want}")
    bad = {k: v for k, v in colours.items() if not re.fullmatch(r"#[0-9a-fA-F]{6}", v)}
    if bad:
        problems.append(f"invalid colours: {bad}")
        return problems

    bg = colours["SchemeNormbg"]
    # Title and status text (SchemeNormfg, drawstatusbar) are text: 3:1. Tags at least 2:1; the generator aims
    # for 2.5:1, since 2:1 still looked faint on a dark bar in the VM. SchemeSel is only the window border.
    pairs = {
        "window title on bar": (colours["SchemeTitlefg"], bg, 3.0),
        "status text on bar": (colours["SchemeNormfg"], bg, 3.0),
    }
    pairs.update({f"tag {n} on bar": (colours[f"SchemeTag{n}fg"], bg, 2.0)
                  for n in range(1, 11) if f"SchemeTag{n}fg" in colours})
    for label, (fg, back, need) in pairs.items():
        ratio = contrast(fg, back)
        if ratio < need:
            problems.append(f"{label} unreadable: {fg} on {back} = {ratio:.2f}:1 (need {need}:1)")
    return problems


def build(home: Path) -> str:
    """Compile chadwm with the generated config; '' when it builds."""
    chadwm = home / ".config/ohmychadwm/chadwm"
    res = subprocess.run(["make", "-C", str(chadwm), "-s"], capture_output=True, text=True, check=False)
    if res.returncode == 0:
        return ""
    lines = (res.stdout + res.stderr).splitlines()
    return next((ln for ln in lines if "error" in ln), lines[-1] if lines else "make failed")


def preview(root: Path, theme: Path, dest: Path) -> None:
    """Render the bar + windows mockup PNG for one theme in a home that holds only that theme."""
    home = root / f"preview-{theme.stem}"
    (home / ".config/ohmychadwm/chadwm/themes").mkdir(parents=True)
    shutil.copy(theme, home / ".config/ohmychadwm/chadwm/themes")
    subprocess.run(["bash", str(PREVIEWS)], env={**os.environ, "HOME": str(home)}, capture_output=True, check=False)
    png = home / f".config/ohmychadwm/previews/{theme.stem}.png"
    if png.is_file():
        shutil.copy(png, dest)


def run_case(root: Path, path: str, idx: int, label: str, wallpaper: Path, out: Path, timeout: int) -> dict:
    """Generate, check, build and keep one theme."""
    name = f"gen_{_slug(label)}"
    home = make_home(root, name, wallpaper)
    rc, log, hung = drive(home, path, answers(idx, name), timeout)
    problems = [f"hung after {timeout}s (a question without an answer?)"] if hung else []
    problems = problems or check_theme(idx, name, home, rc, log)
    theme = home / f".config/ohmychadwm/chadwm/themes/{name}.h"
    if theme.is_file() and not any(p.startswith("generator exited") for p in problems):
        err = build(home)
        if err:
            problems.append(f"chadwm build: {err}")
    keep = out / name
    keep.mkdir(parents=True)
    (keep / "generator.log").write_text(log)
    shutil.copy(wallpaper, keep / f"wallpaper{wallpaper.suffix}")
    if theme.is_file():
        shutil.copy(theme, keep / f"{name}.h")
        preview(root, theme, keep / "preview.png")
    return {"name": name, "label": label, "problems": problems}


def solid_case(root: Path, path: str, wallpaper: Path, timeout: int) -> list[str]:
    """A one-colour wallpaper must be refused with a message, without writing a theme."""
    home = make_home(root, "gen_solid", wallpaper)
    rc, log, hung = drive(home, path, answers(1, "gen_solid"), timeout)
    if hung:
        return [f"hung after {timeout}s"]
    problems = []
    if rc == 0:
        problems.append("one-colour wallpaper was accepted")
    if "Could not extract enough colors" not in log:
        problems.append("no 'not enough colors' message for a one-colour wallpaper")
    if (home / ".config/ohmychadwm/chadwm/themes/gen_solid.h").exists():
        problems.append("theme file written for a one-colour wallpaper")
    return problems


def twin_problem(results: list[dict], out: Path) -> None:
    """'deep' is 'dark' saved at 16 bit: both must get the same bar background."""
    by_label = {r["label"]: r for r in results}
    if "dark" not in by_label or "deep" not in by_label:
        return
    bgs = []
    for label in ("dark", "deep"):
        header = out / by_label[label]["name"] / f"{by_label[label]['name']}.h"
        if not header.is_file():
            return
        bgs.append(theme_values(header.read_text())[1].get("SchemeNormbg", "#000000"))
    if max(abs(int(bgs[0][i:i + 2], 16) - int(bgs[1][i:i + 2], 16)) for i in (1, 3, 5)) > 16:
        by_label["deep"]["problems"].insert(
            0, f"16-bit wallpaper gives other colours than the same image at 8 bit: bar {bgs[1]} vs {bgs[0]}")


def check_shipped() -> int:
    """Every shipped theme: window title at least 3:1, status text at least 1.5:1 against the bar."""
    failed = 0
    for header in sorted((OHM / "chadwm/themes").glob("*.h")):
        colours = theme_values(header.read_text())[1]
        bg = colours["SchemeNormbg"]
        for label, key, need in (("window title", "SchemeTitlefg", 3.0), ("status text", "SchemeNormfg", 1.5)):
            ratio = contrast(colours[key], bg)
            if ratio < need:
                failed += 1
                print(f"FAIL theme {header.stem}: {label} {colours[key]} on {bg} = {ratio:.2f}:1 (need {need}:1)")
    print(f"shipped themes checked, {failed} unreadable")
    return 1 if failed else 0


def recover(kept: Path, new_name: str | None) -> int:
    """Copy a kept theme into the real ~/.config/ohmychadwm and list it in the menu's theme picker."""
    headers = list(kept.glob("*.h"))
    if len(headers) != 1:
        print(f"no single theme .h in {kept}", file=sys.stderr)
        return 1
    name = new_name or headers[0].stem
    if not re.fullmatch(r"[a-z0-9_-]+", name):
        print(f"theme name '{name}': use lowercase letters, digits, _ or -", file=sys.stderr)
        return 1
    cfg = Path(os.environ.get("OHMYCHADWM_CONFIG", Path.home() / ".config/ohmychadwm"))
    config = cfg / "chadwm/config.def.h"
    dest = cfg / f"chadwm/themes/{name}.h"
    if dest.exists() or f"themes/{name}.h" in config.read_text():
        print(f"theme '{name}' already exists — pick another name with --as", file=sys.stderr)
        return 1
    text = headers[0].read_text()
    dest.write_text(re.sub(r"^/\* \S+ —", f"/* {name.capitalize()} —", text, count=1))
    wall = next(kept.glob("wallpaper.*"), None)
    if wall:
        shutil.copy(wall, cfg / f"wallpapers/{name}{wall.suffix}")
    lines = config.read_text().splitlines(keepends=True)
    include = f'//#include "themes/{name}.h"\n'
    at = next((i + 1 for i, ln in enumerate(lines) if ln.startswith("// custom themes")), None)
    if at is None:
        at = next(i for i, ln in enumerate(lines) if ln.startswith("/* fallback layout settings"))
        lines[at:at] = ["// custom themes\n", include, "\n"]
    else:
        lines.insert(at, include)
    config.write_text("".join(lines))
    print(f"recovered '{name}' into {cfg} — pick it in Super+Alt+Space → Theme to activate it")
    return 0


def main() -> int:
    """Parse arguments and either recover a kept theme or run every case."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, help=f"where to keep the themes (default {DEFAULT_OUT}/<time>)")
    ap.add_argument("--quick", action="store_true", help="synthetic wallpapers only, no shipped wallpapers")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--shipped", action="store_true", help="only check title/status contrast of the shipped themes")
    ap.add_argument("--recover", type=Path, metavar="DIR", help="install a kept theme folder into your config")
    ap.add_argument("--as", dest="new_name", help="with --recover: install under this theme name")
    args = ap.parse_args()

    if args.recover:
        return recover(args.recover, args.new_name)
    if args.shipped:
        return check_shipped()
    for tool in ("magick", "make"):
        if not shutil.which(tool):
            print(f"{tool} not installed", file=sys.stderr)
            return 1

    out = args.out or DEFAULT_OUT / time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="ohmychadwm-theme-gen-"))
    try:
        path = f"{make_stubs(root)}:{os.environ.get('PATH', '/usr/bin')}"
        walls = root / "walls"
        walls.mkdir()
        cases = []
        for label, magick_args in {**SYNTHETIC, "solid": SOLID}.items():
            subprocess.run(["magick", *magick_args, str(walls / f"{label}.png")], check=True)
            if label != "solid":
                cases.append((label, walls / f"{label}.png"))
        if not args.quick:
            cases += [(f"wp_{wp.stem}", wp) for wp in sorted((OHM / "wallpapers").iterdir())
                      if wp.suffix.lower() in (".jpg", ".jpeg", ".png")]

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            solid = pool.submit(solid_case, root, path, walls / "solid.png", args.timeout)
            results = list(pool.map(lambda c: run_case(root, path, c[0], c[1][0], c[1][1], out, args.timeout),
                                    enumerate(cases)))
        twin_problem(results, out)
        failed = 0
        for res in results:
            if res["problems"]:
                failed += 1
                for p in res["problems"]:
                    print(f"FAIL {res['name']} ({res['label']}): {p}")
            else:
                print(f"ok {res['name']} ({res['label']})")
        for p in solid.result():
            failed += 1
            print(f"FAIL gen_solid: {p}")

        shots = sorted(out.glob("*/preview.png"))
        if shots:
            subprocess.run(["magick", "montage", *map(str, shots), "-tile", "4x", "-geometry", "480x360+8+8",
                            "-title", "theme_gen", "-label", "%d", str(out / "overview.png")],
                           capture_output=True, check=False)
        print(f"{len(results) - failed} of {len(results)} themes passed; kept in {out}")
        print(f"keep one: python3 {Path(__file__).relative_to(REPO.parent)} --recover {out}/<name> [--as newname]")
        return 1 if failed else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
