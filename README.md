# PlainMount

A free native macOS app for managing NTFS drives. PlainMount's own application code is MIT-licensed.

## Download and install

Download **PlainMount-1.0.4-arm64.zip** from [Releases](https://github.com/0xlaplaced/PlainMount/releases/latest), extract it, and move **PlainMount.app** to **Applications** before opening it. Requires Apple Silicon (M1 or later) and macOS 14 or later; the interface is Turkish.

The ready-to-run ZIP includes the NTFS writing components. No Homebrew, Terminal commands, account, subscription or separate driver installer is needed.

1. Open PlainMount from Applications. This build is ad-hoc signed, without Apple notarization. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. See [Apple's instructions](https://support.apple.com/en-gb/102445).
2. For NTFS writing, enable PlainMount in **System Settings → Privacy & Security → Full Disk Access**, then quit and reopen the app.
3. Select your NTFS drive and choose **Yazmayı etkinleştir**. macOS asks for administrator approval; the app does not store your password. Use the app to disconnect the drive when finished.

**Component licenses:** PlainMount code is MIT; NTFS-3G is GPL; libfuse is LGPL. The bundled FUSE-T server is **free for non-commercial use**, with a separate license required for commercial use or bundling with commercial software. Its [upstream terms](https://github.com/macos-fuse-t/fuse-t/blob/1.2.6/License.txt) are retained in the app. The complete ZIP is not covered solely by MIT. Corresponding NTFS-3G/libfuse source archives and their build recipe are included inside the app, alongside the license notices.

## Features

- List external volumes, capacity and access status.
- Open a selected volume in Finder.
- Mount read-only, disconnect and eject an external drive.
- NTFS writing through a bundled backend in the downloadable ZIP.
- Explain macOS Full Disk Access requirements before changing a connection.
- Light, dark and system appearance; menu bar access and session-only activity history.

The current interface is in Turkish. Apple Silicon and macOS 14 or later are required.

## Build

Install Xcode Command Line Tools, then run:

```sh
./scripts/test.sh
./build.sh
```

The app is created in `dist/PlainMount.app`. Install it in `/Applications` before using privileged disk operations. This local build is ad-hoc signed and is not Apple-notarized.

The default build contains only the MIT application and supports inspection, Finder access and standard read-only disk operations. To reproduce the downloadable package with writing support:

```sh
./scripts/prepare-backend.sh
./build.sh --backend-dir .local-backend
```

The preparation script downloads checksum-pinned upstream archives, builds NTFS-3G and libfuse, and extracts the FUSE-T server without running an installer. Running or redistributing that server is subject to its non-commercial license. Third-party binaries and sources remain outside Git; the app bundle includes their notices and corresponding open-source archives. A compatible independently supplied backend can also be passed with `--backend-dir <directory>`.

## Privacy and safeguards

No account, subscription or API key is required. The app has no telemetry service. Personal disk reports, screenshots, diagnostics, credentials, signing material and build artifacts are excluded from the repository.

Disk identity is revalidated before operations. Administrator passwords are never stored. No permanent privileged service or sudoers rule is installed. The app does not format, force-unmount, automatically repair or remove hibernation data from a volume.

Diagnostics are saved locally only when the user chooses a destination. Such files may contain drive labels and local paths; review them before sharing.

## Source checks

```sh
git config core.hooksPath .githooks
python3 scripts/check_publish_tree.py --self-test
python3 scripts/check_publish_tree.py --staged
```

Core tests use synthetic data and do not change an attached disk. Packaging removes debug/local symbols and checks the app executable for embedded builder paths. GitHub checks are manually triggered and do not publish artifacts or perform live disk operations.

## License

[MIT](LICENSE). The application source may be used, modified and redistributed, including commercially, under the MIT license. External components are outside this license grant.
