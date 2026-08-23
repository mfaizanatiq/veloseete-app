# Veloseete — TestFlight Build 24 (1.0.0)

**Copy the block below into App Store Connect → TestFlight → Build 24 → Test Details → What to Test.**

---

## What to Test

Thanks for testing Veloseete. This build fixes **Garage** for accounts with more than one car — you should see every active vehicle in a list, not just the current one.

### Garage — all your cars
- Open **Garage** and confirm **every active car** appears as its own card (not only the active one).
- The **active** car uses the **lime** card and an **Active** badge.
- Other cars use the standard glass card style.
- Header subtitle should read something like **“3 cars · Pearl active”** when you have multiple vehicles.

### Tap a car for details
- Tap any car card — a detail sheet opens (no separate **Edit** button on the list).
- You can change nickname, make, model, fuel type, odometer, tank size, currency, photo, and paint color.
- Tap **Close** to dismiss without saving.

### Set active & archive
- On a **non-active** car’s detail sheet:
  - **Save changes** — updates the car and closes the sheet.
  - **Set as active** — switches which car is active; back in Garage, lime highlight should move to that car.
  - **Archive vehicle** — confirmation dialog; car moves to the **Archived** section (history kept).
- On the **active** car: **Archive** is hidden; you’ll see a note to set another car active first if you have more than one.

### Multi-car demo account (optional)
Sign in with the demo account to test quickly:

- **Email:** `demo@veloseete.app`
- **Password:** `VeloseeteDemo2026!`

You should see **Pearl**, **Sandstorm**, and **Flash** in Garage, plus **Spark** under **Archived**.

### Please try
1. Sign in (demo or your account with 2+ cars) → **Garage** → confirm all active cars are listed.
2. Tap a non-active car → **Set as active** → confirm lime highlight and subtitle update.
3. Tap the new active car → edit nickname → **Save changes** → confirm it persists after reopening.
4. Tap a non-active car → **Archive vehicle** → confirm it moves to **Archived** and disappears from the main list.
5. Expand **Archived** → restore or confirm **Spark** (demo) still shows saved drives/fills for that car.
6. Switch tabs (Fuels, Drives) after changing active car — data should follow the newly active vehicle.

### Known notes
- Only **non-archived** cars appear in the main Garage list.
- Archiving does not delete fuel logs, drives, or service for that car.
- If you only have one car, **Set as active** and **Archive** behave as expected for a single-vehicle garage.

**Report issues:** Settings → Send feedback, or reply to the TestFlight invite email.

---

## Short version (if ASC field is tight)

Garage now lists **all active cars** — lime card marks the active one. Tap any card for details; use **Save changes**, **Set as active**, or **Archive** at the bottom (no list Edit button). Demo: demo@veloseete.app / VeloseeteDemo2026! — Pearl, Sandstorm, Flash active; Spark archived. Please test multi-car list, switch active, edit & save, and archive.
