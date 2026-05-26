import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/library_database.dart';

/// Maps [LocalLibraryItem] to [Track] for playlist collections and metadata flows.
Track trackFromLocalLibraryItem(LocalLibraryItem item) {
  return Track(
    id: item.id,
    name: item.trackName,
    artistName: item.artistName,
    albumName: item.albumName,
    albumArtist: item.albumArtist,
    coverUrl: item.coverPath,
    isrc: item.isrc,
    duration: item.duration ?? 0,
    trackNumber: item.trackNumber,
    discNumber: item.discNumber,
    releaseDate: item.releaseDate,
    source: 'local',
  );
}
