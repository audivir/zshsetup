#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="micromamba"
brew="micromamba-static"
apt="micromamba"
local_bin="$XDG_BIN_HOME/micromamba"
# release tags carry a build suffix (e.g. 2.9.0-0) that micromamba --version omits
version_file="$ZSHSETUP_HOME/versions/micromamba.version"
musl_dir="$XDG_DATA_HOME/micromamba-musl"

# checks the currently installed version, echoes "" if not installed
check() {
  if [ ! -x "$local_bin" ]; then
    echo ""
  elif [ -f "$version_file" ]; then
    cat "$version_file"
  else
    2>/dev/null "$local_bin" --version || echo ""
  fi
}

# fetches the latest version
fetch() {
  get_latest_github "mamba-org/micromamba-releases"
}

# installs the most recent version
install() {
  local version url target tmpfile
  version="$1"
  target="$local_bin"
  # micromamba and conda-forge packages need glibc, see packages/musl/micromamba
  if [ "$(__libc)" = "musl" ]; then
    require_cmd patchelf glibc || return 1
    mkdir -p "$musl_dir"
    target="$musl_dir/micromamba"
  fi
  set_os_arch "linux" "64" "linux" "aarch64" "osx" "arm64"
  url="https://github.com/mamba-org/micromamba-releases/releases/download/$version/micromamba-$os-$arch"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl -fsSL "$url" -o "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$target"
  trap - EXIT INT TERM
  if [ "$target" != "$local_bin" ]; then
    patchelf --set-interpreter "$(readlink "$XDG_DATA_HOME/glibc/loader")" \
      --add-rpath "$XDG_DATA_HOME/glibc/lib64:$XDG_DATA_HOME/glibc/usr/lib64" --force-rpath "$target"
    cp "$ZSHSETUP_HOME/packages/musl/micromamba" "$local_bin"
    chmod +x "$local_bin"
  fi
  echo "$version" >"$version_file"
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
  rm -f "$version_file"
  rm -rf "$musl_dir"
}

main "$name" "$brew" "$apt" "$@"
