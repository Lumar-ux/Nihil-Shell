# vm.nix by poligle (fedora)
#
# The Fedora test VM (libvirt, virtio-gpu with 3D): one output, Virtual-1,
# like hosts/vm.

{ config, lib, pkgs, ... }:
{
	nihil =
	{
		hostName = "fedora-vm";
		primaryOutput = "Virtual-1";
		outputs =
		{
			"Virtual-1" = { width = 3840; height = 2160; mode = "3840x2160@60"; position = "0x0"; };
		};
	};
}
