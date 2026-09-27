# zshsetup

Cross-platform zsh dotfiles and package-manager bootstrap scripts.

`.zshrc` sets up the XDG base directories, oh-my-zsh, and a set of command line tools. Missing
tools are installed on shell start, either with Homebrew, APT, or a manual install script from
`packages/`.

## Prerequisites

- macOS on arm64, or Linux on x86_64 or arm64
- `curl` (or `wget`, `python3`, or `/usr/lib/apt/apt-helper` on Debian/Ubuntu), `git`, and `tar`
- `zsh` (installed to `~/.local` with [zsh-bin](https://github.com/romkatv/zsh-bin) if missing)

On minimal environments lacking `sudo`, `curl`, and `wget`, `zshsetup` falls back to system `python3` or `/usr/lib/apt/apt-helper` to automatically bootstrap a static `curl` binary into `~/.local/bin`.

## Installation

```bash
(u="https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh" && if command -v curl >/dev/null 2>&1; then curl --fail-with-body -SL "$u"; elif command -v wget >/dev/null 2>&1; then wget -O - "$u"; elif command -v python3 >/dev/null 2>&1; then python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$u"; elif [ -x /usr/lib/apt/apt-helper ]; then t=$(mktemp) && /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$u" "$t" >/dev/null 2>&1 && cat "$t" && rm -f "$t"; fi) | sh
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

- `update_zshsetup` pulls the latest version, upgrades manually installed packages, and
  updates oh-my-zsh.
- `install_manual <package>...` installs manually packaged tools.
- `uninstall_manual <package>...` removes manually installed packages.
- `edit_zshsetup <pre|post>` edits local configuration files with `$EDITOR` (or `micro`).
- `showhist` prints the history with readable timestamps.
- Local changes belong in `preinit.zsh` (before tools and oh-my-zsh) and `postinit.zsh` (after tools and oh-my-zsh).

## Packages

The following packages have bootstrap scripts in `packages/`:

- `bat`: `cat` clone with syntax highlighting and Git integration (requires `curl`, `jq`, `tar`)
- `bun`: Fast all-in-one JavaScript/TypeScript runtime and toolkit (requires `curl`, `jq`, `python3`)
- `curl`: Command-line tool for transferring data with URLs (requires `python3`, `tar`)
- `gawk`: GNU Awk text processing utility (requires `curl`, `make`, `tar`, and `cc` or `zig`)
- `go`: The Go programming language toolchain (requires `curl`, `tar`)
- `jq`: Command-line JSON processor (requires `curl`)
- `kv`: Key-value storage CLI (requires `curl`, `jq`)
- `make`: GNU Make build automation tool (requires `curl`, `tar`, and `cc` or `zig`)
- `micro`: Modern terminal-based text editor (requires `curl`, `jq`, `tar`)
- `micromamba`: Fast standalone conda package manager (requires `curl`, `jq`)
- `oh-my-zsh`: Community-driven zsh configuration framework (requires `curl`, `git`, `zsh`)
- `python3`: Python programming language interpreter (requires `uv`)
- `rustup`: Rust toolchain installer (requires `curl`, `jq`)
- `uv`: Fast Python package and project manager (requires `curl`, `jq`, `tar`)
- `uvc`: Python command wrapper and cache tool (requires `curl`, `sha256sum`)
- `zig`: Zig compiler and toolchain (requires `curl`, `tar`)

## Environment Variables

- `ZSHSETUP_CHOICE`: default package manager (`brew`, `apt`, or `manual`) instead of the menu.
- `ZSHSETUP_IGNORESCRATCH`: do not move the cache directory to `/scratch/$USER/.cache`.
  A `~/.cache/.zshsetup_do_not_use_scratch` file does the same.
- `ZSHSETUP_REQUIRE_ZIG`: install zig even if not required by gawk (when set and non-empty).
- `ZSHSETUP_RUST_TOOLCHAIN`: default toolchain for a manual `rustup` install (`stable` if unset).

## License

MIT, see `LICENSE`. `simple_term_menu.py` is vendored from
[simple-term-menu](https://github.com/IngoMeyer441/simple-term-menu), which is also MIT licensed.
