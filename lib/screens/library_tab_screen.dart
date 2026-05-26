import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/premium_playback_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/queue_tab.dart';
import 'package:spotiflac_android/widgets/library_mini_player.dart';

/// Library tab: original [QueueTab] UI with active downloads on top, plus in-app player.
class LibraryTabScreen extends ConsumerStatefulWidget {
  final PageController? parentPageController;
  final int parentPageIndex;
  final int? nextPageIndex;

  const LibraryTabScreen({
    super.key,
    this.parentPageController,
    this.parentPageIndex = 1,
    this.nextPageIndex,
  });

  @override
  ConsumerState<LibraryTabScreen> createState() => _LibraryTabScreenState();
}

class _LibraryTabScreenState extends ConsumerState<LibraryTabScreen> {
  bool _didRequestFolderScan = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDownloadFolderLinked());
  }

  Future<void> _ensureDownloadFolderLinked() async {
    if (_didRequestFolderScan || !mounted) return;
    _didRequestFolderScan = true;

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final isSaf = settings.storageMode == 'saf' && settings.downloadTreeUri.isNotEmpty;

    if (!settings.localLibraryEnabled) {
      settingsNotifier.setLocalLibraryEnabled(true);
    }

    if (settings.localLibraryPath.isEmpty) {
      if (isSaf) {
        settingsNotifier.setLocalLibraryPath(settings.downloadTreeUri);
      } else if (settings.downloadDirectory.isNotEmpty) {
        settingsNotifier.setLocalLibraryPath(settings.downloadDirectory);
      }
    }

    final updated = ref.read(settingsProvider);
    final scanPath = updated.localLibraryPath;
    if (scanPath.isEmpty) return;

    final libraryState = ref.read(localLibraryProvider);
    if (libraryState.isScanning) return;

    final bookmark = updated.localLibraryBookmark.isNotEmpty
        ? updated.localLibraryBookmark
        : updated.downloadDirectoryBookmark;
    await ref.read(localLibraryProvider.notifier).startScan(
          scanPath,
          iosBookmark: bookmark.isNotEmpty ? bookmark : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final hasMiniPlayer = ref.watch(
      premiumPlaybackProvider.select((s) => s.current != null),
    );
    final bottomInset = (hasMiniPlayer ? 88.0 : 0.0) +
        MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        QueueTab(
          parentPageController: widget.parentPageController,
          parentPageIndex: widget.parentPageIndex,
          nextPageIndex: widget.nextPageIndex,
          miniPlayerBottomInset: bottomInset,
        ),
        if (hasMiniPlayer)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: const LibraryMiniPlayer(),
          ),
      ],
    );
  }
}
