# Changelog

## 1.1.0
- Loot toast options: hide the "You won" banner, change its size, or move the alert banners (*Loot toasts* column in the options). The move box has the size and place of a real toast. Off by default: nothing changes until you use them.
- A simpler `/cll`: it now opens the options panel, where every setting lives. The commands that duplicated an option are gone (`grow`, `scale`, `lock`, `unlock`, `native`), and so is `sim chat`. `/cll sim`, `/cll restore` and `/cll debug` stay; `/cll help` lists them.

## 1.0.1
- The roll frames are now **locked** by default, so a real roll never moves by accident. Unlock them with the new option; they are always movable while `/cll sim` rolls are on screen.
- New two-frame icon, used in the addon list and on the minimap button.
- Internal cleanup.

## 1.0.0
First release, for **WoW Forever**.

- Own loot roll frames (Need / Greed / Pass) in place of Blizzard's, with item tooltip, Ctrl+click preview, Shift+click link, quality colours and a timer.
- Live vote counters on each button, with the list of players on hover (class coloured, with the roll once revealed), also on greyed-out buttons.
- A "hasn't rolled yet" clock with the players still deciding.
- Big drops: rolls beyond the 8 frames wait in a queue (with a "+N more" label) instead of being lost; rolls still running come back after a `/reload`; item data not loaded yet is retried; an expired frame closes itself.
- Blizzard's own roll frames are hidden and stop catching clicks (alpha and mouse state only, the managed container is never moved).
- Chat filter for the per-roll lines; who won what and loot receipts stay visible.
- Minimap button (loot history / options) and an options panel under Options > AddOns. Default scale 1.10.
- `/cll sim` drop simulator and `/cll debug` roll tracing.
