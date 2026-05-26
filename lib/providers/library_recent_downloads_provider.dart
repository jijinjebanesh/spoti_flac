import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/utils/library_playback_mapper.dart';

const _libraryRecentDownloadsLimit = 20;

/// Recent downloads limited to the user's selected download location.
final libraryRecentDownloadsProvider = Provider<List<DownloadHistoryItem>>((ref) {
  final settings = ref.watch(settingsProvider);
  final items = ref.watch(downloadHistoryProvider.select((s) => s.items));
  final filtered = <DownloadHistoryItem>[];
  for (final item in items) {
    if (!LibraryPlaybackMapper.isInSelectedDownloadLocation(item, settings)) {
      continue;
    }
    filtered.add(item);
    if (filtered.length >= _libraryRecentDownloadsLimit) break;
  }
  return filtered;
});
