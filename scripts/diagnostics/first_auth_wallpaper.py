#!/usr/bin/env python3
"""Compare reports taken before applying a video, after applying it, and after a cold boot.

Run as the same logged-in user each time: python3 scripts/diagnostics/first_auth_wallpaper.py
The JSON describes files visible after login. Only observing the first password screen
can establish whether the selected clip actually moved before the first unlock.
"""
import hashlib
import json
import os
import platform
import plistlib
import pwd
import re
import stat
import subprocess
import sys
from pathlib import Path
from uuid import UUID


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=15)


def error_status(error):
    if isinstance(error, FileNotFoundError):
        return "missing"
    if isinstance(error, PermissionError):
        return "permission denied"
    return "unavailable"


def fingerprint(path):
    try:
        if not stat.S_ISREG(path.lstat().st_mode):
            return {"status": "not a regular file"}
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        return {"sha256": digest.hexdigest()}
    except OSError as error:
        return {"status": error_status(error)}


def cache_inventory(directory):
    try:
        entries = list(directory.iterdir())
    except OSError as error:
        return {"status": error_status(error)}
    # Report extensions and content hashes without disclosing account IDs or filenames.
    records = [{"extension": entry.suffix.lower(), **fingerprint(entry)} for entry in entries]
    return sorted(records, key=lambda record: sorted(record.items()))


def active_catalog(major, home, system_support, transaction):
    wallpaper = home / "Library/Application Support/com.apple.wallpaper"
    if major == 15:
        return system_support / "com.apple.idleassetsd/Customer/entries.json"
    if major == 26:
        return wallpaper / "aerials/manifest/entries.json"
    if transaction is None:
        return None
    return wallpaper / "aerials/Hikari" / transaction / "entries.json"


def main():
    if sys.platform != "darwin" or os.getuid() == 0:
        sys.exit("Run on macOS as the logged-in user.")
    version = platform.mac_ver()[0]
    major = int(version.split(".")[0])
    if major not in (15, 26, 27):
        sys.exit("This audit covers macOS 15, 26 and 27.")
    home = Path.home()
    report = {"macOS": version, "build": command("/usr/bin/sw_vers", "-buildVersion").decode().strip()}
    try:
        status = command("/usr/bin/fdesetup", "status").decode().splitlines()
        report["filevault"] = status[0] if status else "unavailable"
    except (OSError, subprocess.SubprocessError):
        report["filevault"] = "unavailable"
    support = home / "Library/Application Support/Hikari"
    transaction = None
    try:
        marker = json.loads((support / "native-lock-active.json").read_bytes())
        transaction = str(UUID(marker["transactionID"])).upper()
        request = json.loads((support / "NativeLockTransactions" / transaction / "request.json").read_bytes())
        digest = request["mediaSHA256"]
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            raise ValueError("invalid media digest")
        report["selected_movie"] = {"sha256": digest.lower()}
    except (OSError, KeyError, TypeError, ValueError, AttributeError):
        report["selected_movie"] = {"status": "active media digest unavailable"}
    catalog = active_catalog(major, home, Path("/Library/Application Support"), transaction)
    report["hikari_catalog"] = fingerprint(catalog) if catalog else {"status": "no active catalog identified"}
    report["user_wallpaper_index"] = fingerprint(home / "Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    try:
        username = pwd.getpwuid(os.getuid()).pw_name
        account_info = command("/usr/bin/dscl", "-plist", ".", "-read", "/Users/" + username, "GeneratedUID")
        account = str(UUID(plistlib.loads(account_info)["dsAttrTypeStandard:GeneratedUID"][0])).upper()
    except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException, KeyError, ValueError, IndexError, TypeError):
        report["account_caches"] = {"status": "account UUID unavailable"}
    else:
        report["desktop_picture_cache"] = cache_inventory(Path("/Library/Caches/Desktop Pictures") / account)
        try:
            disk = plistlib.loads(command("/usr/sbin/diskutil", "info", "-plist", "/"))
            group = str(UUID(disk["APFSVolumeGroupID"])).upper()
            cache = Path("/System/Volumes/Preboot") / group / "var/db/Wallpapers" / account
            report["preboot_wallpaper_cache"] = cache_inventory(cache)
        except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException, KeyError, ValueError, TypeError):
            report["preboot_wallpaper_cache"] = {"status": "startup volume group unavailable"}
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
