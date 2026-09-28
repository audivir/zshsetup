# zshsetup

Cross-platform zsh dotfiles with a package manager for tools in the home directory.

`.zshrc` sets up the XDG base directories, oh-my-zsh, and a set of command line tools. Missing
tools are installed on shell start, either with Homebrew, APT, apk, or
[pmg](https://github.com/audivir/pmg), a package manager for prebuilt binaries that needs no admin
rights.

## Prerequisites

- macOS on arm64, or Linux (glibc, or musl like Alpine) on x86_64 or arm64
- `uv`, `curl`, `wget`, `python3`, or `/usr/lib/apt/apt-helper` (Debian/Ubuntu), and `tar`
  (`git` is installed from prebuilt binaries if missing)
- `sha256sum` (GNU coreutils, BusyBox) or `shasum` (macOS), unless `uv` is in `PATH`
- `zsh` (installed to `~/.local` with pmg from [zsh-bin](https://github.com/romkatv/zsh-bin) if missing)

`install.sh` runs pmg with `uvx`, at the tag `packages/pmg` pins. `packages/pmg` installs that tag
once into its own venv in `~/.local/share/zshsetup/pmg` and runs it from there, reinstalling it
when the pin changes. Without a `uv` in `PATH`, both download a fixed uv into `~/.cache/zshsetup/uv` with any of the tools above and check
its SHA-256: the gnu build on glibc 2.28 or newer, else the static musl build. uv brings the
Python for pmg, and pmg its own CA certificates, so no system certificates are needed.

## Installation

```bash
(u="https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh" && if command -v uv >/dev/null 2>&1; then uv run --quiet --no-project --with certifi python -c 'import certifi, shutil, ssl, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1], context=ssl.create_default_context(cafile=certifi.where())); shutil.copyfileobj(res, sys.stdout.buffer)' "$u"; elif command -v curl >/dev/null 2>&1; then curl -fsSL "$u"; elif command -v wget >/dev/null 2>&1; then wget -O - "$u"; elif command -v python3 >/dev/null 2>&1; then python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$u"; elif [ -x /usr/lib/apt/apt-helper ]; then t=$(mktemp) && /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$u" "$t" >/dev/null 2>&1 && cat "$t" && rm -f "$t"; fi) | sh
```

This clones the repo to `~/.config/zshsetup` and links `~/.zshrc` to its `.zshrc`.

To try it in a container, each image downloads `install.sh` with the tool it has, installs every
package with pmg, and starts `zsh` from `~/.local/bin`. `GH_TOKEN` avoids GitHub's API rate limit
and needs the [GitHub CLI](https://cli.github.com):

```bash
# Alpine (BusyBox wget)
docker run -it --rm -e ZSHSETUP_CHOICE=manual -e GH_TOKEN="$(gh auth token)" alpine:3.22 sh -c 'wget -qO- https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh | sh && PATH="$HOME/.local/bin:$PATH" exec zsh'
# Debian (apt-helper, as there is neither curl, wget, python3, nor CA certificates)
docker run -it --rm -e ZSHSETUP_CHOICE=manual -e GH_TOKEN="$(gh auth token)" debian:stable-slim sh -c 't=$(mktemp) && /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh "$t" >/dev/null && sh "$t" && PATH="$HOME/.local/bin:$PATH" exec zsh'
# Ubuntu (apt-helper, as for Debian)
docker run -it --rm -e ZSHSETUP_CHOICE=manual -e GH_TOKEN="$(gh auth token)" ubuntu:24.04 sh -c 't=$(mktemp) && /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh "$t" >/dev/null && sh "$t" && PATH="$HOME/.local/bin:$PATH" exec zsh'
# Rocky Linux 8 (curl)
docker run -it --rm -e ZSHSETUP_CHOICE=manual -e GH_TOKEN="$(gh auth token)" rockylinux:8 sh -c 'curl -fsSL https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh | sh && PATH="$HOME/.local/bin:$PATH" exec zsh'
# CentOS 7 (curl, glibc 2.17)
docker run -it --rm -e ZSHSETUP_CHOICE=manual -e GH_TOKEN="$(gh auth token)" centos:7 sh -c 'curl -fsSL https://github.com/audivir/zshsetup/raw/refs/heads/main/install.sh | sh && PATH="$HOME/.local/bin:$PATH" exec zsh'
```

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

- `update_zshsetup` pulls the latest version, updates the specs of pmg, upgrades the packages of
  pmg, and updates oh-my-zsh.
- `install_manual <package>...` installs packages with pmg, `uninstall_manual <package>...` removes
  them.
- `pmg` is in `PATH` with completions, e.g. `pmg list`, `pmg use bat@v0.25.0`, or `pmg --help`.
- `edit_zshsetup <pre|post>` edits local configuration files with `$EDITOR` (or `micro`).
- `showhist` prints the history with readable timestamps.
- Local changes belong in `preinit.zsh` (before tools and oh-my-zsh) and `postinit.zsh` (after tools and oh-my-zsh).

## Packages

Installed by default (besides `zsh` and `git` from the installer): `oh-my-zsh`, `curl`, `uv`,
`uvc`, `jq`, `gawk`, `micromamba` (not on musl), `go`, `rustup`, `bun`, `bat`, `micro`, and `kv`.
Add others with `ZSHSETUP_REQUIRE_<PACKAGE>`, or skip defaults with `ZSHSETUP_DISABLE_<PACKAGE>`;
dependencies of installed packages are installed either way.

The specs of pmg for `bat`, `kv`, `micro`, and `uvc` are in `packages/specs/`, all others in
[pmg-specs](https://github.com/audivir/pmg-specs): `bun`, `cc` (a C compiler through zig), `curl`,
`gawk`, `git`, `glibc`, `go`, `jq`, `make`, `micromamba`, `musl`, `musl-libs`, `patchelf`,
`rustup`, `uv`, `zig`, `zsh`, and `zstd`. pmg installs dependencies like `cc` for `rustup` or `musl-libs`
for `bun` on musl, and skips those the system already has.

## Platform Notes

- musl (Alpine): `micromamba` is skipped, since it and all conda-forge packages need glibc.
  With `ZSHSETUP_REQUIRE_MICROMAMBA`, it runs with conda-forge's glibc, and a wrapper
  patches new environments with `patchelf`; it also handles `micromamba run` (with `-n`/`-p`).
- Rust links with `cc`; without one (bare Linux, macOS without developer tools), pmg installs `cc`,
  a wrapper around zig.
- macOS without developer tools: the stubs in `/usr/bin` (`git`, `make`, `cc`, `python3`, ...) only
  offer to install them, so they count as missing and the packages are installed instead.
- musl: Rust toolchains need `libgcc_s` and `bun` needs `libstdc++`; without them on the system,
  the `musl-libs` package takes them from Alpine's packages, without `apk` or root. `bun` finds
  them through its RUNPATH, Rust through `LD_LIBRARY_PATH`.
- Old glibc (CentOS 7, RHEL 8): `uv` (glibc 2.28) and `bat` (2.18) use their static musl builds
  where the system cannot run the gnu builds. `kv` (2.39) uses its dynamic musl build, as it loads
  pdfium at runtime, with the loader of the `musl` package set by `patchelf`.
- Without system CA certificates, `GIT_SSL_CAPATH` and `MAMBA_SSL_VERIFY` point `git` and
  `micromamba` at the Mozilla certificates bundled with [git-static](https://github.com/audivir/git-static).
- A failed install is skipped for a day (see `failed/`); retry with `install_manual <package>`.

## Environment Variables

Set them already for the installation (e.g. `ZSHSETUP_CHOICE=manual sh`), the installer saves
them to `preinit.zsh` for later shells.

- `ZSHSETUP_CHOICE`: default package manager (`brew`, `apt`, `apk`, or `manual` for pmg) instead of
  the menu.
- `ZSHSETUP_CHOICE_<PACKAGE>`: package manager for a single package (e.g. `ZSHSETUP_CHOICE_CURL=apt`),
  overriding `ZSHSETUP_CHOICE`.
- `ZSHSETUP_IGNORESCRATCH`: do not move the cache directory to `/scratch/$USER/.cache`.
  A `~/.cache/.zshsetup_do_not_use_scratch` file does the same.
- `ZSHSETUP_REQUIRE_<PACKAGE>`: install a package that is not installed by default
  (e.g. `ZSHSETUP_REQUIRE_ZIG=1`, or `ZSHSETUP_REQUIRE_MICROMAMBA=1` on musl with a user-space glibc).
- `ZSHSETUP_DISABLE_<PACKAGE>`: do not install a default package (e.g. `ZSHSETUP_DISABLE_BUN=1`);
  it is still installed when another package depends on it.
- `PMG_GH_TOKEN`: GitHub token for the API requests of pmg, which are limited to 60 per hour
  without. It is not saved to `preinit.zsh`.
- `PMG_RUST_TOOLCHAIN`: default toolchain for the `rustup` install of pmg (`stable` if unset).
- `PMG_SPECS_DIR`: specs of pmg to use instead of `packages/specs/`.
- `ZSHSETUP_PMG`: pmg to install instead of the pinned tag, as `uv pip install` takes it; a local
  checkout is installed editable.

## Testing

`./tests/run_tests.sh` runs the scenarios in `tests/scenarios/` in fresh containers (Alpine,
Debian, Ubuntu, Rocky Linux 8), or with `--native` on the current machine with a temporary `HOME`:
`env` (settings and choices), `packages`, `choices` (apt), `lifecycle` (upgrade, uninstall),
`shell` (a full installation from the working tree), and the slow `musl` (micromamba, Rust, bun) and
`all` (every package through a shell start). pmg has its own tests in its repo.
Set `PMG_GH_TOKEN` to avoid GitHub's API rate limit.

## License

MIT, see `LICENSE`.
