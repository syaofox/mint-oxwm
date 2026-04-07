# AGENTS.md — mint-oxwm

## What this repo is

A **Linux Mint 22.3 post-install setup** for OXWM (a Zig-based dynamic window manager). It is **not** a software library or app — it is a collection of bash scripts and X11 dotfiles deployed to `~/.config/` on the target machine.

## Directory structure

| Path | Purpose |
|---|---|
| `install.sh` | Main entry point — 7-step interactive installer (whiptail menu) |
| `dotfiles/` | Config templates deployed to `~/.config/` and `~/.local/share/` |
| `dotfiles/oxwm/` | OXWM `config.lua` + `oxwm-start.sh` (session launcher) |
| `dotfiles/dunst/`, `picom/`, `rofi/` | Notification, compositor, launcher configs |
| `dotfiles/nemo/` | Nemo file manager actions (`.nemo_action`) and scripts (`.sh`) |
| `tools/` | Standalone utility scripts (backup, restore, software install, btrfs, zram) |
| `walls/` | Wallpaper images copied to `~/Pictures/wallpapers/` |
| `docs/计划.md` | Original install plan (Chinese) |

## Key commands

```bash
bash install.sh              # Run the full 7-step interactive installer
bash tools/backup-configs.sh # Interactive backup of user configs (whiptail)
bash tools/restore-configs.sh# Interactive restore from backups/
bash tools/install-software.sh # Install Brave/Chrome/VSCode/Docker (whiptail)
bash tools/mint_btrfs.sh     # Btrfs subvolume optimization (requires sudo)
bash tools/setup_zram.sh     # ZRAM swap setup (requires sudo)
```

## Critical constraints

- **All scripts require `whiptail`** (`sudo apt install whiptail`) — they fail without it
- **Never run scripts as root** — `install.sh`, `backup-configs.sh`, `install-software.sh` check `$EUID` and exit. Only `mint_btrfs.sh` and `setup_zram.sh` require sudo
- **OXWM is NOT in this repo** — it is cloned from `github.com/syaofox/oxwm` to `/tmp/oxwm` during install and built with `zig build -Doptimize=ReleaseSmall`
- **Zig version is pinned to 0.15.2** — installed to `/opt/zig-<arch>-linux-0.15.2/` with symlink at `/usr/local/bin/zig`
- **OXWM config is Lua** — `config.lua` at `~/.config/oxwm/config.lua`. Reloadable at runtime via `Mod+Shift+R` (no rebuild needed)
- **Session entry point** is `~/.config/oxwm/oxwm-start.sh` — sets fcitx5 IME env vars, starts picom/dunst/rofi/pasystray/clipman, then `exec oxwm`
- **Default wallpaper**: `black-nord.png` (referenced in `oxwm-start.sh`)
- **Nerd Font**: JetBrains Mono v3.4.0, installed to `~/.local/share/fonts/`

## OXWM config conventions

- **modkey**: `Mod4` (Super/Windows key)
- **terminal**: `gnome-terminal`
- **layouts**: tiling, normie (floating), grid, monocle, tabbed
- **key launcher**: `Mod+D` → rofi drun with `theme.rasi`
- **screenshot**: `Mod+S` → maim selection to clipboard via xclip
- **power menu**: `Ctrl+Alt+Delete` → rofi sysact.sh

## Tools script dependencies

- `backup-configs.sh` / `restore-configs.sh` — store archives in `backups/` at project root
- `mint_btrfs.sh` — requires btrfs root filesystem, modifies `/etc/fstab` and sysctl, requires reboot
- `setup_zram.sh` — creates systemd service `zram-setup.service`, sets swappiness=150
