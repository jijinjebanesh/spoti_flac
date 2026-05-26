import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioBackgroundHandler extends BaseAudioHandler with SeekHandler {
  static AudioBackgroundHandler? _instance;

  late AudioPlayer _player;
  bool _isInitialized = false;

  AudioBackgroundHandler() {
    _instance = this;
    _initialize();
  }

  /// Get the initialized instance (after AudioService.init() is called)
  static AudioBackgroundHandler? getInstance() => _instance;

  void _initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _player = AudioPlayer();
    debugPrint('✓ AudioBackgroundHandler: Created shared AudioPlayer instance');

    // Sync playback state with audio_service continuously
    _player.playbackEventStream.listen((event) {
      debugPrint(
        '📡 Playback event: playing=${_player.playing}, pos=${_player.position}',
      );
      _broadcastPlaybackState(event);
    });

    // Sync duration updates
    _player.durationStream.listen((_) {
      debugPrint('📡 Duration updated: ${_player.duration}');
      _broadcastPlaybackState(_player.playbackEvent);
    });

    // Set initial state
    _broadcastPlaybackState(_player.playbackEvent);
    debugPrint('✓ AudioBackgroundHandler initialized and ready');
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    try {
      final isPlaying = _player.playing;
      final controls = [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ];

      final state = PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: _mapProcessingState(_player.processingState),
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: mediaItem.value != null ? 0 : null,
      );

      debugPrint(
        '📤 Broadcasting state: playing=$isPlaying, pos=${_player.position}, media_set=${mediaItem.value != null}',
      );
      playbackState.add(state);
    } catch (e) {
      debugPrint('✗ Error broadcasting playback state: $e');
    }
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[state] ??
        AudioProcessingState.idle;
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in play(): $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in pause(): $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in stop(): $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in seek(): $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    // Queue navigation would go here if implemented
  }

  @override
  Future<void> skipToPrevious() async {
    // Queue navigation would go here if implemented
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in setSpeed(): $e');
    }
  }

  /// Called by audio_service_provider to load and play a file
  /// CRITICAL: mediaItem must be set BEFORE calling this
  Future<void> playFromFile(String filePath) async {
    try {
      debugPrint('▶️ playFromFile: Loading $filePath');
      debugPrint('📋 Current mediaItem: ${mediaItem.value?.title}');

      await _player.setFilePath(filePath);
      debugPrint('✓ File loaded: $filePath');

      await _player.play();
      debugPrint('▶️ Playback started');

      _broadcastPlaybackState(_player.playbackEvent);
    } catch (e) {
      debugPrint('✗ Error in playFromFile(): $e');
    }
  }

  /// Stop playback and clean up
  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  /// Request audio focus via native MediaSession
  Future<void> requestAudioFocus() async {
    // Audio service handles this automatically with foreground service
  }

  /// Get the current AudioPlayer instance
  AudioPlayer getPlayer() => _player;

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (e) {
      debugPrint('✗ Error disposing player: $e');
    }
  }
}
