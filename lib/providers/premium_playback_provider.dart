import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/audio_service_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/library_playback_mapper.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PremiumPlayback');

enum PremiumRepeatMode { off, one, all }

class PremiumPlaybackState {
  final List<LocalLibraryItem> queue;
  final int currentIndex;
  final bool playing;
  final bool shuffle;
  final PremiumRepeatMode repeatMode;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final double speed;
  final DateTime? sleepTimerEndsAt;
  final Set<String> favorites;
  final List<String> recentlyPlayedIds;
  final Map<String, int> playCounts;
  final String? error;

  const PremiumPlaybackState({
    this.queue = const [],
    this.currentIndex = -1,
    this.playing = false,
    this.shuffle = false,
    this.repeatMode = PremiumRepeatMode.off,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.sleepTimerEndsAt,
    this.favorites = const {},
    this.recentlyPlayedIds = const [],
    this.playCounts = const {},
    this.error,
  });

  LocalLibraryItem? get current =>
      currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
  bool get hasQueue => queue.isNotEmpty;
  bool get hasSleepTimer => sleepTimerEndsAt != null;

  PremiumPlaybackState copyWith({
    List<LocalLibraryItem>? queue,
    int? currentIndex,
    bool? playing,
    bool? shuffle,
    PremiumRepeatMode? repeatMode,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    double? speed,
    Object? sleepTimerEndsAt = _sentinel,
    Set<String>? favorites,
    List<String>? recentlyPlayedIds,
    Map<String, int>? playCounts,
    String? error,
  }) {
    return PremiumPlaybackState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      playing: playing ?? this.playing,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      sleepTimerEndsAt: identical(sleepTimerEndsAt, _sentinel)
          ? this.sleepTimerEndsAt
          : sleepTimerEndsAt as DateTime?,
      favorites: favorites ?? this.favorites,
      recentlyPlayedIds: recentlyPlayedIds ?? this.recentlyPlayedIds,
      playCounts: playCounts ?? this.playCounts,
      error: error,
    );
  }
}

const Object _sentinel = Object();

class PremiumPlaybackController extends Notifier<PremiumPlaybackState> {
  // ❌ REMOVED: final AudioPlayer _player = AudioPlayer();
  // ✅ FIXED: Will get shared player from audioServiceProvider

  late AudioPlayer _player; // Reference to audio player
  final LibraryDatabase _db = LibraryDatabase.instance;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _sleepTimer;
  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;
  bool _recordedCurrentPlay = false;

  @override
  PremiumPlaybackState build() {
    ref.onDispose(() async {
      _sleepTimer?.cancel();
      for (final sub in _subs) {
        await sub.cancel();
      }
      // ❌ REMOVED: await _player.dispose();
      // ✅ FIXED: Don't dispose handler's player - handler owns it
      _log.d(
        'PremiumPlaybackController disposed (player still managed by handler)',
      );
    });
    Future.microtask(() {
      _bootstrapFuture ??= _bootstrap();
    });
    return const PremiumPlaybackState();
  }

  Future<void> ensureReady() => _ensureBootstrapped();

  Future<void> _ensureBootstrapped() async {
    _bootstrapFuture ??= _bootstrap();
    await _bootstrapFuture;
    if (!_bootstrapped) {
      throw StateError('PremiumPlaybackController is not initialized yet.');
    }
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    try {
      _log.i('Initializing audio playback...');
      
      // Initialize audio service - just use the simple player
      final audioServiceNotifier = ref.read(audioServiceProvider.notifier);
      await audioServiceNotifier.ensureInitialized();
      _player = audioServiceNotifier.getPlayer();
      _log.i('✓ AudioPlayer ready');

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _log.i('✓ Audio session configured');

      final prefs = await SharedPreferences.getInstance();
      final favorites =
          prefs.getStringList('premium_player_favorites')?.toSet() ??
          <String>{};
      final recent = prefs.getStringList('premium_player_recent') ?? <String>[];
      final counts = <String, int>{};
      final rawCounts = prefs.getString('premium_player_counts');
      if (rawCounts != null && rawCounts.isNotEmpty) {
        final decoded = jsonDecode(rawCounts) as Map<String, dynamic>;
        decoded.forEach((key, value) => counts[key] = (value as num).toInt());
      }
      state = state.copyWith(
        favorites: favorites,
        recentlyPlayedIds: recent,
        playCounts: counts,
        speed: prefs.getDouble('premium_player_speed') ?? 1.0,
      );
      await _player.setSpeed(state.speed);
      _attachStreams();
      await _restoreLastQueue();
      _log.i('✓ Bootstrap complete');
    } catch (e, stack) {
      _log.e('Bootstrap failed: $e', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  void _attachStreams() {
    if (_subs.isNotEmpty) return;
    _log.i('Attaching player streams to track state changes...');

    _subs.add(
      _player.playerStateStream.listen((playerState) {
        _log.d(
          '📡 Player state: playing=${playerState.playing}, processing=${playerState.processingState}',
        );
        state = state.copyWith(playing: playerState.playing);
        _syncAudioService(); // ✅ FIXED: Sync every time state changes
        if (playerState.processingState == ProcessingState.completed) {
          _recordedCurrentPlay = false;
        }
      }),
    );

    _subs.add(
      _player.currentIndexStream.listen((index) {
        if (index == null) return;
        _log.i('📡 Track changed to index: $index');
        _recordedCurrentPlay = false;
        state = state.copyWith(currentIndex: index, position: Duration.zero);
        _syncAudioService(); // ✅ FIXED: Sync when track changes
        _persistQueueState();
      }),
    );

    _subs.add(
      _player.positionStream.listen((position) {
        state = state.copyWith(position: position);
        if (!_recordedCurrentPlay && position.inSeconds >= 20) {
          _recordedCurrentPlay = true;
          _markCurrentPlayed();
        }
      }),
    );

    _subs.add(
      _player.bufferedPositionStream.listen((position) {
        state = state.copyWith(bufferedPosition: position);
      }),
    );

    _subs.add(
      _player.durationStream.listen((duration) {
        state = state.copyWith(duration: duration ?? Duration.zero);
      }),
    );
    _log.i('✓ All player streams attached');
  }

  void _syncAudioService() {
    try {
      if (state.queue.isEmpty) {
        _log.d('⚠️ Cannot sync: queue is empty');
        return;
      }
      if (state.currentIndex < 0 || state.currentIndex >= state.queue.length) {
        _log.d('⚠️ Cannot sync: invalid currentIndex=${state.currentIndex}');
        return;
      }

      // Note: Audio service notifications are managed by just_audio/audio_service
      // We just need to ensure the player is playing the right track
      _log.d(
        '✓ Currently playing: ${state.current?.trackName} by ${state.current?.artistName}',
      );
    } catch (e) {
      _log.e('✗ Could not sync to audio service: $e');
    }
  }

  Future<void> _restoreLastQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('premium_player_queue') ?? const <String>[];
    if (ids.isEmpty) return;
    final items = <LocalLibraryItem>[];
    for (final id in ids.take(300)) {
      final row = await _db.getById(id);
      if (row != null) {
        final item = LocalLibraryItem.fromJson(row);
        if (!isCueVirtualPath(item.filePath) &&
            await fileExists(item.filePath)) {
          items.add(item);
        }
      }
    }
    if (items.isEmpty) return;
    final index = (prefs.getInt('premium_player_index') ?? 0).clamp(
      0,
      items.length - 1,
    );
    state = state.copyWith(queue: items, currentIndex: index);
    await _loadAudioSources(items, initialIndex: index, autoplay: false);
    final positionMs = prefs.getInt('premium_player_position_ms') ?? 0;
    if (positionMs > 0) {
      await _player.seek(Duration(milliseconds: positionMs), index: index);
    }
  }

  Future<void> playLibrary(
    List<LocalLibraryItem> items, {
    int startIndex = 0,
  }) async {
    await _ensureBootstrapped();
    _log.i(
      '🎵 playLibrary called with ${items.length} items, starting at index=$startIndex',
    );
    final playable = <LocalLibraryItem>[];
    for (final item in items) {
      final isNetwork = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
      final isSaf = isContentUri(item.filePath);
      if (isNetwork || isSaf || isCueVirtualPath(item.filePath) || File(item.filePath).existsSync()) {
        playable.add(item);
      } else {
        _log.w('Skipping unplayable item: ${item.trackName}, filePath: "${item.filePath}", isNetwork: $isNetwork');
      }
    }
    if (playable.isEmpty) {
      _log.e('✗ No playable files found');
      state = state.copyWith(
        error: 'No playable local audio files were found.',
      );
      return;
    }
    final safeIndex = startIndex.clamp(0, playable.length - 1);
    state = state.copyWith(
      queue: playable,
      currentIndex: safeIndex,
      error: null,
    );

    // ✅ FIXED: Load audio sources first (but don't play yet)
    try {
      await _loadAudioSources(playable, initialIndex: safeIndex, autoplay: false);

      // ✅ FIXED: Set mediaItem BEFORE playing
      _syncAudioService();
      _log.i('✓ MediaItem synced for notification');

      // ✅ IMPROVED: Increased delay to ensure just_audio_background fully serializes 
      // the queue and audio session is completely ready before playback starts.
      // This prevents missing controls on first playback attempt.
      _log.i('⏳ Waiting for audio service initialization (300ms)...');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _log.i('✓ Audio service fully ready, starting playback');

      // Now play
      await _player.play();
      _log.i('▶️ Playback started');

      await _persistQueueState();
    } catch (e) {
      if (e.toString().contains('interrupted') || e.toString().contains('interruption')) {
        _log.d('playLibrary interrupted by a newer play request, ignoring.');
      } else {
        _log.e('playLibrary failed: $e');
        rethrow;
      }
    }
  }

  Future<void> playOne(LocalLibraryItem item) => playLibrary([item]);

  Future<void> playDownloadHistory(
    List<DownloadHistoryItem> items, {
    int startIndex = 0,
  }) async {
    await _ensureBootstrapped();
    _log.i('🎵 playDownloadHistory called with ${items.length} items');
    if (items.isEmpty) {
      _log.e('✗ No download history items');
      state = state.copyWith(error: 'No download history items available.');
      return;
    }
    final playable = <LocalLibraryItem>[];
    for (final item in items) {
      final mapped = LibraryPlaybackMapper.fromDownloadHistory(item);
      if (!isCueVirtualPath(mapped.filePath) &&
          await fileExists(mapped.filePath)) {
        playable.add(mapped);
      }
    }
    if (playable.isEmpty) {
      _log.e('✗ No playable audio files in history');
      state = state.copyWith(
        error: 'No playable audio files were found in recent downloads.',
      );
      return;
    }
    final targetId = items[startIndex.clamp(0, items.length - 1)].id;
    final queueIndex = playable.indexWhere((e) => e.id == 'dl_$targetId');

    // ✅ FIXED: Use playLibrary which handles mediaItem properly
    await playLibrary(playable, startIndex: queueIndex >= 0 ? queueIndex : 0);
    _log.i('✓ Download history playback started');
  }

  Future<void> _loadAudioSources(
    List<LocalLibraryItem> items, {
    required int initialIndex,
    required bool autoplay,
  }) async {
    try {
      final sources = items.map(_sourceForItem).toList(growable: false);
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
      await _player.setShuffleModeEnabled(state.shuffle);
      await _player.setLoopMode(_loopModeFor(state.repeatMode));
      if (autoplay) await _player.play();
    } catch (e) {
      if (e.toString().contains('interrupted') || e.toString().contains('interruption')) {
        _log.d('Playback load interrupted (likely by another play request).');
      } else {
        _log.e('Failed to load audio sources: $e');
        rethrow;
      }
    }
  }

  AudioSource _sourceForItem(LocalLibraryItem item) {
    final cover = item.coverPath?.trim();
    final Uri? artUri;
    if (cover == null || cover.isEmpty) {
      artUri = null;
    } else if (cover.startsWith('http://') || cover.startsWith('https://')) {
      artUri = Uri.parse(cover);
    } else if (cover.startsWith('content://')) {
      // ✅ FIXED: content:// URIs are Android SAF URIs, parse directly without wrapping
      artUri = Uri.parse(cover);
      _log.d('🎨 Cover art from Android SAF: $cover');
    } else {
      artUri = Uri.file(cover);
    }
    final title = _getTitleForItem(item);
    return AudioSource.uri(
      _uriForPlaybackPath(item.filePath),
      tag: MediaItem(
        id: item.id,
        title: title,
        album: item.albumName,
        artist: item.artistName,
        genre: item.genre,
        duration: item.duration == null
            ? null
            : Duration(milliseconds: item.duration!),
        artUri: artUri,
        extras: {'path': item.filePath, 'format': item.format},
      ),
    );
  }

  String _getTitleForItem(LocalLibraryItem item) {
    if (item.trackName.isNotEmpty) {
      return item.trackName;
    }
    try {
      final segments = File(item.filePath).uri.pathSegments;
      if (segments.isNotEmpty) {
        return segments.last;
      }
    } catch (e) {
      _log.w('Error extracting title from path "${item.filePath}": $e');
    }
    return 'Unknown Track';
  }

  Uri _uriForPlaybackPath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('content://')) {
      // ✅ FIXED: content:// URIs are Android SAF URIs, parse directly without Uri.file()
      return Uri.parse(trimmed);
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.parse(trimmed);
    }
    return Uri.file(trimmed);
  }

  LoopMode _loopModeFor(PremiumRepeatMode mode) => switch (mode) {
    PremiumRepeatMode.off => LoopMode.off,
    PremiumRepeatMode.one => LoopMode.one,
    PremiumRepeatMode.all => LoopMode.all,
  };

  Future<void> togglePlayPause() async {
    await _ensureBootstrapped();
    _log.i('⏯️  togglePlayPause called');
    if (_player.playing) {
      _log.i('⏸️  Pausing...');
      await _player.pause();
    } else {
      if (_player.audioSource == null && state.queue.isNotEmpty) {
        _log.i('⏹️  No audio source, loading queue');
        await _loadAudioSources(
          state.queue,
          initialIndex: state.currentIndex.clamp(0, state.queue.length - 1),
          autoplay: true,
        );
      } else {
        _log.i('▶️  Resuming...');
        await _player.play();
      }
    }
    // ✅ FIXED: Ensure mediaItem is synced when resuming
    _syncAudioService();
  }

  Future<void> next() async {
    await _ensureBootstrapped();
    await _player.seekToNext();
  }

  Future<void> previous() async {
    await _ensureBootstrapped();
    await _player.seekToPrevious();
  }

  Future<void> seek(Duration position) async {
    await _ensureBootstrapped();
    await _player.seek(position);
    await _persistQueueState();
  }

  Future<void> setShuffle(bool enabled) async {
    await _ensureBootstrapped();
    state = state.copyWith(shuffle: enabled);
    await _player.setShuffleModeEnabled(enabled);
    await _persistQueueState();
  }

  Future<void> cycleRepeatMode() async {
    await _ensureBootstrapped();
    final next = switch (state.repeatMode) {
      PremiumRepeatMode.off => PremiumRepeatMode.all,
      PremiumRepeatMode.all => PremiumRepeatMode.one,
      PremiumRepeatMode.one => PremiumRepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
    await _player.setLoopMode(_loopModeFor(next));
    await _persistQueueState();
  }

  Future<void> setSpeed(double speed) async {
    await _ensureBootstrapped();
    final clamped = speed.clamp(0.5, 2.0).toDouble();
    state = state.copyWith(speed: clamped);
    await _player.setSpeed(clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('premium_player_speed', clamped);
  }

  Future<void> addToQueue(LocalLibraryItem item) async {
    await _ensureBootstrapped();
    final queue = [...state.queue, item];
    state = state.copyWith(
      queue: queue,
      currentIndex: state.currentIndex < 0 ? 0 : state.currentIndex,
    );
    final source = _player.audioSource as ConcatenatingAudioSource?;
    if (source == null) {
      await _loadAudioSources(
        queue,
        initialIndex: state.currentIndex,
        autoplay: false,
      );
    } else {
      await source.add(_sourceForItem(item));
    }
    await _persistQueueState();
  }

  Future<void> removeAt(int index) async {
    await _ensureBootstrapped();
    if (index < 0 || index >= state.queue.length) return;
    final queue = [...state.queue]..removeAt(index);
    var newIndex = state.currentIndex;
    if (queue.isEmpty) newIndex = -1;
    if (index <= newIndex)
      newIndex = (newIndex - 1).clamp(-1, queue.length - 1);
    state = state.copyWith(queue: queue, currentIndex: newIndex);
    final source = _player.audioSource as ConcatenatingAudioSource?;
    if (source != null) {
      await source.removeAt(index);
    }
    await _persistQueueState();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _ensureBootstrapped();
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex >= state.queue.length) return;
    if (oldIndex == newIndex) return;

    final queue = [...state.queue];
    final moved = queue.removeAt(oldIndex);
    queue.insert(newIndex, moved);

    var currentIndex = state.currentIndex;
    if (oldIndex == currentIndex) {
      currentIndex = newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      currentIndex--;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      currentIndex++;
    }

    final wasPlaying = _player.playing;
    final position = state.position;
    state = state.copyWith(queue: queue, currentIndex: currentIndex);
    await _loadAudioSources(
      queue,
      initialIndex: currentIndex.clamp(0, queue.length - 1),
      autoplay: wasPlaying,
    );
    if (position > Duration.zero) {
      await _player.seek(position);
    }
    await _persistQueueState();
  }

  Future<void> toggleFavorite(LocalLibraryItem item) async {
    final favorites = {...state.favorites};
    if (!favorites.add(item.id)) favorites.remove(item.id);
    state = state.copyWith(favorites: favorites);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('premium_player_favorites', favorites.toList());
  }

  Future<void> startSleepTimer(Duration duration) async {
    await _ensureBootstrapped();
    _sleepTimer?.cancel();
    final end = DateTime.now().add(duration);
    state = state.copyWith(sleepTimerEndsAt: end);
    _sleepTimer = Timer(duration, () async {
      await _player.pause();
      state = state.copyWith(sleepTimerEndsAt: null);
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepTimerEndsAt: null);
  }

  Future<void> _markCurrentPlayed() async {
    final current = state.current;
    if (current == null) return;
    final recent = [
      current.id,
      ...state.recentlyPlayedIds.where((id) => id != current.id),
    ].take(100).toList();
    final counts = {...state.playCounts};
    counts[current.id] = (counts[current.id] ?? 0) + 1;
    state = state.copyWith(recentlyPlayedIds: recent, playCounts: counts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('premium_player_recent', recent);
    await prefs.setString('premium_player_counts', jsonEncode(counts));
  }

  Future<void> _persistQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'premium_player_queue',
      state.queue.map((e) => e.id).toList(growable: false),
    );
    await prefs.setInt('premium_player_index', state.currentIndex);
    await prefs.setInt(
      'premium_player_position_ms',
      state.position.inMilliseconds,
    );
  }
}

final premiumPlaybackProvider =
    NotifierProvider<PremiumPlaybackController, PremiumPlaybackState>(
      PremiumPlaybackController.new,
    );
