"""
Utilities for running the built-in :term:`Discovery Server`

.. versionadded:: 0.1.4
"""
from __future__ import annotations

import argparse
import enum
import importlib.resources
import platform
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import cast

from .exceptions import DiscoveryServerUnavailableError


class Platform(enum.Enum):
    """Enumeration of supported platforms for running the :term:`Discovery Server`
    """
    win32 = enum.auto()
    """32-bit Windows platform"""
    win64 = enum.auto()
    """64-bit Windows platform"""
    macos = enum.auto()
    """macOS platform"""
    linux_i686 = enum.auto()
    """Linux platform (i686)"""
    linux_x86_64 = enum.auto()
    """Linux platform (x86_64)"""
    linux_aarch64 = enum.auto()
    """Linux platform (aarch64)"""

    @classmethod
    def current(cls) -> Platform | None:
        """Get the member matching the current platform
        """
        is_x64 = sys.maxsize > 2**32
        if sys.platform == "win32":
            return cls.win64 if is_x64 else cls.win32
        elif sys.platform == "darwin":
            return cls.macos
        elif sys.platform == "linux":
            if platform.machine() == "x86_64":
                return cls.linux_x86_64
            elif platform.machine() == "i686":
                return cls.linux_i686
            elif platform.machine() == "aarch64":
                return cls.linux_aarch64




_platform_bin_map: dict[Platform, Path] = {
    Platform.win32: Path('utilities') / 'Win_x86' / "NDI Discovery Service.exe",
    Platform.win64: Path('utilities') / 'Win_x64' / "NDI Discovery Service.exe",
    Platform.macos: Path('utilities') / 'Apple' / "Application.Mac.NDI.DirectoryService",
    Platform.linux_i686: Path('i686-linux-gnu') / "ndi-discovery-server",
    Platform.linux_x86_64: Path('x86_64-linux-gnu') / "ndi-discovery-server",
    Platform.linux_aarch64: Path('aarch64-rpi4-linux-gnueabi') / "ndi-discovery-server",
}


def get_run_server_path() -> Path:
    """Get the path to the discovery server executable within the package

    Raises:
        DiscoveryServerUnavailableError: If the discovery server is unavailable
            for the current platform
    """
    _bin_path = importlib.resources.files("cyndilib.wrapper.bin")
    bin_path = cast(Path, _bin_path)
    plat = Platform.current()
    if plat is None:
        raise DiscoveryServerUnavailableError(
            "The built-in discovery server is unavailable for the current platform"
        )
    return bin_path / _platform_bin_map[plat]



def parse_run_server_args() -> list[str]:
    """Parse command-line arguments for running the discovery server

    The options here correspond to that of the discovery server command-line interface,
    but match standard CLI argument conventions
    (e.g., using '-' for short options and '--' for long options).

    """
    parser = argparse.ArgumentParser(description="Run the discovery server")
    parser.add_argument(
        '-b', '--bind',
        type=str,
        help="Set the IP address to bind to (default: 0.0.0.0).",
    )
    parser.add_argument(
        '-p', '--port',
        type=int,
        help="Set the port number to bind (0-65535, default: 5959).",
    )
    parser.add_argument(
        '-c', '--config',
        type=Path,
        help="An alternative config file to get the IP and port on where the service will run.",
    )
    parser.add_argument(
        '-s', '--service',
        action='store_true',
        help="Run this in service mode (only for linux/unix).",
    )
    args = parser.parse_args()
    current_platform = Platform.current()
    args_out = []
    if args.bind:
        args_out.extend(['-bind', args.bind])
    if args.port:
        if not (0 <= args.port <= 65535):
            raise ValueError("Port number must be between 0 and 65535")
        args_out.extend(['-port', str(args.port)])
    if args.config:
        args_out.extend(['-config', str(args.config)])
    linux_platforms = (Platform.linux_i686, Platform.linux_x86_64, Platform.linux_aarch64)
    if args.service and current_platform in linux_platforms:
        args_out.append('-service')
    return args_out


def run() -> None:
    """Run the discovery server as a subprocess

    While running, the stdout and stderr of the discovery server will be
    displayed in the terminal.  The process will continue running until
    interrupted by the user (e.g., via :kbd:`Ctrl+C`).


    Raises
    ------

    DiscoveryServerUnavailableError
        If the discovery server is unavailable for the current platform


    .. program:: cyndilib-discovery-server

    Usage
    -----

    .. code-block:: shell

        cyndilib-discovery-server [-h] [-b BIND] [-p PORT] [-c CONFIG] [-s]

    .. option:: -b <BIND>, --bind <BIND>

        Set the IP address to bind to (default: 0.0.0.0).

    .. option:: -p <PORT>, --port <PORT>

        Set the port number to bind (0-65535, default: 5959).

    .. option:: -c <CONFIG>, --config <CONFIG>

        An alternative config file to get the IP and port on where the service will run.

        An example of the JSON configuration file can be seen below:

        .. code-block:: json

            {
                "binding": "127.0.0.1",
                "port_no": 5959
            }

    .. option:: -s <SERVICE>, --service <SERVICE>

        Run this in service mode (only for linux/unix).

        This option allows the discovery server to run as a background service
        utilizing ``systemd`` or other init systems available on the platform.


    If the :option:`--config` option is specified, it will override both the
    :option:`--bind` and :option:`--port` options.

    If no :option:`--config` option is specified, the values for the
    :option:`--bind` and :option:`--port` options will be used.
    If no values are provided for these options, they will use the default values
    or read from the following configuration files depending on the platform:

    - Linux:
        - ``/etc/ndi/ndi-discovery-service.v1.json``
        - ``/usr/local/etc/ndi/ndi-discovery-service.v1.json``
    - Windows:
        - ``%PROGRAMDATA%\\NDI\\ndi-discovery-service.v1.json``

    """
    path = get_run_server_path()
    args = parse_run_server_args()
    creationflags = 0 if sys.platform != "win32" else subprocess.CREATE_NEW_PROCESS_GROUP

    proc = subprocess.Popen([str(path)] + args, creationflags=creationflags)
    try:
        proc.poll()
        if proc.returncode is not None:
            raise RuntimeError(f"Discovery server exited with return code {proc.returncode}")
        while proc.returncode is None:
            proc.poll()
            time.sleep(0.1)
        if proc.returncode is not None:
            raise RuntimeError(f"Discovery server exited with return code {proc.returncode}")
    except KeyboardInterrupt:
        interrupt_signal = (
            signal.CTRL_BREAK_EVENT
            if sys.platform == "win32"
            else signal.SIGINT
        )
        proc.send_signal(interrupt_signal)
        proc.wait(5)
    finally:
        if proc.returncode is None:
            proc.terminate()
            proc.wait()



if __name__ == "__main__":
    run()
