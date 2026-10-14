#!/bin/zsh
# 使い方:
#   ./build.sh         build/Headroom.app を作る（Apple シリコン + Intel 両対応）
#   ./build.sh dist    さらに配布用の dmg と zip を dist/ に作る
#
# Developer ID で署名・公証する場合（Apple Developer Program への登録が必要）:
#   xcrun notarytool store-credentials <プロファイル名>   # 最初に1回だけ
#   DEVELOPER_ID="Developer ID Application: 名前 (TEAMID)" NOTARY_PROFILE=<プロファイル名> ./build.sh dist
# 指定しなければ簡易署名（ad-hoc）になり、配布先では初回起動時に許可の操作が必要。
set -euo pipefail
cd "$(dirname "$0")"

DISPLAY_NAME=Headroom      # Finder・通知・dmg に出る名前
SHORT_NAME=Headroom        # CFBundleName（15文字以内が推奨）
FILE_NAME=Headroom         # dmg / zip のファイル名
EXECUTABLE=Headroom        # Swift のターゲット名
BUNDLE_ID=local.headroom
VERSION=0.2.0
BUILD_NUMBER=$(date +%Y%m%d%H%M)

DEVELOPER_ID=${DEVELOPER_ID:-}
NOTARY_PROFILE=${NOTARY_PROFILE:-}

APP="build/$DISPLAY_NAME.app"

# --- ビルド（両対応のバイナリ） ---
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN_DIR=$(swift build -c release $ARCHS --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"

# --- アイコン（Icon Composer 形式を Assets.car と旧OS用の .icns に変換） ---
xcrun actool Icon/AppIcon.icon \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist build/icon-partial.plist \
    --output-format human-readable-text > /dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$SHORT_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <!-- Dock に出さずメニューバーだけに常駐させる -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# --- 署名 ---
sign() {
    if [[ -n $DEVELOPER_ID ]]; then
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$1"
    else
        codesign --force --sign - "$1"
    fi
}
sign "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE"))"

[[ ${1:-} == dist ]] || exit 0

# --- 配布用ファイル ---
notarize() {
    [[ -n $NOTARY_PROFILE ]] || return 0
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

DIST=dist
rm -rf "$DIST" && mkdir -p "$DIST"
ZIP="$DIST/$FILE_NAME-$VERSION.zip"
DMG="$DIST/$FILE_NAME-$VERSION.dmg"

# 公証する場合は、先にアプリ本体を公証して「公証済み」の印（チケット）を付ける
if [[ -n $NOTARY_PROFILE ]]; then
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    notarize "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
    rm "$DIST/notarize.zip"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

# dmg：アプリと「アプリケーション」フォルダへのリンク、説明書を入れる
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/アプリケーション"
cp "dist-assets/はじめにお読みください.txt" "$STAGE/"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
sign "$DMG"
if [[ -n $NOTARY_PROFILE ]]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi

echo "Distribution files:"
ls -lh "$DIST"
[[ -n $NOTARY_PROFILE ]] || echo "※ 公証していないため、配布先では初回起動時に許可の操作が必要です（はじめにお読みください.txt 参照）"
