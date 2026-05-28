import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlaylistBackupService');

const _backupFileName = 'playlists_backup.json';

class PlaylistBackupData {
  final List<PlaylistBackupEntry> playlists;
  final DateTime backupTime;
  final String appVersion;

  PlaylistBackupData({
    required this.playlists,
    required this.backupTime,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
    'version': 1,
    'backupTime': backupTime.toIso8601String(),
    'appVersion': appVersion,
    'playlists': playlists.map((p) => p.toJson()).toList(),
  };

  factory PlaylistBackupData.fromJson(Map<String, dynamic> json) {
    final playlistsList = json['playlists'] as List?;
    return PlaylistBackupData(
      playlists:
          playlistsList
              ?.cast<Map<String, dynamic>>()
              .map((p) => PlaylistBackupEntry.fromJson(p))
              .toList() ??
          [],
      backupTime:
          DateTime.tryParse(json['backupTime'] as String? ?? '') ??
          DateTime.now(),
      appVersion: json['appVersion'] as String? ?? 'unknown',
    );
  }
}

class PlaylistBackupEntry {
  final String id;
  final String name;
  final String? coverImagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PlaylistTrackBackupEntry> tracks;

  PlaylistBackupEntry({
    required this.id,
    required this.name,
    this.coverImagePath,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'coverImagePath': coverImagePath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory PlaylistBackupEntry.fromJson(Map<String, dynamic> json) {
    final tracksList = json['tracks'] as List?;
    return PlaylistBackupEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      coverImagePath: json['coverImagePath'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      tracks:
          tracksList
              ?.cast<Map<String, dynamic>>()
              .map((t) => PlaylistTrackBackupEntry.fromJson(t))
              .toList() ??
          [],
    );
  }
}

class PlaylistTrackBackupEntry {
  final String trackKey;
  final String trackJson;
  final DateTime addedAt;

  PlaylistTrackBackupEntry({
    required this.trackKey,
    required this.trackJson,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'trackKey': trackKey,
    'trackJson': trackJson,
    'addedAt': addedAt.toIso8601String(),
  };

  factory PlaylistTrackBackupEntry.fromJson(Map<String, dynamic> json) {
    return PlaylistTrackBackupEntry(
      trackKey: json['trackKey'] as String,
      trackJson: json['trackJson'] as String,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Service for backing up and restoring playlists to/from external storage
class PlaylistBackupService {
  static final PlaylistBackupService _instance = PlaylistBackupService._init();

  factory PlaylistBackupService() {
    return _instance;
  }

  PlaylistBackupService._init();

  /// Get the backup file path from the user's download directory
  Future<File?> _getBackupFilePath(String downloadDirectory) async {
    if (downloadDirectory.isEmpty) {
      _log.w('⚠️ Download directory not configured, cannot create backup');
      return null;
    }

    final dir = Directory(downloadDirectory);
    if (!dir.existsSync()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        _log.e('Failed to create download directory: $e');
        return null;
      }
    }

    return File(p.join(downloadDirectory, _backupFileName));
  }

  /// Backup all playlists to external storage
  Future<bool> backupPlaylists({
    required List<UserPlaylistCollection> playlists,
    required String downloadDirectory,
    required String appVersion,
  }) async {
    try {
      final backupFile = await _getBackupFilePath(downloadDirectory);
      if (backupFile == null) return false;

      // Convert playlists to backup format
      final backupEntries = playlists
          .map((UserPlaylistCollection? playlist) {
            if (playlist == null) return null;
            return PlaylistBackupEntry(
              id: playlist.id,
              name: playlist.name,
              coverImagePath: playlist.coverImagePath,
              createdAt: playlist.createdAt,
              updatedAt: playlist.updatedAt,
              tracks: playlist.tracks.map((CollectionTrackEntry track) {
                return PlaylistTrackBackupEntry(
                  trackKey: track.key,
                  trackJson: jsonEncode(track.track.toJson()),
                  addedAt: track.addedAt,
                );
              }).toList(),
            );
          })
          .whereType<PlaylistBackupEntry>()
          .toList();

      final backup = PlaylistBackupData(
        playlists: backupEntries,
        backupTime: DateTime.now(),
        appVersion: appVersion,
      );

      // Write to file
      await backupFile.writeAsString(jsonEncode(backup.toJson()), flush: true);

      _log.i('✅ Backed up ${playlists.length} playlists to ${backupFile.path}');
      return true;
    } catch (e, stack) {
      _log.e('Failed to backup playlists: $e', e, stack);
      return false;
    }
  }

  /// Restore playlists from external storage backup
  Future<PlaylistBackupData?> restorePlaylistsFromBackup(
    String downloadDirectory,
  ) async {
    try {
      final backupFile = await _getBackupFilePath(downloadDirectory);
      if (backupFile == null || !backupFile.existsSync()) {
        _log.i('No backup file found at ${backupFile?.path}');
        return null;
      }

      final content = await backupFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final backup = PlaylistBackupData.fromJson(json);

      _log.i(
        '✅ Loaded backup with ${backup.playlists.length} playlists from ${backupFile.path}',
      );
      return backup;
    } catch (e, stack) {
      _log.e('Failed to restore playlists from backup: $e', e, stack);
      return null;
    }
  }

  /// Check if backup file exists
  Future<bool> hasBackupFile(String downloadDirectory) async {
    final backupFile = await _getBackupFilePath(downloadDirectory);
    return backupFile != null && backupFile.existsSync();
  }

  /// Delete backup file
  Future<bool> deleteBackupFile(String downloadDirectory) async {
    try {
      final backupFile = await _getBackupFilePath(downloadDirectory);
      if (backupFile != null && backupFile.existsSync()) {
        await backupFile.delete();
        _log.i('🗑️ Deleted backup file');
        return true;
      }
      return false;
    } catch (e) {
      _log.e('Failed to delete backup file: $e');
      return false;
    }
  }
}
