# default.nix by poligle (thinkpad)

{ config, lib, pkgs, ... }:
{
    imports = 
    [
        ./hardware-configuration.nix
        ../../modules/boot.nix
        ../../modules/network.nix
        ../../modules/locale.nix
        ../../modules/audio.nix
        ../../modules/hardware.nix
        ../../modules/users.nix
        ../../modules/packages.nix
        ../../modules/hyprland.nix
        ../../modules/regreet.nix
        ../../modules/desktop.nix
        ../../modules/storage.nix
        ../../modules/services.nix
        ../../modules/nix.nix
        ../../modules/plymouth.nix
        ../../modules/stylix.nix
        ../../modules/virtualisation.nix
        ../../modules/wireshark.nix
        ../../modules/direnv.nix
        ../../modules/nihil.nix
    ];
    programs.zsh.enable = true;
    
    # Host-specific
    networking.hostName = "vm";

	services.openssh.enable = true;
	services.spice-vdagentd.enable = true;
	services.qemuGuest.enable = true;

    # NIHIL: outputs at their logical size (after rotation), so the
    # dot-matrix wallpapers land on exact pixels, plus their Hyprland mode
    # and position. A QEMU guest has one output, Virtual-1.
    nihil =
    {
        primaryOutput = "Virtual-1";
        wallpaper = "night";
        language = "en";
        outputs =
        {
            "Virtual-1" = { width = 3840; height = 2160; mode = "3840x2160@60"; position = "0x0"; };
        };

        # Nilo on the Radeon of the Ryzen, through Vulkan. Set enable = false
        # to drop it (and Ollama) altogether.
        nilo =
        {
            enable = false;
            acceleration = "vulkan";
            integratedGpu = true;
        };
    };
    system.stateVersion = "26.05";
}
