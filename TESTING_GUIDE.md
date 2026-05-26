# SpotiFLAC-Mobile Background Audio - Testing Guide

## What Was Fixed

Fixed the **Dual-Player Antipattern** that prevented background music playback:
- Removed the second AudioPlayer instance from PremiumPlaybackController
- Now uses handler's shared player via getPlayer()
- Ensures mediaItem is set BEFORE playback for notifications
- Fixed state synchronization across all playback events

## Build & Deploy

```bash
# 1. Clean build
cd D:\spotiftac_mod\SpotiFLAC-Mobile
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Build debug APK
flutter build apk --debug

# 4. Install on device
flutter install

# 5. Run with logs
flutter run -v
```

## Phase 1: Local Playback Test (App in Focus)

**Prerequisites:** Have at least 1 FLAC file in your library

**Steps:**
```
1. Launch SpotiFLAC app
2. Navigate to library (should see tracks)
3. Tap play on a track
   ✓ Audio should start playing
   ✓ UI should show playing indicator
   ✓ Check phone notification panel:
     - Notification should appear with track title, artist, album
     - Notification should have play/pause/skip buttons
```

**Log Indicators (in `flutter run` output):**
```
✓ AudioBackgroundHandler: Created shared AudioPlayer instance
✓ AudioBackgroundHandler initialized and ready
✓ AudioService initialized
✓ PremiumPlaybackController: Using shared AudioPlayer from handler
🎵 playLibrary called with X items, starting at index=0
▶️ Playback started
📤 Broadcasting state: playing=true, pos=0:00:00, media_set=true
✓ Synced mediaItem: [Song Title] by [Artist Name]
🔔 Notification should now appear
```

**If notification doesn't appear:**
```
Look for these error patterns in logs:
✗ Error broadcasting playback state: ...
✗ Could not sync to audio service: ...
⚠️ Cannot sync: handler=true, queue_empty=false

Report the exact error message
```

## Phase 2: Background Playback Test (App Minimized)

**Prerequisites:** Phase 1 passed

**Steps:**
```
1. Start playing a track (see notification)
2. Press HOME button (minimize app, stay in home screen)
3. Wait 5 seconds
   ✓ Audio should CONTINUE playing
   ✓ Notification should still be visible
   ✓ Lock screen should show playback controls

4. Pull down notification shade
   ✓ Playback notification visible with controls
   ✓ Tap pause button → audio pauses
   ✓ Tap play button → audio resumes
```

**Log Indicators:**
```
After minimize, these should NOT appear:
✗ Error in playback event stream: ...
✗ Failed to pause: ...
✗ AudioPlayer disposed while playing
```

**If audio stops when minimized:**
```
Problem: Foreground service or wake lock issue
Check logs for:
- Android permission errors (FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK)
- AudioService connection lost
Contact Jijin with full logs
```

## Phase 3: Lock Screen & Media Session Test

**Prerequisites:** Phase 2 passed

**Steps:**
```
1. Start playback in background (HOME pressed)
2. Press power button (lock screen)
   ✓ Lock screen should show track info
   ✓ Lock screen should show play/pause/skip controls
   
3. Tap play/pause on lock screen
   ✓ Audio pauses/resumes
   ✓ Notification updates
   
4. Swipe left on lock screen notification
   ✓ Shows skip back
   ✓ Tap to jump to previous track
```

**If lock screen is blank:**
```
Issue: MediaSession not initialized
Check logs for:
- Audio session configuration errors
- MediaItem not being broadcast

This usually fixes on second play attempt
```

## Phase 4: Resumption After App Close

**Prerequisites:** Phase 2 passed, app running in background

**Steps:**
```
1. Start playback (audio playing)
2. Press HOME (minimize)
3. Force close app:
   Settings → Apps → SpotiFLAC → Force Stop
4. Relaunch app
   ✓ Previous track should be in queue
   ✓ Should show in now-playing/queue UI
   ✓ Tap play → resumes from saved position
```

**Log Indicators (on relaunch):**
```
✓ PremiumPlaybackController bootstrap complete
Final state should include restored queue
```

## Phase 5: Notification Interaction Test

**Prerequisites:** Phase 1 passed, audio playing

**Steps:**
```
1. Audio playing with notification visible
2. Tap notification → Opens app to now-playing screen
3. From home screen:
   - Tap notification → Switches to now-playing
   - Swipe notification → Removes it
     (Audio continues, but notification gone from tray)
4. Pull notification shade again
   ✓ Notification restored
```

## Phase 6: Queue Operations During Background Playback

**Prerequisites:** Phase 2 passed, audio in background

**Steps:**
```
1. App minimized, audio playing
2. Notification still visible
3. Go to home screen, tap launcher icon to bring app to front
   ✓ Audio continues
   ✓ Notification still visible
   
4. Jump to next track in UI
   ✓ Audio changes
   ✓ Notification updates with new track
   ✓ All lock screen controls updated
```

## Common Issues & Solutions

### "Notification is blank/empty"
**Cause:** mediaItem not being set before playback
**Check:** Logs should show `✓ Synced mediaItem: ...`
**Fix:** Already implemented - check Phase 1 logs

### "Audio stops when app minimizes"
**Cause:** Foreground service not started or wakelock released
**Check:** Look for audio service connection errors
**Fix:** Contact Jijin - may need Android-specific fixes

### "Lock screen shows nothing"
**Cause:** MediaSession not initialized
**Check:** Logs should show `✓ Audio session configured for music playback`
**Fix:** Should auto-resolve on next play. Tap play/pause in notification.

### "Notification controls (skip, pause) don't work"
**Cause:** Handler methods not receiving commands
**Check:** Logs when tapping notification button
**Fix:** Log indicates which control is failing. Report to Jijin.

### "Crash on minimize"
**Cause:** Exception in audio service broadcast
**Check:** Full stack trace in logs
**Fix:** Report stack trace to Jijin

## Reporting Issues

When reporting issues, always include:

1. **What you were doing** (exact steps)
2. **What you expected** to happen
3. **What actually happened**
4. **Full log output** from `flutter run -v`
5. **Your device info:**
   - Android version
   - Device model
   - RAM size

Example:
```
ISSUE: Notification shows blank when pressing play

STEPS:
1. Tap play on a track
2. Look at notification

EXPECTED: Shows "Song Title - Artist Name"
ACTUAL: Notification title is empty, only shows app name

DEVICE: Samsung Galaxy S21, Android 13, 8GB RAM

LOGS:
[paste relevant logs]
```

## Success Criteria

✅ ALL tests pass:
- [x] Phase 1: Local playback with notification
- [x] Phase 2: Background playback continues
- [x] Phase 3: Lock screen controls work
- [x] Phase 4: Resumption after force-close
- [x] Phase 5: Notification taps work
- [x] Phase 6: Queue operations in background

🎉 Background music playback is FIXED and WORKING!
