#!/usr/bin/env python3
"""Host installed integration engines in the Hub without duplicate services."""
import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import tempfile
import time

ALLOWED = {"agx.screen-time", "omaconnect", "oma.nearby"}


def entry_id(entry):
    return entry.get("id") if isinstance(entry, dict) else entry


def service_config(config, plugin_id):
    if plugin_id not in ALLOWED:
        raise ValueError("Unsupported Hub integration")
    result = copy.deepcopy(config)
    plugins = result.setdefault("plugins", [])
    if not isinstance(plugins, list):
        raise ValueError("Invalid plugins configuration")
    settings = {}
    layout = result.get("bar", {}).get("layout", {})
    for section, entries in layout.items():
        if not isinstance(entries, list):
            raise ValueError("Invalid bar layout")
        for entry in entries:
            if entry_id(entry) == plugin_id and isinstance(entry, dict):
                settings.update(entry)
        layout[section] = [entry for entry in entries if entry_id(entry) != plugin_id]
    for entry in plugins:
        if entry_id(entry) == plugin_id and isinstance(entry, dict):
            settings.update(entry)
    settings.pop("id", None)
    result["plugins"] = [entry for entry in plugins if entry_id(entry) != plugin_id]
    hub_entries = [entry for entry in result["plugins"] if entry_id(entry) == "kevin.hub"]
    for section, entries in layout.items():
        for index, entry in enumerate(entries):
            if entry_id(entry) == "kevin.hub":
                if isinstance(entry, str):
                    entry = {"id": "kevin.hub"}
                    entries[index] = entry
                hub_entries.append(entry)
    if not hub_entries:
        hub_entries = [{"id": "kevin.hub"}]
        result["plugins"].append(hub_entries[0])
    # Keep every Hub entry consistent (some installations use several bars).
    integrations = {}
    for entry in hub_entries:
        if isinstance(entry, dict):
            integrations.update(entry.get("integrations", {}))
    integrations[plugin_id] = {**integrations.get(plugin_id, {}), **settings}
    for entry in hub_entries:
        if not isinstance(entry, dict):
            raise ValueError("Invalid Hub service entry")
        entry["integrations"] = copy.deepcopy(integrations)
    disabled = result.setdefault("disabledPlugins", [])
    if plugin_id not in disabled:
        disabled.append(plugin_id)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "enable"])
    parser.add_argument("plugin_id", choices=sorted(ALLOWED))
    args = parser.parse_args()
    plugin_dir = Path(__file__).resolve().parents[2] / args.plugin_id
    manifest_path = plugin_dir / "manifest.json"
    installed = False
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        installed = "service" in manifest.get("kinds", []) and manifest.get("id") == args.plugin_id
    config_path = (Path.home() / ".config/omarchy/shell.json").resolve()
    if args.action == "status":
        config = json.loads(config_path.read_text())
        entries = list(config.get("plugins", []))
        for region in config.get("bar", {}).get("layout", {}).values():
            entries.extend(region)
        enabled = installed and args.plugin_id in config.get("disabledPlugins", []) and any(
            isinstance(e, dict) and e.get("id") == "kevin.hub" and args.plugin_id in e.get("integrations", {})
            for e in entries
        )
        print(json.dumps({"installed": installed, "enabled": enabled}))
        return
    if not installed:
        raise ValueError("Install the integration from the Omarchy plugin manager first.")
    with config_path.with_name(".hub-services.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for _ in range(3):
            original = config_path.read_bytes()
            config = json.loads(original)
            updated = service_config(config, args.plugin_id)
            if updated == config:
                return
            payload = (json.dumps(updated, indent=2, ensure_ascii=False) + "\n").encode()
            with tempfile.NamedTemporaryFile(dir=config_path.parent, prefix=".hub-services-", delete=False) as tmp:
                temp_path = Path(tmp.name)
                tmp.write(payload)
                tmp.flush()
                os.fsync(tmp.fileno())
            try:
                os.chmod(temp_path, config_path.stat().st_mode & 0o777)
                if config_path.read_bytes() != original:
                    continue
                backup = Path.home() / ".local/state/omarchy/plugin-backups" / ("hub-service-config-" + str(time.time_ns()) + ".json")
                backup.parent.mkdir(parents=True, exist_ok=True)
                backup.write_bytes(original)
                os.chmod(backup, 0o600)
                os.replace(temp_path, config_path)
                return
            finally:
                temp_path.unlink(missing_ok=True)
        raise RuntimeError("Configuration changed during activation. Try again.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, RuntimeError) as error:
        raise SystemExit(str(error)) from error
