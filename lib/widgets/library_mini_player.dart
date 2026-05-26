import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/screens/premium_music_tab.dart';
import 'package:spotiflac_android/services/library_database.dart';

/// Bottom mini player overlay matching the app's Material 3 styling.
class LibraryMiniPlayer extends ConsumerWidget {
  const LibraryMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(premiumPlaybackProvider);
    final item = state.current;
    if (item == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final progress = state.duration.inMilliseconds == 0
        ? 0.0
        : state.position.inMilliseconds / state.duration.inMilliseconds;

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
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _PlayerCoverArt(item: item, size: 48),
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
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed:
                            ref.read(premiumPlaybackProvider.notifier).previous,
                      ),
                      FilledButton.tonalIcon(
                        onPressed: ref
                            .read(premiumPlaybackProvider.notifier)
                            .togglePlayPause,
                        icon: Icon(
                          state.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: const SizedBox.shrink(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed:
                            ref.read(premiumPlaybackProvider.notifier).next,
                      ),
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
          errorBuilder: (_, __, ___) => _fallback(scheme),
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
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: size, height: size, child: image),
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
