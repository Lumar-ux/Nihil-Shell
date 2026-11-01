# hypridle.nix by poligle

{ config, pkgs, ... }:
let
	host = config.nihil.hostPrograms;
	brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
	dpms = state: "${host.hyprctl} dispatch 'hl.dsp.dpms({ action = \"${state}\" })'";
in
{
	services.hypridle =
	{
		enable = true;

		settings =
		{
			general =
			{
				lock_cmd = "pidof hyprlock || ${host.hyprlock}";
				before_sleep_cmd = "loginctl lock-session";
				after_sleep_cmd = dpms "on";
			};

			listener =
			[
				{
					timeout = 150;
					on-timeout = "${brightnessctl} -s set 10";
					on-resume = "${brightnessctl} -r";
				}
				{
					timeout = 240;
					on-timeout = "loginctl lock-session";
				}
				{
					timeout = 270;
					on-timeout = dpms "off";
					on-resume = dpms "on";
				}
				{
					timeout = 900;
					on-timeout = "systemctl suspend";
				}
			];
		};
	};
}
