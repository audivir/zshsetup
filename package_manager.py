#!/usr/bin/env python3
"""CLI for installing a utility with a user-selected package manager."""

# ruff: noqa: S603,S607
from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Any, Literal

from simple_term_menu import TerminalMenu

if TYPE_CHECKING:
    from typing import TypeAlias

ENV_VAR_NAME = "ZSHSETUP_CHOICE"
PACKAGES = Path(__file__).parent / "packages"

ManagerT: TypeAlias = Literal["brew", "apt", "manual"]


def eprint(*args: Any) -> None:
    """Prints to stderr."""
    print(*args, file=sys.stderr)  # noqa: T201


def create_menu(*options: ManagerT) -> ManagerT | None:
    """Returns the package manager from the environment or a terminal menu, or None if cancelled."""
    if choice := os.getenv(ENV_VAR_NAME):
        if choice in options:
            return choice  # type: ignore[return-value]
        return "manual"
    terminal_menu = TerminalMenu(options)
    choice_ix = terminal_menu.show()
    if isinstance(choice_ix, tuple):
        raise RuntimeError("Multiple options selected")  # noqa: TRY004
    if choice_ix is None:
        return None
    return options[choice_ix]


def package_manager(manual_pkg: str, brew_pkg: str, apt_pkg: str) -> None:  # noqa: C901,PLR0912
    """Installs a package with the user-selected package manager."""
    if not manual_pkg:
        raise ValueError("No package name provided")
    manual_script = PACKAGES / f"{manual_pkg}.sh"
    if not manual_script.exists():
        raise ValueError(f"Script to install {manual_pkg} does not exist: {manual_script}")

    options: list[ManagerT] = []
    psys = platform.system()
    if psys == "Darwin":
        if brew_pkg:
            options.append("brew")
    elif psys == "Linux":
        if apt_pkg:
            options.append("apt")
    else:
        raise ValueError(f"Unsupported OS: {psys}")
    options.append("manual")

    eprint(f"Install {manual_pkg} via:")
    choice = create_menu(*options)
    if not choice:
        raise ValueError("Install choice cancelled")
    print(choice)  # noqa: T201

    env = os.environ.copy()
    postinstall_script: Path | None = None
    if choice == "manual":
        subprocess.check_call([manual_script, "install"])
    elif choice == "brew":
        env["NONINTERACTIVE"] = "1"
        subprocess.check_call(["brew", "install", brew_pkg], env=env)
        postinstall_script = PACKAGES / "brew" / f"{brew_pkg}.sh"
    elif choice == "apt":
        env["DEBIAN_FRONTEND"] = "noninteractive"
        subprocess.check_call(
            ["sudo", "apt-get", "install", "--no-install-recommends", "--yes", apt_pkg], env=env
        )
        postinstall_script = PACKAGES / "apt" / f"{apt_pkg}.sh"
    else:
        raise ValueError(f"Unexpected install choice: {choice}")

    if postinstall_script and postinstall_script.exists():
        subprocess.check_call([postinstall_script])


class Namespace(argparse.Namespace):
    """Stores the parsed CLI arguments."""

    manual_pkg: str
    brew_pkg: str
    apt_pkg: str


def parse_args(argv: list[str]) -> Namespace:
    """Parses command line arguments."""
    parser = argparse.ArgumentParser(description="Select a package manager and install a utility.")
    parser.add_argument(
        "manual_pkg", help="name of the manual install script in packages/ (without .sh)"
    )
    parser.add_argument("brew_pkg", help="Homebrew package name, empty string to disable brew")
    parser.add_argument("apt_pkg", help="APT package name, empty string to disable apt")
    return parser.parse_args(argv, namespace=Namespace())


def main() -> int:
    """Runs the CLI and returns the exit code."""
    args = parse_args(sys.argv[1:])
    try:
        package_manager(args.manual_pkg, args.brew_pkg, args.apt_pkg)
    except Exception as e:  # noqa: BLE001
        eprint(e)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
