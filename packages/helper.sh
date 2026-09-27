#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

packages=(curl git zig make gawk jq micromamba go rustup uv python3 uvc bun bat micro kv)

__available_python3() {
  local py
  py="$(command -v python3 2>/dev/null)" || return 1
  if [[ "$OSTYPE" == darwin* ]] && [ "$py" = "/usr/bin/python3" ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    return 1
  fi
  "$py" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11, 4) else 1)' >/dev/null 2>&1
}

__available_cmd() {
  local cmd="$1"
  if [ "$cmd" = "python3" ]; then
    __available_python3
  else
    command -v "$cmd" >/dev/null 2>&1
  fi
}

# nested package installs reuse the outermost bootstrap, which removes it at the end
__bootstrap_python3() {
  local url dir rc
  dir="${ZSHSETUP_BOOTSTRAP_PYTHON:-}"
  if [ -n "$dir" ]; then
    PATH="$dir/bin:$PATH" "$dir/bin/python3" "$@"
    return
  fi
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64" "unknown-linux-musl"
  url="https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.12.14+20260924-$arch-$os-install_only_stripped.tar.gz"
  dir="$(mktemp -d)"
  if ! curl_or_wget "$url" | tar -xzC "$dir"; then
    rm -rf "$dir"
    return 1
  fi
  rc=0
  ZSHSETUP_BOOTSTRAP_PYTHON="$dir/python" PATH="$dir/python/bin:$PATH" "$dir/python/bin/python3" "$@" || rc=$?
  rm -rf "$dir"
  return "$rc"
}

package_manager() {
  if ! __available_python3; then
    __bootstrap_python3 "$ZSHSETUP_HOME/package_manager.py" "$@"
  else
    python3 "$ZSHSETUP_HOME/package_manager.py" "$@"
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! __available_cmd "$cmd"; then
      if ((${packages[(Ie)$cmd]})) \
        && "$ZSHSETUP_HOME/packages/$cmd.sh" package \
        && __available_cmd "$cmd"; then
        continue
      fi
      echo "Required command not found: $cmd (needed by ${name:-package})" >&2
      return 1
    fi
  done
}

# downloads a file with curl (and falls back to wget if curl is not available)
curl_or_wget() {
  local url dest
  url="$1"
  dest="${2:-}"

  if command -v curl >/dev/null 2>&1; then
    if [ -n "$dest" ]; then
      curl --fail-with-body -sSL "$url" -o "$dest"
    else
      curl --fail-with-body -sSL "$url"
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
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import os, shutil, sys, urllib.request
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
  if [ "$(__libc)" = "musl" ]; then
    echo "zig cc -target $(uname -m)-linux-musl"
  else
    echo "zig cc"
  fi
}

get_latest_github() {
  require_cmd jq || return 1
  local repo
  repo="$1"
  curl_or_wget "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name
}

get_latest_crate() {
  require_cmd jq || return 1
  local crate
  crate="$1"
  curl_or_wget "https://crates.io/api/v1/crates/$crate" | jq -r .crate.max_stable_version
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
set_os_arch() {
  local linux_amd_os linux_amd_arch linux_arm_os linux_arm_arch macos_arm_os macos_arm_arch
  local linux_musl_os linux_musl_arch
  linux_amd_os="$1"
  linux_amd_arch="$2"
  linux_arm_os="$3"
  linux_arm_arch="$4"
  macos_arm_os="$5"
  macos_arm_arch="$6"
  linux_musl_os="${7:-}"
  linux_musl_arch="${8:-}"
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
    if [ "$(__libc)" = "musl" ]; then
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
    *)
      echo "Unknown subcommand $cmd" >&2
      return 1
      ;;
  esac
}
