# HIAH Kernel

**House-in-a-House kernel for running iOS applications inside iOS.**

Virtual process management, window server, and filesystem for multi-app execution on iPhone.

---

## 🚀 Quick Start

### 1. Generate Xcode Project
```bash
nix run '.#xcgen'
```

### 2. Open in Xcode
```bash
open HIAHDesktop.xcodeproj
```

### 3. Configure & Run
1. Select **HIAHDesktop** target
2. Go to **Signing & Capabilities** → Select your **Team**
3. Select your iPhone from device list
4. Press **⌘R** to build and run

---

## ✨ Features

- 🖥️ **Window Server** – Multi-app windowing on iOS
- ⚙️ **Process Manager** – Virtual process table (HIAH Top)
- 📦 **App Installer** – Install .ipa files (HIAH Installer)
- 🗂️ **Virtual Filesystem** – Unix-like structure (`/bin`, `/usr`, `/Applications`)
- 🔧 **HIAH Kernel** – Process spawning via NSExtension
- 📱 **Files.app Integration** – Full filesystem visible in iOS Files app

---

## 📂 Structure

```
./src/              ← Source code (edit here)
./project.yml       ← XcodeGen project spec
./docs/             ← Documentation
./flake.nix         ← Nix build system
```

**Single source of truth: Everything builds from `./src/`**

---

## 📖 Documentation

- [BUILD.md](BUILD.md) – Complete build guide
- [docs/](docs/) – Technical documentation

---

## 🛠️ Requirements

- iOS 16.0+
- Xcode 15.0+
- Nix (for project generation)

---

## 📄 License

MIT License – Copyright (c) 2025 Alex Spaulding
