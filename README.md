# zshsetup

Cross-platform zsh dotfiles and package-manager bootstrap scripts.

`.zshrc` sets up the XDG base directories, oh-my-zsh, and a set of command line tools. Missing
tools are installed on shell start, either with Homebrew, APT, or a manual install script from
`packages/`.

## Prerequisites

- macOS or Linux on x86_64 or arm64
- `curl`, `git`, and `python3`
- `zsh` (installed to `~/.local` with [zsh-bin](https://github.com/romkatv/zsh-bin) if missing)

## Installation

```bash
curl --fail-with-body -L https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh | sh
```

This clones the repo to `~/.config/zshsetup` and links `~/.zshrc` to its `.zshrc`.

If `bash` is the login shell and cannot be changed, switch to `zsh` from `~/.bashrc`:

```bash
export PATH="$PATH:$HOME/.local/bin"
if [[ $- == *i* ]] && command -v zsh >/dev/null 2>&1; then
    exec zsh
fi
```

To keep the `bash` history, convert it into the `zsh` history file:

```bash
python3 <(curl --fail-with-body -L https://gist.githubusercontent.com/muendelezaji/c14722ab66b505a49861b8a74e52b274/raw/bash-to-zsh-hist.py) \
    <~/.bash_history >>~/.config/zshsetup/zsh_history
```

## Usage

- `__update_zshsetup` pulls the latest version, upgrades manually installed packages, and
  updates oh-my-zsh.
- `__uninstall_manual <package>...` removes manually installed packages.
- `showhist` prints the history with readable timestamps.
- Local changes belong below `# BEGIN CUSTOM` in `.zshrc`. Updates stash and reapply them.

Environment variables:

- `ZSHSETUP_CHOICE`: default package manager (`brew`, `apt`, or `manual`) instead of the menu.
- `ZSHSETUP_IGNORESCRATCH`: do not move the cache directory to `/scratch/$USER/.cache`.

## License

MIT, see `LICENSE`. `simple_term_menu.py` is vendored from
[simple-term-menu](https://github.com/IngoMeyer441/simple-term-menu), which is also MIT licensed.
