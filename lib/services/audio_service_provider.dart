import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotiflac_android/services/simple_audio_player.dart';

/// Simple audio service state - tracks current playback
final audioServiceProvider =
    NotifierProvider<AudioServiceNotifier, AudioServiceState>(() {
  return AudioServiceNotifier();
});

class AudioServiceState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String? currentTrackTitle;
  final String? currentTrackArtist;
  final String? currentTrackAlbum;
  final String? coverArtUrl;

  const AudioServiceState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentTrackTitle,
    this.currentTrackArtist,
    this.currentTrackAlbum,
    this.coverArtUrl,
  });

  AudioServiceState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    String? currentTrackTitle,
    String? currentTrackArtist,
    String? currentTrackAlbum,
    String? coverArtUrl,
  }) {
    return AudioServiceState(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
      currentTrackArtist: currentTrackArtist ?? this.currentTrackArtist,
      currentTrackAlbum: currentTrackAlbum ?? this.currentTrackAlbum,
      coverArtUrl: coverArtUrl ?? this.coverArtUrl,
    );
  }
}

class AudioServiceNotifier extends Notifier<AudioServiceState> {
  late AudioPlayer _player;
  bool _initialized = false;

  @override
  AudioServiceState build() {
    _init();
    return const AudioServiceState();
  }

  void _init() {
    if (_initialized) return;
    try {
      final simplePlayer = SimpleAudioPlayer();
      _player = simplePlayer.player;
      
      // Listen to player state changes
      _player.playerStateStream.listen((playerState) {
        state = state.copyWith(isPlaying: playerState.playing);
      });

      _player.positionStream.listen((position) {
        state = state.copyWith(position: position);
      });

      _player.durationStream.listen((duration) {
        if (duration != null) {
          state = state.copyWith(duration: duration);
        }
      });

      _initialized = true;
      debugPrint('[AudioService] ✓ Initialized');
    } catch (e) {
      debugPrint('[AudioService] ✗ Init failed: $e');
    }
  }

  Future<void> ensureInitialized() async {
    _init();
  }

  Future<void> playTrack({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    String? coverArtUrl,
  }) async {
    try {
      await _player.setFilePath(filePath);
      await _player.play();
      state = state.copyWith(
        isPlaying: true,
        currentTrackTitle: title,
        currentTrackArtist: artist,
        currentTrackAlbum: album,
        coverArtUrl: coverArtUrl,
      );
      debugPrint('[AudioService] ✓ Playing: $title');
    } catch (e) {
      debugPrint('[AudioService] ✗ Play failed: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      state = state.copyWith(isPlaying: false);
    } catch (e) {
      debugPrint('[AudioService] ✗ Pause failed: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _player.play();
      state = state.copyWith(isPlaying: true);
    } catch (e) {
      debugPrint('[AudioService] ✗ Resume failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      state = state.copyWith(
        isPlaying: false,
        position: Duration.zero,
        currentTrackTitle: null,
        currentTrackArtist: null,
        currentTrackAlbum: null,
        coverArtUrl: null,
      );
    } catch (e) {
      debugPrint('[AudioService] ✗ Stop failed: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('[AudioService] ✗ Seek failed: $e');
    }
  }

  /// Exposes the underlying AudioPlayer so that other controllers
  /// (e.g. PremiumPlaybackController) can share the same instance.
  AudioPlayer getPlayer() => _player;
}
