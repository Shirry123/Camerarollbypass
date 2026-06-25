# CameraRollBypass

Jailbreak tweak for iPhones with a broken camera.

## Problem
Account verification screens show a black image because the hardware camera is broken.

## Solution
Injects a small gallery button in the **bottom left corner** of any camera/verification screen. Tap it to select a photo from your camera roll instead.

## How to use
1. Open any app that asks you to take a photo
2. See the black screen → look for the gallery button **bottom left**
3. Tap it → pick your photo from camera roll
4. Done

## Compatibility
- iOS 14 – 17
- arm64 / arm64e  
- Rootless + rootful (Palera1n, Dopamine, Unc0ver)

## Build
```bash
git clone https://github.com/yourname/CameraRollBypass
cd CameraRollBypass
make package
```
Requires Theos.

## Install (without building)
Add this repo to Sileo/Zebra and install CameraRollBypass.
