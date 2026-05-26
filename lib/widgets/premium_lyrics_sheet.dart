import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/lyrics_display_helper.dart';

class PremiumLyricsSheet extends StatefulWidget {
  final LocalLibraryItem item;

  const PremiumLyricsSheet({super.key, required this.item});

  @override
  State<PremiumLyricsSheet> createState() => _PremiumLyricsSheetState();
}

class _PremiumLyricsSheetState extends State<PremiumLyricsSheet> {
  bool _loading = true;
  String? _lyrics;
  String? _source;
  bool _instrumental = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _loading = true;
      _error = null;
      _instrumental = false;
      _lyrics = null;
      _source = null;
    });

    try {
      final result = await fetchLyricsForLocalTrack(
        trackName: widget.item.trackName,
        artistName: widget.item.artistName,
        filePath: widget.item.filePath,
        durationSeconds: (widget.item.duration ?? 0) ~/ 1000,
      );

      if (!mounted) return;

      if (result.instrumental) {
        setState(() {
          _instrumental = true;
          _source = result.source;
          _loading = false;
        });
        return;
      }

      if (!result.hasLyrics) {
        setState(() {
          _error = 'Lyrics not available for this track.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _lyrics = result.displayText;
        _source = result.source;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Lyrics request timed out. Try again.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load lyrics.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.item.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh lyrics',
                    onPressed: _loading ? null : _loadLyrics,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (_source != null && _source!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _source!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _instrumental
                        ? Center(
                            child: Text(
                              'Instrumental track',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          )
                        : _error != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lyrics_outlined, size: 48, color: scheme.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(_error!, textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    FilledButton.tonal(
                                      onPressed: _loadLyrics,
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                child: Text(
                                  _lyrics ?? '',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        height: 1.6,
                                      ),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showPremiumLyricsSheet(BuildContext context, LocalLibraryItem item) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => PremiumLyricsSheet(item: item),
  );
}
