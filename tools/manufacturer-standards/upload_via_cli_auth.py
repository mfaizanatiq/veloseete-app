#!/usr/bin/env python3
"""
Upload manufacturer_standards.json to Firestore using the local Firebase CLI
login (~/.config/configstore/firebase-tools.json) instead of a service-account
key. Uses the Firestore REST batchWrite API; doc IDs match upload_to_firestore.py
("<manufacturerKey>__<modelKey>").

Usage:
    python3 upload_via_cli_auth.py <project-id>
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIGSTORE = Path.home() / ".config/configstore/firebase-tools.json"

# Public OAuth client of the open-source Firebase CLI (not a secret).
CLI_CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
CLI_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"

BATCH_LIMIT = 500


def post_json(url: str, payload: dict, token: str | None = None) -> dict:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def access_token() -> str:
    refresh = json.loads(CONFIGSTORE.read_text())["tokens"]["refresh_token"]
    result = post_json("https://oauth2.googleapis.com/token", {
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": CLI_CLIENT_ID,
        "client_secret": CLI_CLIENT_SECRET,
    })
    return result["access_token"]


def firestore_fields(entry: dict) -> dict:
    fields = {}
    for name, value in entry.items():
        if isinstance(value, bool):
            fields[name] = {"booleanValue": value}
        elif isinstance(value, int):
            fields[name] = {"integerValue": str(value)}
        elif isinstance(value, float):
            fields[name] = {"doubleValue": value}
        else:
            fields[name] = {"stringValue": str(value)}
    return fields


def main(project_id: str) -> None:
    entries = json.loads((HERE / "manufacturer_standards.json").read_text())
    token = access_token()
    base = f"projects/{project_id}/databases/(default)/documents"
    url = f"https://firestore.googleapis.com/v1/{base}:batchWrite"

    written = 0
    for start in range(0, len(entries), BATCH_LIMIT):
        chunk = entries[start:start + BATCH_LIMIT]
        writes = [{
            "update": {
                "name": f"{base}/manufacturerStandards/"
                        f"{e['manufacturerKey']}__{e['modelKey']}",
                "fields": firestore_fields(e),
            }
        } for e in chunk]
        result = post_json(url, {"writes": writes}, token)
        errors = [s for s in result.get("status", []) if s.get("code") not in (None, 0)]
        if errors:
            sys.exit(f"batch starting at {start} had errors: {errors[:3]}")
        written += len(chunk)
        print(f"  committed {written}/{len(entries)}")

    print(f"done: {written} documents in manufacturerStandards")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: upload_via_cli_auth.py <project-id>")
    main(sys.argv[1])
