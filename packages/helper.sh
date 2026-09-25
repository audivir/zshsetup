#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

get_latest_github() {
  local repo
  repo="$1"
  curl --fail-with-body -sL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name
}

get_latest_crate() {
  local crate
  crate="$1"
  curl --fail-with-body -sL "https://crates.io/api/v1/crates/$crate" | jq -r .crate.max_stable_version
}

__set_os_arch() {
  local amd_os amd_arch arm_os arm_arch
  arch="$(uname -m)"
  amd_os="$1"
  amd_arch="$2"
  arm_os="$3"
  arm_arch="$4"
  if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
    os="$amd_os"
    arch="$amd_arch"
  elif [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    os="$arm_os"
    arch="$arm_arch"
  else
    echo "Unsupported architecture: $arch" >&2
    return 1
  fi
}

set_os_arch() {
  local linux_amd_os linux_amd_arch linux_arm_os linux_arm_arch macos_amd_os macos_amd_arch macos_arm_os macos_arm_arch
  linux_amd_os="$1"
  linux_amd_arch="$2"
  linux_arm_os="$3"
  linux_arm_arch="$4"
  macos_amd_os="$5"
  macos_amd_arch="$6"
  macos_arm_os="$7"
  macos_arm_arch="$8"
  os="$(uname)"
  if [ "$os" = "Linux" ]; then
    __set_os_arch "$linux_amd_os" "$linux_amd_arch" "$linux_arm_os" "$linux_arm_arch"
  elif [ "$os" = "Darwin" ]; then
    __set_os_arch "$macos_amd_os" "$macos_amd_arch" "$macos_arm_os" "$macos_arm_arch"
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
