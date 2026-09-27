"""Integration tests for packages/pmg.py, running it as a CLI against a local HTTP server.

Run with:
    uv run --no-project --with pytest --with doctyper --with jinja2 --with msgspec --with mxhttp \
        pytest tests/test_pmg.py

Set PMG_OFFLINE=1 to skip the test that installs bat from GitHub.
"""

from __future__ import annotations

import dataclasses
import functools
import http.server
import io
import json
import os
import subprocess
import sys
import tarfile
import threading
import zipfile
from pathlib import Path
from typing import TYPE_CHECKING, Literal, TypeAlias, override

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterator

ArchiveFormat: TypeAlias = Literal["tar.gz", "zip", "bare"]

PMG_PATH = Path(__file__).parents[1] / "packages" / "pmg.py"
PLATFORMS = ("glibc_x64", "glibc_arm64", "musl_x64", "musl_arm64", "macos_arm64")


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    @override
    def log_message(self, format: str, *args: object) -> None:
        pass


@pytest.fixture(scope="module")
def server(tmp_path_factory: pytest.TempPathFactory) -> Iterator[tuple[str, Path]]:
    root = tmp_path_factory.mktemp("assets")
    httpd = http.server.ThreadingHTTPServer(
        ("127.0.0.1", 0), functools.partial(QuietHandler, directory=root)
    )
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_port}", root
    httpd.shutdown()


@dataclasses.dataclass
class Env:
    root: Path
    base_url: str
    assets: Path

    @property
    def home(self) -> Path:
        return self.root / "home"

    @property
    def specs(self) -> Path:
        return self.root / "specs"

    @property
    def bin(self) -> Path:
        return self.home / ".local" / "bin"

    def add_package(
        self,
        name: str,
        deps: tuple[str, ...] = (),
        archive_format: ArchiveFormat = "tar.gz",
        post_install: str | None = None,
    ) -> None:
        script = f"#!/bin/sh\necho {name} 1.0\n".encode()
        if archive_format == "tar.gz":
            asset = f"{name}-1.0.tar.gz"
            bin_path = "bin/" + name
            with tarfile.open(self.assets / asset, "w:gz") as tar_file:
                tar_info = tarfile.TarInfo(f"{name}-1.0/bin/{name}")
                tar_info.size, tar_info.mode = len(script), 0o755
                tar_file.addfile(tar_info, io.BytesIO(script))
        elif archive_format == "zip":
            asset = f"{name}-1.0.zip"
            bin_path = name
            with zipfile.ZipFile(self.assets / asset, "w") as zip_file:
                zip_info = zipfile.ZipInfo(name)
                zip_info.external_attr = 0o755 << 16
                zip_file.writestr(zip_info, script)
        else:
            asset = f"{name}-1.0-linux"
            bin_path = "{{ asset }}"
            (self.assets / asset).write_bytes(script)
        lines = [f"deps = {json.dumps(list(deps))}", f'bin = {{ {name} = "{bin_path}" }}']
        if post_install:
            # a TOML literal string, so the shell command needs no escaping
            lines.append(f"post_install = '{post_install}'")
        lines += [
            "check = {}",
            "[external]",
            "[release]",
            'type = "static"',
            'tag = "v1.0"',
            "[download]",
            'type = "url"',
            f'url = "{self.base_url}/{{{{ asset }}}}"',
            "[asset]",
            *(f'{platform} = "{asset}"' for platform in PLATFORMS),
        ]
        self.specs.mkdir(exist_ok=True)
        (self.specs / f"{name}.toml").write_text("\n".join(lines) + "\n")

    def pmg(self, *args: str, ok: bool = True) -> subprocess.CompletedProcess[str]:
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("XDG_", "PMG_SPECS"))
        }
        env |= {"HOME": str(self.home), "PMG_SPECS": str(self.specs)}
        result = subprocess.run(  # noqa: S603
            [sys.executable, str(PMG_PATH), *args],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert (result.returncode == 0) == ok, result.stderr
        return result

    def run_bin(self, name: str) -> str:
        return subprocess.check_output([self.bin / name], text=True).strip()  # noqa: S603

    def installed(self) -> dict[str, str]:
        rows = (line.split() for line in self.pmg("list").stdout.splitlines())
        return {name: kind for name, _, kind in rows}


@pytest.fixture
def env(tmp_path: Path, server: tuple[str, Path]) -> Env:
    base_url, assets = server
    assets_dir = assets / tmp_path.name
    assets_dir.mkdir()
    return Env(tmp_path, f"{base_url}/{tmp_path.name}", assets_dir)


def test_install_resolves_dependencies(env: Env) -> None:
    env.add_package("app", deps=("lib",))
    env.add_package("lib", deps=("base",))
    env.add_package("base")
    env.pmg("install", "app")
    assert env.run_bin("app") == "app 1.0"
    assert env.run_bin("base") == "base 1.0"
    assert env.installed() == {"app": "explicit", "base": "dependency", "lib": "dependency"}


@pytest.mark.parametrize("archive_format", ["tar.gz", "zip", "bare"])
def test_install_unpacks_archive_formats(env: Env, archive_format: ArchiveFormat) -> None:
    # tar.gz has a top-level dir to strip; zip must keep the executable bit it stores
    env.add_package("tool", archive_format=archive_format)
    env.pmg("install", "tool")
    assert env.run_bin("tool") == "tool 1.0"


def test_autoremove_removes_orphans_transitively(env: Env) -> None:
    env.add_package("app", deps=("lib",))
    env.add_package("lib", deps=("base",))
    env.add_package("base")
    env.pmg("install", "app")
    env.pmg("uninstall", "app")
    assert env.installed() == {"base": "dependency", "lib": "dependency"}
    env.pmg("autoremove")
    assert env.installed() == {}
    assert list(env.bin.iterdir()) == []


def test_autoremove_keeps_dependency_requested_directly(env: Env) -> None:
    env.add_package("app", deps=("lib",))
    env.add_package("lib")
    env.pmg("install", "app", "lib")
    env.pmg("uninstall", "app")
    env.pmg("autoremove")
    assert env.installed() == {"lib": "explicit"}


def test_install_promotes_dependency_to_explicit(env: Env) -> None:
    env.add_package("app", deps=("lib",))
    env.add_package("lib")
    env.pmg("install", "app")
    env.pmg("install", "lib")
    env.pmg("uninstall", "app")
    env.pmg("autoremove")
    assert env.installed() == {"lib": "explicit"}


def test_uninstall_refuses_needed_dependency(env: Env) -> None:
    env.add_package("app", deps=("lib",))
    env.add_package("lib")
    env.pmg("install", "app")
    assert "app depends on lib" in env.pmg("uninstall", "lib", ok=False).stderr
    # removing both at once is fine, dependents go first
    env.pmg("uninstall", "lib", "app")
    assert env.installed() == {}


def test_install_refuses_to_overwrite_foreign_file(env: Env) -> None:
    env.add_package("tool")
    env.bin.mkdir(parents=True)
    (env.bin / "tool").write_text("mine")
    assert "exists and does not belong to tool" in env.pmg("install", "tool", ok=False).stderr
    assert (env.bin / "tool").read_text() == "mine"
    assert env.installed() == {}


def test_failed_post_install_leaves_nothing(env: Env) -> None:
    env.add_package("tool", post_install="exit 3")
    assert "exit code 3" in env.pmg("install", "tool", ok=False).stderr
    assert not (env.bin / "tool").exists()
    assert env.installed() == {}
    assert list((env.home / ".local" / "share" / "pmg" / "tmp").iterdir()) == []


def test_post_install_files_are_installed_and_tracked(env: Env) -> None:
    env.add_package("tool", post_install='cp "$PREFIX/bin/tool" "$PREFIX/bin/tool-copy"')
    env.pmg("install", "tool")
    assert env.run_bin("tool-copy") == "tool 1.0"
    env.pmg("uninstall", "tool")
    assert list(env.bin.iterdir()) == []


def test_dependency_cycle(env: Env) -> None:
    env.add_package("a", deps=("b",))
    env.add_package("b", deps=("a",))
    assert "dependency cycle" in env.pmg("install", "a", ok=False).stderr
    assert env.installed() == {}


@pytest.mark.skipif(os.getenv("PMG_OFFLINE") == "1", reason="PMG_OFFLINE=1")
def test_install_bat_from_github(tmp_path: Path) -> None:
    env = {key: value for key, value in os.environ.items() if not key.startswith("XDG_")}
    env["HOME"] = str(tmp_path)
    subprocess.check_call([sys.executable, str(PMG_PATH), "install", "bat"], env=env)  # noqa: S603
    bat = tmp_path / ".local" / "bin" / "bat"
    version = subprocess.check_output([bat, "--version"], text=True)  # noqa: S603
    assert version.startswith("bat ")
