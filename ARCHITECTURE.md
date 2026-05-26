# SpotiFLAC Music Player Architecture

## High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      USER INTERACTION                           │
│  (Tap Play Button in Track List / Album / Search Results)       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │  PlaybackProvider.playTrackList()    │
        │  (or playLocalPath)                  │
        └──────────┬───────────────────────────┘
                   │
                   ▼
    ┌──────────────────────────────────────────────┐
    │  premiumPlaybackProvider (JustAudio)         │
    │  - Start playback                            │
    │  - Manage audio session                      │
    └──────────┬───────────────────────────────────┘
               │
        ┌──────┴─────┐
        │             │
        ▼             ▼
   ┌─────────┐   ┌──────────────────┐
   │Audio    │   │Notification      │
   │Playing  │   │Service           │
   │↓        │   │- Update UI       │
   │         │   │- Show controls   │
   │         │   └──────────────────┘
   │         │
   │         │ Save Session
   │         ▼
   │   ┌──────────────────┐
   │   │SharedPreferences │
   │   │- Track ID        │
   │   │- Position        │
   │   │- Metadata        │
   │   └──────────────────┘
   │
   └─► BACKGROUND PLAYBACK (Audio continues)
       (Even with app minimized)
```

---

## Module Organization

```
lib/
├── services/
│   ├── notification_service.dart ✅ (Existing - EXTEND for music player)
│   ├── audio_notification_service.dart 🆕 (NEW - Audio service integration)
│   ├── background_playback_handler.dart 🆕 (NEW - Audio session setup)
│   ├── media_control_handler.dart 🆕 (NEW - Handle UI button taps)
│   └── playback_session_storage.dart 🆕 (NEW - Persist playback state)
│
├── providers/
│   ├── playback_provider.dart ✅ (Existing - EXTEND with state listeners)
│   ├── premium_playback_provider.dart ✅ (Existing - Core audio, DO NOT MODIFY)
│   └── playback_state_provider.dart 🆕 (NEW - Riverpod for playback UI)
│
├── models/
│   ├── playback_session.dart 🆕 (NEW - Session data structure)
│   └── playback_state_model.dart 🆕 (NEW - Current track/position state)
│
└── widgets/
    └── mini_player.dart 🆕 (NEW - Optional compact player UI)
```

**Legend:**
- ✅ Existing (Do not break)
- 🆕 New (Create fresh)

---

## Riverpod State Flow (Recommended Structure)

```dart
// Define playback state
class PlaybackStateNotifier extends StateNotifier<PlaybackState> {
  // Watch: current track info
  // Watch: playback position
  // Watch: is playing / is paused / is stopped
  // Watch: error state
}

// Riverpod providers
final playbackStateProvider = StateNotifierProvider<PlaybackStateNotifier, PlaybackState>(...);

// Listeners (for UI updates)
ref.watch(playbackStateProvider).whenData((state) {
  // Update notification
  // Save session
  // Update mini player
});
```

---

## Notification Flow

```
Audio Playing Event
        │
        ├─► AudioNotificationService.updateMediaItem()
        │   └─► Set title, artist, album, cover
        │
        ├─► AudioNotificationService.updatePlaybackState()
        │   └─► Set play/pause/skip buttons
        │
        └─► NotificationService.showMusicPlayerNotification()
            └─► Display in system notification tray
                ├─ Show album art
                ├─ Show track name + artist
                ├─ Show controls (prev/play/pause/next)
                └─ Show current position / duration
```

---

## Background Audio Lifecycle

```
App Foreground              App Paused              App Terminated
──────────────────         ──────────────          ──────────────
  Audio Playing              Audio Playing           Audio Playing
    │                          │                        │
    ├─ Notification active    ├─ Notification stays    ├─ Service continues
    ├─ UI updates real-time   ├─ No UI updates        ├─ Wake lock active
    └─ Normal battery use     └─ Lower battery       │└─ Notification only control
                                                      └─ User can pause/skip
```

---

## Session Persistence Flow

```
Playback Started
    │
    └─► Save PlaybackSession every N seconds:
        ├─ Track ID
        ├─ Current position
        ├─ Timestamp
        ├─ Was playing (true/false)
        └─ Store in SharedPreferences

App Closed
    │
    └─► (Session remains in SharedPreferences)

App Reopened
    │
    └─► Check PlaybackSession in init:
        ├─ If session age < 24 hours
        ├─ If audio file still exists
        └─► Resume playback at saved position
            (with same pause/play state)
```

---

## Integration Points (Where to Hook In)

### 1. When Playback Starts
```
PlaybackProvider.playLocalPath() or playTrackList()
    │
    └─► HOOK: Call AudioNotificationService.updateMediaItem()
    └─► HOOK: Call AudioNotificationService.updatePlaybackState(true)
    └─► HOOK: Start periodic session save timer
```

### 2. When Position Updates
```
just_audio positionStream
    │
    └─► HOOK: Update NotificationService progress
    └─► HOOK: Save PlaybackSession every 5 seconds
```

### 3. When Playback Stops/Pauses
```
just_audio playingStream
    │
    └─► HOOK: Update notification (show pause icon)
    └─► HOOK: Save final session state
    └─► HOOK: Clear wake lock (if using wakelock_plus)
```

### 4. On Notification Button Tap
```
Notification play/pause/skip button clicked
    │
    └─► AudioPlayerHandler._handleMediaButtonEvent()
        ├─ playButtonTapped() → call audioPlayer.play()
        ├─ pauseButtonTapped() → call audioPlayer.pause()
        ├─ skipNextTapped() → play next track via provider
        └─ skipPrevTapped() → play previous track via provider
```

---

## Settings Integration

Add to `lib/models/settings.dart`:
```dart
@JsonSerializable()
class Settings {
  // ... existing fields ...
  
  /// Resume playback where it left off when app restarts
  final bool resumePlaybackOnStartup;
  
  /// Show mini player at bottom of main screen
  final bool showMiniPlayer;
  
  /// Continue playing even when app is minimized/closed
  final bool enableBackgroundPlayback;
  
  /// Maximum age of playback session before discarding (hours)
  final int playbackSessionMaxAgeDays;

  Settings({
    // ... existing params ...
    this.resumePlaybackOnStartup = true,
    this.showMiniPlayer = true,
    this.enableBackgroundPlayback = true,
    this.playbackSessionMaxAgeDays = 1,
  });
}
```

Toggle in UI:
```dart
// In settings screen
ListTile(
  title: const Text('Resume Playback on Startup'),
  trailing: Switch(
    value: settings.resumePlaybackOnStartup,
    onChanged: (value) {
      ref.read(settingsProvider.notifier)
          .setResumePlaybackOnStartup(value);
    },
  ),
),
```

---

## Testing Scenarios

### Scenario 1: Basic Playback
```
1. Tap Play on any track
2. Verify audio plays ✓
3. Check notification appears ✓
4. Verify position updates ✓
```

### Scenario 2: Background Continuation
```
1. Start playback
2. Press home button (minimize app)
3. Wait 10 seconds
4. Verify audio still playing ✓
5. Check notification visible ✓
6. Tap pause in notification
7. Verify audio pauses ✓
```

### Scenario 3: Session Restore
```
1. Start playback at 0:30
2. Tap pause
3. Force close app (Settings > Apps > Force Stop)
4. Reopen app
5. Verify resumed at ~0:30 ✓
6. Verify paused (not playing) ✓
```

### Scenario 4: Button Actions
```
1. Playback active, showing notification
2. Tap play/pause button
3. Verify audio state changes ✓
4. Tap next button (if implemented)
5. Verify plays next track ✓
```

---

## Android Manifest Changes

Update `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
  <!-- Required for notifications on Android 13+ -->
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  
  <!-- Required for background audio service -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
  
  <!-- Optional but recommended for wake lock -->
  <uses-permission android:name="android.permission.WAKE_LOCK" />

  <application ...>
    <!-- No service declaration needed, audio_service handles it -->
  </application>
</manifest>
```

---

## iOS Info.plist Changes (If needed)

```xml
<key>NSBonjourServices</key>
<array>
  <string>_http._tcp</string>
  <string>_airplay._tcp</string>
</array>

<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

---

## File Structure Summary

```
├── MUSIC_PLAYER_IMPLEMENTATION_GUIDE.md (THIS FILE - Detailed guide)
├── ARCHITECTURE.md (THIS FILE - Architectural overview)
│
├── lib/services/
│   ├── audio_notification_service.dart 🆕
│   │   ├── AudioNotificationService (singleton)
│   │   ├── AudioPlayerHandler extends BaseAudioHandler
│   │   └── MediaItem & PlaybackState management
│   │
│   ├── background_playback_handler.dart 🆕
│   │   ├── setupAudioSession()
│   │   └── AVAudioSessionConfiguration
│   │
│   ├── media_control_handler.dart 🆕
│   │   ├── Handle play/pause/skip/previous
│   │   └── Coordinate with playback provider
│   │
│   └── playback_session_storage.dart 🆕
│       ├── savePlaybackSession()
│       ├── getPlaybackSession()
│       └── clearPlaybackSession()
│
├── lib/providers/
│   └── playback_state_provider.dart 🆕
│       ├── Current track info
│       ├── Position & duration
│       ├── Play/pause state
│       └── Listeners for session save & notification update
│
├── lib/models/
│   └── playback_session.dart 🆕
│       ├── trackId, trackName, artistName, albumName
│       ├── coverUrl, filePath
│       ├── position, timestamp, wasPlaying
│       └── JSON serialization
│
└── lib/widgets/
    └── mini_player.dart 🆕 (Optional)
        ├── Display current track
        ├── Show progress bar
        ├── Play/pause button
        └── Skip buttons
```

---

## Database/Storage

**PlaybackSession Stored In:**
- `SharedPreferences` (key: `playback_session`)
- Format: JSON string
- Size: ~500 bytes
- Retained: On app close (not cleared)
- Cleared: After resume OR if > 1 day old

**Notification Metadata Stored In:**
- Memory (during playback)
- Android notification cache (system managed)

**Settings Stored In:**
- `SharedPreferences` or SQLite (wherever existing Settings are stored)

---

## Performance Considerations

| Component | Impact | Mitigation |
|-----------|--------|-----------|
| Position updates | ~10KB/hr memory | Throttle to 1/sec, avoid re-renders |
| Wake lock | 5-10% battery drain | Enable only during playback, disable immediately on pause |
| Notification updates | CPU spike | Use `onlyAlertOnce: true` |
| Cover image caching | 500KB-2MB | Reuse existing CoverCacheManager |
| Session saves | Disk I/O | Write every 5-10 seconds only |

---

## Rollback Plan

If implementation causes issues:

1. **Broken playback:** Revert `playback_provider.dart` changes
2. **Broken notifications:** Remove music player notification channel
3. **Battery drain:** Remove wake lock usage
4. **Session restore issues:** Clear SharedPreferences entry
5. **Audio service crashes:** Remove AudioService.init() call

All new code is isolated, so removal should be safe.

---

## Success Criteria ✅

- [ ] Audio plays in background
- [ ] Notification shows during playback
- [ ] Notification buttons control playback
- [ ] Session restores on app restart
- [ ] No battery drain increase > 5%
- [ ] Works on Android 8, 10, 12
- [ ] Existing features unbroken
- [ ] Code follows Riverpod patterns
- [ ] Proper error handling
- [ ] Tested on physical device

