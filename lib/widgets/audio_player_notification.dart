import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/services/audio_service_provider.dart';

/// Compact audio player notification widget that shows in the app
class AudioPlayerNotification extends ConsumerWidget {
  final VoidCallback? onDismiss;

  const AudioPlayerNotification({
    Key? key,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(audioServiceProvider);

    // Don't show if nothing is playing
    if (!audioState.isPlaying && 
        audioState.currentTrackTitle == null) {
      return const SizedBox.shrink();
    }

    return Dismissible(
      key: const Key('audio_notification'),
      direction: DismissDirection.down,
      onDismissed: (_) {
        ref.read(audioServiceProvider.notifier).stop();
        onDismiss?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border(
            top: BorderSide(color: Colors.grey[800]!, width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Linear progress indicator
            StreamBuilder(
              stream: Stream.periodic(const Duration(milliseconds: 500)),
              builder: (context, snapshot) {
                final progress = audioState.duration.inMilliseconds > 0
                    ? audioState.position.inMilliseconds /
                        audioState.duration.inMilliseconds
                    : 0.0;
                return LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: Colors.grey[700],
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                );
              },
            ),
            // Notification content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  // Cover art or placeholder
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: audioState.coverArtUrl != null
                        ? Image.network(
                            audioState.coverArtUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.music_note),
                          )
                        : const Icon(Icons.music_note, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  // Track info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          audioState.currentTrackTitle ?? 'Unknown Track',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          audioState.currentTrackArtist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Play/Pause button
                  IconButton(
                    icon: Icon(
                      audioState.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFF1DB954),
                    ),
                    onPressed: () async {
                      final notifier =
                          ref.read(audioServiceProvider.notifier);
                      if (audioState.isPlaying) {
                        await notifier.pause();
                      } else {
                        await notifier.resume();
                      }
                    },
                  ),
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () async {
                      await ref.read(audioServiceProvider.notifier).stop();
                      onDismiss?.call();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating mini player that can be dragged around
class AudioMiniPlayer extends ConsumerStatefulWidget {
  final VoidCallback? onExpand;

  const AudioMiniPlayer({
    Key? key,
    this.onExpand,
  }) : super(key: key);

  @override
  ConsumerState<AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

class _AudioMiniPlayerState extends ConsumerState<AudioMiniPlayer> {
  late Offset _offset;
  late Size _screenSize;

  @override
  void initState() {
    super.initState();
    _offset = const Offset(20, 100);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  void _updatePosition(Offset newOffset) {
    setState(() {
      _offset = Offset(
        newOffset.dx.clamp(0, _screenSize.width - 80),
        newOffset.dy.clamp(0, _screenSize.height - 80),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final audioState = ref.watch(audioServiceProvider);

    if (!audioState.isPlaying &&
        audioState.currentTrackTitle == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          _updatePosition(_offset + details.delta);
        },
        child: GestureDetector(
          onTap: widget.onExpand,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[900],
              border: Border.all(
                color: const Color(0xFF1DB954),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Cover art background
                if (audioState.coverArtUrl != null)
                  ClipOval(
                    child: Image.network(
                      audioState.coverArtUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.music_note, size: 40),
                    ),
                  )
                else
                  Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note, size: 40),
                  ),
                // Play/Pause overlay button
                CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  radius: 20,
                  child: IconButton(
                    icon: Icon(
                      audioState.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: const Color(0xFF1DB954),
                      size: 24,
                    ),
                    onPressed: () async {
                      final notifier =
                          ref.read(audioServiceProvider.notifier);
                      if (audioState.isPlaying) {
                        await notifier.pause();
                      } else {
                        await notifier.resume();
                      }
                    },
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
