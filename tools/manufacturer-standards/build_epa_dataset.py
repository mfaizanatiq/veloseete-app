#!/usr/bin/env python3
"""
Build manufacturer_standards.json from the EPA fueleconomy.gov bulk dataset.

Source: https://www.fueleconomy.gov/feg/epadata/vehicles.csv.zip
(official EPA test data, every vehicle sold in the US 1984-2026).

We aggregate model years >= MIN_YEAR per (make, model), convert combined MPG
to L/100km, and exclude pure EVs and plug-in hybrids (the app tracks pump
fuel; PHEV label figures would set a misleading baseline).

Curated entries from curated_extra.json (markets the EPA doesn't cover, e.g.
GCC-spec Chinese models) are merged in last and always win over EPA rows.

Usage:
    python3 build_epa_dataset.py /path/to/vehicles.csv
Writes manufacturer_standards.json next to this script.
"""

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

MIN_YEAR = 2015
MPG_TO_L100KM = 235.214583

HERE = Path(__file__).resolve().parent


def key(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.strip().lower()).strip("-")


def main(csv_path: str) -> None:
    buckets: defaultdict[tuple[str, str], list[float]] = defaultdict(list)
    years: defaultdict[tuple[str, str], set[int]] = defaultdict(set)

    with open(csv_path, newline="", encoding="utf-8", errors="replace") as fh:
        for row in csv.DictReader(fh):
            try:
                year = int(row["year"])
                comb = float(row["comb08"])
            except (KeyError, ValueError):
                continue
            if year < MIN_YEAR or comb <= 0:
                continue
            fuel = (row.get("fuelType1") or "").lower()
            atv = (row.get("atvType") or "").lower()
            if "electricity" in fuel or "ev" == atv or "plug-in" in atv:
                continue

            make = row["make"].strip()
            model = row["model"].strip()
            if not make or not model:
                continue
            buckets[(make, model)].append(MPG_TO_L100KM / comb)
            years[(make, model)].add(year)

    entries = []
    for (make, model), values in sorted(buckets.items()):
        span = years[(make, model)]
        entries.append({
            "manufacturer": make,
            "model": model,
            "manufacturerKey": key(make),
            "modelKey": key(model),
            "avgFuelConsumptionL100km": round(mean(values), 2),
            "sampleCount": len(values),
            "yearRange": f"{min(span)}-{max(span)}",
            "source": "EPA fueleconomy.gov (combined label figure)",
        })

    curated_path = HERE / "curated_extra.json"
    curated_count = 0
    if curated_path.exists():
        curated = json.loads(curated_path.read_text())
        by_key = {(e["manufacturerKey"], e["modelKey"]): e for e in entries}
        for extra in curated:
            extra.setdefault("manufacturerKey", key(extra["manufacturer"]))
            extra.setdefault("modelKey", key(extra["model"]))
            by_key[(extra["manufacturerKey"], extra["modelKey"])] = extra
            curated_count += 1
        entries = sorted(
            by_key.values(),
            key=lambda e: (e["manufacturerKey"], e["modelKey"]),
        )

    out = HERE / "manufacturer_standards.json"
    out.write_text(json.dumps(entries, indent=1))
    print(f"wrote {len(entries)} entries ({curated_count} curated) -> {out}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: build_epa_dataset.py /path/to/vehicles.csv")
    main(sys.argv[1])
