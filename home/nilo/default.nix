# default.nix by poligle (home/nilo)
#
# Nilo's agent for the shell: agent.py with its configuration, wrapped as
# `nilo-agent`. home/shell.nix hands its path to the shell (Config.nilo);
# the shell starts it the first time Nilo opens and talks to it over
# stdin/stdout. Tests: python3 -m unittest home/nilo/test_agent.py

# `nihil` is Home Manager's config.nihil (modules/nihil-options.nix), `user`
# its home.username.
{ pkgs, lib, nihil, user }:
let
    flake = nihil.nilo.flake;
    host = nihil.hostName;

    # What Nilo tells you to run after a change: the system on NixOS, the
    # Home Manager target <user>@<host> elsewhere (flake.nix, FEDORA.md).
    apply =
        if nihil.platform == "nixos"
        then "sudo nixos-rebuild switch --flake ${flake}#${host}"
        else "home-manager switch --flake ${flake}#${user}@${host}";

    config = pkgs.writeText "nilo.json" (builtins.toJSON
    {
        ollama = nihil.nilo.ollamaUrl;
        inherit (nihil) language;
        inherit (nihil.nilo) models contextLength searxng;
        ddgr = "${pkgs.ddgr}/bin/ddgr";
        git = "${pkgs.git}/bin/git";
        inherit host flake apply;
        inherit (nihil) platform;
        # To start Ollama when it is down, and say why it won't (modules/nilo.nix).
        # The host's own systemd: only it talks to the PID 1.
        inherit (nihil.hostPrograms) systemctl journalctl;
        ollamaUnit = "ollama.service";
    });
in
pkgs.writeShellScriptBin "nilo-agent" ''
    exec ${pkgs.python3}/bin/python3 -I ${./agent.py} --config ${config} "$@"
''
