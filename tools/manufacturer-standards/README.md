# Manufacturer fuel-consumption standards

Pipeline that fills the `manufacturerStandards` Firestore collection the app
uses as the "Brochure" baseline on the Fuels tab.

## What's here

| File | Purpose |
|---|---|
| `build_epa_dataset.py` | Aggregates the EPA bulk dataset into per-model L/100km figures |
| `curated_extra.json` | Hand-verified entries for markets the EPA doesn't cover (GCC/Chinese models). Overrides EPA rows. |
| `manufacturer_standards.json` | Generated output — what gets uploaded |
| `upload_to_firestore.py` | Batch-uploads the JSON into `manufacturerStandards` |

## Refresh / upload

```bash
curl -sL -o /tmp/vehicles.csv.zip "https://www.fueleconomy.gov/feg/epadata/vehicles.csv.zip"
unzip -o /tmp/vehicles.csv.zip -d /tmp/epa
python3 build_epa_dataset.py /tmp/epa/vehicles.csv

# one-time setup (a local venv avoids system pip issues):
python3 -m venv .venv && .venv/bin/pip install firebase-admin

.venv/bin/python upload_to_firestore.py /path/to/serviceAccountKey.json
```

Doc IDs are `<manufacturerKey>__<modelKey>` (e.g. `geely__coolray`), which the
app resolves with one direct read before falling back to fuzzy matching.

## Coverage and how to extend it

The EPA dataset covers every vehicle sold in the US (we aggregate model years
2015+, pure EVs and PHEVs excluded) — all the global brands. It does **not**
cover China-market / GCC-only models (Geely, Chery, Jetour, Haval, Changan,
MG's newer models, etc.). Those go into `curated_extra.json`.

To bulk-fill the gap, run a deep-research AI (ChatGPT Deep Research, Gemini
Deep Research, or Perplexity) with a prompt like:

> For the 60 best-selling China-market and GCC-market vehicles not sold in the
> USA (brands: Geely, Chery, Jetour, Haval/GWM, Changan, MG, BYD, Omoda,
> Soueast, Bestune...), find the official combined fuel consumption in L/100km.
> Prefer WLTC/WLTP figures over NEDC/CLTC; use GCC-spec variants where they
> exist (bitauto.com/global, autohome global, auto-data.net are good sources).
> Skip pure EVs. Output a JSON array with fields: manufacturer, model,
> avgFuelConsumptionL100km (number), yearRange, source (URL + test cycle).
> Only include figures you found an explicit source for.

Paste the result into `curated_extra.json`, re-run `build_epa_dataset.py`,
and upload. Always spot-check a few entries — LLMs mix up test cycles, and a
CLTC number (like the Coolray's 5.6) can be ~10% more optimistic than WLTC.
