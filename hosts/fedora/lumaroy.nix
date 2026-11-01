# lumaroy.nix by poligle (fedora)
#
# The user lumaroy, on the Fedora VM and on the laptop alike. zsh, Neovim
# and VS Code stay with his own dotfiles (stow), so NIHIL leaves them out;
# kitty keeps its own installer and NIHIL only writes kitty.conf.

{ config, lib, pkgs, ... }:
{
	home.username = "lumaroy";
	home.homeDirectory = "/home/lumaroy";

	nihil.apps =
	{
		zsh.enable = false;
		nvim.enable = false;
		vscode.enable = false;
		engineering.enable = false;
	};

	# kitty from ~/.local/kitty.app: it uses Fedora's drivers, no GPU wrapper.
	programs.kitty.package = null;
	nihil.terminal = "${config.home.homeDirectory}/.local/bin/kitty";

	nihil =
	{
		wallpaper = "night";
		language = "en";
		nilo =
		{
			enable = true;
			flake = "~/nihil";
		};
	};
}
