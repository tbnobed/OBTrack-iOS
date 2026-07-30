# Memory Index

- [LiveFX axis conventions](livefx-axis-conventions.md) — LiveFX scene is Y-up but FreeD sends Y=forward/Z=up; height↔depth swap symptom is fixed with the bridge's --swap-yz flag, not mirror toggles.

- [FreeD protocol quirks](freed-protocol-quirks.md) — FreeD position units are 64 or 640 per mm depending on vendor (BBC/Mo-Sys vs Vizrt); mismatch shows as exact 10× position error.
- [User-reported breakage pattern](user-reported-breakage-pattern.md) — "broken/missing" reports were stale Xcode builds or swipe-only UX, not regressions; verify vs repo + Build tag first.
