#!/bin/sh
# installs oh-my-zsh into $ZSH, keeping .zshrc; .zshrc requires curl and git before
set -eu

url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
curl -fsSL "$url" | sh -s -- --unattended --keep-zshrc
