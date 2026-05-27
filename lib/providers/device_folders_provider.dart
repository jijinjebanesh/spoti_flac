import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spotiflac_android/services/library_database.dart';

final deviceFoldersProvider = FutureProvider.autoDispose<Map<String, List<LocalLibraryItem>>>((ref) async {
  final audioQuery = OnAudioQuery();
  bool permissionGranted = false;
  if (Platform.isAndroid) {
    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) {
      permissionGranted = true;
    } else {
      final storageStatus = await Permission.storage.request();
      permissionGranted = storageStatus.isGranted;
    }
  } else {
    permissionGranted = true;
  }

  if (!permissionGranted) {
    throw Exception('Permission denied to read audio files');
  }

  final songs = await audioQuery.querySongs(
    sortType: null,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );

  final groups = <String, List<LocalLibraryItem>>{};
  
  for (final song in songs) {
    final path = song.data;
    
    final segments = path.split(Platform.pathSeparator);
    String folder = path;
    if (segments.length > 1) {
      segments.removeLast();
      folder = segments.join(Platform.pathSeparator);
    }
    
    final item = LocalLibraryItem(
      id: song.id.toString(),
      trackName: song.title,
      artistName: song.artist ?? 'Unknown Artist',
      albumName: song.album ?? 'Unknown Album',
      filePath: path,
      format: path.split('.').last,
      scannedAt: DateTime.now(),
      coverPath: song.albumId != null ? 'content://media/external/audio/albumart/${song.albumId}' : null,
    );

    (groups[folder] ??= []).add(item);
  }
  
  final sortedKeys = groups.keys.toList()..sort((a, b) => a.compareTo(b));
  return {for (final key in sortedKeys) key: groups[key]!};
});
