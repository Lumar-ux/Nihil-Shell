# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NIHIL: a personal NixOS flake (Flakes + Home Manager + Stylix) whose centrepiece is a desktop shell written from scratch in Quickshell/QML. It has a monochrome dot-matrix design language: greys build the hierarchy, red (`signal`) only interrupts and is never decoration, the frame is opaque with no shadows. README.md is the user-facing reference for options, keybindings and Nilo.

## Commands

    # Flakes only see git-tracked files: `git add` new files before building
    nix flake check                                   # evaluate/validate (alias: ncheck)
    sudo nixos-rebuild build  --flake .#<host>        # build without activating
    sudo nixos-rebuild switch --flake .#<host>        # apply (or `nh os switch`)
    nix flake update                                  # bump inputs

    # Fedora targets (Home Manager standalone, FEDORA.md)
    home-manager build  --flake .#lumaroy@lumaroy     # or lumaroy@fedora-vm
    home-manager switch --flake .#lumaroy@lumaroy -b hm-backup

    # A refactor that must not change a NixOS host: its drvPath stays the same
    nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath

    # Nilo agent tests (fake Ollama, fake ddgr, throwaway git repo; no network)
    python3 -m unittest home/nilo/test_agent.py
    cd home/nilo && python3 -m unittest test_agent.AgentTest.test_stop   # single test

    # Running shell
    journalctl --user -u nihil-shell -f
    nihil-ipc drawers toggle launcher|dashboard|panel ; nihil-ipc glyph test true

Targets in flake.nix:

- `nixosConfigurations`: `thinkpad` (the real laptop) and `vm` (a QEMU guest, output `Virtual-1`).
- `homeConfigurations`: `lumaroy@lumaroy` (ASUS G513QR on Fedora) and `lumaroy@fedora-vm` (its test VM), built from `hosts/fedora/`: `default.nix` is the Fedora layer, `lumaroy.nix` the user's choices, `g513.nix` and `vm.nix` the outputs of each machine. The system side on Fedora (Hyprland, hyprlock's PAM file, uwsm, /etc) is imperative: FEDORA.md.

The shell aliases (`nrebuild`, `nupdate`, `ncheck` in home/zsh.nix) hardcode `~/nixos-config#thinkpad`, and `nihil.nilo.flake` defaults to `~/nixos-config`. This checkout lives at `~/nihil`, so pass the path and target explicitly.

## Architecture

- **One source of design truth:** `theme/nihil.nix` is plain data (palette, base16, fonts, frame geometry, window gaps, motion). Stylix, Hyprland, hyprlock, the greeter, Plymouth, editors and the shell all read it. Change tokens there, never in a consumer.
- **`nihil.*` options** are declared once, in `modules/nihil-options.nix`, with nothing NixOS-specific, so both NixOS and Home Manager import it. On NixOS the host sets them and `modules/nihil.nix` hands the settable ones to every Home Manager user (`home-manager.sharedModules`); a Fedora target sets them itself. Home Manager modules read `config.nihil`, never `osConfig`. Each host sets `outputs`, `primaryOutput`, `language` and `nilo`.
  - `outputs` also carry their Hyprland `mode`, `position`, `scale` and `transform`; `internalOutput` (lid handling) and `verticalOutput` are options. No module names a connector.
  - `hostPrograms` (`systemctl`, `journalctl`, `hyprctl`, `uwsm`, `hyprlock`): binaries that must be the host's, because they talk to its PID 1 or compositor or need its PAM file. System packages on NixOS, `/usr/bin` when `platform = "fedora"`.
  - `nihil.apps.{zsh,nvim,vscode,engineering}.enable` (declared in those modules, on by default) let a host keep its own dotfiles.
  - Read-only derived options: `tokens`, `strings`, `sounds`, `wallpapers`, `fonts`. Assertions check that `primaryOutput` and `verticalOutput` are in `outputs`, that `wallpaper` exists in `wallpapers/`, and that all languages have identical keys.
  - `modules/nilo.nix` only runs Ollama on NixOS; Nilo's options are in `nihil-options.nix` too.
- **i18n:** every user-facing string lives in `theme/i18n.nix`, one block per language. Every block must define the same keys, or evaluation fails. To add a language, add a block and extend the `language` enum.
- **Shell** (`home/shell/`, run as the `nihil-shell` user service): `home/shell.nix` *generates* `Tokens.qml`, `Config.qml` and `Lang.qml` at build time. They do not exist in the tree. `home/shell.nix` also injects every external program as an absolute path (a Nix store path, or one from `nihil.hostPrograms` / `nihil.terminal`), so the shell never relies on `$PATH`. New external tools must be added there, not called by bare name from QML. QML imports use the `qs.*` module root (`qs.services`, `qs.frame`, …). `shell.qml` force-instantiates the singleton services that must run from startup.
  - `frame/`: a single path forms the screen frame, with the drawers drawn as bumps of it (`Geometry.js`), plus the bar and the Glyph edge light.
  - `drawers/`, `services/`, `components/`, `nilo/`: see the README's Shell section.
  - Keyboard-taking drawers use `WlrKeyboardFocus.OnDemand` with `HyprlandFocusGrab`. Do not use `Exclusive`: Hyprland drops focus grabs when a layer goes exclusive.
- **Hyprland is configured in Lua:** Home Manager generates `hyprland.lua` from `home/hyprland.nix`, so dispatchers are written as Lua (`hl.dsp.focus({ workspace = "e+1" })`). Stylix's Hyprland target is off; NIHIL sets the colours itself.
- **Nilo** (optional, `nihil.nilo.enable`): `home/nilo/agent.py` is standard-library-only Python. It runs with `python3 -I` and gets a generated JSON config from `home/nilo/default.nix`. It talks to the shell over stdin/stdout (`services/Nilo.qml`) and to Ollama over HTTP. File and git tools are confined to one chosen repository, never touch `.git`, and require user confirmation. Keep it free of third-party dependencies.
- **Build-time renders:** `theme/wallpapers.nix` runs `theme/dotmatrix.py` once per wallpaper per output, at that output's logical size. Plymouth frames come from `theme/art/snowflake-29.txt`, and fastfetch uses `snowflake-19.txt`.
- **`tools/`** are one-off generators whose outputs are committed: `brand.py` (logos, favicons, site images; needs Pillow), `sounds.py` (writes `sounds/nihil/*.ogg`; needs numpy and ffmpeg) and `snowflake.py` (writes `theme/art/*.txt`). Re-run them only when changing those assets.
- **`docs/`** is the nihilshell.com website, served by GitHub Pages from that folder.

## Conventions

- Files start with a header comment: `# <file> by poligle`, followed by a short description of its role. Nix uses Allman-style braces (opening `{` on its own line).
- The repo is public: no secrets. Local state (passwords, SSH keys, `~/.config/eda/licenses.env`, `~/eda`) stays outside it.
