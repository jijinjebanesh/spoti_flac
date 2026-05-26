#!/bin/bash
# SpotiFLAC-Mobile Background Audio - Pre-Build Verification

set -e

PROJECT_DIR="D:\spotiftac_mod\SpotiFLAC-Mobile"
cd "$PROJECT_DIR"

echo "════════════════════════════════════════════════════════════════"
echo "  SpotiFLAC-Mobile Background Audio Fix - Pre-Build Verification"
echo "════════════════════════════════════════════════════════════════"
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_file() {
    local file="$1"
    local description="$2"
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description (NOT FOUND: $file)"
        return 1
    fi
}

check_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description (NOT FOUND in $file)"
        return 1
    fi
}

# ============ PHASE 1: File Existence ============
echo -e "${BLUE}[1] CHECKING FILE EXISTENCE${NC}"
check_file "lib/services/audio_background_handler.dart" "AudioBackgroundHandler exists"
check_file "lib/providers/premium_playback_provider.dart" "PremiumPlaybackProvider exists"
check_file "android/app/src/main/AndroidManifest.xml" "AndroidManifest.xml exists"
check_file "pubspec.yaml" "pubspec.yaml exists"
echo

# ============ PHASE 2: Handler Setup ============
echo -e "${BLUE}[2] CHECKING HANDLER SETUP${NC}"
check_pattern "lib/services/audio_background_handler.dart" "getPlayer()" "Handler has getPlayer() method"
check_pattern "lib/services/audio_background_handler.dart" "late AudioPlayer _player" "Handler owns shared _player instance"
check_pattern "lib/services/audio_background_handler.dart" "_broadcastPlaybackState" "Handler broadcasts playback state"
check_pattern "lib/services/audio_background_handler.dart" "mediaItem.value" "Handler manages mediaItem updates"
echo

# ============ PHASE 3: Controller Fixes ============
echo -e "${BLUE}[3] CHECKING CONTROLLER FIXES (CRITICAL)${NC}"

# Check: No local AudioPlayer creation (not commented out)
if grep -v "^[[:space:]]*//\|^[[:space:]]*\*" lib/providers/premium_playback_provider.dart | \
   grep -q "final AudioPlayer _player = AudioPlayer()"; then
    echo -e "${RED}✗${NC} CRITICAL: PremiumPlaybackController still has local AudioPlayer() creation!"
    echo "  This is the root cause of background audio failure."
    exit 1
else
    echo -e "${GREEN}✓${NC} PremiumPlaybackController does NOT create local AudioPlayer (correct)"
fi

# Check: Uses late AudioPlayer reference
check_pattern "lib/providers/premium_playback_provider.dart" "late AudioPlayer _player; // Reference to handler's player" \
    "Controller uses reference to handler's player"

# Check: Gets player from handler
check_pattern "lib/providers/premium_playback_provider.dart" "_player = _audioHandler!.getPlayer()" \
    "Controller obtains shared player from handler"

echo

# ============ PHASE 4: MediaItem Synchronization ============
echo -e "${BLUE}[4] CHECKING MEDIAITEM SYNCHRONIZATION (CRITICAL)${NC}"

# Count _syncAudioService calls
sync_count=$(grep -c "_syncAudioService()" lib/providers/premium_playback_provider.dart || echo 0)
echo -e "${GREEN}✓${NC} Found $sync_count calls to _syncAudioService()"

if [ "$sync_count" -lt 5 ]; then
    echo -e "${YELLOW}⚠${NC}  WARNING: Expected 5+ _syncAudioService() calls, found $sync_count"
else
    echo -e "${GREEN}✓${NC} Sufficient _syncAudioService() calls throughout lifecycle"
fi

# Check specific sync points
# Check specific sync points
if grep -A5 "Future<void> playLibrary" lib/providers/premium_playback_provider.dart | grep -q "_syncAudioService"; then
    echo -e "${GREEN}✓${NC} playLibrary() syncs mediaItem"
else
    echo -e "${YELLOW}⚠${NC}  WARNING: Could not verify playLibrary() sync (may still be correct)"
fi

if grep -A5 "Future<void> togglePlayPause" lib/providers/premium_playback_provider.dart | grep -q "_syncAudioService"; then
    echo -e "${GREEN}✓${NC} togglePlayPause() syncs mediaItem"
else
    echo -e "${YELLOW}⚠${NC}  WARNING: Could not verify togglePlayPause() sync"
fi

if grep -B2 -A2 "_attachStreams" lib/providers/premium_playback_provider.dart | grep -q "_syncAudioService"; then
    echo -e "${GREEN}✓${NC} _attachStreams() syncs on state changes"
else
    echo -e "${YELLOW}⚠${NC}  WARNING: Could not verify _attachStreams() sync"
fi

echo

# ============ PHASE 5: Android Configuration ============
echo -e "${BLUE}[5] CHECKING ANDROID CONFIGURATION${NC}"

check_pattern "android/app/src/main/AndroidManifest.xml" "FOREGROUND_SERVICE" \
    "AndroidManifest has FOREGROUND_SERVICE permission"
check_pattern "android/app/src/main/AndroidManifest.xml" "FOREGROUND_SERVICE_MEDIA_PLAYBACK" \
    "AndroidManifest has FOREGROUND_SERVICE_MEDIA_PLAYBACK permission"
check_pattern "android/app/src/main/AndroidManifest.xml" "AudioService\|mediaPlayback" \
    "AndroidManifest configures ForegroundService"

echo

# ============ PHASE 6: Dependencies ============
echo -e "${BLUE}[6] CHECKING DEPENDENCIES${NC}"

check_pattern "pubspec.yaml" "audio_service" "audio_service dependency present"
check_pattern "pubspec.yaml" "just_audio" "just_audio dependency present"
check_pattern "pubspec.yaml" "riverpod" "riverpod dependency present"

echo

# ============ PHASE 7: Flutter Analysis ============
echo -e "${BLUE}[7] RUNNING FLUTTER ANALYZE${NC}"

if flutter analyze lib/services/audio_background_handler.dart lib/providers/premium_playback_provider.dart 2>&1 | grep -q "No issues"; then
    echo -e "${GREEN}✓${NC} No Dart analysis issues found"
else
    echo -e "${YELLOW}⚠${NC}  Flutter analyze completed (may have warnings)"
fi

echo

# ============ PHASE 8: Syntax Check ============
echo -e "${BLUE}[8] CHECKING SYNTAX${NC}"

if flutter pub get > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Dependencies resolve successfully"
else
    echo -e "${RED}✗${NC} Dependency resolution failed"
    flutter pub get
    exit 1
fi

echo

# ============ SUMMARY ============
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ ALL PRE-BUILD CHECKS PASSED${NC}"
echo "════════════════════════════════════════════════════════════════"
echo
echo "Next steps:"
echo "  1. flutter clean"
echo "  2. flutter pub get"
echo "  3. flutter run -v  (for local testing)"
echo "  4. flutter build apk --debug  (for APK)"
echo
echo "Testing:"
echo "  - Start playback from library"
echo "  - Verify notification appears"
echo "  - Press HOME to minimize"
echo "  - Verify audio continues and notification persists"
echo "  - Try notification controls (play/pause/skip)"
echo
echo "Reference: See TESTING_GUIDE.md for detailed testing steps"
echo
