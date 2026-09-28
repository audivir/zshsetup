#!/bin/sh
# shellcheck shell=sh
# installs zshsetup: bootstraps uv, installs zsh and git with pmg where missing, then runs .zshrc

__available() {
  cmd="$1"
  shift
  # macOS's stubs in /usr/bin (git, make, cc, ...) only offer to install the missing developer tools
  if [ "$(uname)" = "Darwin" ] && [ "$(command -v "$cmd")" -ef /usr/bin/cc ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    return 1
  fi
  command "$cmd" "$@" >/dev/null 2>&1
}

# prints a URL with curl, wget, python3, or apt-helper, for bootstrapping uv
__download() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$url"
  elif [ -x "/usr/lib/apt/apt-helper" ]; then
    # without CA certificates, the checksum of uv still guards the download
    tmp="$(mktemp)"
    if ! /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$url" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      return 1
    fi
    cat "$tmp"
    rm -f "$tmp"
  else
    echo "curl, wget, python3, or apt-helper required!" >&2
    return 1
  fi
}

# the gnu build of uv needs glibc 2.28, older glibc and musl get the static musl build
__uv_libc() {
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | cut -d ' ' -f 2)"
  minor="${glibc#2.}"
  if [ -n "$glibc" ] && [ "${minor%%.*}" -ge 28 ]; then
    echo gnu
  else
    echo musl
  fi
}

# installs a fixed uv into $1, checked against its sha256
__bootstrap_uv() {
  case "$(uname -s)-$(uname -m)-$(__uv_libc)" in
    Linux-x86_64-gnu) target="x86_64-unknown-linux-gnu" sha256="23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8" ;;
    Linux-aarch64-gnu) target="aarch64-unknown-linux-gnu" sha256="0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436" ;;
    Linux-x86_64-musl) target="x86_64-unknown-linux-musl" sha256="db7278c9f57981338fddff1fb250e11964bc0a4fafcb9eed8303fdb117dc067b" ;;
    Linux-aarch64-musl) target="aarch64-unknown-linux-musl" sha256="ad8d8448a2ff642ba62c2f684d7dd22a03f8eb3fc9918c2c3e8ec975f4ed6710" ;;
    Darwin-arm64-*) target="aarch64-apple-darwin" sha256="a9a8df1eedeb192f2e47e40e2faabfb387db4b850209118786d42f89dde3e0ba" ;;
    *)
      echo "no uv for $(uname -s) $(uname -m)" >&2
      return 1
      ;;
  esac
  asset="uv-$target.tar.gz"
  url="https://github.com/astral-sh/uv/releases/download/0.12.19/$asset"
  uv_tmp="$(mktemp -d)"
  __download "$url" >"$uv_tmp/$asset" || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$uv_tmp/$asset" | cut -d ' ' -f 1)"
  else
    actual="$(shasum -a 256 "$uv_tmp/$asset" | cut -d ' ' -f 1)"
  fi
  if [ "$actual" != "$sha256" ]; then
    echo "sha256 mismatch for $url" >&2
    rm -rf "$uv_tmp"
    return 1
  fi
  tar -xzf "$uv_tmp/$asset" -C "$uv_tmp" && mkdir -p "$1" && mv "$uv_tmp/${asset%.tar.gz}/uv" "$1/uv"
  status=$?
  rm -rf "$uv_tmp"
  return "$status"
}

if [ -z "$HOME" ]; then
  echo "HOME must be set"
  exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "Only macOS arm64 is supported" >&2
  exit 1
fi

# the bootstrapped uv goes where packages/pmg would put it, so it is reused and cleaned up by .zshrc
uv="$(command -v uv 2>/dev/null)"
if [ -z "$uv" ]; then
  uv="${XDG_CACHE_HOME:-$HOME/.cache}/zshsetup/uv/uv"
  if [ ! -x "$uv" ] && ! __bootstrap_uv "${uv%/uv}"; then
    echo "Failed to bootstrap uv" >&2
    exit 1
  fi
fi

# pmg at the tag packages/pmg pins, into the directories .zshrc uses; uv checks certificates
# with its own, so the system needs none
pmg_tag="v1.1.0"
pmg() {
  XDG_BIN_HOME="$HOME/.local/bin" XDG_DATA_HOME="$HOME/.local/share" PMG_GH_TOKEN="${ZSHSETUP_GH_TOKEN:-}" \
    "$uv" tool run --quiet --from "${ZSHSETUP_PMG:-https://github.com/audivir/pmg/archive/refs/tags/$pmg_tag.tar.gz}" \
    python -m pmg "$@"
}

export PATH="$HOME/.local/bin:$PATH"
if ! __available zsh --version && ! pmg install zsh; then
  echo "Failed to install zsh" >&2
  exit 1
fi

# for tests/lib.sh
if [ -n "${ZSHSETUP_ZSH_ONLY:-}" ]; then
  exit 0
fi

if ! __available git --version && ! pmg install git; then
  echo "Failed to install git" >&2
  exit 1
fi

# runs .zshrc only when fully downloaded, with the certificates of certifi for Python
zshrc="$(mktemp)"
if ! "$uv" run --quiet --no-project --python 3.13 --with certifi python -c 'import shutil, ssl, sys, urllib.request, certifi
context = ssl.create_default_context(cafile=certifi.where())
shutil.copyfileobj(urllib.request.urlopen(sys.argv[1], context=context), sys.stdout.buffer)' \
  https://github.com/audivir/zshsetup/raw/refs/heads/main/.zshrc >"$zshrc"; then
  rm -f "$zshrc"
  echo "Failed to download .zshrc" >&2
  exit 1
fi
zsh "$zshrc" install
status=$?
rm -f "$zshrc"
exit "$status"
