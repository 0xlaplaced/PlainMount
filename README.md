# PlainMount

A free, MIT-licensed native macOS app for managing NTFS drives.

## Features

- List external volumes, capacity and access status.
- Open a selected volume in Finder.
- Mount read-only, disconnect and eject an external drive.
- Support a separately supplied compatible NTFS writing backend.
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

**Writing backend:** this repository publishes only the MIT application source. It does not include or relicense NTFS-3G, FUSE-T or any other third-party writing runtime. Without such a backend the app supports drive inspection, Finder access and standard read-only disk operations. A compatible backend can be supplied locally with `./build.sh --backend-dir <directory>`; that backend retains its own license terms.

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
