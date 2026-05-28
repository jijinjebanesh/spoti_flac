import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/screens/premium_music_tab.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Bottom mini player overlay matching the app's Material 3 styling.
class LibraryMiniPlayer extends ConsumerWidget {
  const LibraryMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ FIXED: Only watch the current item - NOT position/duration
    final item = ref.watch(premiumPlaybackProvider.select((s) => s.current));
    if (item == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .88),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 420),
                reverseTransitionDuration: const Duration(milliseconds: 320),
                pageBuilder: (_, animation, __) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                  child: const NowPlayingScreen(),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ FIXED: Separated progress into dedicated widget
                _MiniPlayerProgress(),
                // ✅ FIXED: Isolate cover art in RepaintBoundary to prevent flicker from progress updates
                RepaintBoundary(child: _MiniPlayerContent(item: item)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ NEW: Progress bar updates separately without rebuilding cover
class _MiniPlayerProgress extends ConsumerWidget {
  const _MiniPlayerProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      premiumPlaybackProvider.select((s) => s.position),
    );
    final duration = ref.watch(
      premiumPlaybackProvider.select((s) => s.duration),
    );
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      minHeight: 3,
    );
  }
}

// ✅ NEW: Controls update separately without rebuilding cover
class _MiniPlayerControls extends ConsumerWidget {
  const _MiniPlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(premiumPlaybackProvider.select((s) => s.playing));
    final notifier = ref.read(premiumPlaybackProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: notifier.previous,
        ),
        FilledButton.tonalIcon(
          onPressed: notifier.togglePlayPause,
          icon: Icon(
            playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
          label: const SizedBox.shrink(),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: notifier.next,
        ),
      ],
    );
  }
}

// ✅ NEW: Isolate mini player content from progress bar updates
class _MiniPlayerContent extends StatelessWidget {
  final LocalLibraryItem item;
  const _MiniPlayerContent({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          // ✅ FIXED: High-quality cover art with RepaintBoundary
          RepaintBoundary(
            child: _PlayerCoverArt(item: item, size: 48),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  item.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MiniPlayerControls(),
        ],
      ),
    );
  }
}

class _PlayerCoverArt extends StatelessWidget {
  final LocalLibraryItem item;
  final double size;

  const _PlayerCoverArt({required this.item, required this.size});

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
          filterQuality: FilterQuality.high, // ✅ FIXED: High quality image rendering
          errorBuilder: (_, __, ___) => _fallback(scheme),
        );
      } else if (path.startsWith('content://')) {
        final uri = Uri.parse(path);
        final idStr = uri.pathSegments.last;
        final id = int.tryParse(idStr) ?? 0;
        image = QueryArtworkWidget(
          key: ValueKey(path),
          id: id,
          type: ArtworkType.ALBUM,
          artworkFit: BoxFit.cover,
          artworkWidth: size.toDouble(), // ✅ FIXED: Use toDouble() for proper sizing
          artworkHeight: size.toDouble(), // ✅ FIXED: Use toDouble() for proper sizing
          artworkQuality: FilterQuality.high, // ✅ FIXED: High quality artwork
          nullArtworkWidget: _fallback(scheme),
        );
      } else if (File(path).existsSync()) {
        image = Image.file(
          File(path),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high, // ✅ FIXED: High quality image rendering
          errorBuilder: (_, __, ___) => _fallback(scheme),
        );
      } else {
        image = _fallback(scheme);
      }
    } else {
      image = _fallback(scheme);
    }

    return RepaintBoundary( // ✅ FIXED: Isolate cover art in RepaintBoundary
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: size, height: size, child: image),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: scheme.onPrimaryContainer,
        size: size * .48,
      ),
    );
  }
}

String formatPlayerDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString();
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
