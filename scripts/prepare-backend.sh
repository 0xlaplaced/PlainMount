#!/bin/bash
# Build the open-source libraries and extract the non-commercial FUSE-T server.
# Nothing is installed globally and no disk is mounted or modified.
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:-$PWD/.local-backend}"
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
test "$(uname -m)" = arm64 || { echo 'Apple Silicon is required.' >&2; exit 1; }
root=$(mktemp -d /private/tmp/plainmount-backend.XXXXXX)
trap 'rm -rf "$root"' EXIT
verify() {
    actual=$(shasum -a 256 "$1" | awk '{print $1}')
    test "$actual" = "$2" || { echo 'Download checksum mismatch.' >&2; exit 1; }
}
fetch() { curl -fL --retry 2 "$1" -o "$2"; }
ntfs_version=2022.10.3
fuse_version=1.2.6
libfuse_commit=09c8864314d1ab16e93e9f9f7c637cc026fec65f
fetch "https://tuxera.com/opensource/ntfs-3g_ntfsprogs-$ntfs_version.tgz" "$root/ntfs-source.tgz"
verify "$root/ntfs-source.tgz" f20e36ee68074b845e3629e6bced4706ad053804cbaf062fbae60738f854170c
fetch "https://codeload.github.com/macos-fuse-t/libfuse/tar.gz/$libfuse_commit" "$root/libfuse-source.tgz"
verify "$root/libfuse-source.tgz" 13e9b5b3ca03cb7a71715450a59bfd6c9808b15cf92d49d5dcf37bd01e1f5125
fetch "https://github.com/macos-fuse-t/fuse-t/releases/download/$fuse_version/fuse-t-macos-installer-$fuse_version.pkg" "$root/fuse-t.pkg"
verify "$root/fuse-t.pkg" fcfd95e4c09fb1f90efa134ef9b328b5757c59b43d6c7c23384a6a7001db4eb3
# Expand package bytes only; never execute its installer or package scripts.
pkgutil --expand-full "$root/fuse-t.pkg" "$root/package"
payload="$root/package/fuse-t-core.pkg/Payload/Library/Application Support/fuse-t"
mkdir -p "$destination/licenses" "$destination/source" "$root/stage"
cp "$payload/bin/go-nfsv4-$fuse_version" "$destination/go-nfsv4"
for notice in License Attributions; do
    fetch "https://raw.githubusercontent.com/macos-fuse-t/fuse-t/1.2.6/$notice.txt" "$destination/licenses/FUSE-T-$notice.txt"
done
tar -xzf "$root/libfuse-source.tgz" -C "$root"
library="$root/libfuse-$libfuse_commit"
(
    cd "$library/lib"
    xcrun clang -dynamiclib -O2 -arch arm64 -mmacosx-version-min=13.0 \
        -ffile-prefix-map="$root=/usr/src/plainmount-backend" \
        -fdebug-prefix-map="$root=/usr/src/plainmount-backend" \
        -fmodules -DFUSERMOUNT_DIR='"/usr/local/bin"' \
        -D_FILE_OFFSET_BITS=64 -D_REENTRANT -DFUSE_USE_VERSION=26 -I../include \
        buffer.c fuse_darwin.c fuse_loop_mt.c fuse_opt.c helper.c mount_darwin.c \
        cuse_lowlevel.c fuse_kern_chan.c fuse_lowlevel.c fuse_session.c fuse.c \
        fuse_loop.c fuse_mt.c fuse_signals.c modules/iconv.c modules/subdir.c \
        modules/threadid.c modules/volicon.c \
        -liconv -framework CoreFoundation -framework DiskArbitration \
        -Wl,-install_name,@rpath/libfuse-t.dylib -o "$root/stage/libfuse-t.dylib"
)
tar -xzf "$root/ntfs-source.tgz" -C "$root"
(
    cd "$root/ntfs-3g_ntfsprogs-$ntfs_version"
    PKG_CONFIG=/usr/bin/true \
    FUSE_MODULE_CFLAGS="-I$library/include" \
    FUSE_MODULE_LIBS="-L$root/stage -lfuse-t" \
    CFLAGS="-O2 -D_FILE_OFFSET_BITS=64 -mmacosx-version-min=13.0 -ffile-prefix-map=$root=/usr/src/plainmount-backend -fdebug-prefix-map=$root=/usr/src/plainmount-backend" \
    LDFLAGS='-Wl,-rpath,@executable_path -mmacosx-version-min=13.0' \
    ./configure --disable-ntfsprogs --disable-crypto --disable-shared --enable-static \
        --with-fuse=external --disable-ldconfig --disable-mtab --disable-mount-helper \
        --disable-plugins --prefix=/usr/local
    make -j4
    cp src/ntfs-3g "$destination/ntfs-3g"
    cp COPYING "$destination/licenses/NTFS-3G-GPL-2.txt"
    cp COPYING.LIB "$destination/licenses/NTFS-3G-LGPL-2.txt"
)
cp "$root/stage/libfuse-t.dylib" "$destination/libfuse-t.dylib"
cp "$library/COPYING.LIB" "$destination/licenses/LIBFUSE-LGPL-2.1.txt"
cp "$library/COPYING" "$destination/licenses/LIBFUSE-GPL-2.txt"
cp "$root/ntfs-source.tgz" "$destination/source/ntfs-3g-$ntfs_version.tgz"
cp "$root/libfuse-source.tgz" "$destination/source/libfuse-$libfuse_commit.tgz"
cp scripts/prepare-backend.sh "$destination/source/prepare-backend.sh"
cat > "$destination/licenses/COMPONENTS.txt" <<'NOTICE'
PlainMount application code: MIT, see PlainMount-MIT.txt.
NTFS-3G 2022.10.3: GPL version 2 or later, separate executable.
libfuse (macos-fuse-t fork) commit 09c8864314d1ab16e93e9f9f7c637cc026fec65f:
  built from source; library under LGPL 2.1 or later. Original notices retained.
go-nfsv4 from FUSE-T 1.2.6: FUSE-T non-commercial binary license.
  Free for non-commercial use; commercial use or bundling with commercial
  software requires a license from its authors. See FUSE-T-License.txt.
  https://github.com/macos-fuse-t/fuse-t/blob/1.2.6/License.txt

Corresponding NTFS-3G and libfuse source archives and the build recipe are
included in Contents/Resources/Source. No source changes were made.
NTFS-3G dynamically loads libfuse-t.dylib. Modified compatible versions can
be substituted in Contents/Resources/Backend; macOS may require the modified
bundle to be signed again. PlainMount does not verify a vendor signature or
forbid reverse engineering for debugging modifications to the LGPL library.
The MIT grant applies to PlainMount's own code, not the entire binary bundle.
NOTICE
chmod 755 "$destination/ntfs-3g" "$destination/go-nfsv4"
strip -S -x "$destination/ntfs-3g" "$destination/libfuse-t.dylib"
codesign --force --sign - "$destination/libfuse-t.dylib"
codesign --force --sign - "$destination/ntfs-3g"
python3 scripts/check_binary_privacy.py "$destination/ntfs-3g"
python3 scripts/check_binary_privacy.py "$destination/libfuse-t.dylib"
echo 'Backend ready. FUSE-T non-commercial terms apply to the included server.'
