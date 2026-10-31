# packages.nix by poligle

{ config, lib, pkgs, ... }:
{
    environment.systemPackages = with pkgs; 
    [
        wev
        wget
        git
        unzip
        lxqt.lxqt-policykit
        fastfetch
        btop
        brightnessctl
        playerctl
        trash-cli
        sound-theme-freedesktop
        claude-code
    ];

    nixpkgs.config.allowUnfree = true;

    # Lets generic Linux binaries (curl|sh installers, self-updaters like
    # `claude update`) find a dynamic loader on NixOS.
    programs.nix-ld.enable = true;

    fonts.packages = with pkgs; 
    [
        nerd-fonts.jetbrains-mono
        nerd-fonts.hack
    ];
}
