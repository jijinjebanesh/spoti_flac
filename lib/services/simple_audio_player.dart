import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Simple singleton audio player - no complex initialization, just works
class SimpleAudioPlayer {
  static final SimpleAudioPlayer _instance = SimpleAudioPlayer._internal();
  final AudioPlayer _player = AudioPlayer();

  factory SimpleAudioPlayer() => _instance;

  SimpleAudioPlayer._internal() {
    debugPrint('[SimpleAudioPlayer] Initialized');
  }

  AudioPlayer get player => _player;

  Future<void> playFile(String filePath) async {
    try {
      debugPrint('[SimpleAudioPlayer] Playing: $filePath');
      await _player.setFilePath(filePath);
      await _player.play();
    } catch (e) {
      debugPrint('[SimpleAudioPlayer] Error playing: $e');
      rethrow;
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
}
