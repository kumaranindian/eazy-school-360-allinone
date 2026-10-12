#!/usr/bin/env python3
"""Dependency advisory scan for the Dart/Flutter lock file (stdlib only).

Reads pubspec.lock, asks the OSV database (https://osv.dev, ecosystem "Pub")
about every hosted package at its locked version, prints any advisory ids and
exits 1 if there are some. Exit 2 means the scan itself could not run, which
must be treated as "unknown", never as "clean".

Usage: python3 tool/osv_scan_pub.py [pubspec.lock]
Limits: OSV's Pub coverage comes from GitHub/pub advisories; it does not
prove a package is safe, only that no *published* advisory matches.
"""
import json
import re
import sys
import urllib.request

path = sys.argv[1] if len(sys.argv) > 1 else "pubspec.lock"
text = open(path).read().split("\npackages:\n", 1)[1].split("\nsdks:", 1)[0]
pkgs = []
for block in re.split(r"\n(?=  \S+:\n)", "\n" + text):
    name = re.match(r"\s*(\S+):\n", block)
    source = re.search(r"source: (\w+)", block)
    version = re.search(r'\n    version: "([^"]+)"', block)
    if name and source and source.group(1) == "hosted" and version:
        pkgs.append((name.group(1), version.group(1)))

body = json.dumps(
    {"queries": [{"package": {"name": n, "ecosystem": "Pub"}, "version": v} for n, v in pkgs]}
).encode()
req = urllib.request.Request(
    "https://api.osv.dev/v1/querybatch", data=body, headers={"Content-Type": "application/json"}
)
try:
    results = json.load(urllib.request.urlopen(req, timeout=120))["results"]
except Exception as error:  # network, DNS, JSON ...
    print(f"scan could not run: {error!r}")
    sys.exit(2)

bad = [(pkgs[i], [v["id"] for v in r["vulns"]]) for i, r in enumerate(results) if r.get("vulns")]
print(f"checked {len(pkgs)} hosted packages; {len(bad)} with advisories")
for (name, version), ids in bad:
    print(f"  {name} {version}: {', '.join(ids)}")
sys.exit(1 if bad else 0)
