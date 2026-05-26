import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:spotiflac_android/app.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/services/share_intent_service.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/services/audio_service_provider.dart';
import 'package:spotiflac_android/utils/local_library_scan_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize just_audio_background for media notifications & background playback
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.spotiflac.audio.playback',
      androidNotificationChannelName: 'SpotiFLAC Music Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: false,
      preloadArtwork: true,
      fastForwardInterval: const Duration(seconds: 10),
      rewindInterval: const Duration(seconds: 10),
    );
  } catch (e, stack) {
    debugPrint('Failed to initialize JustAudioBackground: $e\n$stack');
  }

  _RuntimeProfile runtimeProfile;
  try {
    runtimeProfile = await _resolveRuntimeProfile();
  } catch (e, stack) {
    debugPrint('Failed to resolve runtime profile: $e\n$stack');
    runtimeProfile = const _RuntimeProfile(
      imageCacheMaximumSize: 240,
      imageCacheMaximumSizeBytes: 60 << 20,
      disableOverscrollEffects: false,
    );
  }

  try {
    _configureImageCache(runtimeProfile);
  } catch (e, stack) {
    debugPrint('Failed to configure image cache: $e\n$stack');
  }

  runApp(
    ProviderScope(
      child: _EagerInitialization(
        child: SpotiFLACApp(
          disableOverscrollEffects: runtimeProfile.disableOverscrollEffects,
        ),
      ),
    ),
  );
}

Future<_RuntimeProfile> _resolveRuntimeProfile() async {
  const defaults = _RuntimeProfile(
    imageCacheMaximumSize: 240,
    imageCacheMaximumSizeBytes: 60 << 20,
    disableOverscrollEffects: false,
  );

  if (!Platform.isAndroid) return defaults;

  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final isArm32Only = androidInfo.supported64BitAbis.isEmpty;
    final isLowRamDevice =
        androidInfo.isLowRamDevice || androidInfo.physicalRamSize <= 2500;

    if (!isArm32Only && !isLowRamDevice) {
      return defaults;
    }

    return _RuntimeProfile(
      imageCacheMaximumSize: 120,
      imageCacheMaximumSizeBytes: 24 << 20,
      disableOverscrollEffects: true,
    );
  } catch (e) {
    debugPrint('Failed to resolve runtime profile: $e');
    return defaults;
  }
}

void _configureImageCache(_RuntimeProfile runtimeProfile) {
  final imageCache = PaintingBinding.instance.imageCache;
  // Keep memory cache bounded so cover-heavy pages don't retain too many
  // full-resolution images simultaneously.
  imageCache.maximumSize = runtimeProfile.imageCacheMaximumSize;
  imageCache.maximumSizeBytes = runtimeProfile.imageCacheMaximumSizeBytes;
}

class _RuntimeProfile {
  final int imageCacheMaximumSize;
  final int imageCacheMaximumSizeBytes;
  final bool disableOverscrollEffects;

  const _RuntimeProfile({
    required this.imageCacheMaximumSize,
    required this.imageCacheMaximumSizeBytes,
    required this.disableOverscrollEffects,
  });
}

class _EagerInitialization extends ConsumerStatefulWidget {
  const _EagerInitialization({required this.child});
  final Widget child;

  @override
  ConsumerState<_EagerInitialization> createState() =>
      _EagerInitializationState();
}

class _EagerInitializationState extends ConsumerState<_EagerInitialization>
    with WidgetsBindingObserver {
  ProviderSubscription<bool>? _localLibraryEnabledSub;
  Timer? _downloadHistoryWarmupTimer;
  Timer? _libraryCollectionsWarmupTimer;
  Timer? _localLibraryWarmupTimer;
  bool _localLibraryWarmupScheduled = false;
  bool _autoScanTriggeredOnLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeAppServices();
      _initializeExtensions();
      _initializeDeferredProviders();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localLibraryEnabledSub?.close();
    _downloadHistoryWarmupTimer?.cancel();
    _libraryCollectionsWarmupTimer?.cancel();
    _localLibraryWarmupTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAutoScanLocalLibrary();
    }
  }

  void _initializeDeferredProviders() {
    _downloadHistoryWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 400),
      () => ref.read(downloadHistoryProvider),
    );
    _libraryCollectionsWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 900),
      () => ref.read(libraryCollectionsProvider),
    );

    _maybeScheduleLocalLibraryWarmup(
      ref.read(
        settingsProvider.select((settings) => settings.localLibraryEnabled),
      ),
    );

    _localLibraryEnabledSub = ref.listenManual<bool>(
      settingsProvider.select((settings) => settings.localLibraryEnabled),
      (previous, next) {
        if (next == true) {
          _maybeScheduleLocalLibraryWarmup(true);
        }
      },
    );
  }

  Timer _scheduleProviderWarmup(Duration delay, VoidCallback action) {
    return Timer(delay, () {
      if (!mounted) return;
      action();
    });
  }

  void _maybeScheduleLocalLibraryWarmup(bool enabled) {
    if (!enabled || _localLibraryWarmupScheduled) return;
    _localLibraryWarmupScheduled = true;
    _localLibraryWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 1600),
      () {
        ref.read(localLibraryProvider);
        if (!_autoScanTriggeredOnLaunch) {
          _autoScanTriggeredOnLaunch = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _maybeAutoScanLocalLibrary();
          });
        }
      },
    );
  }

  Future<void> _maybeAutoScanLocalLibrary() async {
    if (!mounted) return;

    final settings = ref.read(settingsProvider);
    if (!settings.localLibraryEnabled) return;

    if (settings.localLibraryPath.isEmpty) {
      final settingsNotifier = ref.read(settingsProvider.notifier);
      if (settings.storageMode == 'saf' && settings.downloadTreeUri.isNotEmpty) {
        settingsNotifier.setLocalLibraryPath(settings.downloadTreeUri);
      } else if (settings.downloadDirectory.isNotEmpty) {
        settingsNotifier.setLocalLibraryPath(settings.downloadDirectory);
      }
    }

    final scanSettings = ref.read(settingsProvider);
    if (scanSettings.localLibraryPath.isEmpty) return;
    if (settings.localLibraryAutoScan == 'off') return;

    final libraryState = ref.read(localLibraryProvider);
    if (libraryState.isScanning) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lastScanned = readLocalLibraryLastScannedAt(prefs);

    if (lastScanned != null) {
      final elapsed = now.difference(lastScanned);

      switch (settings.localLibraryAutoScan) {
        case 'on_open':
          if (elapsed.inMinutes < 10) return;
          break;
        case 'daily':
          if (elapsed.inHours < 24) return;
          break;
        case 'weekly':
          if (elapsed.inDays < 7) return;
          break;
        default:
          return;
      }
    }

    final iosBookmark = scanSettings.localLibraryBookmark.isNotEmpty
        ? scanSettings.localLibraryBookmark
        : scanSettings.downloadDirectoryBookmark;
    ref.read(localLibraryProvider.notifier).startScan(
          scanSettings.localLibraryPath,
          iosBookmark: iosBookmark.isNotEmpty ? iosBookmark : null,
        );
  }

  Future<void> _initializeAppServices() async {
    try {
      await CoverCacheManager.initialize();
      await Future.wait<void>([
        NotificationService().initialize(),
        ShareIntentService().initialize(),
        // AudioService initializes on first notifier access in build()
      ]);
    } catch (e) {
      debugPrint('Failed to initialize app services: $e');
    }
  }

  Future<void> _initializeExtensions() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final extensionsDir = '${appDir.path}/extensions';
      final dataDir = '${appDir.path}/extension_data';

      await Directory(extensionsDir).create(recursive: true);
      await Directory(dataDir).create(recursive: true);

      await ref
          .read(extensionProvider.notifier)
          .initialize(extensionsDir, dataDir);
    } catch (e) {
      debugPrint('Failed to initialize extensions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
