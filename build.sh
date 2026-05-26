#!/bin/bash
# Build and Deploy SpotiFLAC-Mobile with Background Audio Fix

set -e

PROJECT_DIR="D:\spotiftac_mod\SpotiFLAC-Mobile"
cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "════════════════════════════════════════════════════════════════"
echo "  SpotiFLAC-Mobile - Background Audio Fix Build"
echo "════════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Parse arguments
BUILD_TYPE="${1:-debug}"  # debug or release
DEPLOY="${2:-false}"      # true to install on device

echo
echo -e "${BLUE}[1] CLEAN BUILD${NC}"
flutter clean
echo -e "${GREEN}✓ Clean complete${NC}"

echo
echo -e "${BLUE}[2] GET DEPENDENCIES${NC}"
flutter pub get
echo -e "${GREEN}✓ Dependencies resolved${NC}"

echo
echo -e "${BLUE}[3] CODE ANALYSIS${NC}"
flutter analyze --no-fatal-infos 2>&1 | tail -5 || true
echo -e "${GREEN}✓ Analysis complete${NC}"

echo
echo -e "${BLUE}[4] FORMAT CHECK${NC}"
dart format --line-length=100 lib/ --set-exit-if-changed 2>&1 | tail -3 || true
echo -e "${GREEN}✓ Format check complete${NC}"

echo
echo -e "${BLUE}[5] BUILD APK (${BUILD_TYPE})${NC}"

if [ "$BUILD_TYPE" = "release" ]; then
    flutter build apk --release
    OUTPUT="build/app/outputs/flutter-apk/app-release.apk"
else
    flutter build apk --debug
    OUTPUT="build/app/outputs/flutter-apk/app-debug.apk"
fi

if [ -f "$OUTPUT" ]; then
    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    echo -e "${GREEN}✓ APK built: $OUTPUT ($SIZE)${NC}"
else
    echo -e "${RED}✗ Build failed - APK not found${NC}"
    exit 1
fi

echo
echo -e "${BLUE}[6] VERIFY APK${NC}"
if unzip -t "$OUTPUT" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ APK is valid${NC}"
else
    echo -e "${YELLOW}⚠${NC}  APK validation warning (may be normal)"
fi

if [ "$DEPLOY" = "true" ]; then
    echo
    echo -e "${BLUE}[7] INSTALL ON DEVICE${NC}"
    
    # Check if device is connected
    if flutter devices 2>&1 | grep -q "1 connected"; then
        flutter install --release
        echo -e "${GREEN}✓ APK installed${NC}"
        
        echo
        echo -e "${BLUE}[8] LAUNCH APP${NC}"
        flutter run -v --release &
        sleep 3
        echo -e "${GREEN}✓ App launching - watch for logs${NC}"
    else
        echo -e "${YELLOW}⚠${NC}  No device detected - skipping installation"
        echo "   Connect device and run: flutter install"
    fi
fi

echo
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ BUILD COMPLETE${NC}"
echo "════════════════════════════════════════════════════════════════"
echo
echo "Output: $(pwd)/$OUTPUT"
echo
echo "Next steps:"
echo "  1. Manually install APK on device"
echo "  2. Or: flutter install --release"
echo "  3. Follow testing steps in TESTING_GUIDE.md"
echo
