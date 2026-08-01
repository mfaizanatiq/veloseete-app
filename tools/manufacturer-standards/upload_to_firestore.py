#!/usr/bin/env python3
"""
Upload manufacturer_standards.json into the `manufacturerStandards` collection.

Doc IDs are "<manufacturerKey>__<modelKey>" so the app can resolve a vehicle
with a single direct document read; existing docs with the same ID are
overwritten, legacy docs with other IDs are left untouched.

Setup:
    pip install firebase-admin
    Download a service-account key from Firebase console
    (Project settings -> Service accounts -> Generate new private key).

Usage:
    python3 upload_to_firestore.py /path/to/serviceAccountKey.json
"""

import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

HERE = Path(__file__).resolve().parent
BATCH_LIMIT = 400


def main(key_path: str) -> None:
    entries = json.loads((HERE / "manufacturer_standards.json").read_text())

    firebase_admin.initialize_app(credentials.Certificate(key_path))
    db = firestore.client()
    collection = db.collection("manufacturerStandards")

    batch = db.batch()
    pending = 0
    written = 0
    for entry in entries:
        doc_id = f"{entry['manufacturerKey']}__{entry['modelKey']}"
        batch.set(collection.document(doc_id), entry)
        pending += 1
        if pending >= BATCH_LIMIT:
            batch.commit()
            written += pending
            print(f"  committed {written}/{len(entries)}")
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
        written += pending
    print(f"done: {written} documents in manufacturerStandards")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: upload_to_firestore.py /path/to/serviceAccountKey.json")
    main(sys.argv[1])
