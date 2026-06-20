# Installing Local Dictation

A tiny menu-bar app that turns your voice into text, anywhere on your Mac.
Everything runs **locally** — your audio never leaves your computer.

**Requirements:** an Apple-Silicon Mac (M1 or newer) running macOS 14 or later.

## 1. Install

1. Unzip `LocalDictation.zip`.
2. Drag **LocalDictation.app** into your **Applications** folder.

## 2. Open it the first time

Because this is a personal app (not from the App Store), macOS will block the
first launch with a warning. This is expected — here's how to allow it:

1. Double-click the app. macOS says it "cannot be opened."
2. Open **System Settings → Privacy & Security**.
3. Scroll down — you'll see *"LocalDictation was blocked."* Click **Open Anyway**.
4. Confirm with **Open**.

*(You only do this once.)*

There's no window and no Dock icon — look for a small **microphone icon in your
menu bar** (top-right of the screen).

## 3. Grant two permissions

Click the menu-bar mic icon → **Settings**. The top of the **General** tab shows
what's ready. You'll need:

- **Microphone** — so it can hear you. It asks the first time you dictate; click *Allow*.
- **Accessibility** — so it can type the text for you. Open **System Settings →
  Privacy & Security → Accessibility** and turn on **LocalDictation**.

## 4. Download a speech model

In **Settings → Models**, click **Download** on a model. **Large v3 Turbo**
(recommended) is the most accurate; **Base** or **Tiny** are smaller and faster
to download. Then click **Use** on the one you downloaded.

## 5. Dictate

Hold **Control + Space**, speak, and let go. Your words are typed wherever your
cursor is. You can change the shortcut in **Settings → General**.

---

**Troubleshooting**

- *Nothing happens when I hold the shortcut:* make sure a model is downloaded
  (Settings → Models) and Accessibility is granted (step 3).
- *Power-user install:* instead of step 2 you can run
  `xattr -dr com.apple.quarantine /Applications/LocalDictation.app` in Terminal.
