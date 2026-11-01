# vscode.nix by poligle

{ config, pkgs, lib, ... }:
let
    foreground = "#${config.nihil.tokens.base16.base05}";
in
{
    options.nihil.apps.vscode.enable = lib.mkOption
    {
        type = lib.types.bool;
        default = true;
        description = "Whether Home Manager sets up VS Code with the NIHIL theme. A host that keeps its own dotfiles for it turns this off.";
    };

    config = lib.mkIf config.nihil.apps.vscode.enable
    {
        programs.vscode = 
        {
            enable = true;
            package = pkgs.vscode.fhs;

            profiles.default.extensions = with pkgs.vscode-extensions; 
            [
                ms-python.python
                ms-toolsai.jupyter
            ];

            profiles.default.userSettings = 
            {
                "python.defaultInterpreterPath" = "~/.nix-profile/bin/python";

                # NIHIL: red (base08) is reserved for errors, so variables and
                # tags use the plain foreground instead.
                "editor.tokenColorCustomizations".textMateRules =
                [
                    {
                        scope = [ "variable" "variable.other" "variable.parameter" "support.variable" "entity.name.tag" "meta.definition.variable" ];
                        settings.foreground = foreground;
                    }
                ];
                "editor.semanticTokenColorCustomizations".rules =
                {
                    variable = foreground;
                    parameter = foreground;
                    property = foreground;
                };
            };
        };
    };
}
