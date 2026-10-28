#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version=$(/usr/bin/sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/MountCore/DiskAccess.swift)
test -n "$version"
runtime_dir=""
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != "--backend-dir" ]; then
        echo 'Usage: ./build.sh [--backend-dir /path/to/separately-supplied-backend]' >&2
        exit 1
    fi
    runtime_dir=$(cd "$2" && pwd)
    for item in ntfs-3g libfuse-t.dylib go-nfsv4; do
        test -f "$runtime_dir/$item" || { echo "Missing backend component: $item" >&2; exit 1; }
    done
    test -d "$runtime_dir/licenses" || { echo 'The supplied backend must include its license notices.' >&2; exit 1; }
fi
/usr/bin/swift build -c release -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/src/PlainMount" -Xswiftc -file-prefix-map -Xswiftc "$PWD=/src/PlainMount"
binary_dir=$(/usr/bin/swift build -c release --show-bin-path)
staging=$(/usr/bin/mktemp -d /private/tmp/plainmount-build.XXXXXX)
trap '/bin/rm -rf "$staging"' EXIT
app="$staging/PlainMount.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/AppIcon.iconset
cp "$binary_dir/PlainMount" "$app/Contents/MacOS/PlainMount"
/usr/bin/strip -S -x "$app/Contents/MacOS/PlainMount"
python3 scripts/check_binary_privacy.py "$app/Contents/MacOS/PlainMount"
mkdir -p "$app/Contents/Resources/Licenses"
if [ -n "$runtime_dir" ]; then
    mkdir -p "$app/Contents/Resources/Backend"
    cp "$runtime_dir/ntfs-3g" "$runtime_dir/libfuse-t.dylib" "$runtime_dir/go-nfsv4" "$app/Contents/Resources/Backend/"
    cp -R "$runtime_dir/licenses/." "$app/Contents/Resources/Licenses/"
    if [ -d "$runtime_dir/source" ]; then
        mkdir -p "$app/Contents/Resources/Source"
        cp -R "$runtime_dir/source/." "$app/Contents/Resources/Source/"
    fi
    python3 scripts/check_binary_privacy.py "$app/Contents/Resources/Backend/ntfs-3g"
    python3 scripts/check_binary_privacy.py "$app/Contents/Resources/Backend/libfuse-t.dylib"
    /usr/bin/codesign --verify --strict "$app/Contents/Resources/Backend/go-nfsv4"
    /usr/bin/codesign --force --sign - "$app/Contents/Resources/Backend/ntfs-3g"
fi
cp LICENSE "$app/Contents/Resources/Licenses/PlainMount-MIT.txt"
/usr/bin/swift scripts/icon.swift .build/AppIcon-1024.png
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.plainmount.app</string>
<key>CFBundleName</key><string>PlainMount</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
<key>CFBundleDisplayName</key><string>PlainMount</string>
<key>CFBundleExecutable</key><string>PlainMount</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSRemovableVolumesUsageDescription</key><string>Access is needed to manage files and the connection of your selected external drive.</string>
<key>NSNetworkVolumesUsageDescription</key><string>Access is needed to open files through the local NTFS writing connection in Finder.</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key><string>Copyright 2026 PlainMount contributors. MIT License.</string>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/tr.lproj"
cat > "$app/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"NSRemovableVolumesUsageDescription" = "Access is needed to manage files and the connection of your selected external drive.";
"NSNetworkVolumesUsageDescription" = "Access is needed to open files through the local NTFS writing connection in Finder.";
STRINGS
cat > "$app/Contents/Resources/tr.lproj/InfoPlist.strings" <<'STRINGS'
"NSRemovableVolumesUsageDescription" = "Seçtiğiniz harici diskin dosyalarını ve bağlantısını yönetmek için erişim gerekir.";
"NSNetworkVolumesUsageDescription" = "Yerel NTFS yazma bağlantısındaki dosyalara Finder ile erişmek için izin gerekir.";
STRINGS
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p dist
if [ -d "dist/PlainMount.app" ]; then /bin/rm -rf "dist/PlainMount.app"; fi
/usr/bin/ditto --norsrc --noextattr "$app" "dist/PlainMount.app"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "dist/PlainMount-$version-arm64.zip"
python3 - "dist/PlainMount-$version-arm64.zip" <<'PY'
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
clean = archive.with_suffix('.clean.zip')
with zipfile.ZipFile(archive) as source, zipfile.ZipFile(clean, 'w') as output:
    for entry in source.infolist():
        # Keep executable permissions, discard Unix owner IDs and extra metadata.
        entry.extra = b''
        entry.comment = b''
        output.writestr(entry, source.read(entry))
clean.replace(archive)
PY
echo "Ready: $PWD/dist/PlainMount-$version-arm64.zip"
