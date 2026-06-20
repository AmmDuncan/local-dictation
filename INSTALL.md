# Installing Local Dictation

A tiny menu-bar app that turns your voice into text, anywhere on your Mac.
Everything runs **locally** — your audio never leaves your computer.

**Requirements:** an Apple-Silicon Mac (M1 or newer) running macOS 14 or later.

## 1. Install

This app isn't from the App Store and isn't notarized by Apple, so a plain
double-click gets blocked as *"damaged"* (there's no "Open Anyway" for that —
it's just how macOS treats unnotarized downloads). Use **one** of these instead:

### Easiest — the installer (from the .dmg)

1. Open **LocalDictation-x.y.z.dmg**.
2. **Right-click** *"Install Local Dictation.command"* → **Open** → **Open** again
   at the prompt. (Right-click-Open is what lets a downloaded script run the first
   time.)
3. It copies the app to Applications, clears the download flag, and launches it.

### Or by hand (works from the .dmg or .zip)

1. Drag **LocalDictation.app** into **Applications**.
2. Open **Terminal** and run:
   ```
   xattr -dr com.apple.quarantine /Applications/LocalDictation.app
   ```
   (This just removes the "downloaded from the internet" flag — it doesn't change
   the app.)
3. Open the app normally.

There's no window and no Dock icon — look for a small **microphone icon in your
menu bar** (top-right of the screen).

## 2. Grant two permissions

Click the menu-bar mic icon → **Settings**. The top of the **General** tab shows
what's ready. You'll need:

- **Microphone** — so it can hear you. It asks the first time you dictate; click *Allow*.
- **Accessibility** — so it can type the text for you. Open **System Settings →
  Privacy & Security → Accessibility** and turn on **LocalDictation**.

## 3. Download a speech model

In **Settings → Models**, under **Transcription**, click **Download** on a model.
**Large v3 Turbo** (recommended) is the most accurate; **Base** or **Tiny** are
smaller and faster. Then click **Use** on the one you downloaded.

*(Optional: turn on **Polish with AI** in General and download a polish model
under **Settings → Models → Polish** for nicer punctuation.)*

## 4. Dictate

Hold **Control + Space**, speak, and let go — your words are typed wherever your
cursor is. Prefer tapping once to start and again to stop? Switch **Settings →
General → Activation** to *Tap to start / stop*. **Esc** cancels a dictation.

---

**Troubleshooting**

- *Nothing happens when I hold the shortcut:* make sure a model is downloaded
  (Settings → Models) and Accessibility is granted (step 2). Note: **⌃Space** is
  also macOS's "switch input source" if you have more than one — rebind in
  Settings → General if it clashes.
- *Still says "damaged":* you opened it before clearing quarantine — run the
  `xattr` command above (or re-run the installer), then open it again.
