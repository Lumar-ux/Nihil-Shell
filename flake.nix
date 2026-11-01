# flake.nix by poligle

{
	description = "NixOS Config for poligle@thinkpad";

	inputs = 
	{
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

		home-manager = 
		{
			url = "github:nix-community/home-manager/release-26.05";
			inputs.nixpkgs.follows = "nixpkgs";
		};

        stylix = 
		{
			url = "github:nix-community/stylix/release-26.05";
			inputs.nixpkgs.follows = "nixpkgs";
		};

        zen-browser = {
            url = "github:0xc000022070/zen-browser-flake";
            inputs = {
                home-manager.follows = "home-manager";
            };
        };
	};
	outputs = inputs@{ self, nixpkgs, home-manager, stylix, zen-browser , ... }:
	{
		nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem 
		{
			system = "x86_64-linux";
			modules = [
				./hosts/thinkpad/default.nix
                stylix.nixosModules.stylix

				home-manager.nixosModules.home-manager
				{
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;
					home-manager.backupFileExtension = "hm-backup";

                    home-manager.extraSpecialArgs = { inherit inputs; };
					home-manager.users.poligle = ./home.nix;
				}
			];
		};
		nixosConfigurations.vm = nixpkgs.lib.nixosSystem 
		{
			system = "x86_64-linux";
			modules = [
				./hosts/vm/default.nix
                stylix.nixosModules.stylix

				home-manager.nixosModules.home-manager
				{
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;
					home-manager.backupFileExtension = "hm-backup";

                    home-manager.extraSpecialArgs = { inherit inputs; };
					home-manager.users.poligle = ./home.nix;
				}
			];
		};

		# NIHIL on Fedora, Home Manager standalone (FEDORA.md):
		#   home-manager switch --flake ~/nihil#lumaroy@lumaroy
		homeConfigurations =
		let
			fedora = machine: home-manager.lib.homeManagerConfiguration
			{
				pkgs = import nixpkgs
				{
					system = "x86_64-linux";
					config.allowUnfree = true;
				};
				extraSpecialArgs = { inherit inputs; };
				modules =
				[
					stylix.homeModules.stylix
					./modules/nihil-options.nix
					./modules/stylix.nix
					./hosts/fedora/default.nix
					./hosts/fedora/lumaroy.nix
					machine
					./home.nix
				];
			};
		in
		{
			"lumaroy@lumaroy" = fedora ./hosts/fedora/g513.nix;
			"lumaroy@fedora-vm" = fedora ./hosts/fedora/vm.nix;
		};
	};
}
