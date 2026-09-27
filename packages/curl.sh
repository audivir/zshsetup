#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="curl"
brew=""
# apt skips the recommended ca-certificates with --no-install-recommends
apt="curl ca-certificates"
local_bin="$XDG_BIN_HOME/curl"
bootstrap_version="8.22.0"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk 'NR == 1 {print $2}' || echo ""
}

# fetches the latest version
fetch() {
  if [ -z "$(check)" ]; then
    echo "$bootstrap_version"
  else
    get_latest_github "stunnel/static-curl"
  fi
}

# installs the most recent version
install() {
  local version url tmpdir expected python
  version="${1:-$bootstrap_version}"
  # the static musl build also runs on glibc; the glibc one crashes on older glibc (CentOS 7)
  set_os_arch "linux" "x86_64-musl" "linux" "aarch64-musl" "macos" "arm64"
  url="https://github.com/stunnel/static-curl/releases/download/$version/curl-$os-$arch-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  __bootstrap_download "$url" "$tmpdir/curl.tar.xz"
  # unpacking the .tar.xz needs python3, but a manual python3 needs uv, which needs curl,
  # so without one a temporary python is used, which is not put on PATH
  if __available_python3; then
    python=python3
  else
    set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64" "unknown-linux-musl"
    __bootstrap_download "https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.12.14+20260924-$arch-$os-install_only_stripped.tar.gz" \
      | tar -xzC "$tmpdir" || return 1
    python="$tmpdir/python/bin/python3"
  fi
  # the bootstrap download may come from apt-helper without TLS verification
  if [ "$version" = "$bootstrap_version" ]; then
    case "$url" in
      *linux-x86_64-musl*) expected=dfb02460ba2abe513087538f12a3cf79b74b64a5ea3787ce8ac0cdb11251f884 ;;
      *linux-aarch64-musl*) expected=cf94cbeaae1b3c1944a4a761ef04478f8f0b23e93a324b5ed009b2082eda11f3 ;;
      *macos-arm64*) expected=416cadcd491e57846d23301e4c56e1a1517668c62f63d4ac991ad6caf4feabea ;;
    esac
    if [ "$("$python" -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$tmpdir/curl.tar.xz")" != "$expected" ]; then
      echo "sha256 mismatch for $url" >&2
      return 1
    fi
  fi
  "$python" -m tarfile --filter data -e "$tmpdir/curl.tar.xz" "$tmpdir"
  chmod +x "$tmpdir/curl"
  mv "$tmpdir/curl" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
