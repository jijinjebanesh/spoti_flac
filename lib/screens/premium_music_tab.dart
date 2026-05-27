import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/local_library_track_mapper.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/widgets/premium_lyrics_sheet.dart';
import 'package:on_audio_query/on_audio_query.dart';

class PremiumMusicTab extends ConsumerStatefulWidget {
  const PremiumMusicTab({super.key});

  @override
  ConsumerState<PremiumMusicTab> createState() => _PremiumMusicTabState();
}

class _PremiumMusicTabState extends ConsumerState<PremiumMusicTab>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final TabController _tabController;
  List<LocalLibraryItem> _items = const [];
  LocalLibrarySortMode _sort = LocalLibrarySortMode.album;
  bool _loading = true;
  String? _error;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await LibraryDatabase.instance.getPage(
        LocalLibraryPageRequest(limit: 5000, sortMode: _sort),
      );
      final items = rows.map(LocalLibraryItem.fromJson).where((item) {
        return !item.filePath.contains('.cue#') && File(item.filePath).existsSync();
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<LocalLibraryItem> get _filteredItems {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      return item.trackName.toLowerCase().contains(q) ||
          item.artistName.toLowerCase().contains(q) ||
          item.albumName.toLowerCase().contains(q) ||
          (item.genre ?? '').toLowerCase().contains(q) ||
          item.filePath.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<LocalLibraryItem> _itemsByIds(Iterable<String> ids) {
    final wanted = ids.toSet();
    return _items.where((item) => wanted.contains(item.id)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      localLibraryProvider.select((s) => s.loadedIndexVersion),
      (_, __) => _load(),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredItems;
    final playback = ref.watch(premiumPlaybackProvider);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: _selected.isEmpty
              ? const Text('Music')
              : Text('${_selected.length} selected'),
        ),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              tooltip: 'Play selected',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => ref
                  .read(premiumPlaybackProvider.notifier)
                  .playLibrary(_itemsByIds(_selected)),
            ),
            IconButton(
              tooltip: 'Share selected files',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _shareSelected,
            ),
            IconButton(
              tooltip: 'Delete selected downloads',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteSelected,
            ),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_selected.clear),
            ),
          ] else ...[
            PopupMenuButton<LocalLibrarySortMode>(
              tooltip: 'Sort library',
              icon: const Icon(Icons.sort_rounded),
              onSelected: (mode) {
                setState(() => _sort = mode);
                _load();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: LocalLibrarySortMode.album, child: Text('Album order')),
                PopupMenuItem(value: LocalLibrarySortMode.title, child: Text('Title')),
                PopupMenuItem(value: LocalLibrarySortMode.artist, child: Text('Artist')),
                PopupMenuItem(value: LocalLibrarySortMode.latest, child: Text('Recently added')),
                PopupMenuItem(value: LocalLibrarySortMode.quality, child: Text('Quality')),
              ],
            ),
            IconButton(
              tooltip: 'Rescan/reload library',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, albums, artists, genres, folders',
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
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Songs'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Genres'),
                  Tab(text: 'Folders'),
                  Tab(text: 'Recent'),
                  Tab(text: 'Most played'),
                  Tab(text: 'Favorites'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _EmptyMusicState(
                    icon: Icons.error_outline_rounded,
                    title: 'Library unavailable',
                    subtitle: _error!,
                    action: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  )
                : filtered.isEmpty
                    ? const _EmptyMusicState(
                        icon: Icons.library_music_outlined,
                        title: 'No downloaded songs found',
                        subtitle: 'Scan your download folder from Library settings, or download music first.',
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _SongsList(items: filtered, selected: _selected, onToggleSelect: _toggleSelect),
                          _GroupedList(groups: _groupBy(filtered, (i) => i.albumName.isEmpty ? 'Unknown album' : i.albumName, subtitle: (songs) => songs.first.artistName), icon: Icons.album_rounded),
                          _GroupedList(groups: _groupBy(filtered, (i) => i.artistName.isEmpty ? 'Unknown artist' : i.artistName), icon: Icons.person_rounded),
                          _GroupedList(groups: _groupBy(filtered, (i) => (i.genre?.trim().isEmpty ?? true) ? 'Unknown genre' : i.genre!.trim()), icon: Icons.auto_awesome_rounded),
                          _GroupedList(groups: _groupBy(filtered, (i) => File(i.filePath).parent.path), icon: Icons.folder_rounded),
                          _SongsList(items: _itemsByIds(playback.recentlyPlayedIds).where(filtered.contains).toList(), selected: _selected, onToggleSelect: _toggleSelect),
                          _SongsList(items: [...filtered]..sort((a, b) => (playback.playCounts[b.id] ?? 0).compareTo(playback.playCounts[a.id] ?? 0)), selected: _selected, onToggleSelect: _toggleSelect),
                          _SongsList(items: filtered.where((i) => playback.favorites.contains(i.id)).toList(), selected: _selected, onToggleSelect: _toggleSelect),
                        ],
                      ),
      ),
      bottomNavigationBar: playback.current == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
              ),
              child: _MiniPlayer(onExpand: _openNowPlaying),
            ),
      floatingActionButton: filtered.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => ref.read(premiumPlaybackProvider.notifier).playLibrary(filtered),
              icon: Icon(playback.playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded),
              label: const Text('Play all'),
              backgroundColor: colorScheme.primaryContainer,
            ),
    );
  }

  Map<String, List<LocalLibraryItem>> _groupBy(
    List<LocalLibraryItem> items,
    String Function(LocalLibraryItem item) keyOf, {
    String Function(List<LocalLibraryItem> songs)? subtitle,
  }) {
    final map = <String, List<LocalLibraryItem>>{};
    for (final item in items) {
      (map[keyOf(item)] ??= <LocalLibraryItem>[]).add(item);
    }
    return Map.fromEntries(map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  void _toggleSelect(LocalLibraryItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(item.id)) _selected.remove(item.id);
    });
  }

  Future<void> _shareSelected() async {
    final files = _itemsByIds(_selected).map((e) => XFile(e.filePath)).toList();
    if (files.isEmpty) return;
    await Share.shareXFiles(files, text: 'Shared from SpotiFLAC Music');
  }

  Future<void> _deleteSelected() async {
    final selectedItems = _itemsByIds(_selected);
    if (selectedItems.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete downloaded files?'),
        content: Text('This permanently deletes ${selectedItems.length} local audio file(s).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final item in selectedItems) {
      try {
        final file = File(item.filePath);
        if (file.existsSync()) file.deleteSync();
        await LibraryDatabase.instance.delete(item.id);
      } catch (_) {}
    }
    setState(_selected.clear);
    await ref.read(localLibraryProvider.notifier).reloadFromStorage();
    await _load();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: const NowPlayingScreen(),
        ),
      ),
    );
  }
}

class _SongsList extends ConsumerWidget {
  final List<LocalLibraryItem> items;
  final Set<String> selected;
  final ValueChanged<LocalLibraryItem> onToggleSelect;

  const _SongsList({required this.items, required this.selected, required this.onToggleSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const _EmptyMusicState(icon: Icons.music_note_rounded, title: 'Nothing here yet', subtitle: 'Play music and mark favorites to fill this view.');
    }
    final bottomPadding = ref.watch(premiumPlaybackProvider).current == null ? 96.0 : 170.0;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = selected.contains(item.id);
        return _SongTile(
          item: item,
          selected: isSelected,
          onLongPress: () => onToggleSelect(item),
          onTap: selected.isNotEmpty
              ? () => onToggleSelect(item)
              : () => ref.read(premiumPlaybackProvider.notifier).playLibrary(items, startIndex: index),
        );
      },
    );
  }
}

class _GroupedList extends ConsumerWidget {
  final Map<String, List<LocalLibraryItem>> groups;
  final IconData icon;

  const _GroupedList({required this.groups, required this.icon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = groups.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 170),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final songs = entry.value;
        return Card(
          child: ListTile(
            leading: _CoverArt(item: songs.first, icon: icon, size: 54),
            title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${songs.length} song${songs.length == 1 ? '' : 's'} • ${songs.first.artistName}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => ref.read(premiumPlaybackProvider.notifier).playLibrary(songs),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _GroupSongsScreen(title: entry.key, songs: songs),
            )),
          ),
        );
      },
    );
  }
}

class _GroupSongsScreen extends StatelessWidget {
  final String title;
  final List<LocalLibraryItem> songs;

  const _GroupSongsScreen({required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Consumer(
        builder: (context, ref, _) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
          itemCount: songs.length,
          itemBuilder: (context, index) => _SongTile(
            item: songs[index],
            onTap: () => ref.read(premiumPlaybackProvider.notifier).playLibrary(songs, startIndex: index),
          ),
        ),
      ),
    );
  }
}

class _SongTile extends ConsumerWidget {
  final LocalLibraryItem item;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _SongTile({required this.item, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(premiumPlaybackProvider);
    final isCurrent = playback.current?.id == item.id;
    final favorite = playback.favorites.contains(item.id);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .65)
            : isCurrent
                ? scheme.secondaryContainer.withValues(alpha: .5)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        leading: _CoverArt(item: item, size: 52),
        title: Text(item.trackName.isEmpty ? File(item.filePath).uri.pathSegments.last : item.trackName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${item.artistName} • ${_qualityLabel(item)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: scheme.primary)
            : Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: favorite ? 'Remove favorite' : 'Favorite',
                    icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    onPressed: () => ref.read(premiumPlaybackProvider.notifier).toggleFavorite(item),
                  ),
                  IconButton(
                    tooltip: 'Add to playlist',
                    icon: const Icon(Icons.playlist_add_check_rounded),
                    onPressed: () => showAddTrackToPlaylistSheet(
                      context,
                      ref,
                      trackFromLocalLibraryItem(item),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add to queue',
                    icon: const Icon(Icons.queue_play_next_rounded),
                    onPressed: () => ref.read(premiumPlaybackProvider.notifier).addToQueue(item),
                  ),
                ],
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _MiniPlayer extends ConsumerWidget {
  final VoidCallback onExpand;
  const _MiniPlayer({required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(premiumPlaybackProvider);
    final item = state.current;
    if (item == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final progress = state.duration.inMilliseconds == 0 ? 0.0 : state.position.inMilliseconds / state.duration.inMilliseconds;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .82),
          child: InkWell(
            onTap: onExpand,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Hero(tag: 'now-art-${item.id}', child: _CoverArt(item: item, size: 48)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(item.trackName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                          Text(item.artistName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                      IconButton(icon: const Icon(Icons.skip_previous_rounded), onPressed: ref.read(premiumPlaybackProvider.notifier).previous),
                      FilledButton.tonalIcon(
                        onPressed: ref.read(premiumPlaybackProvider.notifier).togglePlayPause,
                        icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        label: const SizedBox.shrink(),
                      ),
                      IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: ref.read(premiumPlaybackProvider.notifier).next),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(premiumPlaybackProvider);
    final item = state.current;
    final scheme = Theme.of(context).colorScheme;
    if (item == null) return const Scaffold(body: Center(child: Text('Nothing playing')));
    final art = item.coverPath == null ? null : File(item.coverPath!);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Now playing'),
        actions: [
          IconButton(
            tooltip: 'Add to playlist',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () => showAddTrackToPlaylistSheet(
              context,
              ref,
              trackFromLocalLibraryItem(item),
            ),
          ),
          IconButton(
            icon: Icon(state.favorites.contains(item.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
            onPressed: () => ref.read(premiumPlaybackProvider.notifier).toggleFavorite(item),
          ),
          IconButton(icon: const Icon(Icons.queue_music_rounded), onPressed: () => _showQueue(context, ref)),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (item.coverPath != null && item.coverPath!.isNotEmpty)
            if (item.coverPath!.startsWith('http://') || item.coverPath!.startsWith('https://'))
              Image.network(item.coverPath!, fit: BoxFit.cover)
            else if (item.coverPath!.startsWith('content://'))
              QueryArtworkWidget(
                id: int.tryParse(Uri.parse(item.coverPath!).pathSegments.last) ?? 0,
                type: ArtworkType.ALBUM,
                artworkFit: BoxFit.cover,
                nullArtworkWidget: ColoredBox(color: scheme.surface),
              )
            else if (File(item.coverPath!).existsSync())
              Image.file(File(item.coverPath!), fit: BoxFit.cover)
            else
              ColoredBox(color: scheme.surface)
          else
            ColoredBox(color: scheme.surface),
          BackdropFilter(filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38), child: ColoredBox(color: scheme.surface.withValues(alpha: .72))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
              child: Column(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v < -250) ref.read(premiumPlaybackProvider.notifier).next();
                      if (v > 250) ref.read(premiumPlaybackProvider.notifier).previous();
                    },
                    child: Hero(
                      tag: 'now-art-${item.id}',
                      child: _AnimatedDiscArt(item: item),
                    ),
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      text: item.trackName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      text: item.artistName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 18),
                  _WaveformProgress(position: state.position, duration: state.duration, buffered: state.bufferedPosition),
                  Row(
                    children: [
                      Text(_fmt(state.position)),
                      const Spacer(),
                      Text(_fmt(state.duration)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        icon: Icon(state.shuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded),
                        onPressed: () => ref.read(premiumPlaybackProvider.notifier).setShuffle(!state.shuffle),
                      ),
                      IconButton.filledTonal(iconSize: 34, icon: const Icon(Icons.skip_previous_rounded), onPressed: ref.read(premiumPlaybackProvider.notifier).previous),
                      FilledButton(
                        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(24)),
                        onPressed: ref.read(premiumPlaybackProvider.notifier).togglePlayPause,
                        child: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 42),
                      ),
                      IconButton.filledTonal(iconSize: 34, icon: const Icon(Icons.skip_next_rounded), onPressed: ref.read(premiumPlaybackProvider.notifier).next),
                      IconButton.filledTonal(
                        icon: Icon(switch (state.repeatMode) { PremiumRepeatMode.one => Icons.repeat_one_rounded, PremiumRepeatMode.all => Icons.repeat_on_rounded, _ => Icons.repeat_rounded }),
                        onPressed: ref.read(premiumPlaybackProvider.notifier).cycleRepeatMode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.speed_rounded, size: 18),
                        label: Text('${state.speed.toStringAsFixed(2)}×'),
                        onPressed: () => _showSpeed(context, ref, state.speed),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.bedtime_rounded, size: 18),
                        label: Text(state.hasSleepTimer ? 'Sleep on' : 'Sleep timer'),
                        onPressed: () => _showSleepTimer(context, ref),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.lyrics_rounded, size: 18),
                        label: const Text('Lyrics'),
                        onPressed: () => showPremiumLyricsSheet(context, item),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQueue(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _PlaybackQueueSheet(parentRef: ref),
    );
  }
}

class _PlaybackQueueSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;

  const _PlaybackQueueSheet({required this.parentRef});

  @override
  ConsumerState<_PlaybackQueueSheet> createState() => _PlaybackQueueSheetState();
}

class _PlaybackQueueSheetState extends ConsumerState<_PlaybackQueueSheet> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(premiumPlaybackProvider);
    final notifier = ref.read(premiumPlaybackProvider.notifier);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Queue',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${state.queue.length} tracks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Hold and drag to reorder',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: state.queue.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  notifier.reorderQueue(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final item = state.queue[index];
                  final isCurrent = index == state.currentIndex;
                  return Material(
                    key: ValueKey('queue-${item.id}-$index'),
                    color: isCurrent
                        ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .45)
                        : null,
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: _CoverArt(item: item, size: 42),
                      ),
                      title: Text(
                        item.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => notifier.removeAt(index),
                      ),
                      onTap: () async {
                        await notifier.playLibrary(state.queue, startIndex: index);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformProgress extends ConsumerStatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  const _WaveformProgress({required this.position, required this.duration, required this.buffered});

  @override
  ConsumerState<_WaveformProgress> createState() => _WaveformProgressState();
}

class _WaveformProgressState extends ConsumerState<_WaveformProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds <= 0 ? 1.0 : widget.duration.inMilliseconds.toDouble();
    final value = _dragValue ?? widget.position.inMilliseconds.toDouble();
    
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(trackHeight: 8, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
      child: Slider(
        value: value.clamp(0.0, max),
        max: max,
        secondaryTrackValue: widget.buffered.inMilliseconds.clamp(0, max.toInt()).toDouble(),
        onChangeStart: (v) => setState(() => _dragValue = v),
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) {
          ref.read(premiumPlaybackProvider.notifier).seek(Duration(milliseconds: v.round()));
          setState(() => _dragValue = null);
        },
      ),
    );
  }
}

class _AnimatedDiscArt extends ConsumerWidget {
  final LocalLibraryItem item;
  const _AnimatedDiscArt({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(premiumPlaybackProvider.select((s) => s.playing));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: playing ? 1 : 0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.rotate(
        angle: value * math.pi / 80,
        child: child,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 340),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 38, offset: const Offset(0, 24))],
        ),
        child: ClipOval(child: _CoverArt(item: item, size: 340, icon: Icons.album_rounded)),
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  final LocalLibraryItem item;
  final double size;
  final IconData icon;
  const _CoverArt({required this.item, this.size = 56, this.icon = Icons.music_note_rounded});

  @override
  Widget build(BuildContext context) {
    final path = item.coverPath?.trim();
    final scheme = Theme.of(context).colorScheme;
    Widget image;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        image = Image.network(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(scheme),
        );
      } else if (path.startsWith('content://')) {
        final uri = Uri.parse(path);
        final idStr = uri.pathSegments.last;
        final id = int.tryParse(idStr) ?? 0;
        image = QueryArtworkWidget(
          id: id,
          type: ArtworkType.ALBUM,
          artworkFit: BoxFit.cover,
          artworkWidth: size,
          artworkHeight: size,
          nullArtworkWidget: _fallback(scheme),
        );
      } else if (File(path).existsSync()) {
        image = Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(scheme));
      } else {
        image = _fallback(scheme);
      }
    } else {
      image = _fallback(scheme);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 100 ? 32 : 14),
      child: SizedBox(
        width: size,
        height: size,
        child: image,
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]),
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer, size: size * .48),
      );
}

class _EmptyMusicState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _EmptyMusicState({required this.icon, required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

String _qualityLabel(LocalLibraryItem item) {
  final parts = <String>[];
  if (item.format != null) parts.add(item.format!.toUpperCase());
  if (item.bitDepth != null && item.sampleRate != null) {
    parts.add('${item.bitDepth}-bit ${(item.sampleRate! / 1000).toStringAsFixed(1)} kHz');
  } else if (item.bitrate != null) {
    parts.add('${item.bitrate} kbps');
  }
  return parts.isEmpty ? item.albumName : parts.join(' • ');
}

String _fmt(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString();
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

void _showSpeed(BuildContext context, WidgetRef ref, double speed) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Playback speed', style: Theme.of(context).textTheme.titleLarge),
          Slider(
            min: .5,
            max: 2,
            divisions: 30,
            value: speed,
            label: '${speed.toStringAsFixed(2)}×',
            onChanged: (v) {
              setModalState(() => speed = v);
              ref.read(premiumPlaybackProvider.notifier).setSpeed(v);
            },
          ),
        ]),
      ),
    ),
  );
}

void _showSleepTimer(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final minutes in [15, 30, 45, 60, 90])
          ActionChip(label: Text('$minutes min'), onPressed: () {
            ref.read(premiumPlaybackProvider.notifier).startSleepTimer(Duration(minutes: minutes));
            Navigator.pop(context);
          }),
        ActionChip(label: const Text('Cancel timer'), onPressed: () {
          ref.read(premiumPlaybackProvider.notifier).cancelSleepTimer();
          Navigator.pop(context);
        }),
      ]),
    ),
  );
}

