# nihil.nix by poligle
#
# NIHIL on NixOS: the options (modules/nihil-options.nix), what only the
# system can do (fonts, UPower, Ollama in modules/nilo.nix), and the values
# the host set, handed to every Home Manager user so that its modules read
# config.nihil exactly as the system sees it. Each host describes its
# outputs; everything else comes from theme/.

{ config, lib, options, ... }:
let
    cfg = config.nihil;
    ollama = config.services.ollama;
in
{
    imports = [ ./nihil-options.nix ./nilo.nix ];

    config = lib.mkMerge
    [
        {
            nihil.hostName = lib.mkDefault config.networking.hostName;
            nihil.nilo.ollamaUrl = lib.mkDefault "http://${ollama.host}:${toString ollama.port}";
            nihil.hostPrograms =
            {
                systemctl = lib.mkDefault "${config.systemd.package}/bin/systemctl";
                journalctl = lib.mkDefault "${config.systemd.package}/bin/journalctl";
                hyprctl = lib.mkDefault "${config.programs.hyprland.package}/bin/hyprctl";
                uwsm = lib.mkDefault "${config.programs.uwsm.package}/bin/uwsm";
            };

            fonts.packages = [ cfg.fonts ];

            # The shell reads the battery through UPower (D-Bus); waybar used to
            # read /sys directly, so nothing had enabled it before.
            services.upower.enable = lib.mkDefault true;
        }

        # Only the settable options cross over: the read-only ones (tokens,
        # strings, sounds, wallpapers, fonts) are derived again on that side.
        (lib.optionalAttrs (options ? home-manager)
        {
            home-manager.sharedModules =
            [
                ./nihil-options.nix
                {
                    nihil =
                    {
                        inherit (cfg)
                            platform hostName hostPrograms terminal outputs primaryOutput
                            internalOutput verticalOutput wallpaper language
                            trayHidden soundPack nilo;
                    };
                }
            ];
        })
    ];
}
