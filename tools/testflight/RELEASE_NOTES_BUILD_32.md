Build 32: Self-learning odometer calibration + L/100 ↔ km/L toggle.

• EST odometer now learns GPS→dash scale from each refill (EWMA, clamped)
• Garage shows EST → LRN → CAL as calibration advances
• Fill / range prediction uses calibrated km + learned tank range
• Fuels hero: toggle L/100km vs km/L (persists across sessions)
• Fill detail / HUD / widgets respect efficiency unit

Demo: demo@veloseete.app / VeloseeteDemo2026!

Test:
1. Fuels — switch L/100 ↔ km/L; numbers invert correctly (e.g. 8.0 ↔ 12.5)
2. Log a few full fills with GPS drives between — EST should tighten vs dash
3. Garage meta tag moves EST → LRN → CAL after ~3 good cycles
4. Refuel sheet shows variance + “Learning…” / “Calibrated” hint
