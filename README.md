# HIAH Kernel

**iOS Virtual Kernel Library for running dynamic binaries inside standard iOS apps.**

HIAHKernel is a reusable **library dependency** that enables applications (like Wawona) to spawn and manage multiple processes within their own sandbox, bypassing single-executable restrictions via `.dylib` loading.

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

- 🧱 **Reusable Library** – Clean API for embedding dynamic execution logic
- ⚙️ **Virtual Kernel** – Process table, memory management, and signal handling
- 🚀 **Binary Loading** – Execute arbitrary code via `.dylib` dynamic loading
- 🔌 **NSExtension Support** – Isolated process spawning using App Extensions
- 📡 **IPC Layer** – Unix sockets for standard Input/Output redirection

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

- [HIAH Kernel Library](docs/HIAHKernel.md) – **Main Library Documentation**
- [BUILD.md](BUILD.md) – Build instructions
- [Architecture](docs/Architecture-and-Roadmap.md) – Internal design


---

## 🛠️ Requirements

- iOS 16.0+
- Xcode 15.0+
- Nix (for project generation)

---

## 📄 License

MIT License – Copyright (c) 2025 Alex Spaulding
