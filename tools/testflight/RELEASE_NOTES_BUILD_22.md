# Veloseete — TestFlight Build 22 (1.0.0)

**Copy the block below into App Store Connect → TestFlight → Build 22 → Test Details → What to Test.**

---

## What to Test

Thanks for testing Veloseete. This build focuses on a smoother first run and smarter drive tracking before you add a car.

### Start without a car
- Sign up or sign in, complete the short intro, and you can use the app **without adding a vehicle first**.
- Tracking shows the default **sedan** on the map and auto-detect can start recording drives as **“Your drive.”**
- Add a car later from **Garage** whenever you’re ready.

### Link earlier drives
- If you tracked drives before adding a car, you’ll get a prompt when you add one: **“Link earlier drives?”**
- Choose **Link to [car name]** to attach them, or **Not this car** to keep them in the review queue.

### Garage & car setup
- **Paint colors** for your car mark (brand lime is the default).
- **Mark carousel** when picking your car icon.
- **Make picker** with popular brands plus a searchable **More** list (including Chinese makes).

### Drives & tracking
- Pending drives: **Confirm all** in My Drives when several are waiting.
- Route lines on the map have a subtle **glow** for easier reading.
- My Drives list layout and sorting refreshed for clearer day grouping.

### Onboarding & sign-in
- New accounts: **permissions intro** comes before any garage sync error screen.
- Email, Apple, and Google sign-in/sign-up should feel consistent; account linking still works if you use the same email across providers.

### Please try
1. Fresh sign-up → skip adding a car → take a short drive → confirm it appears in pending review.
2. Add your first car → test the **link earlier drives** prompt if you had orphan drives.
3. Sign out and sign back in — your session and pending drives should return.
4. Log a fill, browse Garage, and confirm drives after saving a car.

### Known notes
- Confirming a drive **before** any car is in Garage will ask you to add one first (by design).
- Firebase dSYM warnings during upload are normal and do not affect the app.

**Report issues:** Settings → Send feedback, or reply to the TestFlight invite email.

---

## Short version (if ASC field is tight)

Start without a car — track with the default sedan, add Garage later. Link earlier drives when you add your first car. Paint colors, mark carousel, make picker, Confirm all pending drives, map route glow, and smoother new-user onboarding. Please test sign-up, guest tracking, add-car flow, and sign-in again.
