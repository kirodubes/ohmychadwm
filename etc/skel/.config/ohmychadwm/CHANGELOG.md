# Changelog

## 2026.05.24

### What Changed
- **Default home folders on session start.** `run.sh` now creates the standard
  XDG user directories (Desktop, Downloads, Documents, Music, Pictures, Videos,
  Templates, Public, Projects) on login, the same way XFCE does. Previously a
  fresh ohmychadwm login left the home directory empty because nothing ran the
  XDG folder creation step.
- **Fixed inaccurate restart comments in `run.sh`.** Two comments claimed the
  autostart section re-runs on window-manager restart; it does not. Corrected
  them and removed a wrong keybinding reference (the old comment said
  "Super+Shift+Q" for restart, but that binding is `killclient`; restart is
  Super+Shift+R).

### Technical Details
- Folder creation uses `xdg-user-dirs-update`, guarded by `command -v` so it is
  a no-op when the `xdg-user-dirs` package is absent. The tool reads
  `/etc/xdg/user-dirs.defaults`, writes `~/.config/user-dirs.dirs`, and is
  idempotent — it only creates missing folders and respects ones deliberately
  deleted. Placed right after the `backup-originals.sh` step, before any apps.
- Restart-behavior clarification: the session entry point
  `/usr/bin/exec-ohmychadwm` runs `run.sh` once per login. The bottom loop
  `while type ohmychadwm; do ohmychadwm && continue || break; done` only
  re-execs the `ohmychadwm` binary on Super+Shift+R — it never re-runs the
  autostart header. So the `run()` pgrep guard is defensive, not load-bearing
  for in-place restarts. Keybindings verified against
  `chadwm/config.def.h` (restart = `MODKEY|ShiftMask, XK_r`).

### Files Modified
- `scripts/run.sh`
- `CHANGELOG.md` (created)
