---
name: User-reported breakage pattern
description: How to triage "it's broken / feature missing" reports from this non-technical Mac user before changing code.
---

**Rule:** When the user reports a feature is missing or broken on their iPhone, verify against the repo first — do not assume a code regression.

**Why:** Twice the report turned out not to be a code problem: (1) "settings were removed" — git diff proved nothing was removed; the phone was running a stale build from a different project copy Xcode had open. (2) "calibration doesn't work past step 2" — the wizard used swipe-only TabView page navigation, which is undiscoverable/unreliable (keyboard covers gestures); fixed by adding explicit Back/Next buttons.

**How to apply:**
- First compare their pasted code or symptom against the current repo (git diff / grep) before touching code.
- The main screen's status panel shows a `Build:` tag line (ContentView `buildTag`) — ask what it says to confirm which version the phone runs.
- If code matches, suspect stale Xcode build (Product → Clean Build Folder, "Show in Finder" to confirm project path) or a UX discoverability issue.
- Prefer making interactions explicit (visible buttons over gestures) for this user.
