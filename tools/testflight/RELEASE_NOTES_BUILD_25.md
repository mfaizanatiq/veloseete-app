# Veloseete — TestFlight Build 25 (1.0.0)

**Copy the block below into App Store Connect → TestFlight → Build 25 → Test Details → What to Test.**

---

## What to Test

Thanks for testing Veloseete. This build stabilizes the **live map tracker** and makes **profile photos** more reliable after sign-in / backgrounding.

### Map tracker (Drives → Tracking)
- Open **Drives → Tracking** and leave the map open while parked or walking slowly.
- The car mark should stay steady — **not** constantly jittering or skating around.
- Start a short drive (or enable auto-detect) and confirm the car follows smoothly without spinning or jumping.
- Heading should update when you’re clearly moving; parked GPS noise should not spin the car.

### Profile photo
- Set a profile photo in **Profile** (tap the avatar).
- Background the app, return — photo should still be there.
- Sign out and sign back in — photo should reload from this device.
- **Note:** Photos are stored on-device only. Deleting the app or installing fresh clears them until you set one again.

### Still worth checking (from build 24)
- **Garage** lists all active cars; lime card = active.
- Tap a car → **Save changes** / **Set as active** / **Archive**.
- Sign out from Profile should land on login without crashing.

### Multi-car demo (optional)
- **Email:** `demo@veloseete.app`
- **Password:** `VeloseeteDemo2026!`
- Pearl / Sandstorm / Flash active; Spark archived.

### Please try
1. Tracking map while stationary — no glitchy wandering.
2. Short drive — smooth follow, no heading thrash at stops.
3. Set profile photo → leave app → return → confirm it remains.
4. Sign out → sign in → confirm photo returns (same install).
5. Garage multi-car switch + archive still works.

**Report issues:** Settings → Send feedback, or reply to the TestFlight invite email.

---

## Short version (if ASC field is tight)

Build 25: steadier live map tracker (less GPS jitter/heading spin) and more reliable profile photo reload after sign-in/background. Also includes Garage multi-car list + sign-out crash fix from 24. Please test Tracking while parked and moving, and profile photo after sign-out/sign-in.
