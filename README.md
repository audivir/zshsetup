# zshsetup

Cross-platform zsh dotfiles and package-manager bootstrap scripts.

`.zshrc` sets up the XDG base directories, oh-my-zsh, and a set of command line tools. Missing
tools are installed on shell start, either with Homebrew, APT, or a manual install script from
`packages/`.

## Prerequisites

- macOS on arm64, or Linux (glibc, or musl like Alpine) on x86_64 or arm64
- `curl` (or `wget`, `python3`, or `/usr/lib/apt/apt-helper` on Debian/Ubuntu), `tar`, and CA certificates
  for them (`git` is installed from prebuilt binaries if missing)
- `zsh` (installed to `~/.local` with [zsh-bin](https://github.com/romkatv/zsh-bin) if missing)

On minimal environments lacking `sudo`, `curl`, and `wget`, `zshsetup` falls back to system `python3` or `/usr/lib/apt/apt-helper` to automatically bootstrap a static `curl` binary into `~/.local/bin`.

## Installation

```bash
(u="https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh" && if command -v curl >/dev/null 2>&1; then curl -fsSL "$u"; elif command -v wget >/dev/null 2>&1; then wget -O - "$u"; elif command -v python3 >/dev/null 2>&1; then python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$u"; elif [ -x /usr/lib/apt/apt-helper ]; then t=$(mktemp) && /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$u" "$t" >/dev/null 2>&1 && cat "$t" && rm -f "$t"; fi) | sh
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
python3 <(curl -fsSL https://gist.githubusercontent.com/muendelezaji/c14722ab66b505a49861b8a74e52b274/raw/bash-to-zsh-hist.py) \
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

Installed by default (besides `zsh` and `git` from the installer): `oh-my-zsh`, `curl`, `uv`,
`uvc`, `jq`, `gawk`, `micromamba` (not on musl), `go`, `rustup`, `bun`, `bat`, `micro`, and `kv`.
Add others with `ZSHSETUP_REQUIRE_<PACKAGE>`, or skip defaults with `ZSHSETUP_DISABLE_<PACKAGE>`;
dependencies of installed packages are installed either way.

The following packages have bootstrap scripts in `packages/`. All of them download with `curl`,
which is installed first if missing:

- `bat`: `cat` clone with syntax highlighting and Git integration (requires `jq`)
- `bun`: Fast all-in-one JavaScript/TypeScript runtime and toolkit (requires `jq`, `python3`, and `patchelf` on musl)
- `curl`: Command-line tool for transferring data with URLs (requires `jq`, `python3`)
- `gawk`: GNU Awk text processing utility (requires `make`, `zig`, `python3`)
- `git`: Distributed version control system (requires `jq`)
- `glibc`: User-space glibc for musl hosts, from conda-forge's sysroot (requires `jq`, `python3`, `zstd`)
- `go`: The Go programming language toolchain
- `jq`: Command-line JSON processor
- `kv`: Key-value storage CLI (requires `jq`)
- `make`: GNU Make build automation tool (requires `zig`)
- `micro`: Modern terminal-based text editor (requires `jq`)
- `micromamba`: Fast standalone conda package manager (requires `jq`, and `glibc`, `patchelf` on musl)
- `oh-my-zsh`: Community-driven zsh configuration framework (requires `git`, `zsh`)
- `patchelf`: Modifies the loader and RPATH of ELF binaries (Linux only)
- `python3`: Python programming language interpreter (requires `uv`)
- `rustup`: Rust toolchain installer (requires `jq`, and `zig` on musl)
- `uv`: Fast Python package and project manager (requires `jq`)
- `uvc`: Python command wrapper and cache tool (requires `python3`)
- `zig`: Zig compiler and toolchain (requires `python3`)
- `zstd`: Zstandard compression tool (requires `make`, `zig`)

## Platform Notes

- musl (Alpine): `micromamba` is skipped, since it and all conda-forge packages need glibc.
  With `ZSHSETUP_REQUIRE_MICROMAMBA`, it runs with conda-forge's glibc, and a wrapper
  patches new environments with `patchelf`; it also handles `micromamba run` (with `-n`/`-p`).
- musl: `make` and `gawk` are built statically, as zig misaligns `environ` when linking musl
  dynamically on aarch64.
- musl: Rust toolchains need `libgcc_s` and a `cc`; `rustup` puts GCC's `libgcc_s` and a zig
  `cc` wrapper into `~/.local/share/rustup-musl`, and `.zshrc` only uses them if the system has none.
- musl: `bun` needs `libstdc++` and `libgcc`; without them on the system, they are taken from
  Alpine's packages into `~/.local/share/bun-musl`, and `bun` finds them through its RUNPATH.
  `packages/musl/apk-extract` extracts Alpine packages like these without `apk` or root.
- Without `curl`: the static `curl` is bootstrapped with `wget`, `python3`, or `apt-helper`
  (bare Debian/Ubuntu, without TLS verification) and checked against pinned SHA-256 hashes.
  Its musl build is used on all Linux, as the glibc one crashes on older glibc (CentOS 7).
- Without system CA certificates, `GIT_SSL_CAPATH` points `git` at the Mozilla certificates
  bundled with [git-static](https://github.com/audivir/git-static).
- A failed install is skipped for a day (see `failed/`); retry with `install_manual <package>`.

## Environment Variables

Set them already for the installation (e.g. `ZSHSETUP_CHOICE=manual sh`), the installer saves
them to `preinit.zsh` for later shells.

- `ZSHSETUP_CHOICE`: default package manager (`brew`, `apt`, or `manual`) instead of the menu.
- `ZSHSETUP_CHOICE_<PACKAGE>`: package manager for a single package (e.g. `ZSHSETUP_CHOICE_CURL=apt`),
  overriding `ZSHSETUP_CHOICE`.
- `ZSHSETUP_IGNORESCRATCH`: do not move the cache directory to `/scratch/$USER/.cache`.
  A `~/.cache/.zshsetup_do_not_use_scratch` file does the same.
- `ZSHSETUP_REQUIRE_<PACKAGE>`: install a package that is not installed by default
  (e.g. `ZSHSETUP_REQUIRE_ZIG=1`, or `ZSHSETUP_REQUIRE_MICROMAMBA=1` on musl with a user-space glibc).
- `ZSHSETUP_DISABLE_<PACKAGE>`: do not install a default package (e.g. `ZSHSETUP_DISABLE_BUN=1`);
  it is still installed when another package depends on it.
- `ZSHSETUP_GH_TOKEN`: GitHub token for API requests, which are limited to 60 per hour without.
  It is not saved to `preinit.zsh`.
- `ZSHSETUP_RUST_TOOLCHAIN`: default toolchain for a manual `rustup` install (`stable` if unset).

## Testing

`./tests/run_tests.sh` runs the scenarios in `tests/scenarios/` in fresh containers (Alpine,
Debian, Ubuntu, Rocky Linux 8), or with `--native` on the current machine with a temporary `HOME`:
`env` (settings and choices), `packages`, `choices` (apt), `lifecycle` (upgrade, uninstall),
`shell` (a full installation from the working tree), and the slow `musl` (micromamba, Rust, bun) and
`all` (every package through a shell start).
Set `ZSHSETUP_GH_TOKEN` to avoid GitHub's API rate limit.

## License

MIT, see `LICENSE`.
