╔════════════════════════════════════════════════════════════════════════════════╗
║           SPOTIFLAC MUSIC PLAYER + BACKGROUND AUDIO IMPLEMENTATION             ║
║                                                                                ║
║  Project: SpotiFLAC-Mobile (Flutter)                                          ║
║  Features: Music player notifications, background playback, session restore   ║
║  Status: Ready to implement - See documentation files for details              ║
╚════════════════════════════════════════════════════════════════════════════════╝

📚 DOCUMENTATION FILES CREATED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. QUICKSTART.md (Start here!)
   ├─ Overview of 5 core features
   ├─ Implementation timeline (7 days)
   ├─ Phase-by-phase breakdown
   ├─ File creation & modification checklist
   └─ Testing checklist

2. MUSIC_PLAYER_IMPLEMENTATION_GUIDE.md (Detailed specifications)
   ├─ Complete code examples for each component
   ├─ Integration checklist (phases 1-5)
   ├─ Dependency list & requirements
   ├─ Common issues & solutions
   └─ Code review guidelines

3. ARCHITECTURE.md (System design)
   ├─ Data flow diagrams (text format)
   ├─ Module organization
   ├─ Riverpod state management structure
   ├─ Integration points & hooks
   ├─ Android manifest changes needed
   └─ Success criteria

4. Implementation template files (Copy & customize):
   ├─ lib/services/audio_notification_service.dart.template
   ├─ lib/services/background_playback_handler.dart.template
   └─ lib/models/playback_session.dart.template

═══════════════════════════════════════════════════════════════════════════════

🎯 5 CORE FEATURES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Music Player in Notification [3-4 days]
   - Android notification with play/pause/skip buttons
   - Album art display
   - Current position / duration

2. Background Music Playback [2-3 days]
   - Audio continues when app minimized
   - Audio continues when app closed

3. Playback Session Persistence [2-3 days]
   - Auto-resume on app restart
   - Save current position
   - Expires after 24 hours

4. Mini Player Widget [OPTIONAL, 2 days]
   - Compact player at bottom of main screen
   - Shows current track & progress bar

5. Queue Management [Future enhancement]
   - Skip to next/previous
   - Playlist support

═══════════════════════════════════════════════════════════════════════════════

✅ WHAT'S ALREADY WORKING (DO NOT BREAK):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Track downloading (Spotify, Tidal, Qobuz, Deezer)
✓ Local file playback via just_audio
✓ Download progress notifications
✓ Library management & scanning
✓ Settings & localization
✓ Theme customization
✓ File storage system

🔧 BACKEND COMPONENTS ALREADY PRESENT:
───────────────────────────────────────
✓ just_audio (audio playback engine)
✓ audio_service (background service framework)
✓ just_audio_background (background handler)
✓ audio_session (audio session management)
✓ flutter_local_notifications (notification system)
✓ flutter_riverpod (state management)
✓ shared_preferences (persistence)

═══════════════════════════════════════════════════════════════════════════════

📋 QUICK START:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 1: Read Documentation
───────────────────────────
1. Read QUICKSTART.md (overview & timeline)
2. Read ARCHITECTURE.md (system design)
3. Skim MUSIC_PLAYER_IMPLEMENTATION_GUIDE.md (reference)

STEP 2: Understand Current Architecture
───────────────────────────────────────
- Study playback_provider.dart (how playback works)
- Study notification_service.dart (how notifications work)
- Check premiumPlaybackProvider (the audio player instance)

STEP 3: Prepare Development Environment
────────────────────────────────────────
- Create feature branch: git checkout -b feature/music-player
- Open project in IDE (Android Studio / VS Code)
- Run: flutter pub get
- Create backup of current code

STEP 4: Implement Phase 1 (Days 1-2)
─────────────────────────────────────
1. Copy lib/services/audio_notification_service.dart.template
   → Save as lib/services/audio_notification_service.dart

2. Copy lib/services/background_playback_handler.dart.template
   → Save as lib/services/background_playback_handler.dart

3. Copy lib/models/playback_session.dart.template
   → Save as lib/models/playback_session.dart

4. Update lib/main.dart (add 10-15 lines)
   → Initialize BackgroundPlaybackHandler

5. Test on device: flutter run
   - Start playback
   - Minimize app
   - Verify audio continues

═══════════════════════════════════════════════════════════════════════════════

🔑 FILES TO WORK WITH:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CRITICAL - DO NOT MODIFY:
──────────────────────────
• lib/providers/premium_playback_provider.dart (Core audio engine)
• lib/providers/download_queue_provider.dart (Download system)
• lib/services/ffmpeg_service.dart (Audio conversion)

MODIFY CAREFULLY:
─────────────────
• lib/main.dart (Add initialization)
• lib/services/notification_service.dart (Extend with new method)
• lib/providers/playback_provider.dart (Add listeners)

CREATE NEW:
───────────
• lib/services/audio_notification_service.dart
• lib/services/background_playback_handler.dart
• lib/services/playback_session_storage.dart
• lib/models/playback_session.dart
• lib/widgets/mini_player.dart (optional)

═══════════════════════════════════════════════════════════════════════════════

💡 KEY CONCEPTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Audio Session:
- Configuration that tells OS this app plays music
- Enables background audio
- Allows audio to continue when screen locks

Audio Service:
- Framework managing system notifications
- Handles media buttons and controls
- Displays music metadata in lock screen

Media Item:
- What's currently playing (title, artist, album, cover)
- Shown in notification and lock screen

Playback State:
- Current status (playing/paused)
- UI controls available (buttons)
- Current position and duration

Wake Lock:
- Keeps CPU awake during playback
- Uses battery, should be disabled on pause

Session Persistence:
- Saving current track + position
- Auto-resume on app restart
- Expires after 24 hours

═══════════════════════════════════════════════════════════════════════════════

⚠️ IMPORTANT NOTES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. MAINTAIN EXISTING FUNCTIONALITY
   Don't break what already works!

2. USE EXISTING PATTERNS
   Follow Riverpod & notification patterns already established

3. TEST EARLY & OFTEN
   Test each phase before proceeding to next

4. USE PHYSICAL DEVICE
   Test on real Android device, not just emulator

5. ANDROID 12+ SPECIFIC
   Some permission and behavior changes needed

6. BATTERY IMPACT
   Background audio uses battery - only enable when necessary

═══════════════════════════════════════════════════════════════════════════════

✅ SUCCESS CRITERIA:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After implementation, verify:

✓ Audio plays & continues in background
✓ Notification shows with controls
✓ Play/pause button works
✓ Session restores on app restart
✓ Progress bar updates correctly
✓ Existing features still work
✓ No crashes or warnings
✓ Works on Android 8, 10, 12+
✓ Minimal battery impact
✓ All code follows project conventions

═══════════════════════════════════════════════════════════════════════════════

📖 TIMELINE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Week 1:
├─ Day 1-2: Create audio session & notification services
├─ Day 2-3: Implement notification UI
└─ Day 3: Test basic playback + notifications

Week 2:
├─ Day 1: Implement session persistence
├─ Day 1-2: Integration testing
├─ Day 2-3: Mini player widget (optional)
└─ Day 3: Cross-device testing

Week 3:
├─ Day 1-2: Polish & error handling
├─ Day 2: Documentation
└─ Day 3: Final QA & deployment

═══════════════════════════════════════════════════════════════════════════════

📞 TROUBLESHOOTING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problem: Audio stops when app minimized
Solution: Ensure BackgroundPlaybackHandler.setupAudioSession() called
          Check AudioSession configured with playback category

Problem: Notification doesn't appear
Solution: Verify notification channel created in initialize()
          Check POST_NOTIFICATIONS permission granted
          Test on physical device

Problem: Session doesn't restore
Solution: Verify PlaybackSessionStorage saves before app closes
          Check SharedPreferences key is correct
          Verify audio file still exists

Problem: Crash on startup
Solution: Check initialization order
          Verify all await calls properly awaited
          Review logcat for specific error messages

═══════════════════════════════════════════════════════════════════════════════

📚 REFERENCE DOCS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

External Resources:
- audio_service: https://github.com/ryanheise/audio_service
- just_audio: https://github.com/ryanheise/just_audio
- audio_session: https://github.com/ryanheise/audio_session
- Riverpod: https://riverpod.dev
- Flutter notifications: https://pub.dev/packages/flutter_local_notifications

Local Documentation:
- QUICKSTART.md ............... Overview & timeline
- ARCHITECTURE.md ............. System design
- MUSIC_PLAYER_IMPLEMENTATION_GUIDE.md .. Detailed specs

═══════════════════════════════════════════════════════════════════════════════

🚀 NEXT IMMEDIATE STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Read QUICKSTART.md (20-30 minutes)
2. Read ARCHITECTURE.md (20-30 minutes)  
3. Study playback_provider.dart (10 minutes)
4. Create feature branch for this work
5. Implement Phase 1 (background audio setup)
6. Test on physical Android device
7. Proceed to Phase 2 (notifications)

═══════════════════════════════════════════════════════════════════════════════

Good luck with the implementation! 🎵
