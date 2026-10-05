# Macdow

**A lightweight macOS utility for a more customizable Windows-like desktop experience.**

Macdow is a small Swift-based macOS utility focused on improving everyday desktop workflow. It combines Dock customization with practical desktop conveniences while keeping the application lightweight.

## Features

- **Custom Dock auto-hide behavior**
  - Provides a more responsive and customizable Dock experience than the default macOS behavior.
- **Desktop information**
  - Displays useful information such as day/night state and temperature.
- **Windows application support**
  - Registers common Windows application/document extensions such as `exe`, `msi`, `bat`, `cmd`, and `lnk`.
  - Designed to work alongside tools such as Wine and Rosetta 2.
- **Native and lightweight**
  - Built with Swift and Swift Package Manager.
  - The project is intentionally kept small and focused.

## Requirements

- macOS 14.0 or later
- Swift 5.10
- Xcode or Command Line Tools

## Build

Clone the repository:

```bash
git clone https://github.com/molru-1/macdows.git
cd macdows
```

Build a release version:

```bash
./build.sh
```

Build a debug version:

```bash
./build.sh debug
```

The application bundle will be created at:

```
build/Macdow.app
```

Launch it with:

```bash
open build/Macdow.app
```

## Project Structure

```
.
├── Sources/
│   └── Macdow/
├── Resources/
│   ├── Info.plist
│   └── WineOverrides/
├── Package.swift
├── build.sh
└── README.md
```

## Version

**0.1.0**

Macdow is currently an early-stage project. APIs, UI, behavior, and internal structure may change as development continues.

## Contributing

Bug reports, suggestions, and pull requests are welcome.

If you find an issue or have an idea for improving the macOS desktop experience, feel free to open an issue or submit a pull request.

## License

No license has been specified yet.

If you plan to redistribute or modify Macdow, check the repository for the latest licensing information before doing so.

---

Built for macOS by [molru-1](https://github.com/molru-1).
