"""Tests for packages/pmg.py.

Run with:
    uv run --no-project --with pytest --with jinja2 --with msgspec --with mxhttp \
        pytest tests/test_pmg.py

Set PMG_OFFLINE=1 to skip the tests that download from GitHub.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import jinja2
import msgspec
import pytest
from mxhttp import ChecksumMismatchError

if TYPE_CHECKING:
    from types import ModuleType

PMG_PATH = Path(__file__).parents[1] / "packages" / "pmg.py"


def load_pmg() -> ModuleType:
    spec = importlib.util.spec_from_file_location("pmg", PMG_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(PMG_PATH)
    module = importlib.util.module_from_spec(spec)
    # msgspec resolves the structs' annotations through sys.modules
    sys.modules["pmg"] = module
    spec.loader.exec_module(module)
    return module


pmg = load_pmg()

online = pytest.mark.skipif(os.getenv("PMG_OFFLINE") == "1", reason="PMG_OFFLINE=1")

STATIC_SPEC = """
check = {{}}
[external]
[release]
type = "static"
tag = "v1.2.3"
[download]
{download}
[asset]
macos_arm64 = "tool-{{{{ version }}}}.tar.gz"
"""


def static_spec(download: str) -> str:
    return STATIC_SPEC.format(download=download)


def test_decode_bat() -> None:
    bat = pmg.decode(pmg.bat_test)
    assert bat.release == pmg.GitHubRelease(repo="sharkdp/bat")
    assert bat.download.repo == "sharkdp/bat"
    assert bat.external.brew == "bat"
    assert bat.check.args == ["--version"]
    assert bat.bin == {"bat": "bat"}
    assert bat.min_glibc == "2.18"


def test_missing_required_field() -> None:
    with pytest.raises(msgspec.ValidationError, match="missing required field `check`"):
        pmg.decode(pmg.bat_test.replace("check = {}\n", ""))


def test_unknown_field() -> None:
    with pytest.raises(msgspec.ValidationError, match="unknown field `min_glibcc`"):
        pmg.decode(pmg.bat_test.replace("min_glibc", "min_glibcc"))


def test_github_download_needs_repo_without_github_release() -> None:
    with pytest.raises(msgspec.ValidationError, match="GitHubDownload needs to specify the repo"):
        pmg.decode(static_spec('type = "github"'))


def test_render() -> None:
    rendered = pmg.render("{{ tag }} {{ version }} {{ asset }}", "v0.26.1", asset="a.tar.gz")
    assert rendered == "v0.26.1 0.26.1 a.tar.gz"


def test_render_undefined_variable() -> None:
    with pytest.raises(jinja2.UndefinedError, match="'tagg' is undefined"):
        pmg.render("bat-{{ tagg }}", "v1")


@pytest.mark.parametrize(
    ("system", "machine", "glibc", "min_glibc", "expected"),
    [
        ("Darwin", "arm64", None, "2.18", "macos_arm64"),
        ("Linux", "x86_64", "2.39", "2.18", "glibc_x64"),
        ("Linux", "aarch64", "2.39", None, "glibc_arm64"),
        ("Linux", "aarch64", "2.17", "2.18", "musl_arm64"),
        ("Linux", "x86_64", "2.17", None, "glibc_x64"),
        ("Linux", "x86_64", None, None, "musl_x64"),
    ],
)
def test_detect_platform(  # noqa: PLR0913, PLR0917
    monkeypatch: pytest.MonkeyPatch,
    system: str,
    machine: str,
    glibc: str | None,
    min_glibc: str | None,
    expected: str,
) -> None:
    monkeypatch.setattr(pmg.platform, "system", lambda: system)
    monkeypatch.setattr(pmg.platform, "machine", lambda: machine)
    monkeypatch.setattr(pmg, "glibc_version", lambda: glibc)
    assert pmg.detect_platform(min_glibc) == expected


@pytest.mark.parametrize(
    ("system", "machine", "message"),
    [
        ("Darwin", "x86_64", "only arm64"),
        ("Windows", "AMD64", "unsupported OS"),
        ("Linux", "riscv64", "unsupported architecture"),
    ],
)
def test_detect_platform_unsupported(
    monkeypatch: pytest.MonkeyPatch, system: str, machine: str, message: str
) -> None:
    monkeypatch.setattr(pmg.platform, "system", lambda: system)
    monkeypatch.setattr(pmg.platform, "machine", lambda: machine)
    with pytest.raises(ValueError, match=message):
        pmg.detect_platform(None)


def test_fetch_release_static() -> None:
    assert pmg.fetch_release(pmg.decode(static_spec('type = "url"\nurl = "x"'))) == "v1.2.3"


def test_fetch_release_command() -> None:
    spec = pmg.bat_test.replace(
        'type = "github"\nrepo = "sharkdp/bat"', 'type = "command"\ncmd = "echo v9.9.9"', 1
    )
    spec = spec.replace(
        '[download]\ntype = "github"', '[download]\ntype = "github"\nrepo = "sharkdp/bat"'
    )
    assert pmg.fetch_release(pmg.decode(spec)) == "v9.9.9"


def test_run_download_without_asset_for_host(tmp_path: Path) -> None:
    pkg = pmg.decode(static_spec('type = "url"\nurl = "https://example.com/{{ asset }}"'))
    with pytest.raises(ValueError, match="no asset for glibc_x64"):
        pmg.run_download(pkg, "v1.2.3", "glibc_x64", tmp_path)


def test_run_download_command_not_supported(tmp_path: Path) -> None:
    pkg = pmg.decode(static_spec('type = "command"\ncmd = "true"'))
    with pytest.raises(NotImplementedError):
        pmg.run_download(pkg, "v1.2.3", "macos_arm64", tmp_path)


@online
def test_fetch_release_github() -> None:
    assert pmg.fetch_release(pmg.decode(pmg.bat_test)).startswith("v")


@online
@pytest.mark.parametrize(
    "host", ["glibc_x64", "glibc_arm64", "musl_x64", "musl_arm64", "macos_arm64"]
)
def test_run_download_github(tmp_path: Path, host: str) -> None:
    bat = pmg.decode(pmg.bat_test)
    tag = pmg.fetch_release(bat)
    archive = pmg.run_download(bat, tag, host, tmp_path)
    assert archive.name == pmg.render(bat.asset[host], tag)
    assert archive.stat().st_size > 1_000_000


@online
def test_run_download_url(tmp_path: Path) -> None:
    spec = pmg.bat_test.replace(
        '[download]\ntype = "github"',
        '[download]\ntype = "url"\n'
        'url = "https://github.com/sharkdp/bat/releases/download/{{ tag }}/{{ asset }}"',
    )
    bat = pmg.decode(spec)
    archive = pmg.run_download(bat, "v0.26.1", "macos_arm64", tmp_path)
    assert archive.name == "bat-v0.26.1-aarch64-apple-darwin.tar.gz"
    assert archive.stat().st_size > 1_000_000


@online
def test_download_file_checksum(tmp_path: Path) -> None:
    url = (
        "https://github.com/sharkdp/bat/releases/download/v0.26.1/"
        "bat-v0.26.1-aarch64-apple-darwin.tar.gz"
    )
    digest = "sha256:e30beff26779c9bf60bb541e1d79046250cb74378f2757f8eb250afddb19e114"
    dest = tmp_path / "bat.tar.gz"
    with pytest.raises(ChecksumMismatchError):
        pmg.download_file(url, dest, "sha256:" + "0" * 64)
    assert not dest.exists()
    # the .part left by the mismatch must not be resumed
    assert pmg.download_file(url, dest, digest) == dest
