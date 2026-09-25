#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="micromamba"
local_bin="$XDG_BIN_HOME/micromamba"
# release tags carry a build suffix (e.g. 2.9.0-0) that micromamba --version omits
version_file="$ZSHSETUP_HOME/versions/micromamba.version"

# check the currently installed version, echo "" if not installed
check() {
  if [ ! -x "$local_bin" ]; then
    echo ""
  elif [ -f "$version_file" ]; then
    cat "$version_file"
  else
    2>/dev/null "$local_bin" --version || echo ""
  fi
}

# fetch the latest version
fetch() {
  get_latest_github "mamba-org/micromamba-releases"
}

# install the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "linux" "64" "linux" "aarch64" "osx" "64" "osx" "arm64"
  url="https://github.com/mamba-org/micromamba-releases/releases/download/$version/micromamba-$os-$arch"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl --fail-with-body -L "$url" -o "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$XDG_BIN_HOME/micromamba"
  trap - EXIT INT TERM
  mkdir -p "$(dirname "$version_file")"
  echo "$version" >"$version_file"
}

# uninstall the installed package
uninstall() {
  rm "$local_bin"
  rm -f "$version_file"
}

main "$name" "$@"
