# nilo.nix by poligle
#
# Nilo: an optional assistant in the shell, with a local model on Ollama.
# Off by default. With `nihil.nilo.enable` the system runs Ollama on
# 127.0.0.1 and the shell gets Nilo (SUPER+I, the Copilot key, "?" in the
# launcher). The model, what Nilo may do and how long it stays awake are
# chosen in the shell and need no rebuild; this file decides whether it
# exists, what runs the model and that Nilo may start Ollama when it is down.

{ config, lib, pkgs, ... }:
let
    cfg = config.nihil.nilo;

    packages =
    {
        cpu = pkgs.ollama-cpu;
        vulkan = pkgs.ollama-vulkan;
        rocm = pkgs.ollama-rocm;
        cuda = pkgs.ollama-cuda;
    };
in
{
    # Options: modules/nihil-options.nix (nihil.nilo).
    config = lib.mkIf cfg.enable
    {
        services.ollama =
        {
            enable = true;
            package = packages.${cfg.acceleration};
            environmentVariables = lib.mapAttrs (_: lib.mkDefault) (
            {
                # Nilo sends its own keep-alive (its settings); this one is for
                # everything else that talks to Ollama.
                OLLAMA_KEEP_ALIVE = "5m";
                # One model in memory at a time: switching models frees the old one.
                OLLAMA_MAX_LOADED_MODELS = "1";
                # Local only: no models that run on ollama.com.
                OLLAMA_NO_CLOUD = "1";
            }
            // lib.optionalAttrs cfg.integratedGpu { OLLAMA_IGPU_ENABLE = "1"; });
        };

        # The upstream unit has no Restart=: if Ollama stops on its own (a
        # crash, the GPU not ready yet at boot) it stays down, and Nilo can
        # only say "connection refused". Back off up to a minute between tries.
        systemd.services.ollama.serviceConfig =
        {
            Restart = lib.mkDefault "on-failure";
            RestartSec = lib.mkDefault "2s";
            RestartSteps = lib.mkDefault 5;
            RestartMaxDelaySec = lib.mkDefault "1min";
        };

        # Nilo starts Ollama when it finds it stopped (and with its "start
        # ollama" button): polkit lets wheel users start or restart this one
        # unit without a password. Nothing else about systemd changes.
        security.polkit.enable = lib.mkDefault true;
        security.polkit.extraConfig = ''
            polkit.addRule(function(action, subject)
            {
                if (action.id == "org.freedesktop.systemd1.manage-units"
                    && action.lookup("unit") == "ollama.service"
                    && (action.lookup("verb") == "start" || action.lookup("verb") == "restart")
                    && subject.isInGroup("wheel"))
                    return polkit.Result.YES;
            });
        '';
    };
}
