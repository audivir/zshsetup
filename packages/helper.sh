#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

. "$ZSHSETUP_HOME/packages/packages.sh"

# macOS' /usr/bin/python3 is a stub that opens the developer tools dialog without them
# checks for macOS's stubs in /usr/bin (git, make, cc, python3, ...), which only offer to install
# the developer tools while they are missing
__xcode_stub() {
  [[ "$OSTYPE" == darwin* ]] && [[ "$1" -ef /usr/bin/cc ]] && ! /usr/bin/xcode-select -p >/dev/null 2>&1
}

__usable_python3() {
  local py
  py="$(command -v python3 2>/dev/null)" || return 1
  ! __xcode_stub "$py"
}

__available_python3() {
  __usable_python3 \
    && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11, 4) else 1)' >/dev/null 2>&1
}

__available_cmd() {
  local cmd="$1"
  if [ "$cmd" = "python3" ]; then
    __available_python3
  else
    local cmd_path
    cmd_path="$(command -v "$cmd" 2>/dev/null)" && ! __xcode_stub "$cmd_path"
  fi
}

# nested package installs reuse the outermost bootstrap, which removes it at the end
# installs a package with the package manager from ZSHSETUP_CHOICE_<PACKAGE>, ZSHSETUP_CHOICE, or a menu
# shellcheck disable=SC2206,SC2296,SC2299
package_manager() {
  local name brew apt choice choice_var postinstall
  local -a options sudo apt_install
  name="$1"
  brew="$2"
  apt="$3"
  options=()
  if [ "$(uname)" = "Darwin" ]; then
    [ -n "$brew" ] && options+=(brew)
  elif [ -n "$apt" ]; then
    options+=(apt)
  fi
  options+=(manual)

  echo "Install $name via:" >&2
  choice_var="ZSHSETUP_CHOICE_${${name:u}//-/_}"
  choice="${(P)choice_var:-${ZSHSETUP_CHOICE:-}}"
  if [ -n "$choice" ]; then
    # an unavailable choice (e.g. apt on macOS) falls back to manual
    ((${options[(Ie)$choice]})) || choice="manual"
  elif { : </dev/tty; } 2>/dev/null; then
    PS3="choice: "
    select choice in "${options[@]}"; do
      [ -n "$choice" ] && break
    done </dev/tty >/dev/tty 2>&1
  fi
  if [ -z "$choice" ]; then
    echo "No install choice for $name, set ZSHSETUP_CHOICE or $choice_var" >&2
    return 1
  fi
  echo "$choice" >&2

  case "$choice" in
    manual)
      "$ZSHSETUP_HOME/packages/$name.sh" install || return 1
      ;;
    brew)
      NONINTERACTIVE=1 brew install "$brew" || return 1
      postinstall="$ZSHSETUP_HOME/packages/brew/$brew.sh"
      ;;
    apt)
      sudo=()
      [ "$(id -u)" -eq 0 ] || sudo=(sudo)
      # apt may list several packages, e.g. "curl ca-certificates"
      apt_install=("${sudo[@]}" apt-get install --no-install-recommends --yes ${=apt})
      # fresh systems and containers have no package lists yet
      if ! DEBIAN_FRONTEND=noninteractive "${apt_install[@]}"; then
        "${sudo[@]}" apt-get update && DEBIAN_FRONTEND=noninteractive "${apt_install[@]}" || return 1
      fi
      postinstall="$ZSHSETUP_HOME/packages/apt/${apt%% *}.sh"
      ;;
  esac
  if [ -n "${postinstall:-}" ] && [ -f "$postinstall" ]; then
    "$postinstall" || return 1
  fi
}

# checks with the package's check() whether it is installed, for packages without a command
__installed_package() {
  ((${packages[(Ie)$1]})) && [ -n "$("$ZSHSETUP_HOME/packages/$1.sh" check 2>/dev/null)" ]
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! __available_cmd "$cmd" && ! __installed_package "$cmd"; then
      # rehash, as zsh would otherwise keep running a command it found before, e.g. an old python3
      if ((${packages[(Ie)$cmd]})) \
        && "$ZSHSETUP_HOME/packages/$cmd.sh" package \
        && rehash \
        && { __available_cmd "$cmd" || __installed_package "$cmd"; }; then
        continue
      fi
      echo "Required command not found: $cmd (needed by ${name:-package})" >&2
      return 1
    fi
  done
}

# downloads a file with curl (and falls back to wget if curl is not available)
# downloads without curl, for bootstrapping curl itself and the python3 its installer needs
__bootstrap_download() {
  local url dest
  url="$1"
  dest="${2:-}"

  if command -v curl >/dev/null 2>&1; then
    if [ -n "$dest" ]; then
      curl -fsSL "$url" -o "$dest"
    else
      curl -fsSL "$url"
    fi
    return
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$dest" ]; then
      wget -qO "$dest" "$url"
    else
      wget -qO - "$url"
    fi
    return
  fi
  # python3 needs CA certificates, so apt-helper is still tried after it fails
  if __usable_python3 && python3 -c 'import os, shutil, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1]) as res:
        if len(sys.argv) > 2 and sys.argv[2]:
            with open(sys.argv[2], "wb") as f:
                shutil.copyfileobj(res, f)
        else:
            shutil.copyfileobj(res, sys.stdout.buffer)
except Exception:
    if len(sys.argv) > 2 and sys.argv[2] and os.path.exists(sys.argv[2]):
        os.remove(sys.argv[2])
    raise SystemExit(1)' "$url" "$dest"; then
    return 0
  fi
  if [ -x "/usr/lib/apt/apt-helper" ]; then
    local tmp
    tmp="${dest:-$(mktemp)}"
    if ! /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$url" "$tmp" >/dev/null 2>&1; then
      [ -z "$dest" ] && rm -f "$tmp"
      return 1
    fi
    if [ -z "$dest" ]; then
      cat "$tmp"
      rm -f "$tmp"
    fi
    return 0
  fi
  echo "Failed to download $url with curl, wget, python3, or apt-helper (needed by ${name:-package})" >&2
  return 1
}

# echoes the sha256 of a file, or of stdin without an argument
sha256() {
  python3 -c 'import hashlib, sys
with open(sys.argv[1], "rb") if len(sys.argv) > 1 else sys.stdin.buffer as f:
    print(hashlib.file_digest(f, "sha256").hexdigest())' "$@"
}

# static on musl: zig misaligns environ when linking musl dynamically on aarch64
zig_cc() {
  local version
  if [ "$(__libc)" = "musl" ]; then
    echo "zig cc -target $(uname -m)-linux-musl"
  elif [ "$(uname)" = "Linux" ] && version="$(__glibc_version)" && [ -n "$version" ]; then
    # zig links against its newest glibc unless told the host's
    echo "zig cc -target $(uname -m)-linux-gnu.$version"
  else
    echo "zig cc"
  fi
}

# queries the GitHub API, ZSHSETUP_GH_TOKEN lifts its rate limit of 60 requests per hour
github_api() {
  local -a auth=()
  [ -n "${ZSHSETUP_GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $ZSHSETUP_GH_TOKEN")
  curl -fsSL "${auth[@]}" "https://api.github.com/$1"
}

get_latest_github() {
  require_cmd jq || return 1
  local repo
  repo="$1"
  github_api "repos/$repo/releases/latest" | jq -r .tag_name
}

get_latest_crate() {
  require_cmd jq || return 1
  local crate
  crate="$1"
  curl -fsSL "https://crates.io/api/v1/crates/$crate" | jq -r .crate.max_stable_version
}

# echoes musl, gnu, or nothing if not Linux
__libc() {
  [ "$(uname)" = "Linux" ] || return 0
  if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ]; then
    echo "musl"
    return 0
  fi
  case "$(ldd --version 2>&1 || true)" in
    *musl*) echo "musl" ;;
    *) echo "gnu" ;;
  esac
}

# on musl, linux_musl_os replaces os and linux_musl_arch the libc suffix of arch
# echoes the glibc version, or "" if unknown
__glibc_version() {
  local version
  version="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')" || true
  [ -n "$version" ] || version="$(ldd --version 2>&1 | awk 'NR == 1 {print $NF}')" || true
  echo "$version"
}

# checks that glibc is at least version $1 (or unknown)
__glibc_at_least() {
  local version
  version="$(__glibc_version)"
  autoload -Uz is-at-least
  [ -z "$version" ] || is-at-least "$1" "$version"
}

set_os_arch() {
  local linux_amd_os linux_amd_arch linux_arm_os linux_arm_arch macos_arm_os macos_arm_arch
  local linux_musl_os linux_musl_arch min_glibc
  linux_amd_os="$1"
  linux_amd_arch="$2"
  linux_arm_os="$3"
  linux_arm_arch="$4"
  macos_arm_os="$5"
  macos_arm_arch="$6"
  linux_musl_os="${7:-}"
  linux_musl_arch="${8:-}"
  min_glibc="${9:-}"
  os="$(uname)"
  arch="$(uname -m)"
  if [ "$os" = "Linux" ]; then
    if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
      os="$linux_amd_os"
      arch="$linux_amd_arch"
    elif [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
      os="$linux_arm_os"
      arch="$linux_arm_arch"
    else
      echo "Unsupported architecture: $arch" >&2
      return 1
    fi
    # the musl build also serves glibc hosts too old for the gnu build
    if [ "$(__libc)" = "musl" ] || { [ -n "$min_glibc" ] && ! __glibc_at_least "$min_glibc"; }; then
      [ -n "$linux_musl_os" ] && os="$linux_musl_os"
      [ -n "$linux_musl_arch" ] && arch="${arch%%-*}-$linux_musl_arch"
    fi
  elif [ "$os" = "Darwin" ]; then
    if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
      os="$macos_arm_os"
      arch="$macos_arm_arch"
    else
      echo "Unsupported architecture for macOS: $arch (only arm64 is supported)" >&2
      return 1
    fi
  else
    echo "Unsupported OS: $os" >&2
    return 1
  fi
}

# If temporary directories are needed:
# tmpdir="$(mktemp -d)"
# trap 'rm -rf "$tmpdir"' EXIT INT TERM
# ...
# cd "$tmpdir"
# rm -rf "$tmpdir"
# trap - EXIT INT TERM

# upgrades the version if it is currently installed
upgrade() {
  local name installed latest
  name="$1"

  installed="$(check)"
  if [ -z "$installed" ]; then
    echo "$name is not installed manually, update via package manager" >&2
    exit 0
  fi
  latest="$(fetch)" || return 1
  if [ "$installed" = "$latest" ]; then
    return 0
  fi
  echo "Upgrading $name to $latest..." >&2
  uninstall || return 1
  install "$latest"
}

main() {
  local name brew apt cmd version
  name="$1"
  brew="$2"
  apt="$3"
  cmd="$4"

  case "$cmd" in
    install | upgrade | fetch)
      [ "$name" = "curl" ] || require_cmd curl || return 1
      ;;
  esac
  case "$cmd" in
    package)
      package_manager "$name" "$brew" "$apt"
      ;;
    install)
      version=$(fetch) || return 1
      echo "Installing $name ($version)" >&2
      install "$version"
      ;;
    upgrade)
      upgrade "$name"
      ;;
    uninstall)
      uninstall
      ;;
    fetch)
      fetch
      ;;
    check)
      check
      ;;
    *)
      echo "Unknown subcommand $cmd" >&2
      return 1
      ;;
  esac
}
