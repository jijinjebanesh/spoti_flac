import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/library_playback_mapper.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  Future<void> playLocalPath({
    required String path,
    required String title,
    required String artist,
    String album = '',
    String coverUrl = '',
    Track? track,
  }) async {
    if (isCueVirtualPath(path)) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }
    _log.d('Playing in-app: "$title" by $artist: $path');
    
    // All audio service sync happens in premium_playback_provider
    await ref.read(premiumPlaybackProvider.notifier).playOne(
          LibraryPlaybackMapper.fromDownloadHistory(
            DownloadHistoryItem(
              id: path,
              trackName: title,
              artistName: artist,
              albumName: album,
              coverUrl: coverUrl.isNotEmpty ? coverUrl : null,
              filePath: path,
              service: 'local',
              downloadedAt: DateTime.now(),
            ),
          ),
        );
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    var skippedCueVirtualTrack = false;
    final playableItems = <LocalLibraryItem>[];
    int playableStartIndex = 0;

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final resolvedPath = await _resolveTrackPath(track);
      if (resolvedPath == null) {
        continue;
      }
      if (isCueVirtualPath(resolvedPath)) {
        skippedCueVirtualTrack = true;
        continue;
      }

      final item = LibraryPlaybackMapper.fromDownloadHistory(
        DownloadHistoryItem(
          id: resolvedPath,
          trackName: track.name,
          artistName: track.artistName,
          albumName: track.albumName,
          coverUrl: track.coverUrl ?? '',
          filePath: resolvedPath,
          service: 'local',
          downloadedAt: DateTime.now(),
        ),
      );

      playableItems.add(item);
      if (i == startIndex) {
        playableStartIndex = playableItems.length - 1;
      }
    }

    if (playableItems.isNotEmpty) {
      _log.d('Playing track list with ${playableItems.length} items starting at $playableStartIndex');
      await ref.read(premiumPlaybackProvider.notifier).playLibrary(
            playableItems,
            startIndex: playableStartIndex,
          );
      return;
    }

    if (skippedCueVirtualTrack) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    throw Exception(
      'No local audio file is available to open. Download the track first.',
    );
  }

  Future<void> addTrackToQueue(Track track) async {
    final resolvedPath = await _resolveTrackPath(track);
    if (resolvedPath != null) {
      final item = LibraryPlaybackMapper.fromDownloadHistory(
        DownloadHistoryItem(
          id: resolvedPath,
          trackName: track.name,
          artistName: track.artistName,
          albumName: track.albumName,
          coverUrl: track.coverUrl ?? '',
          filePath: resolvedPath,
          service: 'local',
          downloadedAt: DateTime.now(),
        ),
      );
      ref.read(premiumPlaybackProvider.notifier).addToQueue(item);
    } else {
      throw Exception('Track must be downloaded before adding to queue.');
    }
  }

  Future<void> playStream(Track track) async {
    final settings = ref.read(settingsProvider);
    final extensionState = ref.read(extensionProvider);
    final requested = track.source?.isNotEmpty == true ? track.source! : settings.defaultService;
    final service = resolveEffectiveDownloadService(
      requested,
      extensionState,
    );

    if (service.isEmpty) {
      throw Exception('No extension available to stream this track');
    }

    final tempDir = await getTemporaryDirectory();

    final payload = DownloadRequestPayload(
      trackName: track.name,
      artistName: track.artistName,
      albumName: track.albumName,
      albumArtist: track.albumArtist ?? '',
      coverUrl: track.coverUrl ?? '',
      outputDir: tempDir.path,
      filenameFormat: 'stream_${track.id}',
      service: service,
      source: track.source ?? '',
      isrc: track.isrc ?? '',
      spotifyId: track.id,
      durationMs: (track.duration) * 1000,
      useExtensions: true,
      useFallback: false,
    );

    final response = await PlatformBridge.downloadByStrategy(payload: payload);

    if (response['success'] == true) {
      final filePath = response['file_path'] as String;
      final item = LibraryPlaybackMapper.fromDownloadHistory(
        DownloadHistoryItem(
          id: 'stream_${track.id}',
          trackName: track.name,
          artistName: track.artistName,
          albumName: track.albumName,
          coverUrl: track.coverUrl ?? '',
          filePath: filePath,
          service: service,
          downloadedAt: DateTime.now(),
          duration: track.duration,
        ),
      );
      ref.read(premiumPlaybackProvider.notifier).playLibrary([item]);
    } else {
      throw Exception('Failed to stream track: ${response['error']}');
    }
  }

  Future<String?> _resolveTrackPath(Track track) async {
    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    final localItem = await _findLocalLibraryItemForTrack(track);
    if (localItem != null && await fileExists(localItem.filePath)) {
      return localItem.filePath;
    }

    final historyItem = await _findDownloadHistoryItemForTrack(
      track,
      historyState,
    );
    if (historyItem != null) {
      if (await fileExists(historyItem.filePath)) {
        return historyItem.filePath;
      }
      historyNotifier.removeFromHistory(historyItem.id);
    }

    return null;
  }

  Future<LocalLibraryItem?> _findLocalLibraryItemForTrack(Track track) async {
    final isLocalSource = (track.source ?? '').toLowerCase() == 'local';
    if (isLocalSource) {
      final byId = await ref
          .read(localLibraryProvider.notifier)
          .getById(track.id);
      if (byId != null) return byId;
    }

    final isrc = track.isrc?.trim();
    return ref
        .read(localLibraryProvider.notifier)
        .findExistingAsync(
          isrc: isrc,
          trackName: track.name,
          artistName: track.artistName,
        );
  }

  Future<DownloadHistoryItem?> _findDownloadHistoryItemForTrack(
    Track track,
    DownloadHistoryState historyState,
  ) async {
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    for (final candidateId in _spotifyIdLookupCandidates(track.id)) {
      final bySpotifyId = historyState.getBySpotifyId(candidateId);
      if (bySpotifyId != null) {
        return bySpotifyId;
      }
      final bySpotifyIdAsync = await historyNotifier.getBySpotifyIdAsync(
        candidateId,
      );
      if (bySpotifyIdAsync != null) {
        return bySpotifyIdAsync;
      }
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = historyState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
      final byIsrcAsync = await historyNotifier.getByIsrcAsync(isrc);
      if (byIsrcAsync != null) {
        return byIsrcAsync;
      }
    }

    return historyNotifier.findByTrackAndArtistAsync(
      track.name,
      track.artistName,
    );
  }

  List<String> _spotifyIdLookupCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) {
        candidates.add(compact);
      }
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }

    final uri = Uri.tryParse(trimmed);
    final segments = uri?.pathSegments ?? const <String>[];
    final trackIndex = segments.indexOf('track');
    if (trackIndex >= 0 && trackIndex + 1 < segments.length) {
      final pathId = segments[trackIndex + 1].trim();
      if (pathId.isNotEmpty) {
        candidates.add(pathId);
        candidates.add('spotify:track:$pathId');
      }
    }

    return candidates.toList(growable: false);
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
