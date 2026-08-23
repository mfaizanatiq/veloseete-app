# Veloseete · Portfolio screenshot pack

Ready for case studies, App Store previews, and your personal portfolio.

## Folders

### `screenshots/live/` — real Simulator captures (your account)

| File | Screen |
|---|---|
| `01-drives-tracking.png` | Live tracking map + odometer estimate |
| `02-fuels.png` | Fuels hero, brochure gauge, Coolray stats |
| `03-service.png` | Service tab |
| `04-garage.png` | Garage / fleet |
| `05-driver.png` | Driver hub, badges, insights |
| `06-my-drives.png` | My Drives history |

### `screenshots/` — studio frames (notifications + intelligence explainers)

| File | Story |
|---|---|
| `01`–`07` | UI recreations (Fuels, history, fill detail, live drive, confirm, driver, garage) |
| `08-notif-low-fuel.png` | Lock-screen low-fuel alert |
| `09-notif-drive.png` | Drive review + service nudges |
| `10-intel-fuel-brain.png` | Multi-signal fuel intelligence |
| `11-intel-flow.png` | Decision flow (when we stay quiet) |
| `12-station-map.png` | Station picker |
| `w01`–`w03` | Wide case-study frames (1280×800) |

Use **live** shots for authenticity. Use **studio** shots for notifications and “how the brain works” slides that don’t exist as a single in-app screen.

## Captions

See `CAPTIONS.md`.

## Regenerate studio frames

```bash
cd portfolio
npm install
npx playwright install chromium
node capture.mjs
```

Open `studio.html` in a browser to preview frames.

## Regenerate live frames

Sign into Simulator, then:

```bash
xcrun simctl spawn booted defaults write com.veloseete.app portfolio.forceTab -string fuel
# trips | fuel | service | details | driver
xcrun simctl spawn booted defaults write com.veloseete.app portfolio.forceTripsMode -string "My Drives"
xcrun simctl launch booted com.veloseete.app
# wait for load, then:
xcrun simctl io booted screenshot portfolio/screenshots/live/xx.png
```

## Suggested case-study flow

1. **See the car** — `live/02-fuels.png` + `08-notif-low-fuel.png` + `10-intel-fuel-brain.png`  
2. **Drive without friction** — `live/01-drives-tracking.png` + `live/06-my-drives.png` + `05-pending-review.png`  
3. **Personality** — `live/05-driver.png` + `w02-notif-case.png`
