# Wear OS hardware test checklist

Everything below needs a real Galaxy Watch 8 Classic, a phone and a Chameleon Ultra. The automated tests cover logic against fakes; none of this has run on devices yet, except the Gate G0 spike (`docs/wear-spike-results.md`).

Mark each line pass/fail and note anything odd. A failure in any section is a bug to report with the exact steps.

## 0. Install

1. Install the **phone** APK (`CU GUI Dev`, package `io.chameleon.ultra.dev`). It sits beside your Play Store app and starts empty.
2. Turn on developer mode in the phone app (Settings), then use Settings > **Install on watch** to push the **watch** APK (guide: `docs/wear-install.md`).
3. Phone and watch must be paired through Wear OS, and both dev builds must be the ones from the same build (same signing key).

## 1. Watch shell

- [ ] Home menu shows Read, Slots, Saved cards, Dictionaries, Device, Sync, Diagnostics and fits the round screen (nothing clipped at the edges).
- [ ] The rotating bezel scrolls lists. Note the direction (clockwise should scroll down) and the step size (too fast/slow?).
- [ ] Swipe-back works on every screen and on confirm dialogs (counts as cancel).
- [ ] Text is readable; try the watch's larger font size setting too.

## 2. Connection

- [ ] Opening any device screen shows the connect screen first; it asks for Bluetooth permission once.
- [ ] Scan finds the Chameleon (powered on, BLE on, not connected to a phone); tap connects in about a second.
- [ ] After a manual disconnect the watch does not reconnect by itself until the device is seen again.
- [ ] Turn the Chameleon off and on while the watch app is open: it reconnects within about a minute, or shows a clear failed state.
- [ ] Let the watch screen sleep for 2 to 5 minutes mid-session, wake it: the session is still connected or reconnects.

## 3. Read (the main feature)

Use cards you own. Note the time each step takes.

- [ ] Read HF with no card: "no card" and a working retry.
- [ ] Mifare Classic 1K with default keys: UID/type shown, key map fills, a dump completes, "Save to watch" creates a card, "Write to slot" writes it (check on the Chameleon that the slot works).
- [ ] Mifare Classic needing a key from a dictionary: select the dictionary (section 5), read again, keys are found.
- [ ] Mifare Classic with a weak PRNG (darkside/nested) if you have one: recovery progress shows and keys are found. Note the time.
- [ ] A card that needs hardnested: the watch says it needs the phone app and does NOT crash.
- [ ] NTAG/Ultralight: summary is shown, save and write to slot work.
- [ ] Read LF (EM410X, HID or whatever you have): ID shown, save and write to slot work.
- [ ] Continuous HF and LF scan: screen stays awake while scanning, stops at the first card with a haptic buzz, Stop works, the screen can sleep again afterwards.
- [ ] Leave a screen mid-read with the swipe-back: the Chameleon stops being polled (its LED/behaviour returns to normal).

## 4. Saved cards and slots

- [ ] Saved cards lists what you saved; folders and names look right; a long list scrolls smoothly.
- [ ] Rename and delete work; deleting asks for confirmation.
- [ ] Load into slot: pick a slot, overwrite warning on a used slot, progress ring, success. Verify on the Chameleon.
- [ ] Slots overview: ring shows used/empty/active correctly; bezel moves the focus; tapping opens a slot.
- [ ] Slot detail: activate, enable/disable HF and LF, rename, clear. Verify each on the Chameleon.
- [ ] Slot settings (Mifare Classic: gen1a, gen2, anticollision, detection, PRNG, write mode): each change sticks after leaving and reopening the screen.

## 5. Dictionaries

- [ ] List shows dictionaries with key counts; the total-keys pill and estimated time look sensible.
- [ ] Toggle a dictionary off and on; "Use all" resets.
- [ ] Download a dictionary over the watch's own network; it appears, duplicates are rejected.
- [ ] Delete a dictionary (with confirmation).

## 6. Device settings

- [ ] Device info matches the Chameleon (firmware, battery, mode).
- [ ] Change animation, a button action, long-press threshold and sleep timeout; each persists on the Chameleon after a reconnect.
- [ ] BLE pairing key / clear bonds: only attempt on a Chameleon you can re-pair, since it can lock out other phones.

## 7. Phone <-> watch sync (the least tested part)

Both screens must stay on. Phone: developer mode, Settings > **Watch sync**. Watch: **Sync**.

1. [ ] Both status pills reach "connected" within a few seconds. Force-stop one app: the other goes "not connected".
2. [ ] Run the **Sync check** on the phone and on the watch: expect PASS both ways. Note the speed numbers (KB/s) and the ping.
3. [ ] Create a card on each side and a dictionary on the phone. Tap **Sync now** on the phone: the watch shows a progress ring, and afterwards both libraries match and both last-sync reports look right.
4. [ ] Delete a card on one side, sync: it disappears on the other side.
5. [ ] Turn on **Mirror dictionaries to watch**, sync: a dictionary that exists only on the watch disappears.
6. [ ] Start a sync and cancel it from the watch, then from the phone: both sides say cancelled; nothing is half-applied.
7. [ ] Start a sync and turn off phone Bluetooth: both sides report a lost connection and the libraries are unchanged.
8. [ ] On a phone without Google Play Services (if you have one): the page says sync is unavailable instead of crashing.

## 8. Report back

For anything failing, note: the screen, the exact steps, whether it repeats, and the Chameleon firmware version. For crashes, a note of what you tapped last is enough: the spike's QR report (Diagnostics) can also collect device info.
