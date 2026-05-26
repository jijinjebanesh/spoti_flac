import 'dart:async';

import 'package:spotiflac_android/services/platform_bridge.dart';

final _lrcMetadataPattern = RegExp(r'^\[(ti|ar|al|by|offset|length|re|ve):', caseSensitive: false);
final _lrcBackgroundLinePattern = RegExp(r'^\[bg:(.+)\]$', caseSensitive: false);
final _lrcTimestampPattern = RegExp(r'<\d{2}:\d{2}\.\d{3}>');
final _lrcInlineTimestampPattern = RegExp(r'<\d{2}:\d{2}\.\d{3}>');
final _lrcSpeakerPrefixPattern = RegExp(r'^@\d+:\s*');

/// Strips LRC timestamps and metadata tags for plain-text display.
String cleanLrcForDisplay(String lrc) {
  final lines = lrc.split('\n');
  final cleanLines = <String>[];

  for (final line in lines) {
    var cleaned = line.trim();

    if (_lrcMetadataPattern.hasMatch(cleaned) &&
        !_lrcBackgroundLinePattern.hasMatch(cleaned)) {
      continue;
    }

    final bgMatch = _lrcBackgroundLinePattern.firstMatch(cleaned);
    if (bgMatch != null) {
      cleaned = bgMatch.group(1)?.trim() ?? '';
    }

    cleaned = cleaned.replaceAll(_lrcTimestampPattern, '').trim();
    cleaned = cleaned.replaceAll(_lrcInlineTimestampPattern, '');
    cleaned = cleaned.replaceFirst(_lrcSpeakerPrefixPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isNotEmpty) {
      cleanLines.add(cleaned);
    }
  }

  return cleanLines.join('\n');
}

class LyricsFetchResult {
  final String displayText;
  final String? source;
  final bool instrumental;
  final bool embedded;

  const LyricsFetchResult({
    required this.displayText,
    this.source,
    this.instrumental = false,
    this.embedded = false,
  });

  bool get hasLyrics => displayText.isNotEmpty;
}

/// Loads lyrics for a local file: embedded first, then online providers.
Future<LyricsFetchResult> fetchLyricsForLocalTrack({
  required String trackName,
  required String artistName,
  required String filePath,
  String? spotifyId,
  int durationSeconds = 0,
}) async {
  try {
    final embeddedResult = await PlatformBridge.getLyricsLRCWithSource(
      '',
      trackName,
      artistName,
      filePath: filePath,
      durationMs: 0,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <String, dynamic>{'lyrics': '', 'source': ''},
    );

    final embeddedLyrics = embeddedResult['lyrics']?.toString() ?? '';
    if (embeddedLyrics.isNotEmpty) {
      final source = embeddedResult['source']?.toString() ?? '';
      return LyricsFetchResult(
        displayText: cleanLrcForDisplay(embeddedLyrics),
        source: source.isNotEmpty ? source : 'Embedded',
        embedded: true,
      );
    }
  } catch (_) {}

  try {
    final durationMs = durationSeconds * 1000;
    final result = await PlatformBridge.getLyricsLRCWithSource(
      spotifyId ?? '',
      trackName,
      artistName,
      filePath: null,
      durationMs: durationMs,
    ).timeout(const Duration(seconds: 20));

    final lrcText = result['lyrics']?.toString() ?? '';
    final source = result['source']?.toString() ?? '';
    final instrumental = (result['instrumental'] as bool? ?? false) ||
        lrcText == '[instrumental:true]';

    if (instrumental) {
      return LyricsFetchResult(
        displayText: '',
        source: source.isNotEmpty ? source : null,
        instrumental: true,
      );
    }

    if (lrcText.isEmpty) {
      return const LyricsFetchResult(displayText: '');
    }

    return LyricsFetchResult(
      displayText: cleanLrcForDisplay(lrcText),
      source: source.isNotEmpty ? source : null,
    );
  } on TimeoutException {
    rethrow;
  } catch (_) {
    return const LyricsFetchResult(displayText: '');
  }
}
