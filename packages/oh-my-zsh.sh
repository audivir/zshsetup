#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

for cmd in curl git zsh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd (needed by oh-my-zsh)" >&2
    exit 1
  fi
done

url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
curl --fail-with-body -L "$url" | sh -s -- -unattended --keep-zshrc
