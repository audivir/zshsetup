#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

# user-space glibc for musl hosts, from conda-forge's sysroot (what conda-forge builds against);
# glibc programs need `patchelf --set-interpreter` to use it, see packages/musl/micromamba
name="glibc"
brew=""
apt=""
# the glibc loader, which prints the version with --version
local_bin="$XDG_BIN_HOME/glibc"
install_dir="$XDG_DATA_HOME/glibc"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk 'NR == 1 {sub(/\.$/, "", $NF); print $NF}' || echo ""
}

# queries the newest sysroot build: "version basename"
latest_sysroot() {
  require_cmd jq || return 1
  local arch
  arch="$(uname -m | sed 's/^x86_64$/64/')"
  curl_or_wget "https://api.anaconda.org/package/conda-forge/sysroot_linux-$arch/files" \
    | jq -r '[.[] | select((.basename | endswith(".conda")) and .version != "9999")]
      | sort_by((.version | split(".") | map(tonumber)), .upload_time) | last
      | "\(.version) \(.basename)"'
}

# fetches the latest version
fetch() {
  latest_sysroot | awk '{print $1}'
}

# installs the most recent version
install() {
  require_cmd python3 zstd || return 1
  local version basename tmpdir
  read -r version basename <<<"$(latest_sysroot)"
  if [ "$version" != "$1" ]; then
    echo "$name $1 is not the newest sysroot ($version)" >&2
    return 1
  fi
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "https://conda.anaconda.org/conda-forge/$basename" "$tmpdir/sysroot.conda"
  python3 -m zipfile -e "$tmpdir/sysroot.conda" "$tmpdir/conda"
  mkdir -p "$tmpdir/pkg"
  zstd -dc "$tmpdir"/conda/pkg-*.tar.zst | tar -xC "$tmpdir/pkg"
  rm -rf "$install_dir"
  mv "$tmpdir"/pkg/*-conda-linux-gnu/sysroot "$install_dir"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
  ln -sf "$(echo "$install_dir"/lib64/ld-linux-*.so.*)" "$local_bin"
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
  rm -rf "$install_dir"
}

main "$name" "$brew" "$apt" "$@"
