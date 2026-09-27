#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="git"
brew="git"
apt="git"
local_bin="$XDG_BIN_HOME/git"
# git finds libexec/git-core relative to bin/, which macOS does not resolve through
# symlinks, so the release tree is installed into the prefix of $XDG_BIN_HOME itself
prefix="${XDG_BIN_HOME%/*}"
release_repo="audivir/zshsetup"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $3}' || echo ""
}

# fetches the latest version
# static builds are published by .github/workflows/build-git.yml as releases tagged git-v<version>
fetch() {
  require_cmd jq || return 1
  local version
  version="$(curl_or_wget "https://api.github.com/repos/$release_repo/releases?per_page=100" \
    | jq -r '[.[].tag_name | select(startswith("git-v"))][0] // empty | ltrimstr("git-v")')"
  if [ -z "$version" ]; then
    echo "No static git release found in $release_repo" >&2
    return 1
  fi
  echo "$version"
}

# installs the most recent version
install() {
  local version url tmpdir
  version="$1"
  set_os_arch "linux" "x86_64" "linux" "aarch64" "macos" "aarch64"
  url="https://github.com/$release_repo/releases/download/git-v$version/git-$version-$os-$arch.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzC "$tmpdir"
  mkdir -p "$prefix/bin" "$prefix/libexec" "$prefix/share"
  # libexec/git-core holds relative symlinks to bin/git, so copy the trees as they are
  cp -R "$tmpdir/bin/." "$prefix/bin/"
  cp -R "$tmpdir/libexec/." "$prefix/libexec/"
  cp -R "$tmpdir/share/." "$prefix/share/"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm -f "$local_bin" "$prefix/bin/git-receive-pack" "$prefix/bin/git-upload-archive" \
    "$prefix/bin/git-upload-pack" "$prefix/share/bash-completion/completions/git"
  rm -rf "$prefix/libexec/git-core" "$prefix/share/git-core"
}

main "$name" "$brew" "$apt" "$@"
