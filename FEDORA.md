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

---

## 10. Machine lumaroy (ASUS ROG Strix G513QR)

Complément établi le 2026-10-31 en confrontant ce guide au matériel réel et
au dépôt (branche `nihil`). Les sections 1 à 9 restent valables, sauf là où
celle-ci les contredit. Démarche : tout valider dans une VM Fedora, puis
répliquer sur la machine.

### 10.1 Matériel

| Point | thinkpad (sections 1-9) | lumaroy | Renvoi |
|---|---|---|---|
| Système | — | Fedora 44 Workstation, dnf5, SELinux enforcing, GNOME + GDM | conforme à la section 1 |
| GPU | Radeon intégrée seule | **Hybride** : Radeon Cezanne (PCI `0000:06:00.0`, porte `eDP-1` et `HDMI-A-1`) + RTX 3070 Mobile, pilote propriétaire 615.78 par akmod (PCI `0000:01:00.0`, porte `DP-1`) | 10.4 |
| Écrans | `eDP-1` 1920x1200, `HDMI-A-1` 1440p, `DP-1` vertical | `DP-1` LG 27UP850 3840x2160@60, échelle 1 ; `eDP-1` 1920x1080, échelle 1 | 10.3 |
| Wi-Fi / Bluetooth | rtw89 | MediaTek MT7921 (`mt7921e`) | 10.5 |
| Empreinte | fprintd | aucun lecteur | 10.5 |
| LED micmute | `platform::micmute` | absente | 10.5 |
| Disque | Btrfs (zstd, scrub) | **ext4**, double démarrage Windows sur un second NVMe | 10.7 |
| Démarrage | — | GRUB, UEFI, Secure Boot actif | ne pas toucher au chargeur |
| Locale | `es` | `en_US.UTF-8`, clavier `us` (pc105), Europe/Brussels | déjà en place |
| Utilisateur | `poligle` | `lumaroy` (hostname `lumaroy`), déjà dans `wheel` | 10.3 |

### 10.2 Choix retenus

- **Compte `lumaroy`**, non renommé : `home.username = "lumaroy"`,
  `home.homeDirectory = "/home/lumaroy"`.
- **`nihil.language = "en"`** : `theme/i18n.nix` ne définit que `es` et `en`.
- **`nihil.primaryOutput = "DP-1"`**. Sans risque quand le LG est débranché :
  `home/shell/background/Desktop.qml` replie les widgets sur le premier écran
  présent, et `nihil-wallpaper` retombe sur le rendu de l'écran principal.
- **GDM gardé.** `modules/regreet.nix` et l'étape 14 sont sautés. La session
  « Hyprland (uwsm-managed) » se choisit dans GDM, GNOME reste en repli.
- **Modules Home Manager** : kitty oui ; zsh, nvim, vscode et engineering non.
  Les dotfiles de lumaroy restent maîtres de zsh, LazyVim et VS Code, et
  MATLAB/FEKO/ADS ne servent pas.
- **Nilo** : Ollama en CUDA (RTX 3070, 8 Go de VRAM). Côté NixOS, l'équivalent
  serait `acceleration = "cuda"; integratedGpu = false;`.

### 10.3 Changements dans le dépôt

En plus de la section 3.

1. **Écrans décrits par hôte.** `home/hyprland.nix` code en dur
   `internalPanel = "eDP-1"`, `verticalPanel = "DP-1"` et la liste `monitor`
   du thinkpad (`DP-1` en 1920x1080@165, `transform = 3`, position
   `2560x-240`, plus la règle `m[DP-1]` en orientation `top`). La ligne
   `Virtual-1` y a été ajoutée à la main pour la VM. Sur lumaroy, le LG serait
   tourné de 270° et mal réglé. Proposition :
   - ajouter à `outputType` (`modules/nihil.nix`, futur `nihil-options.nix`)
     les champs `mode` (défaut `"preferred"`), `position` (défaut `"auto"`),
     `scale` (défaut `1`) et `transform` (défaut `0`) ;
   - ajouter `nihil.internalOutput` (défaut `"eDP-1"`) et
     `nihil.verticalOutput` (`nullOr str`, défaut `null`) ;
   - générer `monitor` avec `lib.mapAttrsToList` sur `nihil.outputs`, et ne
     poser la règle d'orientation que si `verticalOutput` est défini.

   Chaque hôte décrit alors ses écrans, thinkpad et vm compris.
2. **Nom d'utilisateur surchargeable.** `home.nix` fixe
   `home.username = "poligle"` et `home.homeDirectory = "/home/poligle"` :
   une cible qui met `lumaroy` échoue sur une définition en conflit. Les
   passer en `lib.mkDefault`, ou les déplacer dans les hôtes.
3. **Imports conditionnels.** Sortir `./home/zsh.nix`, `./home/nvim.nix`,
   `./home/vscode.nix` et `./home/engineering.nix` de la liste commune de
   `home.nix`, et ne les importer que pour les cibles NixOS (une liste
   `home/nixos-only.nix`, ou un test sur `nihil.platform`). Vérifié : aucun
   autre module ne lit `programs.zsh`, `programs.neovim` ni `programs.vscode`.
4. **L'hôte `vm` aussi.** Le point 2 de la section 3.2 et l'étape 7 ne parlent
   que de thinkpad. `hosts/vm/default.nix` a besoin du même
   `home-manager.users.poligle.nihil = { … };`, et
   `nixosConfigurations.vm` doit encore évaluer à l'étape 7.
5. **Clavier et locale par hôte.** Dans ce fork, `modules/locale.nix`
   (Brussels, `en_US`, `us`) et le bloc `input` de `home/hyprland.nix`
   (`kb_layout = "us"`, `kb_model = "pc105"`) ont été changés pour tous les
   hôtes, thinkpad compris. Les déplacer dans les hôtes évite des conflits à
   chaque mise à jour venant de poligle.
6. **Nilo** : `flake` (`home/nilo/default.nix`) n'est qu'un texte inséré dans
   le prompt (`home/nilo/agent.py`, ligne ~970). `"~/nihil"` suffit, le `~`
   n'a pas à être développé.
7. **Deux cibles Home Manager**, mêmes modules, seules les valeurs `nihil`
   changent : `lumaroy@fedora-vm` (`Virtual-1` en 3840x2160, comme
   `hosts/vm`) et `lumaroy@lumaroy` :

```nix
# home.nix by poligle (lumaroy)

{ config, lib, pkgs, ... }:
{
	targets.genericLinux.enable = true;
	targets.genericLinux.gpu.enable = true;    # Mesa de la Radeon, voir 10.4
	fonts.fontconfig.enable = true;

	home.username = "lumaroy";
	home.homeDirectory = "/home/lumaroy";

	programs.kitty.package = null;              # kitty natif, voir 10.6

	nihil =
	{
		platform = "fedora";
		hostName = "lumaroy";
		primaryOutput = "DP-1";
		wallpaper = "night";
		language = "en";
		# mode et position : champs proposés au point 1
		outputs =
		{
			"DP-1"  = { width = 3840; height = 2160; mode = "3840x2160@60"; position = "0x0"; };
			"eDP-1" = { width = 1920; height = 1080; position = "3840x229"; };
		};
		nilo.enable = true;
	};
}
```

   `HDMI-A-1` est vu comme connecté mais n'est pas utilisé sous GNOME : à
   ajouter à `outputs` seulement s'il sert, pour ne pas rendre des fonds
   d'écran inutiles.

### 10.4 GPU hybride

- **Rendu sur la Radeon**, la NVIDIA ne fait qu'afficher `DP-1`. Les numéros
  `card0`/`card1` ne sont pas stables d'un démarrage à l'autre, et les
  chemins `/dev/dri/by-path/…` contiennent des `:`, qui est le séparateur de
  `AQ_DRM_DEVICES`. D'où des liens stables, dans
  `/etc/udev/rules.d/61-nihil-gpu.rules` :

  ```
  KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="0000:06:00.0", SYMLINK+="dri/amd-igpu"
  KERNEL=="card*", SUBSYSTEM=="drm", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia-dgpu"
  ```

- Dans `~/.config/uwsm/env-hyprland` (générable par `xdg.configFile`) :
  `export AQ_DRM_DEVICES=/dev/dri/amd-igpu:/dev/dri/nvidia-dgpu`. Pas dans
  `hyprland.lua` : la variable est lue au lancement de Hyprland, avant la
  config.
- **Binaires Nix** (Quickshell, awww, hyprshot…) : ils tournent sur la
  Radeon, donc `targets.genericLinux.gpu.enable = true;` (Mesa) suffit. Le
  module du Home Manager 26.05 a aussi des options `nvidia.*` : **ne pas les
  activer**, elles épinglent la version exacte du pilote (615.78.08
  aujourd'hui) et cassent à chaque mise à jour d'akmod-nvidia.
- `nvidia_drm modeset=1 fbdev=1` sont déjà actifs.
- La VM ne teste rien de cette section.

### 10.5 Ce qui ne s'applique pas

| Élément du guide | Sur lumaroy |
|---|---|
| `modules/network.nix` : options rtw89 | Puce MT7921 : pas de `rtw89.conf`. Wi-Fi powersave et Bluetooth éteint au démarrage restent valables. |
| `modules/hardware.nix` : empreinte, authselect, `pam_exec` + `lid-closed`, étape 12 | Pas de lecteur : tout est sauté. Le drop-in logind du couvercle (`HandleLidSwitch*=ignore`) reste nécessaire, car `home/hyprland.nix` gère lui-même le couvercle (fermé avec un écran externe : `eDP-1` éteint ; sinon verrouillage). |
| LED micmute : règle udev 90-micmute, `mic-led-sync` | Pas de LED. Le `mic-led-sync` de l'`exec-once` sortira en erreur (`/sys/class/leds/platform::micmute` absent), sans autre effet ; `osd-mic` l'appelle avec `\|\| true`. À rendre conditionnel pour un journal propre. |
| `hosts/thinkpad` : Btrfs, scrub ; section 9 : snapper | ext4 : rien de tout ça. Voir 10.7. |
| `modules/regreet.nix`, étape 14 | GDM gardé. |
| `modules/nilo.nix` : `ollama-vulkan`, `OLLAMA_IGPU_ENABLE=1` | Installeur officiel d'Ollama (CUDA par le pilote de l'hôte), sans `OLLAMA_IGPU_ENABLE`. Le reste du drop-in et la règle polkit restent valables. |
| `modules/users.nix` : `usermod`, `chsh` | `sudo usermod -aG video,input,wireshark lumaroy` (déjà dans `wheel`). `chsh` inutile : zsh est déjà le shell de connexion. |
| Section 6 : alias de `home/zsh.nix` | Module non importé : recopier `nrebuild`, `nupdate`, `ncheck` dans `~/.aliases` (dotfiles), avec la cible `lumaroy@lumaroy`. |

### 10.6 Cohabitation avec les dotfiles (stow)

- **kitty** : `~/.config/kitty` est un lien vers
  `~/dotfiles/home/.config/kitty`. Home Manager écrirait donc dans le dépôt
  dotfiles. Avant le premier switch : supprimer ce lien (la config reste dans
  le dépôt), et exclure kitty de stow (`.stow-local-ignore`, ou retirer
  `home/.config/kitty`) pour qu'un `stow --restow` ne le recrée pas.
- **Binaire kitty** : celui en place vient de l'installeur officiel
  (`~/.local/kitty.app`, lien `~/.local/bin/kitty`), et `home.sessionPath`
  met `~/.local/bin` en tête : c'est lui que lance `SUPER`. D'où
  `programs.kitty.package = null;` (accepté par le Home Manager 26.05) : HM
  ne gère que `kitty.conf`, et le kitty natif utilise les pilotes de Fedora
  sans enveloppe GPU.
- **zsh** : `~/.zshenv` fixe `ZDOTDIR=~/.config/zsh`. Sans `home/zsh.nix`,
  plus rien ne charge les variables de Home Manager : sourcer
  `hm-session-vars.sh` depuis `~/.config/zsh/local.zsh` (dans
  `~/.nix-profile/etc/profile.d/` ou
  `~/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/`, selon
  le profil).
- `~/.zshenv`, `~/.zshrc`, `~/.gitconfig`, `~/.config/nvim` et
  `~/.config/Code` ne sont pas touchés tant que zsh, nvim et vscode ne sont
  pas importés. Un premier `home-manager build` liste les fichiers qui
  entreraient en conflit.

### 10.7 VM d'abord, machine ensuite

**VM**

- Fedora 44 Workstation dans libvirt, avec la même config graphique que la
  VM NixOS existante : SPICE avec `gl` sur le render node de la Radeon
  (`/dev/dri/by-path/pci-0000:06:00.0-render`) et vidéo virtio `accel3d`.
  Sans 3D, Hyprland ne démarre pas.
- La rendre proche de la machine **avant** le premier switch : GNOME + GDM
  par défaut, dotfiles déployés avec stow, paquets de `packages/fedora.txt`.
  Sinon les conflits de 10.6 n'apparaissent que sur la machine.
- Snapshot de la VM avant les étapes 9 (fichiers `/etc`) et 13 (Plymouth).
- Écrire les fichiers `/etc` dans `fedora/etc/` avec un script idempotent
  (section 9), et ne les appliquer que par ce script, dès la VM : c'est ce
  qui rend la réplication fidèle.
- Validé par la VM : Nix + Home Manager standalone, refactorisation
  `osConfig`, Hyprland du COPR avec la config Lua, PAM de hyprlock, SELinux,
  Ollama sur CPU, cohabitation avec les dotfiles.
- Non validé : 10.4 (NVIDIA, `DP-1`), MT7921, batterie et couvercle,
  Secure Boot avec akmod, double démarrage.

**Machine** (ext4 : pas de snapshot)

- Avant de commencer : `sudo tar -czf ~/etc-avant-nihil.tar.gz /etc`, et
  noter le dernier numéro de `dnf history list`.
- Garder GDM et la session GNOME en repli tant que Hyprland n'est pas validé
  sur les deux GPU.
- Retour arrière : génération précédente de Home Manager
  (`home-manager generations`), `sudo dnf history undo <numéro>`, puis `/etc`
  depuis l'archive.

### 10.8 À vérifier

- COPR Hyprland : chroot `fedora-44` disponible, et version qui lit la
  config Lua (`hyprctl version`). Sinon Hyprland depuis Nix (section 4), en
  tenant compte de 10.4.
- Determinate Nix : l'installeur gère lui-même `/etc/nix/nix.conf` ; les
  réglages personnels (`auto-optimise-store`) iraient alors dans
  `/etc/nix/nix.custom.conf`. À confirmer dans sa documentation.
- Fréquence réelle de `eDP-1` (`hyprctl monitors`), et `HDMI-A-1` s'il sert.
- Que la règle udev de 10.4 crée bien `/dev/dri/amd-igpu` et
  `/dev/dri/nvidia-dgpu` (`ls -l /dev/dri`).
