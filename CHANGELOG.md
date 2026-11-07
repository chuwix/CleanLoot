# Changelog

## 1.2.1
- The winner popup has its own stacking direction (downwards or upwards) in the options, independent of the roll frames. Until you pick one it follows the roll frames, as before.

## 1.2.0
- **Winner popup**: when a roll ends, a small card says who won the item and with which roll, shown as the game's own dice (Need) or coin (Greed) and the number. Your own roll is always on it (or *You passed* / *You did not roll*). Hover a card for every roll of that drop, Need before Greed; right-click closes it. It fades after ten seconds. The roll lines stay out of the chat: the numbers are here now. On by default; turn it off in the options (*Winner popup*).
- The popup has its own spot, left of the roll frames, and its own **Move** and **Reset** buttons in the options (a sample card to drag, whatever the lock says). `/cll sim` shows a result card too.
- *Loot toasts*: a new option hides Blizzard's "You won" toast **only for the items the winner popup reports**; other loot toasts stay. An item is covered from the start of its roll.
- A roll is followed from `START_LOOT_ROLL` until the game names a winner, from several signals (the roll's start, history updates, the "complete" event), so a result is not missed when one of them is unreadable. Up to eight cards at once, as many as roll frames. `/cll debug` traces each step.

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
