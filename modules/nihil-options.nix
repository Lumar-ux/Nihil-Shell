# nihil-options.nix by poligle
#
# The NIHIL options alone, with nothing NixOS-specific, so that both NixOS
# (modules/nihil.nix) and Home Manager can import them. On NixOS the host
# sets them and modules/nihil.nix hands the values to Home Manager; on
# another distribution (FEDORA.md) a standalone Home Manager host sets them
# itself. Home Manager modules read config.nihil, never osConfig.

{ config, lib, pkgs, ... }:
let
    cfg = config.nihil;

    outputType = lib.types.submodule
    {
        options =
        {
            width = lib.mkOption
            {
                type = lib.types.ints.positive;
                description = "Logical width in px, after rotation.";
            };
            height = lib.mkOption
            {
                type = lib.types.ints.positive;
                description = "Logical height in px, after rotation.";
            };
            bar = lib.mkOption
            {
                type = lib.types.bool;
                default = true;
                description = "Whether the frame widens into the bar on this output.";
            };
            pitch = lib.mkOption
            {
                type = lib.types.ints.positive;
                default = 9;
                description = "Distance between wallpaper dots in px.";
            };
            mode = lib.mkOption
            {
                type = lib.types.str;
                default = "preferred";
                example = "1920x1080@165";
                description = "Hyprland mode of this output.";
            };
            position = lib.mkOption
            {
                type = lib.types.str;
                default = "auto";
                example = "2560x-240";
                description = "Hyprland position of this output.";
            };
            scale = lib.mkOption
            {
                type = lib.types.number;
                default = 1;
                description = "Hyprland scale of this output.";
            };
            transform = lib.mkOption
            {
                type = lib.types.ints.between 0 7;
                default = 0;
                description = "Hyprland transform of this output (3: rotated 270°).";
            };
        };
    };

    # Programs that must come from the host: systemctl and journalctl talk
    # to its PID 1, hyprctl and uwsm to its compositor, and hyprlock needs
    # its PAM file. On NixOS they are the system packages; elsewhere, the
    # distribution's binaries.
    hostProgram = name: package: binary: lib.mkOption
    {
        type = lib.types.str;
        default = if cfg.platform == "nixos" then "${package}/bin/${binary}" else "/usr/bin/${binary}";
        defaultText = lib.literalMD "`${binary}` from `pkgs.${name}` on NixOS, `/usr/bin/${binary}` elsewhere";
        description = "Absolute path of the host's `${binary}`.";
    };

    modelType = lib.types.submodule
    {
        options =
        {
            tag = lib.mkOption
            {
                type = lib.types.str;
                example = "qwen3.5:9b";
                description = "Model name on ollama.com/library.";
            };
            label = lib.mkOption
            {
                type = lib.types.str;
                description = "Name shown in the shell.";
            };
            size = lib.mkOption
            {
                type = lib.types.number;
                description = "Download size in GB.";
            };
            ram = lib.mkOption
            {
                type = lib.types.number;
                description = ''
                    Memory it takes once loaded, in GB, roughly. The shell recommends
                    the largest model that fits in 45 % of the RAM.
                '';
            };
        };
    };
in
{
    options.nihil =
    {
        platform = lib.mkOption
        {
            type = lib.types.enum [ "nixos" "fedora" ];
            default = "nixos";
            description = "Where NIHIL runs: it picks the defaults of hostPrograms.";
        };

        hostName = lib.mkOption
        {
            type = lib.types.str;
            description = "Host name, for Nilo. On NixOS, networking.hostName.";
        };

        hostPrograms =
        {
            systemctl = hostProgram "systemd" pkgs.systemd "systemctl";
            journalctl = hostProgram "systemd" pkgs.systemd "journalctl";
            hyprctl = hostProgram "hyprland" pkgs.hyprland "hyprctl";
            uwsm = hostProgram "uwsm" pkgs.uwsm "uwsm";
            hyprlock = hostProgram "hyprlock" pkgs.hyprlock "hyprlock";
        };

        terminal = lib.mkOption
        {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/home/lumaroy/.local/bin/kitty";
            description = ''
                Absolute path of the terminal the shell opens. Null: the kitty that
                Home Manager installs in the profile. Set it when kitty comes from
                elsewhere (programs.kitty.package = null).
            '';
        };

        tokens = lib.mkOption
        {
            type = lib.types.attrs;
            default = import ../theme/nihil.nix;
            readOnly = true;
            description = "NIHIL design tokens (theme/nihil.nix).";
        };

        outputs = lib.mkOption
        {
            type = lib.types.attrsOf outputType;
            default = { };
            description = "Outputs of this host, keyed by connector name.";
        };

        primaryOutput = lib.mkOption
        {
            type = lib.types.str;
            description = "Output for the desktop widgets and the lock/login backgrounds.";
        };

        internalOutput = lib.mkOption
        {
            type = lib.types.str;
            default = "eDP-1";
            description = "The laptop's own panel: Hyprland turns it off with the lid closed and another output on.";
        };

        verticalOutput = lib.mkOption
        {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "DP-1";
            description = "An output in portrait, whose workspaces stack windows top to bottom.";
        };

        wallpaper = lib.mkOption
        {
            type = lib.types.str;
            default = "night";
            description = "Default wallpaper: a file name in wallpapers/ without extension.";
        };

        language = lib.mkOption
        {
            type = lib.types.enum [ "es" "en" ];
            default = "es";
            description = "Language of the shell, lock screen, greeter and script messages (theme/i18n.nix).";
        };

        strings = lib.mkOption
        {
            type = lib.types.attrsOf lib.types.str;
            default = (import ../theme/i18n.nix).${cfg.language};
            defaultText = lib.literalExpression "(import ../theme/i18n.nix).\${config.nihil.language}";
            readOnly = true;
            description = "Strings of the selected language.";
        };

        trayHidden = lib.mkOption
        {
            type = lib.types.listOf lib.types.str;
            default = [ "nm-applet" "blueman" ];
            example = [ "nm-applet" "blueman" "steam" ];
            description = ''
                Tray items the bar leaves out, matched case-insensitively against
                part of each item's id or title. The Wi-Fi and Bluetooth applets
                are hidden because the bar has its own icons for both; they keep
                running for password and pairing prompts.
            '';
        };

        soundPack = lib.mkOption
        {
            type = lib.types.enum [ "nihil" "classic" ];
            default = "nihil";
            description = "Interface sounds: the NIHIL pack (sounds/nihil) or the previous ones (sounds/).";
        };

        sounds = lib.mkOption
        {
            type = lib.types.attrsOf lib.types.path;
            readOnly = true;
            description = "Sound file for each interface event, from the selected pack.";
        };

        wallpapers = lib.mkOption
        {
            type = lib.types.package;
            readOnly = true;
            description = "Dot-matrix renders of every wallpaper for every output.";
        };

        fonts = lib.mkOption
        {
            type = lib.types.package;
            readOnly = true;
            description = "NIHIL font families.";
        };

        # Nilo (modules/nilo.nix runs Ollama on NixOS).
        nilo =
        {
            enable = lib.mkEnableOption "Nilo, the shell's assistant, with a local model on Ollama";

            acceleration = lib.mkOption
            {
                type = lib.types.enum [ "cpu" "vulkan" "rocm" "cuda" ];
                default = "cpu";
                example = "vulkan";
                description = ''
                    What runs the model: the CPU, or the GPU through Vulkan (AMD, Intel,
                    NVIDIA), ROCm (AMD) or CUDA (NVIDIA).
                '';
            };

            integratedGpu = lib.mkOption
            {
                type = lib.types.bool;
                default = false;
                description = ''
                    Let Ollama use an integrated GPU, like the Radeon of a Ryzen laptop
                    with `acceleration = "vulkan"`. Ollama leaves them out unless told
                    (`OLLAMA_IGPU_ENABLE`), since a weak one can be slower than the CPU.
                '';
            };

            ollamaUrl = lib.mkOption
            {
                type = lib.types.str;
                default = "http://127.0.0.1:11434";
                description = "Where Nilo reaches Ollama. On NixOS, services.ollama's host and port.";
            };

            flake = lib.mkOption
            {
                type = lib.types.str;
                default = "~/nixos-config";
                example = "~/nihil";
                description = "Where Nilo tells you this configuration lives (shown in its prompts, not expanded).";
            };

            models = lib.mkOption
            {
                type = lib.types.listOf modelType;
                # Download sizes from ollama.com/library/qwen3.5 (default tags);
                # memory is an estimate with Nilo's context.
                default =
                [
                    { tag = "qwen3.5:0.8b"; label = "Qwen 3.5 · 0.8B"; size = 1.3; ram = 2; }
                    { tag = "qwen3.5:2b"; label = "Qwen 3.5 · 2B"; size = 2.7; ram = 3.5; }
                    { tag = "qwen3.5:4b"; label = "Qwen 3.5 · 4B"; size = 3.4; ram = 5; }
                    { tag = "qwen3.5:9b"; label = "Qwen 3.5 · 9B"; size = 6.6; ram = 8.5; }
                    { tag = "qwen3.5:35b-a3b"; label = "Qwen 3.5 · 35B-A3B"; size = 22; ram = 25; }
                ];
                description = ''
                    Models offered in Nilo's settings. Any model on ollama.com/library
                    that supports tools works; others installed with `ollama pull` show
                    up too.
                '';
            };

            contextLength = lib.mkOption
            {
                type = lib.types.ints.between 2048 262144;
                default = 16384;
                description = "Context window Nilo asks for, in tokens: more remembers more and takes more memory.";
            };

            searxng = lib.mkOption
            {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "http://127.0.0.1:8888";
                description = ''
                    A SearXNG instance (with the JSON format enabled) for Nilo's web
                    searches. By default it searches DuckDuckGo through ddgr.
                '';
            };
        };
    };

    config =
    {
        assertions =
        [
            {
                assertion = cfg.outputs ? ${cfg.primaryOutput};
                message = "nihil.primaryOutput must be one of nihil.outputs.";
            }
            {
                assertion = cfg.verticalOutput == null || cfg.outputs ? ${cfg.verticalOutput};
                message = "nihil.verticalOutput must be null or one of nihil.outputs.";
            }
            {
                assertion = builtins.elem cfg.wallpaper cfg.wallpapers.names;
                message = "nihil.wallpaper must match a file in wallpapers/.";
            }
            {
                assertion = let languages = builtins.attrValues (import ../theme/i18n.nix); in
                    lib.all (strings: builtins.attrNames strings == builtins.attrNames (lib.head languages)) languages;
                message = "theme/i18n.nix: every language needs the same keys.";
            }
        ];

        nihil.wallpapers = import ../theme/wallpapers.nix { inherit pkgs lib; outputs = cfg.outputs; };
        nihil.fonts = import ../theme/fonts.nix { inherit pkgs; };

        nihil.sounds =
            let
                freedesktop = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";
                events = [ "switch" "open" "close" "special" "fullscreen" "lock" "power" "menu" "notify" "critical" "volume" ];
            in
            if cfg.soundPack == "nihil" then
                lib.genAttrs events (event: ../sounds/nihil + "/${event}.ogg")
            else
                lib.genAttrs [ "switch" "open" "close" "special" "fullscreen" "lock" "power" "menu" ] (event: ../sounds + "/${event}.ogg")
                // {
                    notify = "${freedesktop}/message.oga";
                    critical = "${freedesktop}/dialog-error.oga";
                    volume = "${freedesktop}/audio-volume-change.oga";
                };
    };
}
