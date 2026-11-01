#!/usr/bin/env bash
# install.sh by poligle (fedora)
#
# The system side of NIHIL on Fedora (FEDORA.md): what modules/*.nix do on
# NixOS and Home Manager cannot. Idempotent: run it again after changing a
# file under fedora/, it only touches what differs. Every file it replaces
# is saved first under /var/lib/nihil/backup-<date>/, with the list of the
# files it created and the dnf history from before.
#
# Left out on purpose: the greeter (GDM stays), Plymouth, fingerprint and
# PAM, and Ollama itself (its installer is run by hand, see the end).

set -euo pipefail

usage()
{
	cat <<-EOF
	Usage: fedora/install.sh [--dry-run] [--sshd] <machine>

	  <machine>   a file of hosts/fedora/ (g513, vm): fedora/machines/<machine>/etc
	              is installed on top of fedora/etc
	  --dry-run   show what would change and change nothing (sudo still reads /etc)
	  --sshd      also enable the SSH server (modules/services.nix)
	EOF
	exit "${1:-0}"
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fedora 44 has no Hyprland of its own; solopasha/hyprland stopped at 0.49.
copr="sdegler/hyprland"
packages=(
	hyprland hyprlock uwsm xdg-desktop-portal-hyprland        # from the COPR
	Thunar thunar-archive-plugin thunar-volman tumbler gvfs   # modules/desktop.nix
	lxqt-policykit wev brightnessctl playerctl qt6ct          # modules/packages.nix, session-env.nix
	blueman                                                   # modules/network.nix
	wireshark                                                 # modules/wireshark.nix
)
# modules/users.nix also has input, for the micmute LED of the ThinkPad
# (hardware.nix); it lets every program read every keyboard, so it is left
# out until a machine needs it.
groups=(video wireshark)

# For tests only: another /etc, no sudo.
etc="${NIHIL_ETC:-/etc}"
state="${NIHIL_STATE:-/var/lib/nihil}"
sudo_cmd=(sudo)
[[ -n "${NIHIL_NO_SUDO:-}" ]] && sudo_cmd=()

dry=0
sshd=0
machine=""
for arg in "$@"
do
	case "$arg" in
		--dry-run) dry=1 ;;
		--sshd) sshd=1 ;;
		-h|--help) usage ;;
		-*) usage 1 ;;
		*) [[ -z "$machine" ]] || usage 1; machine="$arg" ;;
	esac
done
[[ -n "$machine" ]] || usage 1

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;31m!!\033[0m  %s\n' "$*"; }
die() { warn "$*"; exit 1; }

# Writes go through root(), which only prints them with --dry-run; reads
# of /etc go through peek(), since some of it (polkit rules) is root-only.
run() { if (( dry )); then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }
root() { run "${sudo_cmd[@]}" "$@"; }
peek() { "${sudo_cmd[@]}" "$@"; }

[[ "$EUID" -ne 0 ]] || die "Run it as your user: it asks for sudo when needed."
[[ -f "$here/../hosts/fedora/$machine.nix" ]] || die "No hosts/fedora/$machine.nix: unknown machine '$machine'."
if [[ "$etc" == /etc ]]
then
	# shellcheck disable=SC1091
	. /etc/os-release
	[[ "${ID:-}" == fedora ]] || die "Fedora only (this is ${ID:-unknown})."
fi
(( ${#sudo_cmd[@]} == 0 )) || sudo -v

backup="$state/backup-$(date +%Y%m%d-%H%M%S)"
backup_ready=0
prepare_backup()
{
	(( backup_ready )) && return 0
	root mkdir -p -m 0700 "$backup"
	backup_ready=1
}

# 1. Hyprland's COPR and the packages ----------------------------------------

say "COPR $copr"
if dnf copr list 2>/dev/null | grep -v disabled | grep -q "/$copr\$"
then
	note "already enabled"
else
	root dnf copr enable -y "$copr"
fi

say "Packages"
missing=()
for package in "${packages[@]}"
do
	rpm -q "$package" >/dev/null 2>&1 || missing+=("$package")
done
if (( ${#missing[@]} ))
then
	prepare_backup
	dnf history list 2>/dev/null | head -n 5 | root tee "$backup/dnf-history-before" >/dev/null || true
	root dnf install -y "${missing[@]}"
else
	note "all installed"
fi

# 2. Files in /etc ---------------------------------------------------------

changed_units=0
changed_nm=0
changed_logind=0
changed_udev=0

install_tree()
{
	local tree="$1" source relative target
	[[ -d "$tree" ]] || return 0
	while IFS= read -r -d '' source
	do
		relative="${source#"$tree"/}"
		target="$etc/$relative"
		if peek test -e "$target"
		then
			if peek cmp -s "$source" "$target"
			then
				note "= $target"
				continue
			fi
			say "~ $target"
			peek diff -u "$target" "$source" | sed 's/^/    /' || true
			prepare_backup
			root install -D -m 0644 "$target" "$backup/etc/$relative"
		else
			say "+ $target"
			prepare_backup
			printf '%s\n' "$target" | root tee -a "$backup/created" >/dev/null
		fi
		root install -D -m 0644 "$source" "$target"
		if [[ "$etc" == /etc ]]
		then
			# SELinux labels for the file and the directory install -D may have made.
			root restorecon -F "$(dirname "$target")" "$target"
		fi
		case "$relative" in
			udev/*) changed_udev=1 ;;
			systemd/logind.conf.d/*) changed_logind=1 ;;
			systemd/*) changed_units=1 ;;
			NetworkManager/*) changed_nm=1 ;;
		esac
	done < <(find "$tree" -type f -print0 | sort -z)
}

say "Files in $etc"
install_tree "$here/etc"
install_tree "$here/machines/$machine/etc"

if (( changed_units ))
then
	root systemctl daemon-reload
fi
if (( changed_nm ))
then
	root nmcli general reload conf
fi
if (( changed_udev ))
then
	# The new names appear at the next boot; triggering the GPUs now would
	# make the running session probe every output again.
	root udevadm control --reload
fi

# 3. Services and groups ---------------------------------------------------

say "Services"
if systemctl is-enabled -q nihil-bluetooth-off.service 2>/dev/null
then
	note "nihil-bluetooth-off: enabled"
else
	# Not --now: it would turn Bluetooth off under your feet.
	root systemctl enable nihil-bluetooth-off.service
fi
if (( sshd ))
then
	if systemctl is-enabled -q sshd.service 2>/dev/null
	then
		note "sshd: enabled"
	else
		root systemctl enable --now sshd.service
	fi
fi

say "Groups of $USER"
for group in "${groups[@]}"
do
	if ! getent group "$group" >/dev/null
	then
		note "$group: no such group yet (its package comes with this run)"
	elif id -nG "$USER" | tr ' ' '\n' | grep -qx "$group"
	then
		note "$group: member"
	else
		root usermod -aG "$group" "$USER"
	fi
done

# 4. What is left by hand --------------------------------------------------

say "Checks"
if [[ -e /etc/pam.d/hyprlock ]]
then
	note "hyprlock has its PAM file"
else
	warn "No /etc/pam.d/hyprlock: the lock screen would refuse every password."
fi
if compgen -G "/usr/share/wayland-sessions/*uwsm*.desktop" >/dev/null
then
	note "GDM offers: $(basename -a /usr/share/wayland-sessions/*uwsm*.desktop | tr '\n' ' ')"
else
	warn "No uwsm session in /usr/share/wayland-sessions: GDM will not offer Hyprland (uwsm-managed)."
fi
if command -v hyprland >/dev/null
then
	note "$(hyprland --version 2>/dev/null | head -n 1) (home/hyprland.nix is written for 0.55)"
fi
if command -v ollama >/dev/null
then
	note "Ollama: $(command -v ollama)"
else
	note "Ollama is not installed. Its installer sets up ollama.service with CUDA;"
	note "read it before running it:"
	note "  curl -fsSL https://ollama.com/install.sh -o ollama-install.sh && less ollama-install.sh && sh ollama-install.sh"
	note "then: sudo systemctl daemon-reload && sudo systemctl restart ollama"
fi
if (( backup_ready ))
then
	if (( dry ))
	then
		note "What changes would be saved in: $backup"
	else
		note "Backup of what changed: $backup"
	fi
fi
if (( changed_logind || changed_udev ))
then
	note "Reboot for logind (lid) and the GPU names; log out and in for the groups."
fi
(( dry )) && say "Dry run: nothing changed."
exit 0
