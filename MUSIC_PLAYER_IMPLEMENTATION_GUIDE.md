# SpotiFLAC Music Player + Background Audio Implementation Guide

## Project Overview
**SpotiFLAC-Mobile** is a Flutter app for downloading FLAC tracks from Spotify, Tidal, Qobuz & Deezer.
- **Architecture:** Riverpod (state management), GoRouter (navigation)
- **Audio Backend:** `just_audio`, `audio_service`, `just_audio_background`
- **Notifications:** `flutter_local_notifications` (already integrated)
- **Min SDK:** Flutter 3.8.0+

---

## Current Architecture Analysis

### Existing Components (DO NOT TOUCH)
1. **NotificationService** (`lib/services/notification_service.dart`)
   - Download progress notifications
   - Library scan notifications
   - Status notifications
   - ✅ Can be extended for music player controls

2. **PlaybackProvider** (`lib/providers/playback_provider.dart`)
   - `playLocalPath()` - plays single track
   - `playTrackList()` - plays list of tracks
   - Uses `premiumPlaybackProvider` (JustAudio backend)
   - ✅ Already functional, needs enhancement

3. **Audio Stack**
   - `just_audio` - Core audio playback
   - `audio_service` - Background audio service
   - `just_audio_background` - Background handler
   - ✅ Already in pubspec.yaml, underutilized

4. **State Management**
   - Riverpod providers
   - Settings stored in `SharedPreferences`
   - ✅ Ready for playback state persistence

---

## Feature Implementation Plan

### 1️⃣ MUSIC PLAYER NOTIFICATION (Audio Session Integration)
**Goal:** Display playback controls in system notification when music plays

#### Files to Create:
```
lib/services/audio_notification_service.dart
lib/services/media_control_handler.dart
lib/models/playback_state_model.dart
```

#### Implementation Steps:

**Step 1A:** Create `lib/services/audio_notification_service.dart`
```dart
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioNotificationService {
  static final AudioNotificationService _instance = 
      AudioNotificationService._internal();
  
  factory AudioNotificationService() => _instance;
  AudioNotificationService._internal();

  Future<void> initializeAudioService(AudioPlayer audioPlayer) async {
    await AudioService.init(
      builder: () => AudioPlayerHandler(audioPlayer: audioPlayer),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.spotiflac.channel.audio',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: false,
      ),
    );
  }

  Future<void> updateMediaItem({
    required String id,
    required String title,
    required String artist,
    required String album,
    String? artUri,
  }) async {
    await AudioService.currentMediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artUri: artUri != null ? Uri.parse(artUri) : null,
        duration: Duration.zero,
      ),
    );
  }

  Future<void> updatePlaybackState(bool isPlaying, Duration position) async {
    await AudioService.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        playing: isPlaying,
        processingState: AudioProcessingState.ready,
        updatePosition: position,
        speed: 1.0,
      ),
    );
  }
}

class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer audioPlayer;

  AudioPlayerHandler({required this.audioPlayer}) {
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    audioPlayer.playingStream.listen((isPlaying) {
      _updatePlaybackState(isPlaying);
    });

    audioPlayer.positionStream.listen((position) {
      _updatePlaybackState(audioPlayer.playing, position);
    });
  }

  void _updatePlaybackState(bool isPlaying, [Duration? position]) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        playing: isPlaying,
        updatePosition: position ?? audioPlayer.position,
      ),
    );
  }

  @override
  Future<void> play() => audioPlayer.play();

  @override
  Future<void> pause() => audioPlayer.pause();

  @override
  Future<void> seek(Duration position) => audioPlayer.seek(position);

  @override
  Future<void> skipToNext() async {
    // Implement skip logic via provider
  }

  @override
  Future<void> skipToPrevious() async {
    // Implement previous logic via provider
  }
}
```

**Step 1B:** Update `lib/providers/playback_provider.dart`
```dart
// Add after existing imports
import 'package:spotiflac_android/services/audio_notification_service.dart';
import 'package:audio_service/audio_service.dart';

// Extend PlaybackController
Future<void> initializeAudioService() async {
  final audioPlayer = ref.read(premiumPlaybackProvider);
  await AudioNotificationService()
      .initializeAudioService(audioPlayer);
}

Future<void> updateNotificationMetadata({
  required String trackId,
  required String title,
  required String artist,
  required String album,
  String? coverUrl,
}) async {
  await AudioNotificationService().updateMediaItem(
    id: trackId,
    title: title,
    artist: artist,
    album: album,
    artUri: coverUrl,
  );
}
```

---

### 2️⃣ BACKGROUND MUSIC PLAYBACK (Keep Playing When App Closed)
**Goal:** App continues playing music even when minimized/closed

#### Files to Create:
```
lib/services/background_playback_handler.dart
lib/utils/audio_session_config.dart
```

#### Implementation Steps:

**Step 2A:** Create `lib/services/background_playback_handler.dart`
```dart
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class BackgroundPlaybackHandler {
  static final BackgroundPlaybackHandler _instance = 
      BackgroundPlaybackHandler._internal();

  factory BackgroundPlaybackHandler() => _instance;
  BackgroundPlaybackHandler._internal();

  Future<void> setupAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.default_,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.media,
      ),
      androidWillPauseWhenDucked: true,
    ));
  }

  Future<void> enableWakeLock() async {
    // Keep CPU awake during playback
    // May need: wakelock_plus plugin
  }

  Future<void> disableWakeLock() async {
    // Release CPU when paused
  }
}
```

**Step 2B:** Update `lib/main.dart` initialization
```dart
// Add after NotificationService initialization in _initializeAppServices()

try {
  await BackgroundPlaybackHandler().setupAudioSession();
  // Later: initialize audio notification service
  // await ref.read(playbackProvider.notifier).initializeAudioService();
} catch (e) {
  debugPrint('Failed to setup background playback: $e');
}
```

**Step 2C:** Update `pubspec.yaml` (add if needed)
```yaml
dependencies:
  # Already present:
  just_audio: ^0.10.5
  just_audio_background: ^0.0.1-beta.17
  audio_service: ^0.18.18
  audio_session: ^0.2.2
  
  # Add for wake lock (optional but recommended):
  wakelock_plus: ^1.2.3
```

---

### 3️⃣ MINI PLAYER IN NOTIFICATION
**Goal:** Show compact playback controls in notification with album art

#### Implementation:

**Step 3A:** Extend `NotificationService` with music controls
```dart
// In lib/services/notification_service.dart, add new channel:

static const String musicPlayerChannelId = 'music_player';
static const String musicPlayerChannelName = 'Music Player';
static const String musicPlayerChannelDescription = 'Music playback controls';

// Add to initialize() method:
await androidImpl?.createNotificationChannel(
  const AndroidNotificationChannel(
    musicPlayerChannelId,
    musicPlayerChannelName,
    description: musicPlayerChannelDescription,
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  ),
);

// New method for music player notification:
Future<void> showMusicPlayerNotification({
  required String trackId,
  required String trackName,
  required String artistName,
  required String albumName,
  required bool isPlaying,
  String? coverPath, // Path to downloaded cover image
  Duration? currentPosition,
  Duration? totalDuration,
}) async {
  if (!_isInitialized) await initialize();

  final durationStr = totalDuration != null
      ? '${totalDuration.inMinutes}:${(totalDuration.inSeconds % 60).toString().padLeft(2, '0')}'
      : '0:00';
  final positionStr = currentPosition != null
      ? '${currentPosition.inMinutes}:${(currentPosition.inSeconds % 60).toString().padLeft(2, '0')}'
      : '0:00';

  final androidDetails = AndroidNotificationDetails(
    musicPlayerChannelId,
    musicPlayerChannelName,
    channelDescription: musicPlayerChannelDescription,
    importance: Importance.low,
    priority: Priority.low,
    ongoing: isPlaying,
    autoCancel: false,
    playSound: false,
    enableVibration: false,
    icon: '@mipmap/ic_launcher',
    largeIcon: coverPath != null ? FilePathAndroidBitmap(coverPath) : null,
    actions: [
      const AndroidNotificationAction(
        'previous',
        'Previous',
        icon: '@drawable/ic_previous', // Need to add this icon
      ),
      AndroidNotificationAction(
        'play_pause',
        isPlaying ? 'Pause' : 'Play',
        icon: isPlaying ? '@drawable/ic_pause' : '@drawable/ic_play',
      ),
      const AndroidNotificationAction(
        'next',
        'Next',
        icon: '@drawable/ic_next',
      ),
    ],
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: false,
    presentBadge: false,
    presentSound: false,
  );

  final details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await _showSafely(
    id: musicPlayerNotificationId, // Define constant: const int musicPlayerNotificationId = 4;
    title: trackName,
    body: '$artistName • $albumName • $positionStr / $durationStr',
    details: details,
  );
}

Future<void> updateMusicPlayerNotification({
  required Duration currentPosition,
  required Duration totalDuration,
  required bool isPlaying,
}) async {
  // Call showMusicPlayerNotification with updated position
}

Future<void> hideMusicPlayerNotification() async {
  await _notifications.cancel(id: musicPlayerNotificationId);
}
```

**Step 3B:** Create Android drawable icons (need to add to project)
```
android/app/src/main/res/drawable/ic_play.xml
android/app/src/main/res/drawable/ic_pause.xml
android/app/src/main/res/drawable/ic_previous.xml
android/app/src/main/res/drawable/ic_next.xml
```

Each file follows this pattern (ic_play.xml as example):
```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
  <path
      android:fillColor="@android:color/white"
      android:pathData="M8,5v14l11,-7z"/>
</vector>
```

---

### 4️⃣ PLAYBACK STATE PERSISTENCE
**Goal:** Save current track & position to resume on app restart

#### Files to Create:
```
lib/models/playback_session.dart
lib/services/playback_session_storage.dart
```

#### Implementation:

**Step 4A:** Create `lib/models/playback_session.dart`
```dart
import 'package:json_annotation/json_annotation.dart';

part 'playback_session.g.dart';

@JsonSerializable()
class PlaybackSession {
  final String trackId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? coverUrl;
  final String filePath;
  final Duration position;
  final DateTime timestamp;
  final bool wasPlaying;

  PlaybackSession({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.coverUrl,
    required this.filePath,
    required this.position,
    required this.timestamp,
    this.wasPlaying = false,
  });

  factory PlaybackSession.fromJson(Map<String, dynamic> json) =>
      _$PlaybackSessionFromJson(json);

  Map<String, dynamic> toJson() => _$PlaybackSessionToJson(this);
}
```

**Step 4B:** Create `lib/services/playback_session_storage.dart`
```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/playback_session.dart';

class PlaybackSessionStorage {
  static const String _playbackSessionKey = 'playback_session';

  static Future<void> savePlaybackSession(PlaybackSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playbackSessionKey,
      jsonEncode(session.toJson()),
    );
  }

  static Future<PlaybackSession?> getPlaybackSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_playbackSessionKey);
    
    if (jsonStr == null) return null;
    
    try {
      return PlaybackSession.fromJson(jsonDecode(jsonStr));
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearPlaybackSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playbackSessionKey);
  }
}
```

**Step 4C:** Update `lib/main.dart` - Add playback resume logic
```dart
// In _EagerInitializationState._initializeAppServices()

Future<void> _restorePlaybackSession() async {
  try {
    final session = await PlaybackSessionStorage.getPlaybackSession();
    if (session == null) return;

    // Check if session is still valid (file exists, reasonable time)
    final now = DateTime.now();
    final sessionAge = now.difference(session.timestamp);
    
    if (sessionAge.inHours > 24) {
      await PlaybackSessionStorage.clearPlaybackSession();
      return;
    }

    // Restore playback on next frame (after UI is ready)
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          ref.read(playbackProvider.notifier).playLocalPath(
            path: session.filePath,
            title: session.trackName,
            artist: session.artistName,
            album: session.albumName,
            coverUrl: session.coverUrl ?? '',
          ).then((_) {
            // Seek to saved position
            final audioPlayer = ref.read(premiumPlaybackProvider);
            audioPlayer.seek(session.position);
            if (!session.wasPlaying) {
              audioPlayer.pause();
            }
          });
        }
      });
    }
  } catch (e) {
    debugPrint('Failed to restore playback session: $e');
  }
}
```

---

### 5️⃣ PLAYER UI CONTROLS
**Goal:** Add mini player widget to main shell & full player screen (optional)

#### Files to Create:
```
lib/widgets/mini_player.dart
lib/screens/full_player_screen.dart
```

#### Implementation (Optional):

**Step 5A:** Create `lib/widgets/mini_player.dart`
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch playback state
    // Display current track info + play/pause button
    // Show progress bar
    // Tappable to open full player
    return Container(
      // Implementation
    );
  }
}
```

**Step 5B:** Add to `lib/screens/main_shell.dart`
```dart
// Inside Scaffold, add before/after child:
bottomNavigationBar: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (isPlayingTrack) // Watch this state
      const MiniPlayer(),
    // Existing navigation bar
  ],
),
```

---

## Integration Checklist

### Phase 1: Audio Session Setup (Week 1)
- [ ] Create `audio_notification_service.dart`
- [ ] Create `background_playback_handler.dart`
- [ ] Update `main.dart` initialization
- [ ] Test background playback with simple track
- [ ] Verify audio continues when app minimized

### Phase 2: Notification Integration (Week 1-2)
- [ ] Create playback controls icons (.xml drawables)
- [ ] Add music player notification channel
- [ ] Implement `showMusicPlayerNotification()`
- [ ] Hook notification actions to playback controls
- [ ] Test notification appears during playback
- [ ] Test click actions (play/pause/next/previous)

### Phase 3: State Persistence (Week 2)
- [ ] Create `PlaybackSession` model with JSON serialization
- [ ] Create `PlaybackSessionStorage` service
- [ ] Add resume logic to app initialization
- [ ] Test session restore after app kill
- [ ] Add user setting: "Resume playback" toggle

### Phase 4: Mini Player UI (Week 2-3) - Optional
- [ ] Create `MiniPlayer` widget
- [ ] Integrate into `main_shell.dart`
- [ ] Add state watchers for current track/progress
- [ ] Test UI responsiveness during playback
- [ ] Polish animations

### Phase 5: Testing & Polish (Week 3)
- [ ] Cross-device testing (Android 8, 10, 12+)
- [ ] Test with different audio formats (FLAC, MP3, etc)
- [ ] Verify battery drain is minimal
- [ ] Test interrupted playback (calls, alarms)
- [ ] Document any platform limitations

---

## Important Considerations

### ⚠️ Do NOT Touch:
1. **NotificationService** download/library scan channels - keep independent
2. **PlaybackProvider** existing `playLocalPath()` & `playTrackList()` logic
3. **premiumPlaybackProvider** core audio playback
4. **Settings provider** - only extend with new playback settings
5. **Download queue** - audio player is separate concern

### 🔧 Compatibility Notes:
- **Android:** Works on API 21+ (API 24+ for full features)
- **iOS:** May require NSBonjourServices in Info.plist
- **Background Audio:** Requires AudioSession configuration
- **Notifications:** Different behavior on Android 12+ (DBAs)

### 📱 Performance Optimization:
- Use `WakeLock` only during active playback
- Throttle notification updates (max 1/sec)
- Cache cover images in notification
- Monitor memory with large playlists

### 🔐 Permissions Required (Update AndroidManifest.xml):
```xml
<!-- Already present, verify: -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- May need to add: -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

### 🎯 Settings to Add (lib/models/settings.dart):
```dart
// Add these fields:
bool resumePlaybackOnStartup = true;
int defaultPlaybackVolume = 100;
bool showMiniPlayer = true;
bool enableBackgroundPlayback = true;
```

---

## Dependencies Already Available

✅ `just_audio` - Core playback
✅ `audio_service` - Background service framework
✅ `just_audio_background` - Background handler
✅ `audio_session` - Audio session management
✅ `flutter_local_notifications` - Notification display
✅ `flutter_riverpod` - State management (use for playback state)
✅ `shared_preferences` - Persist playback session
✅ `json_annotation` - Serialization

---

## Testing Strategy

### Unit Tests:
```dart
// test/services/playback_session_storage_test.dart
test('savePlaybackSession persists and retrieves session', () async {
  final session = PlaybackSession(...);
  await PlaybackSessionStorage.savePlaybackSession(session);
  final retrieved = await PlaybackSessionStorage.getPlaybackSession();
  expect(retrieved, session);
});
```

### Widget Tests:
```dart
// test/widgets/mini_player_test.dart
testWidgets('MiniPlayer displays current track', (tester) async {
  await tester.pumpWidget(createTestWidget());
  expect(find.byType(MiniPlayer), findsOneWidget);
  expect(find.text('Track Name'), findsOneWidget);
});
```

### Integration Tests:
```dart
// test_driver/playback_e2e.dart
- Launch app
- Start playback
- Minimize app
- Wait 10 seconds
- Verify audio continues
- Restore app
- Verify notification visible
```

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Audio stops when app minimized | Audio session not configured | Call `BackgroundPlaybackHandler.setupAudioSession()` in main |
| Notification not appearing | Channel not created | Ensure `createNotificationChannel()` called in `initialize()` |
| Playback not resuming | Session not persisted | Verify `savePlaybackSession()` called on every position update |
| Action buttons don't work | Handler not connected | Register action callbacks in `AudioPlayerHandler` |
| Battery drain | WakeLock always active | Disable WakeLock on pause/stop |

---

## Next Steps

1. **Start with Phase 1:** Audio session setup is foundation for everything
2. **Test early:** Verify background playback works BEFORE adding UI
3. **Use existing patterns:** Follow Riverpod/NotificationService patterns in codebase
4. **Avoid scope creep:** Don't build full equalizer/playlist editor yet
5. **Get feedback:** Test with real tracks on physical device

---

## Questions & Support

For issues with specific implementation:
1. Check `premiumPlaybackProvider` for audio player reference
2. Review existing notification patterns in `NotificationService`
3. Reference Riverpod docs: https://riverpod.dev
4. Audio service docs: https://github.com/ryanheise/audio_service
5. JustAudio docs: https://github.com/ryanheise/just_audio
