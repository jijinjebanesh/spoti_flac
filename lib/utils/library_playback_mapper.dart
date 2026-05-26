import 'package:path/path.dart' as p;
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';

/// Maps library models into [LocalLibraryItem] for the in-app player.
class LibraryPlaybackMapper {
  const LibraryPlaybackMapper._();

  static LocalLibraryItem fromDownloadHistory(DownloadHistoryItem item) {
    return LocalLibraryItem(
      id: 'dl_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      albumArtist: item.albumArtist,
      filePath: item.filePath,
      coverPath: _coverPathForHistory(item),
      scannedAt: item.downloadedAt,
      isrc: item.isrc,
      trackNumber: item.trackNumber,
      totalTracks: item.totalTracks,
      discNumber: item.discNumber,
      totalDiscs: item.totalDiscs,
      duration: item.duration,
      releaseDate: item.releaseDate,
      bitDepth: item.bitDepth,
      sampleRate: item.sampleRate,
      bitrate: item.bitrate,
      genre: item.genre,
      composer: item.composer,
      label: item.label,
      copyright: item.copyright,
      format: item.format,
    );
  }

  static LocalLibraryItem fromLocalLibrary(LocalLibraryItem item) => item;

  static List<LocalLibraryItem> fromDownloadHistoryList(
    List<DownloadHistoryItem> items,
  ) {
    return items.map(fromDownloadHistory).toList(growable: false);
  }

  static String? _coverPathForHistory(DownloadHistoryItem item) {
    final cover = item.coverUrl?.trim();
    if (cover == null || cover.isEmpty) return null;
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return cover;
    }
    return cover;
  }

  static bool isInSelectedDownloadLocation(
    DownloadHistoryItem item,
    AppSettings settings,
  ) {
    if (settings.storageMode == 'saf') {
      if (settings.downloadTreeUri.isEmpty) return true;
      if (item.storageMode != 'saf') return false;
      final itemTree = item.downloadTreeUri?.trim() ?? '';
      if (itemTree.isEmpty) return true;
      return itemTree == settings.downloadTreeUri;
    }

    final downloadDir = settings.downloadDirectory.trim();
    if (downloadDir.isEmpty) return true;
    return _pathUnderDirectory(item.filePath, downloadDir);
  }

  static bool _pathUnderDirectory(String filePath, String directory) {
    final normalizedFile = p.normalize(filePath).toLowerCase();
    final normalizedDir = p.normalize(directory).toLowerCase();
    if (normalizedFile == normalizedDir) return true;
    final dirWithSep = normalizedDir.endsWith(p.separator)
        ? normalizedDir
        : '$normalizedDir${p.separator}';
    return normalizedFile.startsWith(dirWithSep);
  }
}
