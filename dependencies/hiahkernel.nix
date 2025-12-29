{
  lib,
  pkgs,
  buildModule,
  hiahkernelSrc,
  xcode ? null,
  pkgsCross ? null,
  sidestore ? null,
}:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  projectVersion = "1.0.0";
  
  # GNU tools for iOS (bash, coreutils, unzip)
  gnuTools = import ./gnu-tools.nix {
    inherit lib pkgs;
    buildPackages = pkgs;
  };
  
  # iOS Simulator build
  iosSimulator = pkgs.stdenv.mkDerivation rec {
    name = "hiah-kernel";
    version = projectVersion;
    src = hiahkernelSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      xcodeUtils.findXcodeScript
    ];
    
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      fi
      
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      
      export ARCH="$SIMULATOR_ARCH"
      export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC -fobjc-arc -I$PWD/src"
      export OBJCFLAGS="$CFLAGS"
      export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -framework Foundation -framework UIKit"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building HIAHKernel for iOS Simulator ($ARCH)..."
      
      # Build HIAHHook
      echo "Compiling HIAHHook.c..."
      $CC -c src/hooks/HIAHHook.c -o HIAHHook.o $CFLAGS -O2
      
      # Build HIAHGuestHooks
      echo "Compiling HIAHGuestHooks.m..."
      $CC -c src/hooks/HIAHGuestHooks.m -o HIAHGuestHooks.o $OBJCFLAGS -O2
      
      # Build HIAHProcess
      echo "Compiling HIAHProcess.m..."
      $CC -c src/HIAHProcess.m -o HIAHProcess.o $OBJCFLAGS -O2
      
      # Build HIAHLogging (Kernel logger)
      echo "Compiling HIAHLogging.m..."
      $CC -c src/HIAHDesktop/HIAHLogging.m -o HIAHLogging.o $OBJCFLAGS -O2
      
      # Build HIAHKernel
      echo "Compiling HIAHKernel.m..."
      $CC -c src/HIAHKernel.m -o HIAHKernel.o $OBJCFLAGS -O2
      
      # Create static library
      echo "Creating static library libHIAHKernel.a..."
      ar rcs libHIAHKernel.a HIAHLogging.o HIAHHook.o HIAHGuestHooks.o HIAHProcess.o HIAHKernel.o
      
      # Create dynamic library
      echo "Creating dynamic library libHIAHKernel.dylib..."
      $CC -dynamiclib -o libHIAHKernel.dylib \
        HIAHLogging.o HIAHHook.o HIAHGuestHooks.o HIAHProcess.o HIAHKernel.o \
        $LDFLAGS \
        -install_name @rpath/libHIAHKernel.dylib
      
      echo "Build complete!"
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/{lib,include/HIAHKernel,share/HIAHKernel/extension}
      
      # Install libraries
      cp libHIAHKernel.a $out/lib/
      cp libHIAHKernel.dylib $out/lib/
      
      # Install headers
      cp src/HIAHKernel.h $out/include/HIAHKernel/
      cp src/HIAHProcess.h $out/include/HIAHKernel/
      cp src/hooks/HIAHHook.h $out/include/HIAHKernel/
      cp src/hooks/HIAHGuestHooks.h $out/include/HIAHKernel/
      
      # Install extension source (for bundling)
      cp -r src/extension/* $out/share/HIAHKernel/extension/
      
      runHook postInstall
    '';
    
    __noChroot = true;
    
    meta = with lib; {
      description = "Virtual kernel for iOS multi-process execution";
      homepage = "https://github.com/aspauldingcode/HIAHKernel";
      license = licenses.mit;
      platforms = [ "aarch64-darwin" "x86_64-darwin" ];
    };
  };
  
  # iOS Test App for Simulator
  iosTestApp = pkgs.stdenv.mkDerivation rec {
    name = "hiahkernel-testapp-ios";
    version = projectVersion;
    src = hiahkernelSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      xcodeUtils.findXcodeScript
    ];
    
    buildInputs = [ iosSimulator ];
    
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      fi
      
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      
      export ARCH="$SIMULATOR_ARCH"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building HIAHKernel Test App for iOS Simulator..."
      
      # Create test app source
      mkdir -p TestApp
      cat > TestApp/main.m << 'EOF'
#import <UIKit/UIKit.h>
#import <HIAHKernel/HIAHKernel.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = @"HIAHKernel Test";
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor]
    ]];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    
    // Initialize the kernel
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    kernel.onOutput = ^(pid_t pid, NSString *output) {
        NSLog(@"[Process %d] %@", pid, output);
    };
    
    NSLog(@"[HIAHKernel Test] Kernel initialized: %@", kernel);
    NSLog(@"[HIAHKernel Test] Control socket: %@", kernel.controlSocketPath);
    
    return YES;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
EOF
      
      # Create Info.plist
      cat > TestApp/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HIAHKernelTest</string>
    <key>CFBundleIdentifier</key>
    <string>com.aspauldingcode.HIAHKernelTest</string>
    <key>CFBundleName</key>
    <string>HIAHKernel Test</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
</dict>
</plist>
EOF
      
      # Compile test app
      $CC TestApp/main.m -o HIAHKernelTest \
        -arch $ARCH \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=15.0 \
        -fobjc-arc \
        -I${iosSimulator}/include \
        -L${iosSimulator}/lib \
        -lHIAHKernel \
        -framework UIKit \
        -framework Foundation \
        -Wl,-rpath,@executable_path/Frameworks
      
      # Create app bundle
      mkdir -p HIAHKernelTest.app/Frameworks
      cp HIAHKernelTest HIAHKernelTest.app/
      cp TestApp/Info.plist HIAHKernelTest.app/
      cp ${iosSimulator}/lib/libHIAHKernel.dylib HIAHKernelTest.app/Frameworks/
      
      echo "Test app built successfully!"
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/Applications $out/bin
      cp -r HIAHKernelTest.app $out/Applications/
      
      # Create simulator launch script
      cat > $out/bin/hiahkernel-ios-simulator << 'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="$1"
shift || true

# Find an available iOS Simulator
DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1)

if [ -z "$DEVICE_ID" ]; then
    echo "Error: No iOS simulator found"
    echo "   Please install Xcode and create an iPhone simulator"
    exit 1
fi

echo "📱 Device ID: $DEVICE_ID"

# Boot simulator if needed
echo "Booting simulator..."
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
sleep 2

# Install the app
echo "Installing app..."
xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"

# Get bundle identifier from Info.plist
BUNDLE_ID=$(defaults read "$APP_BUNDLE/Info.plist" CFBundleIdentifier 2>/dev/null || echo "com.aspauldingcode.HIAHKernelTest")

# Launch the app
echo "Launching $BUNDLE_ID..."
xcrun simctl launch --console-pty "$DEVICE_ID" "$BUNDLE_ID" "$@"
LAUNCHER
      chmod +x $out/bin/hiahkernel-ios-simulator
      
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  # HIAHTop - Process Monitor App for iOS Simulator
  iosTopApp = pkgs.stdenv.mkDerivation rec {
    name = "hiah-top";
    version = projectVersion;
    src = hiahkernelSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      xcodeUtils.findXcodeScript
    ];
    
    buildInputs = [ iosSimulator ];
    
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      fi
      
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      
      export ARCH="$SIMULATOR_ARCH"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building HIAHKernel-Top Process Monitor for iOS Simulator..."
      
      HIAHFLAGS="-arch $ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fobjc-arc -I${iosSimulator}/include -Isrc -Isrc/HIAHTop"
      
      # Compile each source file separately for better error messages
      echo "Compiling HIAHProcessStats.m..."
      $CC -c src/HIAHTop/HIAHProcessStats.m -o HIAHProcessStats.o $HIAHFLAGS
      
      echo "Compiling HIAHResourceCollector.m..."
      $CC -c src/HIAHTop/HIAHResourceCollector.m -o HIAHResourceCollector.o $HIAHFLAGS
      
      echo "Compiling HIAHManagedProcess.m..."
      $CC -c src/HIAHTop/HIAHManagedProcess.m -o HIAHManagedProcess.o $HIAHFLAGS
      
      echo "Compiling HIAHProcessManager.m..."
      $CC -c src/HIAHTop/HIAHProcessManager.m -o HIAHProcessManager.o $HIAHFLAGS
      
      echo "Compiling HIAHTopViewController.m..."
      $CC -c src/HIAHTop/HIAHTopViewController.m -o HIAHTopViewController.o $HIAHFLAGS
      
      echo "Compiling main.m..."
      $CC -c src/HIAHTop/main.m -o main.o $HIAHFLAGS
      
      # Link everything together
      echo "Linking HIAHTop..."
      $CC HIAHProcessStats.o HIAHResourceCollector.o HIAHManagedProcess.o HIAHProcessManager.o HIAHTopViewController.o main.o \
        -o HIAHTop \
        -arch $ARCH \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=15.0 \
        -L${iosSimulator}/lib \
        -lHIAHKernel \
        -framework UIKit \
        -framework Foundation \
        -framework CoreGraphics \
        -framework QuartzCore \
        -Wl,-rpath,@executable_path/Frameworks
      
      # Create app bundle
      mkdir -p HIAHTop.app/Frameworks
      cp HIAHTop HIAHTop.app/
      cp src/HIAHTop/Info.plist HIAHTop.app/
      cp ${iosSimulator}/lib/libHIAHKernel.dylib HIAHTop.app/Frameworks/
      
      echo "HIAHKernel-Top built successfully!"
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/Applications $out/bin
      cp -r HIAHTop.app $out/Applications/
      
      runHook postInstall
    '';
    
    __noChroot = true;
    
    meta = with lib; {
      description = "Process Monitor for HIAHKernel Virtual Processes";
      homepage = "https://github.com/aspauldingcode/HIAHKernel";
      license = licenses.mit;
      platforms = [ "aarch64-darwin" "x86_64-darwin" ];
    };
  };
  
  # HIAH Desktop - Full desktop environment with floating windows, app launcher, and multi-display support
  iosDesktopApp = pkgs.stdenv.mkDerivation rec {
    name = "hiah-desktop";
    version = projectVersion;
    src = hiahkernelSrc;
    
    nativeBuildInputs = with pkgs; [
      clang
      xcodeUtils.findXcodeScript
    ];
    
    buildInputs = [ iosSimulator ];
    
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      fi
      
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      
      export ARCH="$SIMULATOR_ARCH"
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building HIAH Desktop for iOS Simulator..."
      
      HIAHFLAGS="-arch $ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fobjc-arc -I${iosSimulator}/include -Isrc -Isrc/HIAHTop -Isrc/HIAHDesktop"
      
      # Compile HIAHTop components (reuse from iosTopApp build)
      echo "Compiling HIAHLogging.m..."
      $CC -c src/HIAHDesktop/HIAHLogging.m -o HIAHLogging.o $HIAHFLAGS
      
      echo "Compiling HIAHMachOUtils.m..."
      $CC -c src/HIAHDesktop/HIAHMachOUtils.m -o HIAHMachOUtils.o $HIAHFLAGS
      
      echo "Compiling HIAHProcessStats.m..."
      $CC -c src/HIAHTop/HIAHProcessStats.m -o HIAHProcessStats.o $HIAHFLAGS
      
      echo "Compiling HIAHResourceCollector.m..."
      $CC -c src/HIAHTop/HIAHResourceCollector.m -o HIAHResourceCollector.o $HIAHFLAGS
      
      echo "Compiling HIAHManagedProcess.m..."
      $CC -c src/HIAHTop/HIAHManagedProcess.m -o HIAHManagedProcess.o $HIAHFLAGS
      
      echo "Compiling HIAHProcessManager.m..."
      $CC -c src/HIAHTop/HIAHProcessManager.m -o HIAHProcessManager.o $HIAHFLAGS
      
      echo "Compiling HIAHTopViewController.m..."
      $CC -c src/HIAHTop/HIAHTopViewController.m -o HIAHTopViewController.o $HIAHFLAGS
      
      echo "Compiling HIAHWindowServer.m..."
      $CC -c src/HIAHWindowServer/HIAHWindowServer.m -o HIAHWindowServer.o $HIAHFLAGS -Isrc/HIAHWindowServer
      
      echo "Compiling HIAHAppWindowSession.m..."
      $CC -c src/HIAHWindowServer/HIAHAppWindowSession.m -o HIAHAppWindowSession.o $HIAHFLAGS -Isrc/HIAHWindowServer
      
      echo "Compiling HIAHFloatingWindow.m..."
      $CC -c src/HIAHWindowServer/HIAHFloatingWindow.m -o HIAHFloatingWindow.o $HIAHFLAGS -Isrc/HIAHWindowServer
      
      echo "Compiling HIAHAppLauncher.m..."
      $CC -c src/HIAHWindowServer/HIAHAppLauncher.m -o HIAHAppLauncher.o $HIAHFLAGS -Isrc/HIAHWindowServer
      
      echo "Compiling HIAHStateMachine.m..."
      $CC -c src/HIAHWindowServer/HIAHStateMachine.m -o HIAHStateMachine.o $HIAHFLAGS -Isrc/HIAHWindowServer
      
      echo "Compiling HIAHeDisplayMode.m..."
      $CC -c src/HIAHDesktop/HIAHeDisplayMode.m -o HIAHeDisplayMode.o $HIAHFLAGS -Isrc/HIAHWindowServer -Isrc/HIAHDesktop
      
      echo "Compiling HIAHFilesystem.m..."
      $CC -c src/HIAHDesktop/HIAHFilesystem.m -o HIAHFilesystem.o $HIAHFLAGS -Isrc/HIAHDesktop
      
      echo "Compiling HIAHCarPlayController.m..."
      $CC -c src/HIAHDesktop/HIAHCarPlayController.m -o HIAHCarPlayController.o $HIAHFLAGS -Isrc/HIAHWindowServer -Isrc/HIAHDesktop
      
      echo "Compiling HIAHDesktopApp.m..."
      $CC -c src/HIAHDesktop/HIAHDesktopApp.m -o HIAHDesktopApp.o $HIAHFLAGS -Isrc/HIAHWindowServer -Isrc/HIAHDesktop
      
      echo "Compiling EMProxyBridge.m..."
      $CC -c src/HIAHLoginWindow/VPN/EMProxyBridge.m -o EMProxyBridge.o $HIAHFLAGS -Isrc/HIAHLoginWindow/VPN
      
      echo "Compiling HIAHVPNManager.m..."
      $CC -c src/HIAHLoginWindow/VPN/HIAHVPNManager.m -o HIAHVPNManager.o $HIAHFLAGS -Isrc/HIAHLoginWindow/VPN
      
      echo "Compiling MinimuxerBridge.m..."
      $CC -c src/HIAHLoginWindow/VPN/MinimuxerBridge.m -o MinimuxerBridge.o $HIAHFLAGS -Isrc/HIAHLoginWindow/VPN
      
      echo "Compiling HIAHJITManager.m..."
      $CC -c src/HIAHLoginWindow/JIT/HIAHJITManager.m -o HIAHJITManager.o $HIAHFLAGS -Isrc/HIAHLoginWindow/JIT
      
      echo "Compiling HIAHCertificateMonitor.m..."
      $CC -c src/HIAHLoginWindow/Refresh/HIAHCertificateMonitor.m -o HIAHCertificateMonitor.o $HIAHFLAGS -Isrc/HIAHLoginWindow/Refresh
      
      echo "Compiling HIAHBackgroundRefresher.m..."
      $CC -c src/HIAHLoginWindow/Refresh/HIAHBackgroundRefresher.m -o HIAHBackgroundRefresher.o $HIAHFLAGS -Isrc/HIAHLoginWindow/Refresh
      
      echo "Compiling HIAHLoginViewController.m..."
      $CC -c src/HIAHLoginWindow/UI/HIAHLoginViewController.m -o HIAHLoginViewController.o $HIAHFLAGS -Isrc/HIAHLoginWindow/UI
      
      # Link everything together
      echo "Linking HIAH Desktop..."
      $CC EMProxyBridge.o HIAHVPNManager.o MinimuxerBridge.o HIAHJITManager.o HIAHCertificateMonitor.o HIAHBackgroundRefresher.o HIAHLoginViewController.o HIAHLogging.o HIAHMachOUtils.o HIAHProcessStats.o HIAHResourceCollector.o HIAHManagedProcess.o HIAHProcessManager.o HIAHTopViewController.o HIAHWindowServer.o HIAHAppWindowSession.o HIAHFloatingWindow.o HIAHAppLauncher.o HIAHStateMachine.o HIAHeDisplayMode.o HIAHFilesystem.o HIAHCarPlayController.o HIAHDesktopApp.o \
        -o HIAHDesktop \
        -arch $ARCH \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=15.0 \
        -L${iosSimulator}/lib \
        -lHIAHKernel \
        -lz \
        -framework UIKit \
        -framework Foundation \
        -framework CoreGraphics \
        -framework QuartzCore \
        -framework CarPlay \
        -framework UniformTypeIdentifiers \
        -framework Security \
        -framework NetworkExtension \
        -Wl,-rpath,@executable_path/Frameworks
      
      # Create app bundle
      mkdir -p HIAHDesktop.app/Frameworks
      cp HIAHDesktop HIAHDesktop.app/
      cp src/HIAHDesktop/Info.plist HIAHDesktop.app/
      cp ${iosSimulator}/lib/libHIAHKernel.dylib HIAHDesktop.app/Frameworks/
      
      # Bundle GNU tools for virtual filesystem
      echo "Bundling GNU tools..."
      mkdir -p HIAHDesktop.app/bin HIAHDesktop.app/usr/bin
      if [ -d "${gnuTools}/bin" ]; then
        cp -r ${gnuTools}/bin/* HIAHDesktop.app/bin/ || true
        echo "✓ Bundled bin tools"
      fi
      if [ -d "${gnuTools}/usr/bin" ]; then
        cp -r ${gnuTools}/usr/bin/* HIAHDesktop.app/usr/bin/ || true
        echo "✓ Bundled usr/bin tools"
      fi
      chmod -R +x HIAHDesktop.app/bin/* HIAHDesktop.app/usr/bin/* 2>/dev/null || true
      
      # Bundle HIAHTop and HIAHInstaller apps
      echo "Bundling HIAHTop and HIAHInstaller apps..."
      mkdir -p HIAHDesktop.app/BundledApps/HIAHTop.app
      mkdir -p HIAHDesktop.app/BundledApps/HIAHInstaller.app
      
      # Copy HIAHTop sources
      if [ -d src/HIAHTop ]; then
        cp src/HIAHTop/*.m src/HIAHTop/*.h HIAHDesktop.app/BundledApps/HIAHTop.app/ 2>/dev/null || true
        cp src/HIAHTop/Info.plist HIAHDesktop.app/BundledApps/HIAHTop.app/ 2>/dev/null || true
        echo "✓ Bundled HIAHTop.app"
      fi
      
      # Copy HIAHInstaller sources
      if [ -d src/HIAHInstaller ]; then
        cp src/HIAHInstaller/*.m src/HIAHInstaller/*.h HIAHDesktop.app/BundledApps/HIAHInstaller.app/ 2>/dev/null || true
        cp src/HIAHInstaller/Info.plist HIAHDesktop.app/BundledApps/HIAHInstaller.app/ 2>/dev/null || true
        echo "✓ Bundled HIAHInstaller.app"
      fi
      
      # Bundle sample apps (Calculator, Notes, Weather, Timer, Canvas)
      echo "Bundling sample apps..."
      for app in Calculator Notes Weather Timer Canvas; do
        if [ -d src/SampleApps/$app ]; then
          mkdir -p HIAHDesktop.app/BundledApps/$app.app
          cp src/SampleApps/$app/*.swift HIAHDesktop.app/BundledApps/$app.app/ 2>/dev/null || true
          cp src/SampleApps/$app/Info.plist HIAHDesktop.app/BundledApps/$app.app/ 2>/dev/null || true
          echo "✓ Bundled $app.app"
        fi
      done
      
      # Bundle HIAH Terminal app
      if [ -d src/HIAHTerminal ]; then
        mkdir -p HIAHDesktop.app/BundledApps/HIAHTerminal.app
        cp src/HIAHTerminal/*.swift src/HIAHTerminal/*.m src/HIAHTerminal/*.h HIAHDesktop.app/BundledApps/HIAHTerminal.app/ 2>/dev/null || true
        cp src/HIAHTerminal/Info.plist HIAHDesktop.app/BundledApps/HIAHTerminal.app/ 2>/dev/null || true
        echo "✓ Bundled HIAHTerminal.app"
      fi
      
      # Copy and apply entitlements for CarPlay support
      if [ -f src/HIAHDesktop/HIAHDesktop.entitlements ]; then
        echo "Applying CarPlay entitlements..."
        cp src/HIAHDesktop/HIAHDesktop.entitlements HIAHDesktop.app/
        # Sign with entitlements for simulator (ad-hoc signing)
        codesign --force --sign - --entitlements src/HIAHDesktop/HIAHDesktop.entitlements HIAHDesktop.app/HIAHDesktop || true
        codesign --force --sign - --entitlements src/HIAHDesktop/HIAHDesktop.entitlements HIAHDesktop.app/Frameworks/libHIAHKernel.dylib || true
      fi
      
      # Build ProcessRunner extension (.appex)
      echo "Building HIAHProcessRunner extension..."
      
      EXTFLAGS="-arch $ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fobjc-arc -I${iosSimulator}/include -Isrc -Isrc/hooks -fapplication-extension"
      
      # Compile HIAHHook
      echo "Compiling HIAHHook.c for extension..."
      $CC -c src/hooks/HIAHHook.c -o ext_hiahhook.o $EXTFLAGS -O2
      
      # Compile extension dependencies
      echo "Compiling HIAHLogging.m for extension..."
      $CC -c src/HIAHDesktop/HIAHLogging.m -o ext_logging.o $EXTFLAGS
      
      echo "Compiling HIAHMachOUtils.m for extension..."
      $CC -c src/HIAHDesktop/HIAHMachOUtils.m -o ext_machoutils.o $EXTFLAGS
      
      echo "Compiling HIAHDyldBypass.m for extension..."
      $CC -c src/hooks/HIAHDyldBypass.m -o ext_dyldbypass.o $EXTFLAGS
      
      echo "Compiling HIAHSigner.m for extension..."
      $CC -c src/extension/HIAHSigner.m -o ext_signer.o $EXTFLAGS -Isrc/extension

      # Compile extension
      echo "Compiling HIAHProcessRunner.m..."
      $CC -c src/extension/HIAHProcessRunner.m -o HIAHProcessRunner.o $EXTFLAGS
      
      # Link extension executable
      echo "Linking HIAHProcessRunner..."
      $CC ext_hiahhook.o ext_logging.o ext_machoutils.o ext_dyldbypass.o ext_signer.o HIAHProcessRunner.o \
        -o HIAHProcessRunner \
        -arch $ARCH \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=15.0 \
        -e _NSExtensionMain \
        -fapplication-extension \
        -framework Foundation \
        -framework UIKit \
        -framework Security \
        -Wl,-rpath,@executable_path/../../Frameworks
      
      # Create extension bundle
      mkdir -p HIAHDesktop.app/PlugIns/HIAHProcessRunner.appex
      cp HIAHProcessRunner HIAHDesktop.app/PlugIns/HIAHProcessRunner.appex/
      cp src/extension/Info.plist HIAHDesktop.app/PlugIns/HIAHProcessRunner.appex/
      
      # Sign extension with entitlements
      if [ -f src/extension/Entitlements.plist ]; then
        codesign --force --sign - --entitlements src/extension/Entitlements.plist HIAHDesktop.app/PlugIns/HIAHProcessRunner.appex/HIAHProcessRunner || true
      fi
      
      # Bundle SideStore components if available
    if [ -n "${sidestore.all or ""}" ]; then
      echo "Bundling SideStore components..."
      mkdir -p HIAHDesktop.app/Frameworks
      cp ${sidestore.all}/lib/*.a HIAHDesktop.app/Frameworks/ 2>/dev/null || true
      # AltSign and Roxas are source packages, they will be built by Xcode
      # but we stage them in the vendor directory for the build system
    fi
    
    # Final app bundle signing
      echo "Signing app bundle..."
      codesign --force --sign - --deep HIAHDesktop.app || true
      
      echo "HIAH Desktop with CarPlay support and ProcessRunner extension built successfully!"
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/Applications
      cp -r HIAHDesktop.app $out/Applications/
      
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  # HIAHInstaller - App Installer for HIAH Desktop
  iosInstallerApp = pkgs.stdenv.mkDerivation rec {
    name = "hiah-installer";
    version = projectVersion;
    src = hiahkernelSrc;
    
    nativeBuildInputs = with pkgs; [ clang xcodeUtils.findXcodeScript ];
    
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      fi
      
      ARCH="arm64"
    '';
    
    buildPhase = ''
      INSTALLERFLAGS="-arch $ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fobjc-arc"
      
      echo "Building HIAH Installer..."
      $CC -c src/HIAHInstaller/HIAHInstallerApp.m -o HIAHInstallerApp.o $INSTALLERFLAGS
      
      $CC HIAHInstallerApp.o -o HIAHInstaller \
        -arch $ARCH \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=15.0 \
        -framework UIKit \
        -framework Foundation \
        -framework UniformTypeIdentifiers
      
      mkdir -p HIAHInstaller.app
      cp HIAHInstaller HIAHInstaller.app/
      cp src/HIAHInstaller/Info.plist HIAHInstaller.app/
      
      codesign --force --sign - --deep HIAHInstaller.app || true
    '';
    
    installPhase = ''
      mkdir -p $out
      cp -r HIAHInstaller.app $out/
    '';
    
    __noChroot = true;
  };

  # iOS Device kernel library
  iosDevice = iosSimulator.overrideAttrs (old: {
    preConfigure = builtins.replaceStrings 
      ["iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" "SIMULATOR_ARCH" "-mios-simulator-version-min=15.0"]
      ["iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" "arm64" "-miphoneos-version-min=15.0"]
      (old.preConfigure or "");
    buildPhase = builtins.replaceStrings 
      ["-mios-simulator-version-min=15.0"] 
      ["-miphoneos-version-min=15.0"]
      (old.buildPhase or "");
  });
  
  # iOS Device Desktop app
  iosDesktopDevice = iosDesktopApp.overrideAttrs (old: {
    name = "hiah-desktop-device";
    buildInputs = [ iosDevice ];  # Use device kernel lib
    
    preConfigure = builtins.replaceStrings 
      ["iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" "SIMULATOR_ARCH"]
      ["iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" "arm64"]
      (old.preConfigure or "");
      
    buildPhase = builtins.replaceStrings 
      ["-mios-simulator-version-min=15.0" "iOS Simulator" "-I${iosSimulator}/include" "-L${iosSimulator}/lib"]
      ["-miphoneos-version-min=15.0" "iOS Device" "-I${iosDevice}/include" "-L${iosDevice}/lib"]
      (old.buildPhase or "");
    
    # Override installPhase to EXCLUDE GNU tools for device (iOS security restrictions)
    installPhase = builtins.replaceStrings
      ["# Bundle GNU tools..." "echo \"Bundling GNU tools...\"" 
       "mkdir -p HIAHDesktop.app/bin HIAHDesktop.app/usr/bin"
       ''if [ -d "''${gnuTools}/bin" ]; then
        cp -r ''${gnuTools}/bin/* HIAHDesktop.app/bin/ || true
        echo "✓ Bundled bin tools"
      fi
      if [ -d "''${gnuTools}/usr/bin" ]; then
        cp -r ''${gnuTools}/usr/bin/* HIAHDesktop.app/usr/bin/ || true
        echo "✓ Bundled usr/bin tools"
      fi
      chmod -R +x HIAHDesktop.app/bin/* HIAHDesktop.app/usr/bin/* 2>/dev/null || true'']
      ["# GNU tools excluded for device build" "echo \"Skipping GNU tools for device build...\"" 
       "# Skipped: mkdir -p HIAHDesktop.app/bin HIAHDesktop.app/usr/bin"
       "# GNU tools not included in device build for security/signing reasons"]
      (old.installPhase or "");
  });

in {
  ios = iosSimulator;           # hiah-kernel - Core library
  iosTopApp = iosTopApp;           # hiah-top - Process Manager
  iosDesktopApp = iosDesktopApp;    # hiah-desktop - Desktop Environment  
  iosInstallerApp = iosInstallerApp; # hiah-installer - App Installer for HIAH Desktop
  
  # Device builds
  iosDesktopDevice = iosDesktopDevice;
}

