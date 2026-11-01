# g513.nix by poligle (fedora)
#
# ASUS ROG Strix G513QR: Radeon (eDP-1, HDMI-A-1) and RTX 3070 (DP-1). The
# outputs follow the GNOME layout: the 4K LG on DP-1 first, the laptop panel
# to its right. Rendering on the Radeon (AQ_DRM_DEVICES) is FEDORA.md 10.4.

{ config, lib, pkgs, ... }:
{
	# Hyprland renders on the Radeon and hands DP-1 to the RTX 3070. uwsm
	# reads this before starting Hyprland, which needs it at launch; the
	# names come from fedora/machines/g513/etc/udev/rules.d/61-nihil-gpu.rules.
	xdg.configFile."uwsm/env-hyprland".text =
		"export AQ_DRM_DEVICES=/dev/dri/amd-igpu:/dev/dri/nvidia-dgpu\n";

	nihil =
	{
		hostName = "lumaroy";
		primaryOutput = "DP-1";
		outputs =
		{
			"DP-1"  = { width = 3840; height = 2160; mode = "3840x2160@60"; position = "0x0"; };
			"eDP-1" = { width = 1920; height = 1080; position = "3840x229"; };
		};
	};
}
