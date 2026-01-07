## Maintaining

### Testing system services

First, we need to install the app:
1. Archive the app.
2. Once you have your archive in the Organizer window, right-click it, and click **Show in Finder**.
3. Right-click again, now on the latest `Gifski_DATE_.xcarchive`, and click **Show Package Contents**.
4. Open `/Products/Applications` and move `Gifski.app` to your `Applications` directory.

Then, we need to check if our system has the latest service installed:
1. In your terminal, enter the command:
```bash
/System/Library/CoreServices/pbs -dump | grep Gifski.app
```
2. If you see `NSBundlePath = "/Applications/Gifski.app”` - you're good to go.
3. If you don't see the line above, try updating the cache:
```bash
/System/Library/CoreServices/pbs -update
```

### Troubleshooting system services

Sometimes the service doesn't work and it's really hard to understand why without any tools. You can use a debug flag on the instance of `Finder` app and see the logs it dumps:

```bash
/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder -NSDebugServices com.sindresorhus.Gifski
```

### Video rotation handling

Videos can have a `preferredTransform` that rotates the raw frames (e.g., portrait videos filmed on phones). There are two coordinate spaces:

1. **Natural space**: Raw frame dimensions (`naturalSize`), unrotated (e.g., 1920x1080)
2. **Preferred space**: How the user sees the video after rotation (e.g., 1080x1920 for portrait)

In this app:
- UI dimensions (`metadata.dimensions`) are in **preferred space** (already rotated)
- Crop rect from UI is defined in **preferred space**
- `AVAssetImageGenerator` with `appliesPreferredTrackTransform = true` returns images in **preferred space**
- Preview manually applies transform, so images are also in **preferred space**
- `AVComposition` layer instructions operate in **natural space** (must transform crop back)

When cropping images: Apply crop directly (images are pre-rotated).
When exporting video: Transform crop from preferred → natural space first.
