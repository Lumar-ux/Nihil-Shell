# default.nix by poligle (fedora)
#
# NIHIL on Fedora with Home Manager standalone (FEDORA.md): what the NixOS
# modules did for the user and Home Manager does here. The system side
# (Hyprland, hyprlock and its PAM file, uwsm, greetd, polkit, Ollama) comes
# from dnf and /etc, FEDORA.md section 5.

{ config, lib, pkgs, ... }:
{
	# XDG_DATA_DIRS, locales and terminfo outside NixOS. It also turns on
	# targets.genericLinux.gpu: the Mesa drivers for the Nix binaries
	# (Quickshell, awww), which the first switch installs with sudo.
	targets.genericLinux.enable = true;

	# fonts.packages on NixOS (modules/nihil.nix, modules/packages.nix).
	fonts.fontconfig.enable = true;
	home.packages =
	[
		config.nihil.fonts
		pkgs.nerd-fonts.jetbrains-mono
		pkgs.nerd-fonts.hack
	];

	# systemctl, journalctl, hyprctl, uwsm and hyprlock from /usr/bin.
	nihil.platform = "fedora";

	# hyprlock from dnf: it brings /etc/pam.d/hyprlock, without which a Nix
	# hyprlock could not check the password. Home Manager writes its config.
	programs.hyprlock.package = null;

	# GNOME stays installed as the fallback session: Stylix keeps out of its
	# shell theme and background. The GTK settings (theme, fonts, cursor) live
	# in the same dconf and are shared, since the apps under Hyprland read them.
	stylix.targets.gnome.enable = false;
}
