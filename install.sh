#!/bin/sh
# shellcheck shell=sh

__available() {
  cmd="$1"
  shift
  command "$cmd" "$@" >/dev/null 2>&1
}

__download() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl --fail-with-body -sSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$url"
  elif [ -x "/usr/lib/apt/apt-helper" ]; then
    tmp="$(mktemp)"
    if ! /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$url" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      exit 1
    fi
    cat "$tmp"
    rm -f "$tmp"
  else
    echo "curl, wget, python3, or apt-helper required!" >&2
    exit 1
  fi
}

if [ -z "$HOME" ]; then
  echo "HOME must be set"
  exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "Only macOS arm64 is supported" >&2
  exit 1
fi

if { ! __available curl --help && ! __available wget --help && [ ! -x /usr/lib/apt/apt-helper ] && ! __available python3 --version; } || ! __available git --help; then
  echo "curl (or wget/apt-helper/python3) and git required!"
  exit 1
fi

if ! __available zsh --help; then
  export PATH="$PATH:$HOME/.local/bin"
  if ! __available zsh --help; then
    __download https://raw.githubusercontent.com/romkatv/zsh-bin/master/install \
      | sh -s -- -d "$HOME/.local" -e "no" || exit 1
  fi
fi

__download https://github.com/audivir/zshsetup/raw/refs/heads/main/.zshrc | zsh -s -- install
