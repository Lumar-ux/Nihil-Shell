# FEDORA.md by poligle

Guide pour faire tourner NIHIL sur Fedora au lieu de NixOS, en gardant
déclaratif tout ce qui peut l'être. Il décrit les changements à faire dans le
dépôt et sur le système. Rien n'est encore appliqué.

---

## 1. Principe

NIHIL est aujourd'hui en deux couches :

| Couche | Où | Sur Fedora |
|---|---|---|
| **Système** | `modules/*.nix`, `hosts/*/default.nix` (boot, PAM, greeter, polkit, udev, Ollama…) | Remplacée par `dnf`, `systemctl` et des fichiers dans `/etc` (section 5) |
| **Utilisateur** | `home.nix`, `home/*.nix`, `home/shell/`, `theme/` | Gardée telle quelle avec **Nix + Home Manager en mode standalone** |

On garde donc le flake. Il expose toujours `nixosConfigurations.{thinkpad,vm}`
et y ajoute `homeConfigurations."poligle@fedora"`. Les deux cibles doivent
continuer d'évaluer.

Hypothèse : **Fedora Workstation 43 ou plus récent** (dnf5, PipeWire,
NetworkManager, zram et SELinux sont actifs par défaut).
Sur Fedora Atomic (Silverblue, etc.), remplacez `dnf install` par
`rpm-ostree install`. L'installeur Determinate gère `/nix` sur un `/`
en lecture seule.

---

## 2. Installer Nix

```sh
# Determinate Nix Installer : multi-utilisateur, flakes activés, gère SELinux
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
# nouveau shell, puis :
nix --version
```

Premier déploiement (une fois la section 3 faite) :

```sh
cd ~/nihil
git add -A            # les flakes ne voient que les fichiers suivis par git
nix run home-manager/release-26.05 -- switch --flake .#poligle@fedora
```

Ensuite, `home-manager switch --flake ~/nihil#poligle@fedora` suffit.

---

## 3. Restructurer le flake

### 3.1 Ajouter une cible Home Manager standalone (`flake.nix`)

```nix
homeConfigurations."poligle@fedora" = home-manager.lib.homeManagerConfiguration
{
	pkgs = import nixpkgs
	{
		system = "x86_64-linux";
		config.allowUnfree = true;          # spotify, obsidian, vscode…
	};
	extraSpecialArgs = { inherit inputs; };
	modules =
	[
		stylix.homeModules.stylix
		./modules/nihil-options.nix          # voir 3.2
		./hosts/fedora/home.nix
		./home.nix
	];
};
```

### 3.2 Supprimer la dépendance à `osConfig`

C'est le gros du travail. Aujourd'hui tous les modules HM lisent la
configuration NixOS à travers `osConfig`, qui n'existe pas en standalone.

1. **Séparer `modules/nihil.nix`** en deux fichiers :
   - `modules/nihil-options.nix` : les *options* pures (`tokens`, `outputs`,
     `primaryOutput`, `wallpaper`, `language`, `strings`, `trayHidden`,
     `soundPack`, `sounds`, `wallpapers`, `fonts`), les assertions et le bloc
     `nihil.nilo.*` de `modules/nilo.nix`, sans rien de propre à NixOS. Ce
     module doit pouvoir être importé **à la fois** par NixOS et par Home Manager.
   - `modules/nihil.nix` (NixOS uniquement) : importe le précédent et garde
     `fonts.packages`, `services.upower`, puis `services.ollama` et polkit
     (`modules/nilo.nix`).
2. **Côté NixOS**, transmettre les valeurs à HM pour ne pas les dupliquer.
   Dans le bloc `home-manager` de `flake.nix`, importer
   `./modules/nihil-options.nix` dans `home-manager.sharedModules`.
   Dans `hosts/thinkpad/default.nix`, mettre
   `home-manager.users.poligle.nihil = { inherit (config.nihil) outputs primaryOutput wallpaper language nilo; };`.
   Sinon, déplacer le bloc `nihil = { … }` de l'hôte directement dans un
   module HM.
3. **Remplacer `osConfig.nihil` par `config.nihil`** dans :
   `home/shell.nix`, `home/hyprland.nix`, `home/hyprlock.nix`,
   `home/wallpaper.nix`, `home/scripts.nix`, `home/zsh.nix`, `home/nvim.nix`,
   `home/vscode.nix`, `home/engineering.nix`, `home/fastfetch.nix`,
   `home/nilo/default.nix`. Ce dernier reçoit `osConfig` en argument depuis
   `home/shell.nix` : passez-lui `config` à la place.
4. **Remplacer les autres `osConfig.*`** :

   | Référence actuelle | Remplacement |
   |---|---|
   | `osConfig.programs.hyprland.package` (`home/wallpaper.nix`, `home/refresh.nix`) | `pkgs.hyprland`, ou `/usr/bin/hyprctl` si Hyprland vient de dnf (section 4) |
   | `osConfig.programs.uwsm.package` (`home/shell.nix`) | `pkgs.uwsm`, ou `/usr/bin/uwsm` |
   | `osConfig.systemd.package` (`home/nilo/default.nix`) | `/usr/bin/systemctl` et `/usr/bin/journalctl` : il faut le systemd **de l'hôte** pour parler au PID 1 de Fedora |
   | `pkgs.systemd` dans `commands.systemctl` (`home/shell.nix`) et `power-off` (`home/scripts.nix`) | `/usr/bin/systemctl` (même raison) |
   | `osConfig.services.ollama.{host,port}` | nouvelle option `nihil.nilo.ollamaUrl` (défaut `http://127.0.0.1:11434`) |
   | `osConfig.networking.hostName` | nouvelle option `nihil.hostName` |

   Pour garder une seule source, on peut ajouter une option
   `nihil.platform = enum [ "nixos" "fedora" ]` et choisir les chemins avec
   `if config.nihil.platform == "fedora" then "/usr/bin/…" else "${pkgs.…}/bin/…"`.
   CLAUDE.md demande des chemins absolus plutôt que `$PATH`, et `/usr/bin/…`
   reste un chemin absolu.

### 3.3 Nouvel hôte : `hosts/fedora/home.nix`

```nix
# home.nix by poligle (fedora)

{ config, lib, pkgs, ... }:
{
	targets.genericLinux.enable = true;     # XDG_DATA_DIRS, locales, terminfo hors NixOS
	fonts.fontconfig.enable = true;          # remplace fonts.packages (système)
	home.packages = [ config.nihil.fonts pkgs.nerd-fonts.jetbrains-mono pkgs.nerd-fonts.hack ];

	nihil =
	{
		platform = "fedora";
		hostName = "fedora";
		primaryOutput = "eDP-1";
		wallpaper = "night";
		language = "es";
		outputs =
		{
			"eDP-1" = { width = 1920; height = 1200; };
		};
		nilo.enable = true;
	};
}
```

### 3.4 Stylix

- Utiliser `stylix.homeModules.stylix`. Le contenu de `modules/stylix.nix`
  (scheme, image, curseur, polices, opacités) peut être importé tel quel côté
  HM.
- Les cibles système `plymouth`, `regreet` et `console` n'existent pas en HM.
  Elles sont traitées à la main (section 5).
- Les lignes `stylix.targets.*` des modules HM (`hyprlock`, `zen-browser`)
  restent valables.

---

## 4. GPU / OpenGL hors NixOS

Les binaires Nix ne trouvent pas les pilotes Mesa de Fedora. Sans correctif,
Quickshell, kitty, Hyprland et hyprlock plantent au démarrage avec une erreur
EGL/GL.

**Recommandation : un modèle hybride.**

| Composant | Source | Pourquoi |
|---|---|---|
| Hyprland, hyprlock, hypridle, xdg-desktop-portal-hyprland, uwsm | **dnf** (COPR `solopasha/hyprland` pour des versions récentes) | Session, PAM (`/etc/pam.d/hyprlock`) et portails intégrés au système, sans souci de GL |
| Quickshell, kitty, awww | **Nix**, avec l'enveloppe GPU de Home Manager | Versions de nixpkgs exactes |
| Config (Lua Hyprland, hyprlock, hypridle…) | **Home Manager** | Inchangée |

Home Manager permet de garder les modules en mettant
`programs.hyprlock.package = null;`, `services.hypridle.package = …` (le
binaire système), etc.

Pour le GPU des binaires Nix, deux options :

- `targets.genericLinux.gpu.enable = true;` si votre version de Home Manager
  le propose (installe un lien `/run/opengl-driver`, demande un `sudo` au
  premier switch) ;
- sinon **nixGL** (`github:nix-community/nixGL`) : `config.lib.nixGL.wrap pkgs.quickshell`
  dans `home/shell.nix` et `home/kitty.nix`.

> ⚠️ La config Hyprland est en **Lua** (`hyprland.lua`, `hl.dsp.*`), ce qui
> exige un Hyprland très récent. Vérifiez que la version COPR la supporte
> (`hyprctl version`). Sinon, prenez Hyprland depuis Nix (`pkgs.hyprland` +
> nixGL) et lancez-le par une entrée de session dans
> `/usr/share/wayland-sessions/`.

---

## 5. Équivalents Fedora des modules système

Paquets de base :

```sh
sudo dnf copr enable solopasha/hyprland
sudo dnf install hyprland hyprlock hypridle uwsm xdg-desktop-portal-hyprland \
    zsh blueman thunar thunar-archive-plugin thunar-volman gvfs tumbler \
    lxqt-policykit fprintd-pam wireshark greetd cage brightnessctl playerctl \
    upower udisks2 openssh-server qt6ct wev
```

| Module NixOS | Action sur Fedora |
|---|---|
| `modules/boot.nix` | Fedora utilise GRUB2 + BLS. `systemd-boot` est possible mais rien ne l'impose. Pour garder 10 entrées : `installonly_limit=10` dans `/etc/dnf/dnf.conf`. `exfat`, `ext4` et `vfat` sont déjà supportés. |
| `modules/plymouth.nix` | `nix build --impure --expr 'let pkgs = import <nixpkgs> {}; in import ./theme/plymouth.nix { inherit pkgs; }'` (ou une sortie `packages.x86_64-linux.plymouth-nihil` ajoutée au flake), puis copier `share/plymouth/themes/nihil` dans `/usr/share/plymouth/themes/` et lancer `sudo plymouth-set-default-theme -R nihil`. Démarrage silencieux : `sudo grubby --update-kernel=ALL --args="quiet splash loglevel=3 udev.log_level=3 rd.udev.log_level=3 systemd.show_status=auto"`. |
| `modules/audio.nix` | Rien : PipeWire, pipewire-pulse et rtkit sont actifs par défaut. |
| `modules/network.nix` | NetworkManager est déjà là. Wi-Fi powersave : `/etc/NetworkManager/conf.d/wifi-powersave.conf` avec `[connection]` et `wifi.powersave = 2`. Options rtw89 : copier le bloc `extraModprobeConfig` dans `/etc/modprobe.d/rtw89.conf`. Bluetooth éteint au démarrage : `AutoEnable=false` dans `/etc/bluetooth/main.conf`, ou recopier l'unité `bluetooth-off-at-boot` dans `/etc/systemd/system/` (avec `/usr/bin/bluetoothctl`). |
| `modules/hardware.nix` | **Empreinte** : `sudo authselect enable-feature with-fingerprint`, puis `fprintd-enroll`. La règle « ignorer l'empreinte couvercle fermé » (`pam_exec` + script `lid-closed`) se met à la main : installer le script dans `/usr/local/libexec/lid-closed`, puis ajouter `auth [success=1 default=ignore] pam_exec.so quiet /usr/local/libexec/lid-closed` juste avant `pam_fprintd.so`. Comme authselect écrase `/etc/pam.d/system-auth`, passer par un **profil authselect personnalisé** (`authselect create-profile nihil -b local`). Garder `hyprlock` sans empreinte. **Couvercle** : `/etc/systemd/logind.conf.d/nihil.conf` avec `[Login]` et `HandleLidSwitch=ignore`, `HandleLidSwitchExternalPower=ignore`, `HandleLidSwitchDocked=ignore`. **LED micmute** : copier la règle `services.udev.extraRules` dans `/etc/udev/rules.d/90-micmute.rules` (avec `/usr/bin/chgrp` et `/usr/bin/chmod`), puis `sudo udevadm control --reload`. zram et libinput sont déjà actifs. |
| `modules/hyprland.nix` | dnf (section 4). UWSM fournit l'entrée de session « Hyprland (uwsm-managed) ». |
| `modules/regreet.nix` | `greetd` et `cage` sont dans les dépôts Fedora. ReGreet n'y est pas forcément : prenez-le depuis Nix (`nix profile install nixpkgs#regreet`, chemin absolu dans la config). `/etc/greetd/config.toml` : `command = "cage -s -d -m last -- regreet"`. Pour le CSS NIHIL, exposer depuis le flake un fichier généré à partir de `theme/nihil.nix`, le copier vers `/etc/greetd/regreet.css` avec un `regreet.toml` (horloge `%H:%M`, `greeting_msg`), puis `sudo systemctl disable gdm && sudo systemctl enable greetd`. Vérifier les contextes SELinux (`restorecon -Rv /etc/greetd`). On peut aussi garder GDM. |
| `modules/desktop.nix` | `thunar`, plugins, `gvfs` et `tumbler` via dnf. dconf est déjà présent. |
| `modules/storage.nix` | `udisks2` est déjà présent. Copier la règle polkit dans `/etc/polkit-1/rules.d/50-nihil-mount.rules`. |
| `modules/users.nix` | `sudo usermod -aG wheel,video,input,wireshark poligle`, puis `chsh -s /usr/bin/zsh`. Utiliser le zsh de **dnf** comme shell de login. Home Manager gère seulement `~/.zshrc` (si vous voulez le zsh de Nix, il faut l'ajouter à `/etc/shells`). |
| `modules/locale.nix` | `sudo timedatectl set-timezone Europe/Brussels`, `sudo localectl set-locale LANG=en_US.UTF-8`, `sudo localectl set-x11-keymap us`. Console : `FONT=Lat2-Terminus16` dans `/etc/vconsole.conf`. `XKB_DEFAULT_LAYOUT` (ajouté par `regreet.nix`) : à mettre dans `home.sessionVariables`. |
| `modules/nix.nix` | Les flakes sont déjà activés par Determinate. GC : `nix.gc = { automatic = true; frequency = "weekly"; options = "--delete-older-than 7d"; };` côté HM, ou `sudo nix-collect-garbage`. `programs.nh` → `home.packages = [ pkgs.nh ];` et `home.sessionVariables.NH_FLAKE = "$HOME/nihil";` (puis `nh home switch`). `auto-optimise-store` → `/etc/nix/nix.conf`. |
| `modules/packages.nix` | `nix-ld` est inutile : Fedora a un chargeur dynamique standard. `wev`, `git`, `btop`, `brightnessctl`, `playerctl`, `trash-cli` : dnf ou `home.packages`. `sound-theme-freedesktop` : dnf, ou laisser Nix le résoudre (il est référencé par chemin de store). `claude-code` : installeur natif dans `~/.local/bin` (déjà dans `home.sessionPath`). Agent polkit `lxqt-policykit` : dnf, puis l'`exec-once` de `home/hyprland.nix` doit pointer vers `/usr/bin/lxqt-policykit-agent`. |
| `modules/services.nix` | `sudo systemctl enable --now sshd` |
| `modules/stylix.nix` | Côté HM (section 3.4). |
| `modules/virtualisation.nix` | Désactivé : rien à faire. Pour Docker : `dnf install moby-engine` ou podman (natif sur Fedora). |
| `modules/wireshark.nix` | `dnf install wireshark`, puis le groupe `wireshark` (ligne `users.nix`). |
| `modules/direnv.nix` | `programs.direnv = { enable = true; nix-direnv.enable = true; };` dans un module HM. |
| `modules/nilo.nix` (Ollama) | Installer Ollama (script officiel `ollama.com/install.sh`, ou `pkgs.ollama-vulkan` avec une unité système écrite à la main dans `/etc/systemd/system/ollama.service`). Drop-in `/etc/systemd/system/ollama.service.d/nihil.conf` : `Environment=OLLAMA_HOST=127.0.0.1:11434 OLLAMA_KEEP_ALIVE=5m OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_NO_CLOUD=1 OLLAMA_IGPU_ENABLE=1`, plus `Restart=on-failure`, `RestartSec=2s`, `RestartSteps=5`, `RestartMaxDelaySec=1min`. Copier la règle polkit « start/restart ollama.service pour wheel » dans `/etc/polkit-1/rules.d/50-nihil-ollama.rules`. |
| `modules/nihil.nix` | Scindé (section 3.2). `services.upower` est déjà présent sur Fedora. |
| `hosts/thinkpad/default.nix` | Btrfs zstd/noatime : options dans `/etc/fstab` (Fedora installe déjà en Btrfs avec `compress=zstd:1`). Scrub : `btrfsmaintenance` ou un timer `btrfs scrub`. |

---

## 6. Ajustements dans les modules Home Manager

- **`home/zsh.nix`** : alias Fedora.
  ```nix
  nrebuild = "home-manager switch --flake ~/nihil#poligle@fedora";
  nupdate  = "cd ~/nihil && nix flake update && sudo dnf upgrade -y && home-manager switch --flake ~/nihil#poligle@fedora";
  ncheck   = "cd ~/nihil && nix flake check";
  ngc      = "nix-collect-garbage --delete-older-than 7d";
  ```
- **`home/nilo/default.nix`** : `flake = "~/nihil"` et `host = config.nihil.hostName`.
- **`home/nilo/agent.py`** : les prompts (lignes ~887-939) disent « NixOS » et
  conseillent `sudo nixos-rebuild switch --flake {flake}#{host}`. Il faut
  passer la plateforme et la commande d'application dans le JSON de config
  (par exemple `"platform"` et `"applyCommand"`) au lieu de les coder en dur.
  `system_info` lit déjà `/etc/os-release` et ignore proprement l'absence de
  `/nix/var/nix/profiles/system`. Mettre à jour `home/nilo/test_agent.py` en
  conséquence.
- **`home/hyprlock.nix`** : `programs.hyprlock.package = null;` (on utilise le
  hyprlock de dnf, qui a son `/etc/pam.d/hyprlock`). Un hyprlock Nix ne
  pourrait pas s'authentifier sans ce fichier PAM.
- **`home/scripts.nix`** : `lock-screen` lance `${pkgs.hyprlock}/bin/hyprlock`,
  à remplacer par `/usr/bin/hyprlock`. Faire de même pour `power-off`
  (`/usr/bin/systemctl`).
- **`home/hypridle.nix`** : `pkgs.hyprland` et `pkgs.hyprlock` → binaires
  système (`/usr/bin/hyprctl`, `/usr/bin/hyprlock`).
- **`home/refresh.nix`**, **`home/wallpaper.nix`** : `hyprctl` système.
- **`home/hyprland.nix`** : `exec-once` de l'agent polkit et des applets avec
  des chemins Fedora. `internalPanel` et `verticalPanel` doivent correspondre
  aux noms de sortie de la machine.
- **`home/shell.nix`** : `commands.systemctl` et `commands.uwsm` vers `/usr/bin/…`.
  `quickshell` enveloppé pour le GPU (section 4). Les outils restants
  (`nmcli`, `pw-play`, `cava`, `qalc`…) peuvent rester en chemins de store
  Nix : ce sont des clients et ils parlent aux démons de Fedora sans problème.
  Seuls `nmcli` et `wpctl` doivent rester compatibles avec la version du démon
  (en pratique, ils le sont).
- **`home/engineering.nix`** : `buildFHSEnv` marche aussi sous Nix sur Fedora
  (user namespaces actifs par défaut). On peut aussi lancer MATLAB, FEKO et
  ADS nativement, puisque Fedora a une FHS. Dans ce cas, simplifier les
  lanceurs et retirer l'environnement FHS.
- **`home/vscode.nix`** : `pkgs.vscode.fhs` fonctionne. Sinon, prendre le
  dépôt RPM de Microsoft avec `package = null`. `python.defaultInterpreterPath`
  reste `~/.nix-profile/bin/python`, ou `~/.local/state/nix/profiles/home-manager/home-path/bin/python`
  selon le profil.
- **`home/fastfetch.nix`** : facultatif. Le logo est le flocon NixOS
  (`theme/art/snowflake-19.txt`). On peut générer un logo Fedora au même
  format avec un équivalent de `tools/snowflake.py`.
- **`home/desktop-entries.nix`** : retirer `nixos-manual.desktop` et ajouter
  les entrées Fedora à masquer (par exemple les outils GNOME, si Workstation
  les installe).
- **`home/session-env.nix`** : `QT_QPA_PLATFORMTHEME = "qt6ct"` demande
  `qt6ct` (dnf ou Stylix HM).
- **`home.nix`** : `home.homeDirectory` est inchangé. `pkgs.awww`,
  `hyprshot` et `hyprpicker` restent en Nix. `kicad`, `libreoffice` et
  `octave` peuvent passer en dnf ou Flatpak pour une meilleure intégration.
- **`README.md`** et **`CLAUDE.md`** : documenter la nouvelle cible et les
  commandes.

---

## 7. Ordre d'exécution

1. [ ] Installer Fedora Workstation (Btrfs par défaut).
2. [ ] `dnf` : paquets de la section 5 et COPR Hyprland.
3. [ ] Installer Nix (section 2).
4. [ ] Cloner le dépôt dans `~/nihil`.
5. [ ] Refactoriser : `modules/nihil-options.nix`, `osConfig` → `config`, option `platform` (section 3.2).
6. [ ] Créer `hosts/fedora/home.nix` et `homeConfigurations."poligle@fedora"`, puis `git add`.
7. [ ] `nix flake check`, et `sudo nixos-rebuild build --flake .#thinkpad` doit toujours passer (sur une machine NixOS ou avec `nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel`).
8. [ ] `home-manager build --flake .#poligle@fedora`, puis `switch`.
9. [ ] Fichiers `/etc` : logind, udev, modprobe, polkit, Bluetooth, NetworkManager.
10. [ ] Groupes, `chsh`, `sshd`.
11. [ ] Ollama et Nilo.
12. [ ] Empreinte et PAM (authselect). **Garder une session root ouverte** pendant le test.
13. [ ] Plymouth et grubby.
14. [ ] greetd + ReGreet, en dernier : un greeter cassé bloque la connexion graphique.

---

## 8. Vérification

```sh
nix flake check
home-manager build --flake ~/nihil#poligle@fedora
python3 -m unittest home/nilo/test_agent.py

# dans la session Hyprland
journalctl --user -u nihil-shell -f
nihil-ipc drawers toggle launcher
nihil-ipc glyph test true
nihil-wallpaper list && nihil-wallpaper next
lock-screen                       # mot de passe, puis empreinte (sudo)
systemctl status ollama           # puis SUPER+I pour Nilo
```

À vérifier aussi : sons (`pw-play`), luminosité et volume (OSD), LED
micmute, couvercle fermé ou docké, Bluetooth éteint au démarrage, montage
USB sans mot de passe depuis Thunar.

---

## 9. Limites connues

- **Pas de rollback système** : seules les générations Home Manager se
  restaurent (`home-manager generations`). Pour le système, utiliser les
  snapshots Btrfs (`snapper` + `python3-dnf-plugin-snapper`).
- **Fichiers `/etc` impératifs** : ils ne sont plus dans le dépôt. On peut
  les versionner dans un dossier `fedora/etc/` avec un script
  d'installation, sans secrets (le dépôt est public).
- **Deux sources de paquets** (dnf et Nix) : les versions de Hyprland
  (dnf) et de sa config Lua (HM) peuvent diverger. Vérifier après chaque
  `dnf upgrade`.
- **SELinux** : les binaires dans `/nix/store` lancés par des services
  système (greetd/ReGreet, Ollama Nix) peuvent être refusés. Consulter
  `ausearch -m avc -ts recent`.
- **Plymouth, ReGreet et la console** ne sont plus thémés automatiquement
  par Stylix.
