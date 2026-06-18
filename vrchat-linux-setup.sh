#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="0.1.0"
RTSP_REPO="SpookySkeletons/proton-ge-rtsp"
WAYVR_REPO="wayvr-org/wayvr"
VRCHAT_APPID="438100"
DEFAULT_NATIVE_VR_LAUNCH='PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 PRESSURE_VESSEL_FILESYSTEMS_RW=/var/lib/flatpak/app/io.github.wivrn.wivrn %command%'
STATE_DIR_REL=".local/share/vrchat-linux-setup"
WAYVR_BIN_REL=".local/bin/WayVR.AppImage"
WAYVR_DESKTOP_REL=".local/share/applications/wayvr.desktop"
WAYVR_LAUNCHER_REL=".local/bin/wayvr-launch"
STEAM_FLATPAK_ID="com.valvesoftware.Steam"
WIVRN_FLATPAK_ID="io.github.wivrn.wivrn"
WIVRN_FLATPAK_PERM_CMD_1='flatpak override --user --filesystem=xdg-config/openxr:ro --filesystem=xdg-config/openvr:ro --filesystem=xdg-run/wivrn --filesystem=/var/lib/flatpak/app/io.github.wivrn.wivrn:ro --filesystem=~/.var/app/io.github.wivrn.wivrn:ro com.valvesoftware.Steam'
WIVRN_FLATPAK_PERM_CMD_2='flatpak override --user --env=PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 --env=PRESSURE_VESSEL_FILESYSTEMS_RW=/var/lib/flatpak/app/io.github.wivrn.wivrn com.valvesoftware.Steam'
STEAM_NATIVE_FOUND="no"
STEAM_FLATPAK_FOUND="no"
STEAM_SNAP_FOUND="no"
WIVRN_KIND=""
WIVRN_VERSION=""
RTSP_ASSET_NAME=""
RTSP_TOOL_NAME=""

OS_ID=""
OS_NAME=""
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=""
STEAM_KIND=""
STEAM_ROOT=""
STEAM_CONFIG=""
STEAM_USERDATA_DIR=""
STEAM_APPS_DIR=""
STEAM_FLATPAK_SCOPE=""
STATE_DIR=""
WAYVR_BIN=""
WAYVR_DESKTOP=""
WAYVR_LAUNCHER=""
RTSP_TAG=""
RTSP_URL=""
RTSP_SHA_URL=""
RTSP_RELEASE_URL=""
RTSP_NOTES=""
WAYVR_TAG=""
WAYVR_URL=""
WAYVR_RELEASE_URL=""
WAYVR_NOTES=""
WIVRN_INSTALLED="no"
WAYVR_INSTALLED="no"
VRCHAT_INSTALLED="no"

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_as_user() {
  if [[ $EUID -eq 0 ]]; then
    sudo -u "$REAL_USER" -H "$@"
  else
    "$@"
  fi
}

run_in_user_shell() {
  local cmd="$1"
  if [[ $EUID -eq 0 ]]; then
    sudo -u "$REAL_USER" -H bash -lc "$cmd"
  else
    bash -lc "$cmd"
  fi
}

sudo_do() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

pause_prompt() {
  local _reply=""
  if [[ -r /dev/tty ]]; then
    read -r -p "$1" _reply </dev/tty || exit 1
  else
    read -r -p "$1" _reply || exit 1
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-Y}"
  local suffix="[Y/n]"
  local reply=""

  [[ "$default" == "N" ]] && suffix="[y/N]"

  while true; do
    if [[ -r /dev/tty ]]; then
      read -r -p "$prompt $suffix " reply </dev/tty || exit 1
    else
      read -r -p "$prompt $suffix " reply || exit 1
    fi
    reply="${reply:-$default}"
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) say "Please answer y or n." ;;
    esac
  done
}

steam_is_initialized() {
  detect_steam
  [[ -f "$STEAM_CONFIG" ]] || return 1
  [[ -d "$STEAM_USERDATA_DIR" ]] || return 1
  find "$STEAM_USERDATA_DIR" -path '*/config/localconfig.vdf' -print -quit 2>/dev/null | grep -q .
}

installed_rtsp_versions() {
  detect_steam
  [[ -n "$STEAM_ROOT" ]] || return 0
  local dest="$STEAM_ROOT/compatibilitytools.d"
  [[ -d "$dest" ]] || return 0
  find "$dest" -maxdepth 1 -mindepth 1 -type d -name 'GE-Proton*-rtsp*' -printf '%f\n' 2>/dev/null | sort -V
}

detect_steam_variants() {
  STEAM_NATIVE_FOUND="no"
  STEAM_FLATPAK_FOUND="no"
  STEAM_SNAP_FOUND="no"

  local resolved=""

  for cand in \
    "$REAL_HOME/.steam/steam" \
    "$REAL_HOME/.steam/root" \
    "$REAL_HOME/.local/share/Steam"
  do
    resolved="$(readlink -f "$cand" 2>/dev/null || printf '%s' "$cand")"
    if [[ -d "$resolved" ]]; then
      STEAM_NATIVE_FOUND="yes"
      break
    fi
  done

  if [[ "$STEAM_NATIVE_FOUND" != "yes" ]] && native_steam_package_installed; then
    STEAM_NATIVE_FOUND="yes"
  fi

  if run_in_user_shell "flatpak info $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
    STEAM_FLATPAK_FOUND="yes"
  fi

  if have snap && snap list steam >/dev/null 2>&1; then
    STEAM_SNAP_FOUND="yes"
  fi
}

remove_suboptimal_steam() {
  detect_steam_variants

  if [[ "$STEAM_FLATPAK_FOUND" == "yes" ]]; then
    if run_in_user_shell "flatpak info --user $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
      run_in_user_shell "flatpak uninstall -y --user $STEAM_FLATPAK_ID" || warn "Failed to remove user Flatpak Steam."
    fi
    if run_in_user_shell "flatpak info --system $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
      sudo_do flatpak uninstall -y --system $STEAM_FLATPAK_ID || warn "Failed to remove system Flatpak Steam."
    fi
  fi

  if [[ "$STEAM_SNAP_FOUND" == "yes" ]]; then
    sudo_do snap remove steam || warn "Failed to remove Steam Snap."
  fi
}

detect_wivrn() {
  WIVRN_INSTALLED="no"
  WIVRN_KIND=""
  WIVRN_VERSION=""

  if run_in_user_shell "flatpak info $WIVRN_FLATPAK_ID >/dev/null 2>&1"; then
    WIVRN_INSTALLED="yes"
    WIVRN_KIND="flatpak"
    WIVRN_VERSION="$(run_in_user_shell "flatpak info $WIVRN_FLATPAK_ID 2>/dev/null | awk -F': *' '/^Version:/ {print \$2; exit}'")"
    return
  fi

  if dpkg-query -W -f='${Version}\n' wivrn >/dev/null 2>&1; then
    WIVRN_INSTALLED="yes"
    WIVRN_KIND="apt:wivrn"
    WIVRN_VERSION="$(dpkg-query -W -f='${Version}\n' wivrn 2>/dev/null | head -n1)"
    return
  fi

  if dpkg-query -W -f='${Version}\n' wivrn-dashboard >/dev/null 2>&1; then
    WIVRN_INSTALLED="yes"
    WIVRN_KIND="apt:wivrn-dashboard"
    WIVRN_VERSION="$(dpkg-query -W -f='${Version}\n' wivrn-dashboard 2>/dev/null | head -n1)"
    return
  fi

  if have wivrn-dashboard; then
    WIVRN_INSTALLED="yes"
    WIVRN_KIND="command"
    WIVRN_VERSION="$(run_in_user_shell "wivrn-dashboard --version 2>/dev/null | head -n1 || true")"
    return
  fi
}

require_supported_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-$OS_ID}"
  else
    die "Could not detect your operating system."
  fi

  case "$OS_ID ${ID_LIKE:-}" in
    linuxmint*|*ubuntu*|*debian*|*pop*) ;;
    *)
      die "This script targets Debian based systems such as Pop!_OS, Ubuntu, Debian, and Linux Mint. Detected: $OS_NAME"
      ;;
  esac
}

resolve_real_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    REAL_USER="$SUDO_USER"
  else
    REAL_USER="$USER"
  fi

  REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
  [[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || die "Could not resolve the home directory for user $REAL_USER"

  STATE_DIR="$REAL_HOME/$STATE_DIR_REL"
  WAYVR_BIN="$REAL_HOME/$WAYVR_BIN_REL"
  WAYVR_DESKTOP="$REAL_HOME/$WAYVR_DESKTOP_REL"
  WAYVR_LAUNCHER="$REAL_HOME/$WAYVR_LAUNCHER_REL"
}

need_cmds() {
  local missing=()
  local cmd
  for cmd in curl python3 tar awk sed grep findmnt getent lspci; do
    have "$cmd" || missing+=("$cmd")
  done

  if ((${#missing[@]})); then
    say "Installing required base packages: ${missing[*]}"
    sudo_do apt-get update
    sudo_do apt-get install -y curl python3 tar pciutils util-linux gawk sed grep coreutils findutils
  fi
}

ensure_flatpak_stack() {
  local pkgs=()
  have flatpak || pkgs+=(flatpak)
  if ! systemctl list-unit-files | grep -q '^avahi-daemon.service'; then
    pkgs+=(avahi-daemon)
  fi
  have pgrep || pkgs+=(procps)
  have lsof || pkgs+=(lsof)
  have xdg-open || pkgs+=(xdg-utils)
  have glxinfo || pkgs+=(mesa-utils)
  if ((${#pkgs[@]})); then
    sudo_do apt-get update
    sudo_do apt-get install -y "${pkgs[@]}"
  fi

  if ! flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    sudo_do flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

ensure_i386_arch() {
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    say "Enabling 32-bit (i386) packages for Steam..."
    sudo_do dpkg --add-architecture i386
    sudo_do apt-get update
  fi
}

steam_command_exists() {
  have steam || have steam-launcher
}

native_steam_package_installed() {
  local pkg
  for pkg in steam steam-launcher steam-installer; do
    if dpkg-query -W -f='${db:Status-Status}\n' "$pkg" 2>/dev/null | grep -qx installed; then
      return 0
    fi
  done

  steam_command_exists
}

detect_steam() {
  STEAM_KIND=""
  STEAM_ROOT=""
  STEAM_CONFIG=""
  STEAM_USERDATA_DIR=""
  STEAM_APPS_DIR=""
  STEAM_FLATPAK_SCOPE=""

  local native_candidates=()
  local cand=""
  local resolved=""

  [[ -d "$REAL_HOME/.steam/steam" ]] && native_candidates+=("$REAL_HOME/.steam/steam")
  [[ -d "$REAL_HOME/.steam/root" || -L "$REAL_HOME/.steam/root" ]] && native_candidates+=("$REAL_HOME/.steam/root")
  [[ -d "$REAL_HOME/.local/share/Steam" ]] && native_candidates+=("$REAL_HOME/.local/share/Steam")

  for cand in "${native_candidates[@]}"; do
    resolved="$(readlink -f "$cand" 2>/dev/null || printf '%s' "$cand")"
    if [[ -d "$resolved" ]]; then
      STEAM_KIND="native"
      STEAM_ROOT="$resolved"
      break
    fi
  done

  if [[ -z "$STEAM_KIND" ]] && native_steam_package_installed; then
    STEAM_KIND="native"
  fi

  if [[ -z "$STEAM_KIND" ]] && run_in_user_shell "flatpak info $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
    STEAM_KIND="flatpak"
    STEAM_ROOT="$REAL_HOME/.var/app/$STEAM_FLATPAK_ID/data/Steam"
    if run_in_user_shell "flatpak info --user $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
      STEAM_FLATPAK_SCOPE="user"
    elif run_in_user_shell "flatpak info --system $STEAM_FLATPAK_ID >/dev/null 2>&1"; then
      STEAM_FLATPAK_SCOPE="system"
    fi
  fi

  if [[ -n "$STEAM_ROOT" ]]; then
    STEAM_CONFIG="$STEAM_ROOT/config/config.vdf"
    STEAM_USERDATA_DIR="$STEAM_ROOT/userdata"
    STEAM_APPS_DIR="$STEAM_ROOT/steamapps"
  fi
}

install_native_steam() {
  say "Installing native Steam..."
  ensure_i386_arch

  if apt-cache show steam >/dev/null 2>&1; then
    sudo_do apt-get install -y steam
    return
  fi

  if apt-cache show steam-launcher >/dev/null 2>&1; then
    sudo_do apt-get install -y steam-launcher
    return
  fi

  if apt-cache show steam-installer >/dev/null 2>&1; then
    sudo_do apt-get install -y steam-installer
    return
  fi

  say "Adding Valve's official Steam repository because no native Steam package is available from current APT sources..."
  sudo_do install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://repo.steampowered.com/steam/steam.gpg | sudo_do tee /usr/share/keyrings/steam.gpg >/dev/null
  cat <<'EOF_REPO' | sudo_do tee /etc/apt/sources.list.d/steam-stable.list >/dev/null
# Valve official Steam repository
# Added by vrchat-linux-setup.sh
deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] https://repo.steampowered.com/steam/ stable steam
deb-src [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] https://repo.steampowered.com/steam/ stable steam
EOF_REPO
  sudo_do apt-get update
  sudo_do apt-get install -y steam-launcher
}

ensure_steam_installed() {
  detect_steam_variants
  detect_steam

  if [[ "$STEAM_NATIVE_FOUND" == "yes" ]]; then
    say "Native Steam was detected."
    if [[ "$STEAM_FLATPAK_FOUND" == "yes" || "$STEAM_SNAP_FOUND" == "yes" ]]; then
      warn "A suboptimal Steam install was also detected."
      if prompt_yes_no "Remove suboptimal Steam installs and keep only native Steam?" "Y"; then
        remove_suboptimal_steam
        detect_steam_variants
        detect_steam
      fi
    fi
    return
  fi

  if [[ "$STEAM_FLATPAK_FOUND" == "yes" || "$STEAM_SNAP_FOUND" == "yes" ]]; then
    warn "A suboptimal Steam install was detected."
    say "For Linux VR, native Steam is the preferred path."

    if [[ "$STEAM_FLATPAK_FOUND" == "yes" ]]; then
      say "Detected: Flatpak Steam"
    fi
    if [[ "$STEAM_SNAP_FOUND" == "yes" ]]; then
      say "Detected: Snap Steam"
    fi

    if prompt_yes_no "Install native Steam now?" "Y"; then
      install_native_steam
      detect_steam

      if prompt_yes_no "Remove the suboptimal Steam install(s) now?" "Y"; then
        remove_suboptimal_steam
        detect_steam_variants
        detect_steam
      fi
    else
      if [[ "$STEAM_FLATPAK_FOUND" == "yes" ]]; then
        warn "Continuing with Flatpak Steam because you chose not to install native Steam."
      else
        die "Native Steam was declined, and only Snap Steam was detected. This setup is not recommended for Linux VR."
      fi
    fi
  fi

  if [[ -z "$STEAM_KIND" ]]; then
    install_native_steam
    detect_steam
  fi

  if [[ "$STEAM_KIND" == "native" && -z "$STEAM_ROOT" ]]; then
    say "Native Steam is installed but has not been initialized for user $REAL_USER yet."
  fi

  [[ -n "$STEAM_KIND" ]] || die "Steam installation could not be detected after install."
}

ensure_wivrn() {
  detect_wivrn

  if [[ "$WIVRN_INSTALLED" == "yes" ]]; then
    say "WiVRn detected."
    say "  Source:  $WIVRN_KIND"
    say "  Version: ${WIVRN_VERSION:-unknown}"
  else
    say "Installing WiVRn from Flathub system-wide..."
    sudo_do flatpak install -y --system flathub "$WIVRN_FLATPAK_ID"
    detect_wivrn
  fi

  sudo_do systemctl enable --now avahi-daemon

  if have ufw && sudo_do ufw status 2>/dev/null | grep -q '^Status: active'; then
    sudo_do ufw allow 5353/udp >/dev/null || true
    sudo_do ufw allow 9757 >/dev/null || true
  fi

  if [[ "$STEAM_KIND" == "flatpak" && "$WIVRN_KIND" == "flatpak" ]]; then
    say "Applying WiVRn Flatpak permissions to Flatpak Steam..."
    if [[ "$STEAM_FLATPAK_SCOPE" == "system" ]]; then
      run_in_user_shell "${WIVRN_FLATPAK_PERM_CMD_1/--user /}"
      run_in_user_shell "${WIVRN_FLATPAK_PERM_CMD_2/--user /}"
    else
      run_in_user_shell "$WIVRN_FLATPAK_PERM_CMD_1"
      run_in_user_shell "$WIVRN_FLATPAK_PERM_CMD_2"
    fi
  elif [[ "$STEAM_KIND" == "flatpak" && "$WIVRN_KIND" != "flatpak" ]]; then
    warn "Flatpak Steam was selected, but WiVRn is not installed as a Flatpak."
    warn "This script only applies the documented Flatpak Steam overrides for Flatpak WiVRn."
    warn "Native Steam is the preferred path here."
  fi
}

ensure_wayvr() {
  if ! prompt_yes_no "Install WayVR as an optional in VR desktop overlay? It is not required for WiVRn or VRChat." "Y"; then
    return
  fi
  fetch_wayvr_release
  install_wayvr_appimage
}

launch_wivrn_dashboard_for_user() {
  detect_wivrn
  [[ "$WIVRN_INSTALLED" == "yes" ]] || return 0

  if pgrep -u "$REAL_USER" -fa 'wivrn-dashboard|wivrn-server|io.github.wivrn.wivrn|WiVRn' >/dev/null 2>&1; then
    return 0
  fi

  local desktop_file=""
  local launch_cmd=""
  local tries=0

  # Build one launch command that matches the desktop launcher path as closely as possible.
  for desktop_file in \
    "$REAL_HOME/.local/share/flatpak/exports/share/applications/io.github.wivrn.wivrn.desktop" \
    "/var/lib/flatpak/exports/share/applications/io.github.wivrn.wivrn.desktop" \
    "$REAL_HOME/.local/share/applications/io.github.wivrn.wivrn.desktop" \
    "/usr/share/applications/io.github.wivrn.wivrn.desktop"
  do
    if [[ -f "$desktop_file" ]] && have gio; then
      launch_cmd="nohup gio launch '$desktop_file' >/dev/null 2>&1 &"
      break
    fi
  done

  if [[ -z "$launch_cmd" ]] && have gtk-launch; then
    launch_cmd="nohup gtk-launch io.github.wivrn.wivrn >/dev/null 2>&1 &"
  fi

  if [[ -z "$launch_cmd" ]]; then
    if [[ "$WIVRN_KIND" == "flatpak" ]]; then
      launch_cmd="nohup flatpak run '$WIVRN_FLATPAK_ID' >/dev/null 2>&1 &"
    elif have wivrn-dashboard; then
      launch_cmd="nohup wivrn-dashboard >/dev/null 2>&1 &"
    else
      return 1
    fi
  fi

  # First launch.
  run_in_user_shell "$launch_cmd" || return 1

  # Wait to see whether the WiVRn server actually comes up, not just the window.
  for tries in {1..8}; do
    if run_in_user_shell "lsof -nP -iTCP:9757 -sTCP:LISTEN >/dev/null 2>&1 || lsof -nP -iUDP:9757 >/dev/null 2>&1"; then
      return 0
    fi
    sleep 1
  done

  # manual workaround works: close the broken first launch and reopen once.
  pkill -u "$REAL_USER" -TERM -f 'wivrn-dashboard|wivrn-server|io.github.wivrn.wivrn|WiVRn' >/dev/null 2>&1 || true
  sleep 2
  pkill -u "$REAL_USER" -KILL -f 'wivrn-dashboard|wivrn-server|io.github.wivrn.wivrn|WiVRn' >/dev/null 2>&1 || true
  sleep 1

  # Second launch.
  run_in_user_shell "$launch_cmd" || return 1

  for tries in {1..10}; do
    if run_in_user_shell "lsof -nP -iTCP:9757 -sTCP:LISTEN >/dev/null 2>&1 || lsof -nP -iUDP:9757 >/dev/null 2>&1"; then
      return 0
    fi
    sleep 1
  done

  # Last fallback: confirm at least that WiVRn is running, even if port detection missed it.
  pgrep -u "$REAL_USER" -fa 'wivrn-dashboard|wivrn-server|io.github.wivrn.wivrn|WiVRn' >/dev/null 2>&1
}

launch_wayvr_for_user() {
  local bin_name=""
  [[ -x "$WAYVR_BIN" ]] || return 0

  bin_name="$(basename "$WAYVR_BIN")"

  if pgrep -u "$REAL_USER" -fa "$bin_name|wayvr" >/dev/null 2>&1; then
    return 0
  fi

  run_in_user_shell "nohup \"$WAYVR_BIN\" >/dev/null 2>&1 &" || return 1

  sleep 5
  pgrep -u "$REAL_USER" -fa "$bin_name|wayvr" >/dev/null 2>&1
}

launch_post_install_helpers() {
  say
  say "WiVRn Dashboard was not opened automatically."
  say "Open WiVRn Server yourself from the desktop app launcher."
  say "Then connect your headset in WiVRn."
  if [[ -x "$WAYVR_BIN" ]]; then
    say "If you want desktop overlays in VR, launch WayVR after WiVRn is connected."
    say "If WayVR is running but you do not see it, double-tap B or Y on the left controller."
    say "The main WayVR controls are on the left wrist watch."
  fi
}

check_gpu() {
  local gpu_info renderer nvidia_ok
  gpu_info="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  [[ -n "$gpu_info" ]] || return 0

  if grep -qi 'nvidia' <<<"$gpu_info"; then
    if have nvidia-smi && nvidia-smi >/dev/null 2>&1; then
      say "Detected NVIDIA GPU and working nvidia-smi."
    else
      warn "An NVIDIA GPU was detected, but nvidia-smi is not working. Fix your NVIDIA driver first or VR will likely fail."
    fi
  elif grep -Eqi 'amd|advanced micro devices|radeon' <<<"$gpu_info"; then
    if have glxinfo; then
      renderer="$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer string/ {print $2; exit}')"
      if grep -qi 'llvmpipe' <<<"${renderer:-}"; then
        warn "Your OpenGL renderer is llvmpipe, which usually means hardware acceleration is not configured correctly."
      else
        say "Detected AMD GPU. OpenGL renderer: ${renderer:-unknown}"
      fi
    else
      say "Detected AMD GPU."
    fi
  fi
}

fetch_github_release() {
  local repo="$1"
  local kind="$2"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" -o "$tmp"

  if [[ "$kind" == "rtsp" ]]; then
    mapfile -t _fields < <(python3 - "$tmp" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

body = (data.get('body') or '').strip()
tag = data.get('tag_name') or ''
html = data.get('html_url') or ''
asset_name = ''
asset_url = ''
sha_url = ''

for asset in data.get('assets', []):
    n = asset.get('name', '')
    u = asset.get('browser_download_url', '')
    if n.endswith('.tar.gz') and not asset_url:
        asset_name = n
        asset_url = u
    if n.endswith('.sha512sum') and not sha_url:
        sha_url = u

print(tag)
print(asset_name)
print(asset_url)
print(sha_url)
print(html)
print(body)
PY
)

    RTSP_TAG="${_fields[0]:-}"
    RTSP_ASSET_NAME="${_fields[1]:-}"
    RTSP_URL="${_fields[2]:-}"
    RTSP_SHA_URL="${_fields[3]:-}"
    RTSP_RELEASE_URL="${_fields[4]:-}"
    RTSP_NOTES="${_fields[5]:-}"
    RTSP_TOOL_NAME="${RTSP_ASSET_NAME%.tar.gz}"

    [[ -n "$RTSP_TAG" && -n "$RTSP_ASSET_NAME" && -n "$RTSP_URL" && -n "$RTSP_TOOL_NAME" ]] || die "Could not determine latest Proton-GE-RTSP release."
  else
    mapfile -t _fields < <(python3 - "$tmp" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

body = (data.get('body') or '').strip()
tag = data.get('tag_name') or ''
html = data.get('html_url') or ''
asset_url = ''

for asset in data.get('assets', []):
    n = asset.get('name', '')
    u = asset.get('browser_download_url', '')
    if n.endswith('.AppImage') and not asset_url:
        asset_url = u

print(tag)
print(asset_url)
print(html)
print(body)
PY
)

    WAYVR_TAG="${_fields[0]:-}"
    WAYVR_URL="${_fields[1]:-}"
    WAYVR_RELEASE_URL="${_fields[2]:-}"
    WAYVR_NOTES="${_fields[3]:-}"
    [[ -n "$WAYVR_TAG" && -n "$WAYVR_URL" ]] || die "Could not determine latest WayVR release."
  fi

  rm -f "$tmp"
}

fetch_rtsp_release() {
  fetch_github_release "$RTSP_REPO" rtsp
}

fetch_wayvr_release() {
  fetch_github_release "$WAYVR_REPO" wayvr
}

verify_rtsp_archive() {
  local archive="$1"
  local sha_file="$2"

  [[ -n "$RTSP_SHA_URL" ]] || return 0
  have sha512sum || return 0

  curl -fsSL "$RTSP_SHA_URL" -o "$sha_file"
  (cd "$(dirname "$archive")" && sha512sum -c "$(basename "$sha_file")")
}

install_rtsp() {
  local force="${1:-0}"

  fetch_rtsp_release
  detect_steam
  [[ -n "$STEAM_ROOT" ]] || die "Steam must be installed before Proton-GE-RTSP can be installed."

  local dest="$STEAM_ROOT/compatibilitytools.d"
  local current_dir="$dest/$RTSP_TOOL_NAME"
  local tmpdir archive sha_file

  run_as_user mkdir -p "$dest"
  check_steam_not_running

  if [[ -d "$current_dir" ]]; then
    if [[ "$force" == "1" ]]; then
      say "Reinstalling Proton-GE-RTSP: $RTSP_TOOL_NAME"
      run_as_user rm -rf "$current_dir"
    else
      say "$RTSP_TOOL_NAME is already installed."
      return 0
    fi
  fi

  tmpdir="$(run_as_user mktemp -d)"
  archive="$tmpdir/$RTSP_ASSET_NAME"
  sha_file="$tmpdir/${RTSP_TOOL_NAME}.sha512sum"

  say "Downloading latest Proton-GE-RTSP release: $RTSP_TAG"
  say "Using asset: $RTSP_ASSET_NAME"
  run_as_user curl -fL "$RTSP_URL" -o "$archive"
  verify_rtsp_archive "$archive" "$sha_file"

  say "Installing Proton-GE-RTSP into $dest"
  run_as_user tar -xf "$archive" -C "$dest"
  rm -rf "$tmpdir"
}

check_steam_not_running() {
  local matches=()

  while IFS= read -r line; do
    [[ -n "$line" ]] && matches+=("$line")
  done < <(
    pgrep -ax steam 2>/dev/null || true
    pgrep -ax steamwebhelper 2>/dev/null || true
    pgrep -ax pressure-vessel 2>/dev/null || true
    pgrep -ax wineserver 2>/dev/null || true
  )

  if ((${#matches[@]})); then
    say "The script found these Steam/Proton-related processes still running:"
    printf '%s\n' "${matches[@]}"
    die "Fully close Steam, VRChat, and related helper processes, then re-run the command."
  fi
}

launch_steam_for_user() {
  local i
  local desktop_file=""

  detect_steam

  # First try: use the desktop's Steam URI handler.
  # This is the same path that already works later for steam://install/<appid>.
  run_in_user_shell "nohup xdg-open 'steam://open/main' >/dev/null 2>&1 &" || true

  for i in {1..45}; do
    if pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
      || pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  # Second try: desktop entry launch.
  if have gio; then
    desktop_file="$(find /usr/share/applications "$REAL_HOME/.local/share/applications" \
      -maxdepth 2 -type f \( -name 'steam.desktop' -o -name 'com.valvesoftware.Steam.desktop' \) \
      2>/dev/null | head -n1 || true)"

    if [[ -n "$desktop_file" ]]; then
      run_in_user_shell "nohup gio launch '$desktop_file' >/dev/null 2>&1 &" || true

      for i in {1..45}; do
        if pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
          || pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1; then
          return 0
        fi
        sleep 1
      done
    fi
  fi

  # Last fallback: direct launcher command.
  if [[ "$STEAM_KIND" == "flatpak" ]]; then
    run_in_user_shell "nohup flatpak run '$STEAM_FLATPAK_ID' >/dev/null 2>&1 &" || true
  elif have steam; then
    run_in_user_shell "nohup steam >/dev/null 2>&1 &" || true
  elif have steam-launcher; then
    run_in_user_shell "nohup steam-launcher >/dev/null 2>&1 &" || true
  else
    return 1
  fi

  for i in {1..45}; do
    if pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
      || pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

close_steam_for_setup() {
  local names=(steam steamwebhelper pressure-vessel wineserver)
  local name=""
  local tries=0

  say
  say "Closing Steam so the installer can finish Proton and VRChat setup..."

  for name in "${names[@]}"; do
    pkill -u "$REAL_USER" -TERM -x "$name" 2>/dev/null || true
  done

  for tries in {1..20}; do
    if ! pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x pressure-vessel >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x wineserver >/dev/null 2>&1; then
      say "Steam closed."
      return 0
    fi
    sleep 1
  done

  warn "Steam did not exit cleanly. Forcing shutdown..."

  for name in "${names[@]}"; do
    pkill -u "$REAL_USER" -KILL -x "$name" 2>/dev/null || true
  done

  sleep 2

  if pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x pressure-vessel >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x wineserver >/dev/null 2>&1; then
    die "Steam could not be closed automatically. Close it manually, then run the script again."
  fi
}

ensure_steam_closed_for_update() {
  if ! pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
    && ! pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1 \
    && ! pgrep -u "$REAL_USER" -x pressure-vessel >/dev/null 2>&1 \
    && ! pgrep -u "$REAL_USER" -x wineserver >/dev/null 2>&1; then
    return 0
  fi

  say
  say "Steam or related Proton helper processes are still running."
  say "Proton-GE-RTSP updates need Steam closed before the update can continue."

  if ! prompt_yes_no "Close Steam automatically now and continue the Proton-GE-RTSP update?" "Y"; then
    say "Skipping Proton-GE-RTSP update because Steam was left running."
    return 1
  fi

  local names=(steam steamwebhelper pressure-vessel wineserver)
  local name=""
  local tries=0

  say
  say "Closing Steam so the Proton-GE-RTSP update can continue..."

  for name in "${names[@]}"; do
    pkill -u "$REAL_USER" -TERM -x "$name" 2>/dev/null || true
  done

  for tries in {1..20}; do
    if ! pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x pressure-vessel >/dev/null 2>&1 \
      && ! pgrep -u "$REAL_USER" -x wineserver >/dev/null 2>&1; then
      say "Steam closed."
      return 0
    fi
    sleep 1
  done

  warn "Steam did not exit cleanly. Forcing shutdown..."

  for name in "${names[@]}"; do
    pkill -u "$REAL_USER" -KILL -x "$name" 2>/dev/null || true
  done

  sleep 2

  if pgrep -u "$REAL_USER" -x steam >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x steamwebhelper >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x pressure-vessel >/dev/null 2>&1 \
    || pgrep -u "$REAL_USER" -x wineserver >/dev/null 2>&1; then
    die "Steam could not be closed automatically. Close it manually, then re-run the update."
  fi

  say "Steam closed."
}

prompt_steam_login() {
  if steam_is_initialized; then
    say "Steam already looks initialized and signed in enough for configuration. Skipping first-run/login."
    return
  fi

  say
  say "Steam now needs to be opened at least once so it can finish setup and so you can sign in."
  launch_steam_for_user || true
  say "If Steam did not open automatically, launch it yourself now."
  pause_prompt "Once Steam is open and you are signed in, press Enter to continue..."
  detect_steam
}

open_vrchat_install() {
  local uri="steam://install/${VRCHAT_APPID}"
  if have xdg-open; then
    run_in_user_shell "xdg-open '$uri' >/dev/null 2>&1" || true
  fi
}

steam_library_paths() {
  local library_vdf="$STEAM_ROOT/steamapps/libraryfolders.vdf"
  if [[ -f "$library_vdf" ]]; then
    python3 - "$library_vdf" <<'PY'
import re
import sys

with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
    text = f.read()

for path in re.findall(r'"path"\s*"([^"]+)"', text):
    print(path.replace('\\\\', '\\'))
PY
  fi
  printf '%s\n' "$STEAM_ROOT"
}

find_appmanifest() {
  local manifest=""
  local lib=""
  while IFS= read -r lib; do
    [[ -n "$lib" ]] || continue
    manifest="$lib/steamapps/appmanifest_438100.acf"
    if [[ -f "$manifest" ]]; then
      printf '%s\n' "$manifest"
      return 0
    fi
  done < <(steam_library_paths | awk '!seen[$0]++')
  return 1
}

detect_vrchat_install() {
  detect_steam
  local manifest
  manifest="$(find_appmanifest "$STEAM_ROOT" || true)"
  if [[ -n "$manifest" ]]; then
    VRCHAT_INSTALLED="yes"
    STEAM_APPS_DIR="$(dirname "$manifest")"
  else
    VRCHAT_INSTALLED="no"
  fi
}

prompt_install_vrchat() {
  detect_vrchat_install
  if [[ "$VRCHAT_INSTALLED" == "yes" ]]; then
    say "VRChat is already installed."
    return
  fi

  say
  say "VRChat is not installed yet. The script will open its Steam install page now."
  open_vrchat_install
  say "Install VRChat in Steam and wait for the download to finish."
  say "Leave Steam open while the download/install completes."
  say "After you confirm it is finished, the script will close Steam automatically and continue."
  while true; do
    pause_prompt "Press Enter after VRChat finishes installing..."
    detect_vrchat_install
    [[ "$VRCHAT_INSTALLED" == "yes" ]] && break
    warn "VRChat still was not detected. Make sure the install finished inside Steam."
  done
}

steam_config_script() {
  cat <<'PY'
import collections
import os
import sys

appid = sys.argv[1]
compat_tool = sys.argv[2]
launch_opts = sys.argv[3]
config_vdf = sys.argv[4]
localconfig_vdf = sys.argv[5]

OrderedDict = collections.OrderedDict

class ParseError(Exception):
    pass

def tokenize(text):
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            i += 2
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c in '{}':
            yield c
            i += 1
            continue
        if c == '"':
            i += 1
            buf = []
            while i < n:
                c = text[i]
                if c == '\\' and i + 1 < n:
                    buf.append(text[i + 1])
                    i += 2
                    continue
                if c == '"':
                    i += 1
                    break
                buf.append(c)
                i += 1
            else:
                raise ParseError('unterminated quoted string')
            yield ('STRING', ''.join(buf))
            continue
        start = i
        while i < n and not text[i].isspace() and text[i] not in '{}':
            i += 1
        yield ('STRING', text[start:i])


def parse_object(tokens, idx=0):
    data = OrderedDict()
    while idx < len(tokens):
        tok = tokens[idx]
        if tok == '}':
            return data, idx + 1
        if tok == '{':
            raise ParseError('unexpected {')
        key = tok[1]
        idx += 1
        if idx >= len(tokens):
            raise ParseError('missing value for key')
        tok = tokens[idx]
        if tok == '{':
            value, idx = parse_object(tokens, idx + 1)
        elif tok == '}':
            raise ParseError('unexpected } after key')
        else:
            value = tok[1]
            idx += 1
        data[key] = value
    return data, idx


def parse_vdf(path, root_name):
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read()
        text = text.lstrip('\ufeff')
        tokens = list(tokenize(text))
        if tokens:
            parsed, idx = parse_object(tokens, 0)
            if idx != len(tokens):
                raise ParseError(f'unparsed tokens remain in {path}')
            if root_name not in parsed or not isinstance(parsed[root_name], dict):
                parsed[root_name] = OrderedDict()
            return parsed
    root = OrderedDict()
    root[root_name] = OrderedDict()
    return root


def ensure_path(data, path):
    cur = data
    for part in path:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = OrderedDict()
        cur = cur[part]
    return cur


def escape(value):
    value = str(value)
    return value.replace('\\', '\\\\').replace('"', '\\"')


def dump_obj(data, indent=0):
    lines = []
    for key, value in data.items():
        key_s = f'"{escape(key)}"'
        if isinstance(value, dict):
            lines.append('\t' * indent + key_s)
            lines.append('\t' * indent + '{')
            lines.extend(dump_obj(value, indent + 1))
            lines.append('\t' * indent + '}')
        else:
            lines.append('\t' * indent + f'{key_s}\t\t"{escape(value)}"')
    return lines


def write_vdf(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = '\n'.join(dump_obj(data)) + '\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)

config = parse_vdf(config_vdf, 'InstallConfigStore')
steam_cfg = ensure_path(config, ['InstallConfigStore', 'Software', 'Valve', 'Steam'])
compat = ensure_path(steam_cfg, ['CompatToolMapping'])
compat[appid] = OrderedDict([
    ('name', compat_tool),
    ('config', ''),
    ('priority', '250'),
])
write_vdf(config_vdf, config)

if launch_opts != '__SKIP__':
    localcfg = parse_vdf(localconfig_vdf, 'UserLocalConfigStore')
    apps = ensure_path(localcfg, ['UserLocalConfigStore', 'Software', 'Valve', 'Steam', 'apps'])
    app = apps.get(appid)
    if not isinstance(app, dict):
        app = OrderedDict()
        apps[appid] = app
    app['LaunchOptions'] = launch_opts
    write_vdf(localconfig_vdf, localcfg)
PY
}

configure_steam_for_vrchat() {
  detect_steam
  [[ -n "$STEAM_ROOT" ]] || die "Steam was not detected."

  check_steam_not_running
  fetch_rtsp_release
  local compat_tool="$RTSP_TOOL_NAME"
  local launch_opts=""
  detect_wivrn

  if [[ "$STEAM_KIND" == "flatpak" ]]; then
    launch_opts=""
  elif [[ "$WIVRN_KIND" == "flatpak" ]]; then
    launch_opts="$DEFAULT_NATIVE_VR_LAUNCH"
  else
    launch_opts='PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%'
  fi
  local localconfig
  local updated_any="no"

  if [[ "$STEAM_KIND" == "flatpak" ]]; then
    say "Flatpak Steam detected."
    say "WiVRn Flatpak overrides were applied globally, so a per-game launch option is usually not needed."
    launch_opts=""
  fi

  [[ -f "$STEAM_CONFIG" ]] || warn "Steam config.vdf not found yet. The script will create the required node if needed."

  if [[ -d "$STEAM_USERDATA_DIR" ]]; then
    if [[ -z "$launch_opts" ]]; then
      launch_opts="__SKIP__"
    fi
    while IFS= read -r localconfig; do
      run_as_user python3 -c "$(steam_config_script)" "$VRCHAT_APPID" "$compat_tool" "$launch_opts" "$STEAM_CONFIG" "$localconfig"
      updated_any="yes"
    done < <(find "$STEAM_USERDATA_DIR" -path '*/config/localconfig.vdf' 2>/dev/null | sort)
  fi

  if [[ "$updated_any" != "yes" ]]; then
    warn "No Steam user localconfig.vdf files were found. Steam may need to be launched once and signed in first."
  else
    say "Steam has been configured so VRChat uses $compat_tool."
    if [[ "$STEAM_KIND" == "native" ]]; then
      say "VRChat launch option was set to: $launch_opts"
      say "If the WiVRn dashboard later shows different launch arguments, use those instead."
    else
      say "Flatpak Steam WiVRn overrides were applied globally."
    fi
  fi
}

install_wayvr_appimage() {
  local target_dir
  target_dir="$(dirname "$WAYVR_BIN")"
  run_as_user mkdir -p \
    "$target_dir" \
    "$(dirname "$WAYVR_DESKTOP")" \
    "$(dirname "$WAYVR_LAUNCHER")" \
    "$STATE_DIR"

  say "Downloading WayVR AppImage: $WAYVR_TAG"
  run_in_user_shell "curl -fL '$WAYVR_URL' -o '$WAYVR_BIN'"
  run_as_user chmod +x "$WAYVR_BIN"

  run_in_user_shell "cat > '$WAYVR_LAUNCHER' <<EOF_WAYVR_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
exec \"$WAYVR_BIN\" \"\$@\"
EOF_WAYVR_LAUNCHER
chmod +x '$WAYVR_LAUNCHER'
cat > '$WAYVR_DESKTOP' <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=WayVR
Exec=$WAYVR_LAUNCHER
TryExec=$WAYVR_LAUNCHER
Icon=applications-games
Terminal=false
Categories=Game;Utility;X-WiVRn-VR;
Keywords=vr;openxr;overlay;wivrn;
StartupNotify=false
EOF_DESKTOP
printf '%s\n' '$WAYVR_TAG' > '$STATE_DIR/wayvr-version.txt'"

  WAYVR_INSTALLED="yes"
}

print_rtsp_changelog() {
  fetch_rtsp_release
  say
  say "Latest Proton-GE-RTSP: $RTSP_TAG"
  say "$RTSP_RELEASE_URL"
  say
  say "$RTSP_NOTES"
}

print_wayvr_changelog() {
  fetch_wayvr_release
  say
  say "Latest WayVR: $WAYVR_TAG"
  say "$WAYVR_RELEASE_URL"
  say
  say "$WAYVR_NOTES"
}

print_status() {
  detect_steam
  detect_vrchat_install
  fetch_rtsp_release
  say "OS:            $OS_NAME"
  say "User:          $REAL_USER"
  say "Steam kind:    ${STEAM_KIND:-not installed}"
  say "Steam root:    ${STEAM_ROOT:-not found}"
  detect_wivrn
  if [[ "$WIVRN_INSTALLED" == "yes" ]]; then
    say "WiVRn:         installed"
    say "WiVRn source:  ${WIVRN_KIND:-unknown}"
    say "WiVRn version: ${WIVRN_VERSION:-unknown}"
  else
    say "WiVRn:         not installed"
  fi
  say "VRChat:        $VRCHAT_INSTALLED"
  local existing_rtsp=""
  existing_rtsp="$(installed_rtsp_versions || true)"

  say "RTSP release:  $RTSP_TAG"
  say "RTSP tool:     $RTSP_TOOL_NAME"
  if [[ -n "$STEAM_ROOT" && -d "$STEAM_ROOT/compatibilitytools.d/$RTSP_TOOL_NAME" ]]; then
    say "RTSP status:   installed (latest)"
  elif [[ -n "$existing_rtsp" ]]; then
    say "RTSP status:   older version(s) installed"
    printf '%s\n' "$existing_rtsp" | sed 's/^/RTSP found:    /'
  else
    say "RTSP status:   not installed"
  fi
  if [[ -x "$WAYVR_BIN" ]]; then
    say "WayVR:         installed ($WAYVR_BIN)"
  else
    say "WayVR:         not installed by this script"
  fi
}

update_mode() {
  detect_steam

  if flatpak info --system "$WIVRN_FLATPAK_ID" >/dev/null 2>&1; then
    say "Checking for WiVRn Flatpak updates..."
    sudo_do flatpak update -y --system "$WIVRN_FLATPAK_ID" || warn "WiVRn Flatpak update failed."
  elif run_as_user flatpak info --user "$WIVRN_FLATPAK_ID" >/dev/null 2>&1; then
    say "Checking for WiVRn Flatpak updates..."
    run_as_user flatpak update -y --user "$WIVRN_FLATPAK_ID" || warn "WiVRn Flatpak update failed."
  fi

  fetch_rtsp_release
  if [[ -n "$STEAM_ROOT" ]]; then
    local rtsp_dest="$STEAM_ROOT/compatibilitytools.d/$RTSP_TOOL_NAME"
    local existing_rtsp=""
    existing_rtsp="$(installed_rtsp_versions || true)"

    if [[ -d "$rtsp_dest" ]]; then
      say "Proton-GE-RTSP is already at the latest detected version: $RTSP_TAG"
    else
      if [[ -n "$existing_rtsp" ]]; then
        say "Detected older Proton-GE-RTSP install(s):"
        printf '%s\n' "$existing_rtsp" | sed 's/^/  - /'
      else
        say "Proton-GE-RTSP is not currently installed."
      fi

      if prompt_yes_no "Install/update Proton-GE-RTSP to $RTSP_TAG?" "Y"; then
        if ensure_steam_closed_for_update; then
          install_rtsp

          if prompt_yes_no "Update Steam's VRChat compatibility selection to $RTSP_TAG now?" "Y"; then
            configure_steam_for_vrchat
          fi
        fi
      fi
    fi
  fi

  if [[ -x "$WAYVR_BIN" ]]; then
    fetch_wayvr_release
    local installed_wayvr=""
    installed_wayvr="$(cat "$STATE_DIR/wayvr-version.txt" 2>/dev/null || true)"

    if [[ "$installed_wayvr" == "$WAYVR_TAG" ]]; then
      say "WayVR is already at the latest detected version: $WAYVR_TAG"
    else
      if prompt_yes_no "Install/update WayVR to $WAYVR_TAG?" "Y"; then
        install_wayvr_appimage
      fi
    fi
  fi
}

repair_eac() {
  detect_vrchat_install
  [[ "$VRCHAT_INSTALLED" == "yes" ]] || die "VRChat is not installed."
  check_steam_not_running

  local compat_root prefix backup shadercache
  compat_root="$STEAM_APPS_DIR/compatdata/$VRCHAT_APPID"
  shadercache="$STEAM_APPS_DIR/shadercache/$VRCHAT_APPID"
  [[ -d "$compat_root" ]] || die "VRChat Proton prefix was not found at $compat_root"

  backup="${compat_root}.backup.$(date +%Y%m%d-%H%M%S)"
  run_as_user mv "$compat_root" "$backup"
  say "Moved VRChat Proton prefix to: $backup"

  if [[ -d "$shadercache" ]] && prompt_yes_no "Also remove VRChat shader cache?" "N"; then
    run_as_user rm -rf "$shadercache"
    say "Removed shader cache: $shadercache"
  fi

  say "On next launch, Steam will regenerate the VRChat Proton prefix."
  say "Do not add SDL_VIDEODRIVER or VR_OVERRIDE yourself for VRChat."
}

create_helper_notes() {
  run_as_user mkdir -p "$STATE_DIR"
  run_in_user_shell "cat > '$STATE_DIR/README.txt' <<"EOF_NOTES"
VRChat Linux setup notes
========================

What this script did:
- Installed or checked Steam
- Installed WiVRn from Flathub
- Enabled avahi-daemon
- Opened WiVRn firewall ports if UFW was active
- Installed Proton-GE-RTSP into Steam's compatibilitytools.d
- Configured Steam so VRChat uses Proton-GE-RTSP
- Installed WayVR if you selected it
- Tried to open WiVRn Dashboard automatically
- Registered WayVR for WiVRn launching instead of trying to start it too early

What each app is for:
- WiVRn Dashboard: the PC-side streaming/server app for connecting your headset
- WayVR: an optional in-VR desktop overlay for viewing screens and launching desktop apps in VR
- VRChat does not require WayVR

What you still need to do manually:
1. Install/open WiVRn on your Quest from the Meta Store.
2. Make sure WiVRn Dashboard is open on the PC.
3. Connect the headset in WiVRn.
4. If you installed WayVR and want to use it, launch it from WiVRn after the headset is connected.
5. If WayVR is running but not visible, double-tap B or Y on the left controller and check the left wrist watch.
6. Launch VRChat after the headset is connected.

Useful commands:
- Re-run interactive menu: bash $SCRIPT_NAME
- Update mode: bash $SCRIPT_NAME update
- EAC repair mode: bash $SCRIPT_NAME repair-eac
EOF_NOTES
"
}

finish_instructions() {
  say
  say "Setup is finished on the Linux side."
  say
  say "What opens automatically:"
  say "  - WiVRn Dashboard is not opened automatically by this script."
  say "    Open WiVRn Server from the desktop app launcher so it will function."
  say
  say
  say "What each thing does:"
  say "  - WiVRn Dashboard is the PC-side streaming/server app. Leave it open, then connect from the headset."
  say "  - WayVR is optional. It is an in-VR desktop overlay for viewing screens and launching desktop apps in VR."
  say "    It must be started after WiVRn is connected so an XR runtime exists."
  say
  say "Do this now:"
  say "  1) On your Quest, install/open WiVRn from the Meta Store."
  say "  2) On the PC, make sure WiVRn Dashboard is open."
  say "  3) Connect the headset to the PC in WiVRn."
  if [[ -x "$WAYVR_BIN" ]]; then
    say "  4) If you want desktop overlays in VR, launch WayVR from WiVRn's application list/drop-down."
    say "     If WayVR is running but you do not see it, double-tap B or Y on the left controller."
    say "     The main WayVR controls are on the left wrist watch."
    say "     On first start, when WayVR asks which display to share, choose the screens it requests."
    say "  5) Launch VRChat from Steam."
  else
    say "  4) Launch VRChat from Steam."
  fi
  if [[ "$STEAM_KIND" == "native" ]]; then
    say "     The script set VRChat's compatibility tool to $RTSP_TOOL_NAME and its launch option to:"
    say "     $DEFAULT_NATIVE_VR_LAUNCH"
    say "     If WiVRn Dashboard shows different launch arguments, replace the launch option with WiVRn's value."
  else
    say "     Flatpak Steam WiVRn overrides were already applied globally."
  fi
  say
}

full_install() {
  require_supported_os
  resolve_real_user
  need_cmds
  ensure_flatpak_stack
  ensure_steam_installed
  check_gpu
  prompt_steam_login
  ensure_wivrn
  prompt_install_vrchat
  close_steam_for_setup
  install_rtsp
  configure_steam_for_vrchat
  ensure_wayvr
  launch_post_install_helpers
  create_helper_notes
  finish_instructions
}

repair_install() {
  require_supported_os
  resolve_real_user
  need_cmds
  ensure_flatpak_stack
  ensure_steam_installed
  check_gpu
  prompt_steam_login
  ensure_wivrn
  prompt_install_vrchat
  close_steam_for_setup

  fetch_rtsp_release

  local existing_rtsp=""
  existing_rtsp="$(installed_rtsp_versions || true)"

  if [[ -d "$STEAM_ROOT/compatibilitytools.d/$RTSP_TOOL_NAME" ]]; then
    say "Latest Proton-GE-RTSP is already installed: $RTSP_TOOL_NAME"
    if prompt_yes_no "Reinstall $RTSP_TOOL_NAME to correct a possible bad or partial install?" "N"; then
      install_rtsp 1
    fi
  elif [[ -n "$existing_rtsp" ]]; then
    say "Detected existing Proton-GE-RTSP install(s):"
    printf '%s\n' "$existing_rtsp" | sed 's/^/  - /'
    if prompt_yes_no "Install/correct to the latest RTSP version ($RTSP_TOOL_NAME)?" "Y"; then
      install_rtsp
    fi
  else
    say "No Proton-GE-RTSP install was detected."
    install_rtsp
  fi

  if prompt_yes_no "Apply or re-apply the optimal VRChat Steam compatibility and launch-option settings now?" "Y"; then
    configure_steam_for_vrchat
  fi

  if [[ -x "$WAYVR_BIN" ]]; then
    say "WayVR is already installed at: $WAYVR_BIN"
    if prompt_yes_no "Reinstall/update WayVR to the latest release?" "N"; then
      fetch_wayvr_release
      install_wayvr_appimage
    fi
  else
    ensure_wayvr
  fi

  launch_post_install_helpers
  create_helper_notes
  finish_instructions
}

full_uninstall() {
  require_supported_os
  resolve_real_user
  need_cmds
  ensure_flatpak_stack
  detect_steam_variants
  detect_steam
  detect_wivrn
  fetch_rtsp_release || true

  say
  warn "This will uninstall Steam, remove WiVRn, remove RTSP, remove WayVR,"
  warn "log you out of Steam, and optionally delete local Steam data and installed games."
  warn "This is meant for a full uninstall."
  say

  prompt_yes_no "Continue to uninstall?" "N" || return 0

  local confirm=""
  read -r -p "Type WIPE to continue: " confirm || exit 1
  [[ "$confirm" == "WIPE" ]] || die "Uninstall cancelled."

  check_steam_not_running

  # Remove RTSP compatibility tools from detected Steam root
  if [[ -n "$STEAM_ROOT" && -d "$STEAM_ROOT/compatibilitytools.d" ]]; then
    say "Removing Proton-GE-RTSP compatibility tools from $STEAM_ROOT/compatibilitytools.d"
    run_as_user find "$STEAM_ROOT/compatibilitytools.d" -maxdepth 1 -mindepth 1 -type d -name 'GE-Proton*-rtsp*' -exec rm -rf {} +
  fi

  # Remove WayVR installed by this script
  if [[ -e "$WAYVR_BIN" || -e "$WAYVR_DESKTOP" || -d "$STATE_DIR" ]]; then
    say "Removing WayVR files installed by this script..."
    run_as_user rm -f "$WAYVR_BIN" "$WAYVR_DESKTOP"
    run_as_user rm -rf "$STATE_DIR"
  fi

  # Remove WiVRn
  detect_wivrn
  if [[ "$WIVRN_KIND" == "flatpak" ]]; then
    say "Uninstalling WiVRn Flatpak..."
    run_as_user flatpak uninstall -y "$WIVRN_FLATPAK_ID" || warn "Failed to uninstall WiVRn Flatpak."
  fi

  if dpkg-query -W -f='${db:Status-Status}\n' wivrn 2>/dev/null | grep -qx installed; then
    say "Removing APT package: wivrn"
    sudo_do apt-get remove -y wivrn || warn "Failed to remove package wivrn."
  fi

  if dpkg-query -W -f='${db:Status-Status}\n' wivrn-dashboard 2>/dev/null | grep -qx installed; then
    say "Removing APT package: wivrn-dashboard"
    sudo_do apt-get remove -y wivrn-dashboard || warn "Failed to remove package wivrn-dashboard."
  fi

  if prompt_yes_no "Disable avahi-daemon? This can affect network discovery for other software too." "N"; then
    sudo_do systemctl disable --now avahi-daemon || warn "Failed to disable avahi-daemon."
  fi

  # Remove Steam packages
  detect_steam_variants

  if [[ "$STEAM_NATIVE_FOUND" == "yes" ]]; then
    if prompt_yes_no "Uninstall native Steam package(s)?" "Y"; then
      for pkg in steam steam-launcher steam-installer; do
        if dpkg-query -W -f='${db:Status-Status}\n' "$pkg" 2>/dev/null | grep -qx installed; then
          say "Removing package: $pkg"
          sudo_do apt-get remove -y "$pkg" || warn "Failed to remove package $pkg."
        fi
      done

      if [[ -f /etc/apt/sources.list.d/steam-stable.list ]]; then
        sudo_do rm -f /etc/apt/sources.list.d/steam-stable.list
      fi
      if [[ -f /usr/share/keyrings/steam.gpg ]]; then
        sudo_do rm -f /usr/share/keyrings/steam.gpg
      fi
      sudo_do apt-get update || true
    fi
  fi

  if [[ "$STEAM_FLATPAK_FOUND" == "yes" || "$STEAM_SNAP_FOUND" == "yes" ]]; then
    if prompt_yes_no "Remove Flatpak/Snap Steam installs too?" "Y"; then
      remove_suboptimal_steam
    fi
  fi

  if prompt_yes_no "Delete Steam user data and default Steam library folders from your home directory? This logs you out and removes local installs in default paths." "N"; then
    say "Removing Steam user data from $REAL_HOME ..."
    run_as_user rm -rf \
      "$REAL_HOME/.steam" \
      "$REAL_HOME/.local/share/Steam" \
      "$REAL_HOME/.var/app/$STEAM_FLATPAK_ID"
  fi

  say
  say "Full uninstall/reset finished."
  say "You can now re-run the installer from a much cleaner state."
}

usage() {
  cat <<EOF_USAGE
Usage: $SCRIPT_NAME [install|repair-install|update|status|repair-eac|rtsp-changelog|wayvr-changelog|uninstall-all|help]

install         Full guided install for Steam + WiVRn + VRChat Proton setup
repair-install  Detect an existing or partial setup and correct/reinstall only what is needed
update          Update important non-auto-updating pieces managed by this script
status          Show detected install status
repair-eac      Move VRChat's Proton prefix aside so Steam regenerates it next launch
rtsp-changelog  Show latest Proton-GE-RTSP release notes
wayvr-changelog Show latest WayVR release notes
uninstall-all   Remove as much of this setup as possible for a true clean re-test
help            Show this help

Run without arguments for the interactive menu.
EOF_USAGE
}

interactive_menu() {
  local choice=""
  while true; do
    say
    say "VRChat on Linux setup"
    say "  1) Full install/setup"
    say "  2) Repair/correct existing install"
    say "  3) Update installed components"
    say "  4) Show status"
    say "  5) Repair VRChat EAC/Proton prefix"
    say "  6) Show latest RTSP changelog"
    say "  7) Show latest WayVR changelog"
    say "  8) Full uninstall/reset"
    say "  9) Quit"
    read -r -p "Select 1-9: " choice || exit 1
    case "$choice" in
      1) full_install ;;
      2) repair_install ;;
      3) require_supported_os; resolve_real_user; need_cmds; ensure_flatpak_stack; detect_steam; update_mode ;;
      4) require_supported_os; resolve_real_user; need_cmds; ensure_flatpak_stack; print_status ;;
      5) require_supported_os; resolve_real_user; need_cmds; ensure_flatpak_stack; repair_eac ;;
      6) require_supported_os; resolve_real_user; need_cmds; print_rtsp_changelog ;;
      7) require_supported_os; resolve_real_user; need_cmds; print_wayvr_changelog ;;
      8) full_uninstall ;;
      9) exit 0 ;;
      *) say "Invalid selection." ;;
    esac
  done
}

main() {
  case "${1:-}" in
    install)
      full_install
      ;;
    repair-install)
      repair_install
      ;;
    update)
      require_supported_os
      resolve_real_user
      need_cmds
      ensure_flatpak_stack
      detect_steam
      update_mode
      ;;
    status)
      require_supported_os
      resolve_real_user
      need_cmds
      ensure_flatpak_stack
      print_status
      ;;
    repair-eac)
      require_supported_os
      resolve_real_user
      need_cmds
      ensure_flatpak_stack
      repair_eac
      ;;
    rtsp-changelog)
      require_supported_os
      resolve_real_user
      need_cmds
      print_rtsp_changelog
      ;;
    wayvr-changelog)
      require_supported_os
      resolve_real_user
      need_cmds
      print_wayvr_changelog
      ;;
    uninstall-all)
      full_uninstall
      ;;
    help|-h|--help)
      usage
      ;;
    "")
      interactive_menu
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
