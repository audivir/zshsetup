#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["doctyper", "jinja2", "msgspec", "mxhttp"]
# ///
"""A simple one-file package manager.

Templates in the spec are Jinja templates with {{ tag }} (the release tag, e.g. "v0.26.1"),
{{ version }} (the tag without a leading "v") and, in download URLs, {{ asset }}.
"""

from __future__ import annotations

import contextlib
import functools
import logging
import os
import platform
import subprocess
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Annotated, Literal, NotRequired, TypeAlias, TypedDict
from urllib.parse import urlsplit

import doctyper
import jinja2
import msgspec
from mxhttp import BearerAuth, Downloader, RawPath, SyncConsumer, base_url, get

if TYPE_CHECKING:
    from collections.abc import Generator

    from _typeshed import StrPath

logger = logging.getLogger("pmg")

GH_TOKEN_ENV = "PMG_GH_TOKEN"

Command: TypeAlias = str
Platform: TypeAlias = Literal["glibc_x64", "glibc_arm64", "musl_x64", "musl_arm64", "macos_arm64"]


class BaseStruct(msgspec.Struct, forbid_unknown_fields=True, kw_only=True): ...


class GitHubRelease(BaseStruct, tag="github", kw_only=True):
    repo: str


class CommandRelease(BaseStruct, tag="command", kw_only=True):
    # prints the latest tag
    cmd: Command


class StaticRelease(BaseStruct, tag="static", kw_only=True):
    tag: str


Release: TypeAlias = GitHubRelease | CommandRelease | StaticRelease


class GitHubDownload(BaseStruct, tag="github", kw_only=True):
    # defaults to the release's repo
    repo: str | None = None


class UrlDownload(BaseStruct, tag="url", kw_only=True):
    url: str


class CommandDownload(BaseStruct, tag="command", kw_only=True):
    # for installers like rustup's; gets {{ tag }} and {{ version }}, needs no asset
    cmd: Command


Download: TypeAlias = GitHubDownload | UrlDownload | CommandDownload


class Asset(TypedDict):
    # file names of a GitHub release or {{ asset }} in download URLs; a missing platform is unsupported
    glibc_x64: NotRequired[str]
    glibc_arm64: NotRequired[str]
    musl_x64: NotRequired[str]
    musl_arm64: NotRequired[str]
    macos_arm64: NotRequired[str]


class External(BaseStruct, kw_only=True):
    brew: str | None = None
    apt: str | None = None
    apk: str | None = None
    dnf: str | None = None
    yum: str | None = None


class Check(BaseStruct, kw_only=True):
    # run on the installed binary; the version is the first match of regex
    args: list[str] = msgspec.field(default_factory=lambda: ["--version"])
    regex: str = r"\d+(?:\.\d+)+"


class Package(BaseStruct, kw_only=True):
    # the name is the spec file's stem
    release: Release
    download: Download
    deps: list[str] = []
    external: External | None = None
    # glibc hosts older than this get the musl asset
    min_glibc: str | None = None
    asset: Asset
    # archives holding a single top-level directory are unpacked into it; name in bin dir = path in archive
    bin: dict[str, str] = {}
    check: Check
    # run in the install dir after unpacking, e.g. to patchelf
    post_install: Command | None = None
    # extra cleanup; files the manager installed are removed anyway
    uninstall: Command | None = None

    def __post_init__(self) -> None:
        dl, rl = self.download, self.release
        if isinstance(dl, GitHubDownload) and not dl.repo:
            if not isinstance(rl, GitHubRelease):
                raise ValueError(
                    "GitHubDownload needs to specify the repo if GitHubRelease is not used"
                )
            dl.repo = rl.repo
        self.min_glibc_tuple  # fails if not parsed correctly

    @property
    def min_glibc_tuple(self) -> tuple[int, ...] | None:
        if not self.min_glibc:
            return None
        return version_tuple(self.min_glibc)


class GitHubAsset(msgspec.Struct, kw_only=True):
    name: str
    browser_download_url: str
    # "sha256:<hex>", only for assets uploaded since mid 2025
    digest: str | None = None


class GitHubReleaseInfo(msgspec.Struct, kw_only=True):
    tag_name: str
    assets: list[GitHubAsset]


@base_url("https://api.github.com")
class GitHubApi(SyncConsumer):
    @get("/repos/{owner}/{name}/releases/latest")
    def latest_release(self, owner: str, name: str) -> GitHubReleaseInfo: ...  # type: ignore[empty-body]

    @get("/repos/{owner}/{name}/releases/tags/{tag}")
    def release(self, owner: str, name: str, tag: str) -> GitHubReleaseInfo: ...  # type: ignore[empty-body]


class Files(SyncConsumer):
    @get("/{path}")
    def download(self, path: Annotated[str, RawPath]) -> Downloader: ...  # type: ignore[empty-body]


def decode(spec: str) -> Package:
    return msgspec.toml.decode(spec, type=Package)


@functools.cache
def github_api() -> GitHubApi:
    token = os.getenv(GH_TOKEN_ENV) or os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN")
    return GitHubApi(auth=BearerAuth(token) if token else None)


def split_repo(repo: str) -> tuple[str, str]:
    owner, _, name = repo.partition("/")
    return owner, name


@functools.cache
def jinja_env() -> jinja2.Environment:
    # undefined variables are errors instead of empty strings
    return jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)


def render(template: str, tag: str, **extra: str) -> str:
    return jinja_env().from_string(template).render(tag=tag, version=tag.removeprefix("v"), **extra)


def glibc_version() -> tuple[int, ...] | None:
    """Returns the G"""
    with contextlib.suppress(ValueError, OSError):
        if value := os.confstr("CS_GNU_LIBC_VERSION"):
            return version_tuple(value.removeprefix("glibc "))
    return None


def version_tuple(version: str) -> tuple[int, ...]:
    """Converts a dot-seperated version to a integer tuple."""
    return tuple(int(part) for part in version.split("."))


def detect_platform(min_glibc: tuple[int, ...] | None) -> Platform:
    """Returns the host's platform, using the musl assets for glibc hosts older than `min_glibc`."""
    system, machine = platform.system(), platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        is_arm = False
    elif machine in {"arm64", "aarch64"}:
        is_arm = True
    else:
        raise ValueError(f"unsupported architecture: {machine}")
    if system == "Darwin":
        if not is_arm:
            raise ValueError("only arm64 is supported on macOS")
        return "macos_arm64"
    if system != "Linux":
        raise ValueError(f"unsupported OS: {system}")
    glibc = glibc_version()
    if glibc is None or (min_glibc and glibc < min_glibc):
        return "musl_arm64" if is_arm else "musl_x64"
    return "glibc_arm64" if is_arm else "glibc_x64"


def fetch_release(pkg: Package) -> str:
    """Returns the latest tag."""
    rl = pkg.release
    if isinstance(rl, GitHubRelease):
        return github_api().latest_release(*split_repo(rl.repo)).tag_name
    if isinstance(rl, CommandRelease):
        return subprocess.run(
            rl.cmd, shell=True, check=True, capture_output=True, text=True
        ).stdout.strip()
    return rl.tag


def download_file(url: str, dest: Path, checksum: str | None = None) -> Path:
    """Downloads `url` to `dest`, verifying `checksum` ("sha256:<hex>") if given."""
    parts = urlsplit(url)
    path = parts.path.lstrip("/") + (f"?{parts.query}" if parts.query else "")
    files = Files(base_url=f"{parts.scheme}://{parts.netloc}", follow_redirects=True)
    # overwrite, as a .part left by a failed checksum would otherwise be resumed
    return files.download(path=path)(dest, checksum=checksum, overwrite=True)


@contextlib.contextmanager
def target_layout() -> Generator[Path]:
    """Creates a temporary target layout."""
    with tempfile.TemporaryDirectory() as tmp:
        # tmp / bin / lib / include / man / completions
        yield Path(tmp)


def run_download(pkg: Package, tag: str, host: Platform, dl_dir: StrPath) -> Path:
    """Renders the url with the host's asset and downloads the data to `dl_dir`."""
    dl_dir = Path(dl_dir)
    dl = pkg.download
    if isinstance(dl, CommandDownload):
        raise NotImplementedError("CommandDownload not yet supported")
    asset_template = pkg.asset.get(host)
    if asset_template is None:
        raise ValueError(f"no asset for {host}")
    asset = render(asset_template, tag)
    if isinstance(dl, GitHubDownload):
        if not dl.repo:
            raise RuntimeError("GitHubDownload's repo not set in __post_init__")
        info = github_api().release(*split_repo(dl.repo), tag=tag)
        found = next((a for a in info.assets if a.name == asset), None)
        if found is None:
            raise ValueError(f"{dl.repo} {tag} has no asset {asset}")
        return download_file(found.browser_download_url, dl_dir / asset, found.digest)
    url = render(dl.url, tag, asset=asset)
    return download_file(url, dl_dir / Path(urlsplit(url).path).name)


bat_test = """
min_glibc = "2.18"
bin = { bat = "bat" }
check = {}

# [external] # external not yet done
# brew = "bat"
# apt = "bat"

[release]
type = "github"
repo = "sharkdp/bat"

[download]
type = "github"

[asset]
glibc_x64 = "bat-{{ tag }}-x86_64-unknown-linux-gnu.tar.gz"
glibc_arm64 = "bat-{{ tag }}-aarch64-unknown-linux-gnu.tar.gz"
musl_x64 = "bat-{{ tag }}-x86_64-unknown-linux-musl.tar.gz"
musl_arm64 = "bat-{{ tag }}-aarch64-unknown-linux-musl.tar.gz"
macos_arm64 = "bat-{{ tag }}-aarch64-apple-darwin.tar.gz"
"""


def install_package(pkg_name: str) -> None:
    try:
        pkg = get_pkg_from_registry(pkg_name)
        tag = fetch_release(pkg)
        host = detect_platform(pkg.min_glibc_tuple)
        with tempfile.TemporaryDirectory() as dl_dir, target_layout() as target:
            archive = run_download(pkg, tag, host, dl_dir)
            run_install(archive, target)
            track_installed_files()
            verify_no_overwrites()
            move_data()
    except BaseException:
        rewind_state()
        raise


def install(pkg_names: str):
    # assert xdg_spec is set!
    #
    deps = create_dependency_graph(pkg_names)  # in correct order
    for dep in deps:
        install_package(dep)
    for p in pkg_names:
        if p in deps:
            continue
        install_package(p)


def uninstall_package(name: str) -> None:
    try:
        pkg = get_pkg_from_registry(name)
        check_for_reverse_deps()
        remove_installed_files()
        run_postuninstall()
        unset_installed()
        unset_dependencies()
    except:
        raise ValueError("failed to install")


def uninstall(pkg_names: list[str]) -> None:
    for p in pkg_names:
        uninstall_package(p)


def autoremove() -> None:
    a = list_all_installed()
    b = list_manually_installed()
    c = list_transitive_dependencies()
    for f in a - b - c:
        uninstall_package(f)


if __name__ == "__main__":
    # assert xdg_spec is set!
    app = doctyper.DocTyper()
    app.command()(install)
    app.command()(uninstall)
    app.command()(autoremove)
    try:
        app()
    except Exception as e:
        logger.error("Error: %s", e)
        raise SystemExit(1) from e
