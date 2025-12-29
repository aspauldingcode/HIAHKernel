# HIAH Kernel – Build Guide

## 🚀 Quick Build (Recommended)

### Step 1: Generate Xcode Project

```bash
nix run '.#xcgen'
```

This generates `HIAHDesktop.xcodeproj` from `project.yml`.

### Step 2: Open in Xcode

```bash
open HIAHDesktop.xcodeproj
```

### Step 3: Configure Signing

1. Select **HIAHDesktop** target in Xcode
2. Go to **Signing & Capabilities** tab
3. Select your **Team** from the dropdown
4. Xcode will automatically manage provisioning

### Step 4: Build & Run

- Select your iPhone from the device dropdown
- Press **⌘R** (Run)

---

## 📁 Project Structure

```
HIAHKernel/
├── src/                    ← Source code (edit here)
│   ├── HIAHKernel.h/m      ← Virtual kernel core
│   ├── HIAHProcess.h/m     ← Process model
│   ├── HIAHDesktop/        ← Desktop environment
│   ├── HIAHWindowServer/   ← Window management
│   ├── HIAHTop/            ← Process monitor
│   ├── HIAHInstaller/      ← App installer
│   ├── HIAHTerminal/       ← Terminal emulator
│   ├── SampleApps/         ← Built-in apps
│   ├── hooks/              ← HIAH Hook system
│   └── extension/          ← HIAHProcessRunner.appex
│
├── project.yml             ← XcodeGen specification
├── HIAHDesktop.xcodeproj/  ← Generated (git ignored)
├── docs/                   ← Documentation
└── flake.nix               ← Nix build system
```

---

## 🔧 Development Workflow

### Edit → Generate → Build

1. **Edit** files in `./src/`
2. **Regenerate** (if you added new files):
   ```bash
   nix run '.#xcgen'
   ```
3. **Build** in Xcode (⌘R)

### XcodeGen Benefits

- ✅ `project.yml` is human-readable and version controlled
- ✅ No `.pbxproj` merge conflicts
- ✅ Regenerate anytime with one command
- ✅ Source files reference `./src/` directly

---

## 📱 Running on iPhone

### Requirements

- iPhone running iOS 16.0+
- Apple Developer account (free or paid)
- Xcode 15.0+

### Steps

1. Connect iPhone via USB
2. Trust the computer on your iPhone
3. In Xcode: Select your iPhone from device list
4. Set your signing team
5. Press **⌘R** to build and run

### First Run

On first install, you may need to:
1. Go to **Settings → General → VPN & Device Management**
2. Trust your developer certificate

---

## 🖥️ Running on Simulator

```bash
nix run '.#hiah-desktop'
```

Or in Xcode:
1. Select a Simulator from device list
2. Press **⌘R**

---

## 🔄 Regenerating the Project

If the Xcode project gets out of sync or you add new source files:

```bash
nix run '.#xcgen'
```

This reads `project.yml` and generates a fresh `HIAHDesktop.xcodeproj`.

---

## 🛠️ Build Targets

| Target | Type | Description |
|--------|------|-------------|
| `HIAHDesktop` | Application | Main desktop environment |
| `HIAHProcessRunner` | App Extension | Runs guest .ipa apps |

---

## 📝 Adding New Source Files

1. Add your `.m`, `.h`, or `.swift` file to `./src/`
2. Regenerate the project:
   ```bash
   nix run '.#xcgen'
   ```
3. The file will appear in Xcode automatically

---

## ⚠️ Troubleshooting

### "Signing certificate not found"
→ Select your Team in Signing & Capabilities

### "Could not find HIAHProcessRunner.appex"
→ Make sure HIAHProcessRunner target is built (it's a dependency)

### "App Group not configured"
→ The App Group `group.com.aspauldingcode.HIAHDesktop` is set in `project.yml`

### Xcode project out of date
→ Run `nix run '.#xcgen'` to regenerate

---

## 📖 More Documentation

- [Virtual Filesystem](docs/VirtualFilesystem.md) – Files.app integration
- [HIAH Desktop](docs/HIAHDesktop.md) – Desktop environment
- [HIAH Kernel](docs/HIAHKernel.md) – Core library
- [HIAHProcessRunner](docs/HIAHProcessRunner.md) – Guest app extension

---

## 📄 License

MIT License – Copyright (c) 2025 Alex Spaulding
