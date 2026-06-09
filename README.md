# SimplePresent

A **simple** task management system focused on **present** tasks.

## Building

This project includes a `Makefile` with convenience targets to build desktop releases.

Common targets (run from the project root):

- `make pub-get` — run `flutter pub get`
- `make build-linux` — build a Linux release (run on a Linux host with Flutter desktop enabled)
- `make build-windows` — build a Windows release (run on a Windows host; cross-compilation is not provided here)
- `make build-all` — run both builds (Windows build will fail on non-Windows hosts)
- `make package-linux` — copy Linux build output into `dist/`
- `make package-windows` — copy Windows exe into `dist/`
- `make clean` — run `flutter clean`
- `make test` — run Flutter tests

Examples:

```bash
# ensure dependencies
make pub-get

# build Linux release (on Linux)
make build-linux

# build Windows release (on Windows)
make build-windows

# package linux build into dist/
make package-linux
```

Notes
- Building Windows requires a Windows host (or a CI runner capable of Windows builds). The Makefile will still attempt `flutter build windows`, but it will fail on non-Windows systems.
- Adjust the `package-*` copy paths in the `Makefile` if your Flutter build artifacts are placed differently on your machine.
