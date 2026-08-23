# Apple App Review — Demo Account

Paste into **App Store Connect → App Information → App Review Information → Sign-in required**.

| Field | Value |
|-------|--------|
| **Username** | `demo@veloseete.app` |
| **Password** | `VeloseeteDemo2026!` |

## Pro demo experience

**Active garage (3 cars)** — switch active car from Garage (tap a car → **Set as active**):

| Nickname | Car | Role |
|----------|-----|------|
| **Pearl** | Toyota Camry Hybrid LE | Daily commuter (default) — ~5.4 L/100, 14 drives |
| **Sandstorm** | Nissan Patrol LE | Diesel SUV — long Dubai runs, 9 drives |
| **Flash** | BMW 330i M Sport | Sport sedan — 10 shorter drives |

**Archived (1 car)** — expand “Archived” in Garage:

| **Spark** | Honda Civic LX | Sold/archived — history preserved, restore demo |

Each active car has full **Fuels** hero (L/100 + brochure gauge), **fill history**, **My Drives** with Dubai map routes, and **Service** entries.

**Totals:** 27 fills · 38 drives · 8 service records · AED currency · Dubai region

## Refresh demo data

```bash
python3 tools/demo-account/seed_demo_account.py
```

Requires network access to Firebase (`velocity-5e576`).

## Notes for reviewers

- Default selected car: **Pearl** (Fuels tab opens with data immediately).
- Use **Garage → vehicle switcher** to explore Sandstorm and Flash.
- **Spark** demonstrates archive + restore without losing history.
- Location **Always** recommended for live trip tracking demo.
- Email/password sign-in for this account; Apple/Google work for new users.
