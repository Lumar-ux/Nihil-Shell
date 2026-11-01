# default.nix by poligle (home/nilo)
#
# Nilo's agent for the shell: agent.py with its configuration, wrapped as
# `nilo-agent`. home/shell.nix hands its path to the shell (Config.nilo);
# the shell starts it the first time Nilo opens and talks to it over
# stdin/stdout. Tests: python3 -m unittest home/nilo/test_agent.py

# `nihil` is Home Manager's config.nihil (modules/nihil-options.nix).
{ pkgs, lib, nihil }:
let
    config = pkgs.writeText "nilo.json" (builtins.toJSON
    {
        ollama = nihil.nilo.ollamaUrl;
        inherit (nihil) language;
        inherit (nihil.nilo) models contextLength searxng;
        ddgr = "${pkgs.ddgr}/bin/ddgr";
        git = "${pkgs.git}/bin/git";
        host = nihil.hostName;
        inherit (nihil.nilo) flake;
        # To start Ollama when it is down, and say why it won't (modules/nilo.nix).
        # The host's own systemd: only it talks to the PID 1.
        inherit (nihil.hostPrograms) systemctl journalctl;
        ollamaUnit = "ollama.service";
    });
in
pkgs.writeShellScriptBin "nilo-agent" ''
    exec ${pkgs.python3}/bin/python3 -I ${./agent.py} --config ${config} "$@"
''
