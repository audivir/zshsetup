#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Required command not found: $cmd (needed by ${name:-package})" >&2
      return 1
    fi
  done
}

get_latest_github() {
  require_cmd curl jq || return 1
  local repo
  repo="$1"
  curl --fail-with-body -sL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name
}

get_latest_crate() {
  require_cmd curl jq || return 1
  local crate
  crate="$1"
  curl --fail-with-body -sL "https://crates.io/api/v1/crates/$crate" | jq -r .crate.max_stable_version
}

set_os_arch() {
  local linux_amd_os linux_amd_arch linux_arm_os linux_arm_arch macos_arm_os macos_arm_arch
  linux_amd_os="$1"
  linux_amd_arch="$2"
  linux_arm_os="$3"
  linux_arm_arch="$4"
  macos_arm_os="$5"
  macos_arm_arch="$6"
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

# upgrade the version if it is currently installed
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
  local name cmd version
  name="$1"
  cmd="$2"

  case "$cmd" in
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
    *)
      echo "Unknown subcommand $cmd" >&2
      return 1
      ;;
  esac
}
