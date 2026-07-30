---
name: LiveFX axis conventions
description: Assimilate LiveFX Y-up scene vs FreeD Y-forward/Z-up packets; swap symptom and the bridge's --swap-yz fix.
---

LiveFX's internal 3D scene is Y-up / Z-depth, but FreeD packets carry Y=forward, Z=up. Some LiveFX setups read the packet literally instead of converting.

**Symptom:** raising the phone changes CG depth, walking forward changes CG height; left/right stays correct. Mirror/invert toggles cannot fix a swap.

**Fix:** `freed_bridge.py --swap-yz` (or env `SWAP_YZ=1`) swaps FreeD Y/Z position fields right after pose conversion, before trim flips/offsets, so all downstream knobs operate in the final output frame. Banner prints `Axis remap : Y/Z SWAPPED`.

**Why:** user observed wrong axes in LiveFX (July 2026); researched and confirmed LiveFX's Y-up layer-property convention.
