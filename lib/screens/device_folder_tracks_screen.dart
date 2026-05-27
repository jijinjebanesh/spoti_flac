import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/widgets/library_mini_player.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/services/library_database.dart';

class DeviceFolderTracksScreen extends ConsumerStatefulWidget {
  final String folderPath;
  final List<LocalLibraryItem> songs;

  const DeviceFolderTracksScreen({
    super.key,
    required this.folderPath,
    required this.songs,
  });

  @override
  ConsumerState<DeviceFolderTracksScreen> createState() => _DeviceFolderTracksScreenState();
}

class _DeviceFolderTracksScreenState extends ConsumerState<DeviceFolderTracksScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<LocalLibraryItem> _filteredSongs = [];

  final List<String> _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');
  String? _currentLetter;
  bool _isDraggingSidebar = false;

  @override
  void initState() {
    super.initState();
    _filteredSongs = widget.songs;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSongs = widget.songs;
      } else {
        _filteredSongs = widget.songs.where((item) {
          return item.trackName.toLowerCase().contains(query) ||
                 item.artistName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _scrollToLetter(String letter) {
    if (_filteredSongs.isEmpty) return;
    
    int targetIndex = -1;
    if (letter == '#') {
      targetIndex = 0;
    } else {
      for (int i = 0; i < _filteredSongs.length; i++) {
        final title = _filteredSongs[i].trackName.trim().toUpperCase();
        if (title.isNotEmpty && title.startsWith(letter)) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex != -1) {
      // Estimate offset: rows are approx 180px height. Grid has crossAxisCount approx 3 on mobile.
      // We will use a fallback estimation
      final crossAxisCount = MediaQuery.of(context).size.width ~/ 130;
      final row = targetIndex ~/ crossAxisCount;
      final offset = row * 190.0; 
      
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleSidebarDrag(Offset localPosition, BoxConstraints constraints) {
    final y = localPosition.dy;
    final itemHeight = constraints.maxHeight / _alphabet.length;
    int index = (y / itemHeight).floor();
    index = index.clamp(0, _alphabet.length - 1);
    
    final letter = _alphabet[index];
    if (letter != _currentLetter) {
      setState(() {
        _currentLetter = letter;
      });
      _scrollToLetter(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = p.basename(widget.folderPath).isEmpty
        ? widget.folderPath
        : p.basename(widget.folderPath);
    
    final hasMiniPlayer = ref.watch(premiumPlaybackProvider.select((s) => s.current != null));
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final miniPlayerInset = hasMiniPlayer ? 88.0 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs in folder',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16, 16, 36, 32 + bottomPadding + miniPlayerInset),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemCount: _filteredSongs.length,
            itemBuilder: (context, index) {
              final item = _filteredSongs[index];
              return _FolderTrackTile(
                item: item,
                songs: _filteredSongs,
                index: index,
              );
            },
          ),
          
          if (_filteredSongs.isNotEmpty)
            Positioned(
              right: 2,
              top: 16,
              bottom: 32 + bottomPadding + miniPlayerInset,
              width: 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onVerticalDragDown: (details) {
                      setState(() => _isDraggingSidebar = true);
                      _handleSidebarDrag(details.localPosition, constraints);
                    },
                    onVerticalDragUpdate: (details) {
                      _handleSidebarDrag(details.localPosition, constraints);
                    },
                    onVerticalDragEnd: (_) {
                      setState(() {
                        _isDraggingSidebar = false;
                        _currentLetter = null;
                      });
                    },
                    onVerticalDragCancel: () {
                      setState(() {
                        _isDraggingSidebar = false;
                        _currentLetter = null;
                      });
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _alphabet.map((letter) {
                          final isActive = letter == _currentLetter;
                          return Expanded(
                            child: Center(
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                  color: isActive 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),

          if (_isDraggingSidebar && _currentLetter != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _currentLetter!,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),

          if (hasMiniPlayer)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + bottomPadding,
              child: const LibraryMiniPlayer(),
            ),
        ],
      ),
    );
  }
}

class _FolderTrackTile extends ConsumerWidget {
  final LocalLibraryItem item;
  final List<LocalLibraryItem> songs;
  final int index;

  const _FolderTrackTile({
    required this.item,
    required this.songs,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget image;
    final path = item.coverPath;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        image = Image.network(path, fit: BoxFit.cover, errorBuilder: (_,__,___) => _fallback(colorScheme));
      } else if (path.startsWith('content://')) {
        final uri = Uri.parse(path);
        final idStr = uri.pathSegments.last;
        final id = int.tryParse(idStr) ?? 0;
        image = QueryArtworkWidget(
          id: id,
          type: ArtworkType.ALBUM,
          artworkFit: BoxFit.cover,
          nullArtworkWidget: _fallback(colorScheme),
        );
      } else if (File(path).existsSync()) {
        image = Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_,__,___) => _fallback(colorScheme));
      } else {
        image = _fallback(colorScheme);
      }
    } else {
      image = _fallback(colorScheme);
    }

    return GestureDetector(
      onTap: () => ref
          .read(premiumPlaybackProvider.notifier)
          .playLibrary(songs, startIndex: index),
      onLongPress: () {
        Navigator.push(
          context,
          slidePageRoute<void>(
            page: TrackMetadataScreen(
              localItem: item,
              localNavigationItems: songs,
              navigationIndex: index,
              coverHeroTag: 'cover_lib_local_${item.id}',
            ),
          ),
        );
      },
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Hero(
                        tag: 'cover_lib_local_${item.id}',
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: image,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.trackName.isEmpty ? p.basename(item.filePath) : item.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
    );
  }
}
