/**
 * HIAHDesktopApp.m - HIAH Desktop Environment
 * Floating window manager with eDisplay Mode support
 */

// Import Swift-generated header for HIAHLoginViewController
#import "HIAHDesktop-Swift.h"
#import "HIAHAppLauncher.h"
#import "HIAHAppWindowSession.h"
#import "HIAHCarPlayController.h"
#import "HIAHFilesystem.h"
#import "HIAHFloatingWindow.h"
#import "HIAHKernel.h"
#import "HIAHLogging.h"
#import "HIAHMachOUtils.h"
#import "HIAHProcess.h"
#import "HIAHStateMachine.h"
#import "HIAHTopViewController.h"
#import "HIAHWindowServer.h"
#import "HIAHeDisplayMode.h"
#import "../HIAHLoginWindow/Signing/HIAHSignatureBypass.h"
#import "../HIAHLoginWindow/VPN/HIAHVPNStateMachine.h"
#import "../HIAHLoginWindow/VPN/HIAHVPNReminderViewController.h"
#import "../HIAHLoginWindow/VPN/LocalDevVPN/HIAHLocalDevVPNSetupViewController.h"
#import <CarPlay/CarPlay.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <zlib.h>

// Forward declaration for Swift bridge
@class HIAHSwiftBridge;

#pragma mark - HIAH Installer UI

@interface HIAHInstallerViewController
    : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *pickButton;
@end

@implementation HIAHInstallerViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSLog(@"[Installer] viewDidLoad called");

  self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
  self.view.userInteractionEnabled = YES;

  UILabel *title = [[UILabel alloc] init];
  title.text = @"HIAH Installer";
  title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
  title.textColor = [UIColor whiteColor];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:title];

  self.statusLabel = [[UILabel alloc] init];
  self.statusLabel.text = @"Select an app to install";
  self.statusLabel.font = [UIFont systemFontOfSize:14];
  self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1];
  self.statusLabel.numberOfLines = 0;
  self.statusLabel.textAlignment = NSTextAlignmentCenter;
  self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.statusLabel];

  self.pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.pickButton setTitle:@"Pick .ipa or .app" forState:UIControlStateNormal];
  [self.pickButton setTitleColor:[UIColor whiteColor]
                        forState:UIControlStateNormal];
  self.pickButton.backgroundColor = [UIColor systemBlueColor];
  self.pickButton.titleLabel.font =
      [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
  self.pickButton.layer.cornerRadius = 12;
  self.pickButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.pickButton.userInteractionEnabled = YES;
  [self.pickButton addTarget:self
                      action:@selector(pickTapped)
            forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.pickButton];

  NSLog(@"[Installer] Button created: %@", self.pickButton);
  NSLog(@"[Installer] Button frame will be: center, 220x50");

  [NSLayoutConstraint activateConstraints:@[
    [title.topAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                       constant:60],
    [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                               constant:20],
    [self.statusLabel.centerXAnchor
        constraintEqualToAnchor:self.view.centerXAnchor],
    [self.statusLabel.leadingAnchor
        constraintEqualToAnchor:self.view.leadingAnchor
                       constant:40],
    [self.statusLabel.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor
                       constant:-40],
    [self.pickButton.topAnchor
        constraintEqualToAnchor:self.statusLabel.bottomAnchor
                       constant:40],
    [self.pickButton.centerXAnchor
        constraintEqualToAnchor:self.view.centerXAnchor],
    [self.pickButton.widthAnchor constraintEqualToConstant:220],
    [self.pickButton.heightAnchor constraintEqualToConstant:50]
  ]];

  // Add tap gesture as backup
  UITapGestureRecognizer *tap =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(pickTapped)];
  [self.pickButton addGestureRecognizer:tap];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  NSLog(@"[Installer] viewDidAppear - button frame: %@",
        NSStringFromCGRect(self.pickButton.frame));
  NSLog(@"[Installer] view frame: %@", NSStringFromCGRect(self.view.frame));
  NSLog(@"[Installer] view userInteractionEnabled: %d",
        self.view.userInteractionEnabled);
  NSLog(@"[Installer] button userInteractionEnabled: %d",
        self.pickButton.userInteractionEnabled);
}

- (void)pickTapped {
  NSLog(@"[Installer] Pick button tapped");

  self.statusLabel.text = @"Opening file picker...";

  // Configure types for .ipa and .app files
  NSMutableArray *types = [NSMutableArray array];

  // .ipa files - try multiple identifiers
  UTType *ipaType = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
  if (!ipaType)
    ipaType = [UTType typeWithIdentifier:@"com.apple.ios-package-archive"];
  if (!ipaType)
    ipaType = [UTType typeWithFilenameExtension:@"ipa"];
  if (ipaType) {
    [types addObject:ipaType];
    NSLog(@"[Installer] Added .ipa type: %@", ipaType);
  }

  // .app bundles
  UTType *appType = [UTType typeWithIdentifier:@"com.apple.application-bundle"];
  if (!appType)
    appType = [UTType typeWithFilenameExtension:@"app"];
  if (appType) {
    [types addObject:appType];
    NSLog(@"[Installer] Added .app type: %@", appType);
  }

  // Add zip as well (since .ipa is a zip file)
  UTType *zipType = [UTType typeWithIdentifier:@"public.zip-archive"];
  if (!zipType)
    zipType = [UTType typeWithFilenameExtension:@"zip"];
  if (zipType) {
    [types addObject:zipType];
    NSLog(@"[Installer] Added .zip type: %@", zipType);
  }

  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  picker.modalPresentationStyle = UIModalPresentationFullScreen;

  NSLog(@"[Installer] Presenting picker with %lu types",
        (unsigned long)types.count);
  [self presentViewController:picker
                     animated:YES
                   completion:^{
                     NSLog(@"[Installer] Picker presented");
                   }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (urls.count == 0)
    return;
  NSURL *url = urls.firstObject;

  NSLog(@"[Installer] Picked file: %@", url);

  self.statusLabel.text = @"Installing...";
  self.pickButton.enabled = NO;

  // Start accessing security-scoped resource
  BOOL access = [url startAccessingSecurityScopedResource];
  NSLog(@"[Installer] Security-scoped access: %d", access);

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   [self installApp:url];

                   // Stop accessing security-scoped resource
                   if (access) {
                     [url stopAccessingSecurityScopedResource];
                   }
                 });
}

+ (NSString *)applicationsPath {
  // Use Documents folder (visible in Files.app) via HIAHFilesystem
  return [[HIAHFilesystem shared] appsPath];
}

// Pure native zip extraction using minizip-style implementation
+ (BOOL)unzipFileSync:(NSString *)zipPath toDirectory:(NSString *)destPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:destPath
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

  // Open zip file
  FILE *zipFile = fopen([zipPath UTF8String], "rb");
  if (!zipFile)
    return NO;

  // Find end of central directory (scan from end)
  fseek(zipFile, -22, SEEK_END);
  uint8_t eocd[22];
  fread(eocd, 1, 22, zipFile);

  // Extract central directory offset (bytes 16-19 in little-endian)
  uint32_t cdOffset =
      eocd[16] | (eocd[17] << 8) | (eocd[18] << 16) | (eocd[19] << 24);
  uint16_t numEntries = eocd[10] | (eocd[11] << 8);

  // Process each entry in central directory
  fseek(zipFile, cdOffset, SEEK_SET);

  for (int i = 0; i < numEntries; i++) {
    uint8_t cdHeader[46];
    fread(cdHeader, 1, 46, zipFile);

    uint16_t fileNameLen = cdHeader[28] | (cdHeader[29] << 8);
    uint16_t extraLen = cdHeader[30] | (cdHeader[31] << 8);
    uint16_t commentLen = cdHeader[32] | (cdHeader[33] << 8);
    uint32_t localHeaderOffset = cdHeader[42] | (cdHeader[43] << 8) |
                                 (cdHeader[44] << 16) | (cdHeader[45] << 24);
    uint32_t compressedSize = cdHeader[20] | (cdHeader[21] << 8) |
                              (cdHeader[22] << 16) | (cdHeader[23] << 24);
    uint32_t uncompressedSize = cdHeader[24] | (cdHeader[25] << 8) |
                                (cdHeader[26] << 16) | (cdHeader[27] << 24);
    uint16_t compressionMethod = cdHeader[10] | (cdHeader[11] << 8);

    char *fileName = malloc(fileNameLen + 1);
    fread(fileName, 1, fileNameLen, zipFile);
    fileName[fileNameLen] = '\0';

    // Skip extra and comment
    fseek(zipFile, extraLen + commentLen, SEEK_CUR);

    NSString *filePath = [destPath
        stringByAppendingPathComponent:[NSString
                                           stringWithUTF8String:fileName]];

    // Check if directory (ends with /)
    if (fileName[fileNameLen - 1] == '/') {
      [fm createDirectoryAtPath:filePath
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
      free(fileName);
      continue;
    }

    // Create parent directory
    [fm createDirectoryAtPath:[filePath stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];

    // Save current position and jump to local header
    long currentPos = ftell(zipFile);
    fseek(zipFile, localHeaderOffset, SEEK_SET);

    uint8_t localHeader[30];
    fread(localHeader, 1, 30, zipFile);
    uint16_t localFileNameLen = localHeader[26] | (localHeader[27] << 8);
    uint16_t localExtraLen = localHeader[28] | (localHeader[29] << 8);

    // Skip to file data
    fseek(zipFile, localFileNameLen + localExtraLen, SEEK_CUR);

    // Read compressed data
    uint8_t *compressedData = malloc(compressedSize);
    fread(compressedData, 1, compressedSize, zipFile);

    if (compressionMethod == 0) {
      // Stored (uncompressed)
      [[NSData dataWithBytes:compressedData
                      length:compressedSize] writeToFile:filePath
                                              atomically:YES];
    } else if (compressionMethod == 8) {
      // Deflate
      uint8_t *uncompressedData = malloc(uncompressedSize);
      z_stream strm = {0};
      strm.next_in = compressedData;
      strm.avail_in = compressedSize;
      strm.next_out = uncompressedData;
      strm.avail_out = uncompressedSize;

      inflateInit2(&strm, -MAX_WBITS);
      inflate(&strm, Z_FINISH);
      inflateEnd(&strm);

      [[NSData dataWithBytes:uncompressedData
                      length:uncompressedSize] writeToFile:filePath
                                                atomically:YES];
      free(uncompressedData);
    }

    free(compressedData);
    free(fileName);

    // Restore position
    fseek(zipFile, currentPos, SEEK_SET);
  }

  fclose(zipFile);
  return YES;
}

+ (void)unzipFile:(NSString *)zipPath
      toDirectory:(NSString *)destPath
       completion:(void (^)(BOOL success))completion {
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:destPath
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

  NSLog(@"[Unzip] Unzipping via HIAH Kernel: %@", zipPath);
  NSLog(@"[Unzip] Destination: %@", destPath);

  // Use HIAH Kernel to spawn unzip process
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  HIAHFilesystem *fs = [HIAHFilesystem shared];

  // Use virtual filesystem paths
  NSString *unzipPath = [fs.usrBinPath stringByAppendingPathComponent:@"unzip"];

  NSLog(@"[Unzip] Spawning unzip directly via HIAH Kernel");
  NSLog(@"[Unzip] Binary: %@", unzipPath);
  NSLog(@"[Unzip] Args: -q %@ -d %@", zipPath, destPath);

  // Spawn unzip directly (no shell script needed)
  [kernel
      spawnVirtualProcessWithPath:unzipPath
                        arguments:@[ @"-q", zipPath, @"-d", destPath ]
                      environment:@{}
                       completion:^(pid_t pid, NSError *error) {
                         if (error) {
                           NSLog(@"[Unzip] HIAH Kernel spawn error: %@", error);
                           if (completion)
                             completion(NO);
                         } else {
                           NSLog(@"[Unzip] Spawned via HIAH Kernel, PID: %d",
                                 pid);

                           // Give it time to complete (async)
                           dispatch_after(
                               dispatch_time(DISPATCH_TIME_NOW,
                                             2 * NSEC_PER_SEC),
                               dispatch_get_global_queue(
                                   DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                               ^{
                                 // Check if extraction succeeded by looking for
                                 // Payload folder
                                 NSString *payloadPath = [destPath
                                     stringByAppendingPathComponent:@"Payload"];
                                 BOOL success = [[NSFileManager defaultManager]
                                     fileExistsAtPath:payloadPath];
                                 NSLog(@"[Unzip] Extraction %@",
                                       success ? @"succeeded" : @"failed");
                                 if (completion)
                                   completion(success);
                               });
                         }
                       }];
}

- (void)installApp:(NSURL *)fileURL {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *appsDir = [[self class] applicationsPath];

  NSLog(@"[Installer] Installing from: %@", fileURL.path);
  NSLog(@"[Installer] Apps directory: %@", appsDir);

  // Ensure Applications folder exists
  NSError *dirError = nil;
  [fm createDirectoryAtPath:appsDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&dirError];
  if (dirError) {
    NSLog(@"[Installer] Error creating apps dir: %@", dirError);
  }

  // Check if source file exists
  if (![fm fileExistsAtPath:fileURL.path]) {
    NSLog(@"[Installer] ERROR: Source file doesn't exist at %@", fileURL.path);
    [self showResult:NO message:@"File not accessible"];
    return;
  }

  NSString *ext = fileURL.pathExtension.lowercaseString;
  NSLog(@"[Installer] File extension: %@", ext);

  if ([ext isEqualToString:@"app"]) {
    // Direct .app bundle
    NSString *appName = fileURL.lastPathComponent;
    NSString *destPath = [appsDir stringByAppendingPathComponent:appName];

    NSLog(@"[Installer] Destination: %@", destPath);

    // Check if source and destination are the same
    if ([fileURL.path isEqualToString:destPath]) {
      NSLog(@"[Installer] App already in Applications folder");
      [self
          showResult:YES
             message:[NSString
                         stringWithFormat:@"%@ already installed",
                                          [appName
                                              stringByDeletingPathExtension]]];
      return;
    }

    // Copy via temp location to avoid conflicts
    NSString *tempPath =
        [NSTemporaryDirectory() stringByAppendingPathComponent:appName];

    // Remove temp and dest
    [fm removeItemAtPath:tempPath error:nil];
    [fm removeItemAtPath:destPath error:nil];

    // Copy to temp first
    NSError *error = nil;
    [fm copyItemAtURL:fileURL
                toURL:[NSURL fileURLWithPath:tempPath]
                error:&error];

    if (error) {
      NSLog(@"[Installer] Copy to temp error: %@", error);
      [self showResult:NO
               message:[NSString stringWithFormat:@"Failed: %@",
                                                  error.localizedDescription]];
    } else {
      // Move from temp to destination
      [fm moveItemAtPath:tempPath toPath:destPath error:&error];

      if (error) {
        NSLog(@"[Installer] Move error: %@", error);
        [self
            showResult:NO
               message:[NSString stringWithFormat:@"Failed: %@",
                                                  error.localizedDescription]];
      } else {
        NSLog(@"[Installer] Install successful");
        // Set executable permissions and patch for dynamic loading
        NSString *plist =
            [destPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
        NSString *exec = info[@"CFBundleExecutable"];
        if (exec) {
          NSString *execPath = [destPath stringByAppendingPathComponent:exec];
          [fm setAttributes:@{NSFilePosixPermissions : @0755}
               ofItemAtPath:execPath
                      error:nil];

          // Patch to a dlopen-compatible Mach-O type (see HIAHMachOUtils)
          if ([HIAHMachOUtils patchBinaryToDylib:execPath]) {
            NSLog(@"[Installer] Patched %@ for dynamic loading", exec);
          }
        }
        [self
            showResult:YES
               message:[NSString stringWithFormat:
                                     @"✓ %@ installed",
                                     [appName stringByDeletingPathExtension]]];
      }
    }

  } else if ([ext isEqualToString:@"ipa"] || [ext isEqualToString:@"zip"]) {
    // .ipa file - extract and install
    NSString *ipaName = fileURL.lastPathComponent;
    NSLog(@"[Installer] Extracting .ipa: %@", ipaName);

    // Create temp extraction directory in virtual filesystem tmp
    HIAHFilesystem *fs = [HIAHFilesystem shared];
    NSString *tempDir =
        [fs.tmpPath stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSLog(@"[Installer] Temp dir: %@", tempDir);
    [fm createDirectoryAtPath:tempDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];

    // Unzip .ipa directly (no HIAH Kernel)
    BOOL unzipSuccess = [[self class] unzipFileSync:fileURL.path
                                        toDirectory:tempDir];

    if (!unzipSuccess) {
      NSLog(@"[Installer] Unzip failed");
      [self showResult:NO message:@"Failed to extract .ipa"];
      [fm removeItemAtPath:tempDir error:nil];
      return;
    } else {

      // Find .app in Payload folder
      NSString *payloadDir =
          [tempDir stringByAppendingPathComponent:@"Payload"];
      NSArray *contents = [fm contentsOfDirectoryAtPath:payloadDir error:nil];
      NSString *appBundle = nil;

      for (NSString *item in contents) {
        if ([item hasSuffix:@".app"]) {
          appBundle = item;
          break;
        }
      }

      if (!appBundle) {
        NSLog(@"[Installer] No .app found in .ipa");
        [self showResult:NO message:@"Invalid .ipa - no app bundle found"];
        [fm removeItemAtPath:tempDir error:nil];
        return;
      }

      NSLog(@"[Installer] Found app: %@", appBundle);

      // Copy to Applications folder
      NSString *sourcePath =
          [payloadDir stringByAppendingPathComponent:appBundle];
      NSString *destPath = [appsDir stringByAppendingPathComponent:appBundle];

      // Remove existing
      [fm removeItemAtPath:destPath error:nil];

      // Copy
      NSError *copyError = nil;
      [fm copyItemAtPath:sourcePath toPath:destPath error:&copyError];

      if (copyError) {
        NSLog(@"[Installer] Copy error: %@", copyError);
        [self showResult:NO
                 message:[NSString
                             stringWithFormat:@"Failed: %@",
                                              copyError.localizedDescription]];
      } else {
        // Set executable permissions and patch for dynamic loading
        NSString *plist =
            [destPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
        NSString *exec = info[@"CFBundleExecutable"];
        if (exec) {
          NSString *execPath = [destPath stringByAppendingPathComponent:exec];
          [fm setAttributes:@{NSFilePosixPermissions : @0755}
               ofItemAtPath:execPath
                      error:nil];

          // Patch to a dlopen-compatible Mach-O type (see HIAHMachOUtils)
          if ([HIAHMachOUtils patchBinaryToDylib:execPath]) {
            NSLog(@"[Installer] Patched %@ for dynamic loading", exec);
          }
        }
        NSLog(@"[Installer] .ipa installed successfully");
        [self showResult:YES
                 message:[NSString
                             stringWithFormat:
                                 @"✓ %@ installed from .ipa",
                                 [appBundle stringByDeletingPathExtension]]];
      }

      // Clean up temp
      [fm removeItemAtPath:tempDir error:nil];
    }

  } else {
    [self showResult:NO message:@"Unsupported file type"];
  }
}

- (void)showResult:(BOOL)success message:(NSString *)msg {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.statusLabel.text = msg;
    self.pickButton.enabled = YES;

    if (success) {
      // Notify HIAH Desktop to refresh app list
      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"HIAHDesktopRefreshApps"
                        object:nil];
    }
  });
}

@end

#pragma mark - Desktop View Controller

@interface DesktopViewController
    : UIViewController <HIAHFloatingWindowDelegate, HIAHAppLauncherDelegate,
                        HIAHStateMachineDelegate>
@property(nonatomic, strong) UIView *desktop;
@property(nonatomic, strong) HIAHAppLauncher *dock;
@property(nonatomic, strong) HIAHKernel *kernel;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, HIAHFloatingWindow *> *windows;
@property(nonatomic, assign) NSInteger nextWindowID;
@property(nonatomic, strong) UIScreen *screen;
@property(nonatomic, strong) UIWindowScene *windowScene;

// Helper to get main screen from windowScene context (iOS 26.0+)
- (UIScreen *)mainScreenFromContext;
@property(nonatomic, weak) HIAHStateMachine *stateMachine;
@end

@implementation DesktopViewController

- (UIScreen *)mainScreenFromContext {
  // Try to get main screen from windowScene first (iOS 26.0+)
  if (self.windowScene) {
    return self.windowScene.screen;
  }
  // Fallback: get from connected scenes
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *ws = (UIWindowScene *)scene;
      if (ws.screen) {
        return ws.screen;
      }
    }
  }
  // Final fallback for iOS < 26.0
  return [UIScreen mainScreen];
}

+ (UIViewController *)loadAppFromBundle:(NSString *)appPath {
  if (!appPath)
    return nil;

  NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
  if (!appBundle)
    return nil;

  NSError *error = nil;
  if (![appBundle loadAndReturnError:&error]) {
    NSLog(@"[AppLoader] Failed to load: %@", error);
    return nil;
  }

  // Get principal class
  Class principalClass = appBundle.principalClass;
  if (!principalClass) {
    NSString *className =
        [appBundle objectForInfoDictionaryKey:@"NSPrincipalClass"];
    if (className)
      principalClass = NSClassFromString(className);
  }

  if (!principalClass) {
    NSString *execName =
        [appBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    if (execName) {
      principalClass = NSClassFromString(
          [execName stringByAppendingString:@"ViewController"]);
      if (!principalClass)
        principalClass = NSClassFromString(execName);
    }
  }

  if (principalClass &&
      [principalClass isSubclassOfClass:[UIViewController class]]) {
    return [[principalClass alloc] init];
  }

  return nil;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.kernel = [HIAHKernel sharedKernel];
  self.windows = [NSMutableDictionary dictionary];
  self.nextWindowID = 1;
  if (!self.screen) {
    self.screen =
        self.windowScene ? self.windowScene.screen : [UIScreen mainScreen];
  }

  self.stateMachine = [HIAHStateMachine shared];
  self.stateMachine.delegate = self;

  [self setupDesktop];
  [self setupDock];
}

- (void)setupDesktop {
  self.desktop = [[UIView alloc] initWithFrame:self.view.bounds];
  self.desktop.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  CAGradientLayer *grad = [CAGradientLayer layer];
  grad.frame = self.desktop.bounds;
  grad.colors = @[
    (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1].CGColor,
    (id)[UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1].CGColor
  ];
  [self.desktop.layer insertSublayer:grad atIndex:0];
  [self.view addSubview:self.desktop];

  UILabel *title = [[UILabel alloc] init];
  title.text = @"HIAHKernel Desktop";
  title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
  title.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  [self.desktop addSubview:title];

  UILabel *status = [[UILabel alloc] init];
  status.tag = 100;
  status.text = @"Tap an app to launch";
  status.font = [UIFont systemFontOfSize:12];
  status.textColor = [UIColor colorWithWhite:1.0 alpha:0.3];
  status.translatesAutoresizingMaskIntoConstraints = NO;
  [self.desktop addSubview:status];

  // Account button (top-right)
  UIButton *accountButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [accountButton setImage:[UIImage systemImageNamed:@"person.circle.fill"] forState:UIControlStateNormal];
  accountButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
  accountButton.translatesAutoresizingMaskIntoConstraints = NO;
  accountButton.tag = 200;
  [accountButton addTarget:self action:@selector(showAccountMenu:) forControlEvents:UIControlEventTouchUpInside];
  [self.desktop addSubview:accountButton];

  [NSLayoutConstraint activateConstraints:@[
    [title.topAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                       constant:10],
    [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
    [status.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    
    // Account button constraints
    [accountButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
    [accountButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
    [accountButton.widthAnchor constraintEqualToConstant:32],
    [accountButton.heightAnchor constraintEqualToConstant:32]
  ]];
}

- (void)showAccountMenu:(UIButton *)sender {
  // Get account info from HIAHAccountManager
  Class accountManagerClass = NSClassFromString(@"HIAHAccountManager");
  NSString *appleID = @"Not signed in";
  
  if (accountManagerClass) {
    id shared = [accountManagerClass valueForKey:@"shared"];
    if (shared) {
      id account = [shared valueForKey:@"account"];
      if (account) {
        appleID = [account valueForKey:@"appleID"] ?: @"Unknown";
      }
    }
  }
  
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Apple Account"
                       message:[NSString stringWithFormat:@"Signed in as:\n%@", appleID]
                preferredStyle:UIAlertControllerStyleActionSheet];
  
  [alert addAction:[UIAlertAction actionWithTitle:@"Sign Out"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction * _Nonnull action) {
    [self handleSignOutWithWarning];
  }]];
  
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  
  // For iPad - set the popover source
  if (alert.popoverPresentationController) {
    alert.popoverPresentationController.sourceView = sender;
    alert.popoverPresentationController.sourceRect = sender.bounds;
  }
  
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleSignOutWithWarning {
  // Check if VPN is active
  HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
  BOOL vpnActive = [vpnSM isConnected];
  
  if (vpnActive) {
    // Warn user to disable VPN before signing out
    UIAlertController *warning = [UIAlertController
        alertControllerWithTitle:@"VPN Active"
                         message:@"HIAH-VPN is currently enabled.\n\n⚠️ Please disable it in LocalDevVPN before signing out.\n\nYou'll need to disable it again before signing back in."
                  preferredStyle:UIAlertControllerStyleAlert];
    
    [warning addAction:[UIAlertAction actionWithTitle:@"Open Settings"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * _Nonnull action) {
      NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
      if (settingsURL) {
        [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
      }
    }]];
    
    [warning addAction:[UIAlertAction actionWithTitle:@"Sign Out Anyway"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction * _Nonnull action) {
      [self handleSignOut];
    }]];
    
    [warning addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];
    
    [self presentViewController:warning animated:YES completion:nil];
  } else {
    // VPN not active - proceed with sign out
    [self handleSignOut];
  }
}

- (void)handleSignOut {
  NSLog(@"[Desktop] User requested sign out");
  
  // Call logout on HIAHAccountManager
  Class accountManagerClass = NSClassFromString(@"HIAHAccountManager");
  if (accountManagerClass) {
    id shared = [accountManagerClass valueForKey:@"shared"];
    if ([shared respondsToSelector:@selector(logout)]) {
      [shared performSelector:@selector(logout)];
    }
  }
  
  // Post notification for sign out - this will trigger the app to show login gate
  [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHAuthenticationSignOut" object:nil];
  
  // Transition back to login gate by creating new login window
  UIWindowScene *windowScene = nil;
  for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      windowScene = (UIWindowScene *)scene;
      break;
    }
  }
  
  if (windowScene) {
    // Create a new login gate window
    UIWindow *loginWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
    loginWindow.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create login gate view controller with sign in button
    UIViewController *loginVC = [[UIViewController alloc] init];
    loginVC.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // House icon
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"house.fill"]];
    iconView.tintColor = [UIColor systemBlueColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [loginVC.view addSubview:iconView];
    
    // Title
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"HIAH Desktop";
    titleLabel.font = [UIFont systemFontOfSize:40 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [loginVC.view addSubview:titleLabel];
    
    // Message
    UILabel *messageLabel = [[UILabel alloc] init];
    messageLabel.text = @"You have been signed out.\n\nSign in again to use HIAH Desktop.";
    messageLabel.font = [UIFont systemFontOfSize:16];
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.numberOfLines = 0;
    messageLabel.textColor = [UIColor secondaryLabelColor];
    messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [loginVC.view addSubview:messageLabel];
    
    // Login button - use target/action to app delegate
    UIButton *loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [loginButton setTitle:@"Sign In with Apple Account" forState:UIControlStateNormal];
    [loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    loginButton.backgroundColor = [UIColor systemBlueColor];
    loginButton.layer.cornerRadius = 12;
    loginButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [loginButton addTarget:[UIApplication sharedApplication].delegate
                    action:@selector(openLoginWindow:)
          forControlEvents:UIControlEventTouchUpInside];
    [loginVC.view addSubview:loginButton];
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
      [iconView.centerXAnchor constraintEqualToAnchor:loginVC.view.centerXAnchor],
      [iconView.centerYAnchor constraintEqualToAnchor:loginVC.view.centerYAnchor constant:-120],
      [iconView.widthAnchor constraintEqualToConstant:100],
      [iconView.heightAnchor constraintEqualToConstant:100],
      
      [titleLabel.centerXAnchor constraintEqualToAnchor:loginVC.view.centerXAnchor],
      [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:20],
      
      [messageLabel.centerXAnchor constraintEqualToAnchor:loginVC.view.centerXAnchor],
      [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
      [messageLabel.leadingAnchor constraintEqualToAnchor:loginVC.view.leadingAnchor constant:40],
      [messageLabel.trailingAnchor constraintEqualToAnchor:loginVC.view.trailingAnchor constant:-40],
      
      [loginButton.centerXAnchor constraintEqualToAnchor:loginVC.view.centerXAnchor],
      [loginButton.topAnchor constraintEqualToAnchor:messageLabel.bottomAnchor constant:40],
      [loginButton.widthAnchor constraintEqualToConstant:280],
      [loginButton.heightAnchor constraintEqualToConstant:54]
    ]];
    
    loginWindow.rootViewController = loginVC;
    [loginWindow makeKeyAndVisible];
    
    // Update scene delegate's window
    if ([windowScene.delegate respondsToSelector:@selector(setWindow:)]) {
      [(id)windowScene.delegate setWindow:loginWindow];
    }
  }
}

- (void)setupDock {
  CGFloat w = MIN(self.view.bounds.size.width - 32, 500);
  CGFloat y = self.view.bounds.size.height - 80 - 20;
  self.dock = [[HIAHAppLauncher alloc]
      initWithFrame:CGRectMake((self.view.bounds.size.width - w) / 2, y - 240,
                               w, 320)];
  self.dock.delegate = self;
  self.dock.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
                               UIViewAutoresizingFlexibleLeftMargin |
                               UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:self.dock];
  [self updateDock];

  // Listen for app installation notifications
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(refreshApps)
                                               name:@"HIAHDesktopRefreshApps"
                                             object:nil];
}

- (void)refreshApps {
  NSLog(@"[Desktop] Refreshing app list");
  [self.dock refreshApps];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  for (CALayer *l in self.desktop.layer.sublayers) {
    if ([l isKindOfClass:[CAGradientLayer class]])
      l.frame = self.desktop.bounds;
  }
}

// Note: shouldAutorotate is deprecated in iOS 16+, rotation is handled by the
// system
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return UIInterfaceOrientationMaskAll;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)c {
  [super viewWillTransitionToSize:size withTransitionCoordinator:c];
  CGRect old = self.view.bounds;
  [c animateAlongsideTransition:nil
                     completion:^(id ctx) {
                       [self adjustWindowsFrom:old
                                            to:CGRectMake(0, 0, size.width,
                                                          size.height)];
                       [self updateDock];
                     }];
}

- (void)adjustWindowsFrom:(CGRect)old to:(CGRect)new {
  CGFloat sx = new.size.width / old.size.width,
          sy = new.size.height / old.size.height;
  UIEdgeInsets s = UIEdgeInsetsZero;
  if (@available(iOS 11.0, *))
    s = self.view.safeAreaInsets;
  CGRect safe = CGRectMake(s.left, s.top, new.size.width - s.left - s.right,
                           new.size.height - s.top - s.bottom);

  for (HIAHFloatingWindow *w in self.windows.allValues) {
    if (w.isMaximized) {
      w.frame = safe;
      continue;
    }
    CGRect f = CGRectMake(w.frame.origin.x * sx, w.frame.origin.y * sy,
                          w.frame.size.width * sx, w.frame.size.height * sy);
    f.origin.x =
        MAX(safe.origin.x, MIN(f.origin.x, CGRectGetMaxX(safe) - f.size.width));
    f.origin.y = MAX(safe.origin.y,
                     MIN(f.origin.y, CGRectGetMaxY(safe) - f.size.height));
    f.size.width = MAX(200, f.size.width);
    f.size.height = MAX(150, f.size.height);
    w.frame = f;
  }
}

#pragma mark - HIAHAppLauncherDelegate

- (void)appLauncher:(HIAHAppLauncher *)l
       didSelectApp:(NSString *)name
           bundleID:(NSString *)bid {
  [self launchApp:name bundleID:bid];
}

- (void)appLauncher:(HIAHAppLauncher *)l
    didRequestRestoreWindow:(NSInteger)wid {
  HIAHFloatingWindow *w = self.windows[@(wid)];
  if (w) {
    [w restore];
    [w bringToFront];
  }
}

#pragma mark - App Launching

- (void)launchApp:(NSString *)name bundleID:(NSString *)bid {
  NSLog(@"[Desktop] Launching app: %@", name);

  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  NSString *appPath = [[[HIAHFilesystem shared] appsPath]
      stringByAppendingPathComponent:[name stringByAppendingString:@".app"]];

  // Check if this is a bundled app (HIAHTop, HIAHInstaller, etc.) or a .ipa app
  BOOL isBundledApp =
      ([bid hasPrefix:@"com.aspauldingcode."] ||
       [bid isEqualToString:@"com.aspauldingcode.HIAHTop"] ||
       [bid isEqualToString:@"com.aspauldingcode.HIAHInstaller"] ||
       [bid isEqualToString:@"com.aspauldingcode.HIAHTerminal"]);

  // Explicitly check for sample apps to ensure they run in-process for now
  if ([bid containsString:@"Calculator"] || [bid containsString:@"Notes"] ||
      [bid containsString:@"Weather"] || [bid containsString:@"Timer"] ||
      [bid containsString:@"Canvas"]) {
    isBundledApp = YES;
  }

  NSInteger wid = self.nextWindowID;
  CGFloat ox = (self.windows.count % 5) * 30,
          oy = (self.windows.count % 5) * 30;
  CGRect f = CGRectMake(50 + ox, 80 + oy, 320, 480);
  if (CGRectGetMaxX(f) > self.desktop.bounds.size.width - 20)
    f.origin.x = 50;
  if (CGRectGetMaxY(f) > self.desktop.bounds.size.height - 100)
    f.origin.y = 80;

  self.nextWindowID++;
  HIAHFloatingWindow *w = [[HIAHFloatingWindow alloc] initWithFrame:f
                                                           windowID:wid
                                                              title:name];
  w.delegate = self;
  w.titleBarColor = [self colorFor:name];

  if (isBundledApp) {
    // Bundled apps: Load view controller directly (runs in-process)
    pid_t virtualPID = (pid_t)(1000 + wid);

    HIAHProcess *appProcess = [HIAHProcess processWithPath:appPath
                                                 arguments:@[]
                                               environment:@{}];
    appProcess.pid = virtualPID;
    appProcess.physicalPid = getpid(); // Runs in main process
    [kernel registerProcess:appProcess];
    NSLog(@"[Desktop] Registered %@ as PID %d (physical: %d)", name, virtualPID,
          getpid());

    [w setContentViewController:[self contentFor:name bundleID:bid]];
  } else {
    // .ipa apps: ALWAYS use extension-based loading
    // Do NOT attempt in-process loading - it will fail with code signature
    // errors and the binary hasn't been signed yet
    NSLog(@"[Desktop] Spawning .ipa app through HIAH Kernel extension: %@",
          name);

    // Stage app to App Group so the extension can access it
    NSString *stagedAppPath =
        [[HIAHFilesystem shared] stageAppForExtension:appPath];
    if (!stagedAppPath) {
      HIAHLogError(HIAHLogFilesystem, "Failed to stage app for extension: %s",
                   [name UTF8String]);
      UIViewController *errorVC = [[UIViewController alloc] init];
      errorVC.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
      UILabel *errorLabel = [[UILabel alloc] init];
      errorLabel.text =
          @"Failed to stage app.\nApp Group may not be configured.";
      errorLabel.numberOfLines = 0;
      errorLabel.textAlignment = NSTextAlignmentCenter;
      errorLabel.textColor = [UIColor redColor];
      errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
      [errorVC.view addSubview:errorLabel];
      [NSLayoutConstraint activateConstraints:@[
        [errorLabel.centerXAnchor
            constraintEqualToAnchor:errorVC.view.centerXAnchor],
        [errorLabel.centerYAnchor
            constraintEqualToAnchor:errorVC.view.centerYAnchor],
        [errorLabel.leadingAnchor
            constraintEqualToAnchor:errorVC.view.leadingAnchor
                           constant:20],
        [errorLabel.trailingAnchor
            constraintEqualToAnchor:errorVC.view.trailingAnchor
                           constant:-20]
      ]];
      [w setContentViewController:errorVC];
      [self.windows setObject:w forKey:@(wid)];
      [self.desktop addSubview:w];
      [self.stateMachine focusWindowWithID:wid];
      return;
    }

    NSLog(@"[Desktop] App staged at: %@", stagedAppPath);

    // Get the executable path from the STAGED bundle
    NSBundle *bundle = [NSBundle bundleWithPath:stagedAppPath];
    NSString *executableName =
        [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    if (!executableName) {
      executableName = name; // Fallback to app name
    }
    NSString *executablePath =
        [stagedAppPath stringByAppendingPathComponent:executableName];

    NSLog(@"[Desktop] Executable path: %@", executablePath);

    // Make sure the executable is executable and patched for loading
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:executablePath]) {
      chmod([executablePath UTF8String], 0755);
      NSLog(@"[Desktop] Set executable permissions");

      // CRITICAL: Patch to a dlopen-compatible Mach-O type (see HIAHMachOUtils)
      if ([HIAHMachOUtils patchBinaryToDylib:executablePath]) {
        NSLog(@"[Desktop] Patched binary for dynamic loading: %@",
              executablePath);
      }
    }

    // Spawn through HIAH Kernel and use window capture
    [kernel
        spawnVirtualProcessWithPath:executablePath
                          arguments:@[]
                        environment:@{}
                         completion:^(pid_t spawnedPID, NSError *error) {
                           dispatch_async(dispatch_get_main_queue(), ^{
                             if (error) {
                               NSLog(@"[Desktop] Failed to spawn %@: %@", name,
                                     error);
                               // Show error in window
                               UIViewController *errorVC =
                                   [[UIViewController alloc] init];
                               errorVC.view.backgroundColor =
                                   [UIColor colorWithWhite:0.05 alpha:1];
                               UILabel *errorLabel = [[UILabel alloc] init];
                               errorLabel.text = [NSString
                                   stringWithFormat:@"Failed to spawn:\n%@",
                                                    error.localizedDescription];
                               errorLabel.numberOfLines = 0;
                               errorLabel.textAlignment = NSTextAlignmentCenter;
                               errorLabel.textColor = [UIColor redColor];
                               errorLabel
                                   .translatesAutoresizingMaskIntoConstraints =
                                   NO;
                               [errorVC.view addSubview:errorLabel];
                               [NSLayoutConstraint activateConstraints:@[
                                 [errorLabel.centerXAnchor
                                     constraintEqualToAnchor:
                                         errorVC.view.centerXAnchor],
                                 [errorLabel.centerYAnchor
                                     constraintEqualToAnchor:
                                         errorVC.view.centerYAnchor],
                                 [errorLabel.leadingAnchor
                                     constraintEqualToAnchor:errorVC.view
                                                                 .leadingAnchor
                                                    constant:20],
                                 [errorLabel.trailingAnchor
                                     constraintEqualToAnchor:errorVC.view
                                                                 .trailingAnchor
                                                    constant:-20]
                               ]];
                               [w setContentViewController:errorVC];
                             } else {
                               NSLog(@"[Desktop] Process spawned with PID %d, "
                                     @"setting up window capture...",
                                     spawnedPID);

                               // Use HIAHAppWindowSession to capture the app's
                               // UI
                               HIAHProcess *process =
                                   [kernel processForPID:spawnedPID];
                               if (process) {
                                 HIAHAppWindowSession *session =
                                     [[HIAHAppWindowSession alloc]
                                         initWithProcess:process
                                                  kernel:kernel];

                                 // HIAHAppWindowSession IS a UIViewController,
                                 // use it directly
                                 [w setContentViewController:session];

                                 // Wait longer for the extension process to
                                 // fully initialize before creating scene
                                 // Extension processes need more time to
                                 // register with FrontBoard and initialize UI
                                 // capabilities
                                 dispatch_after(
                                     dispatch_time(
                                         DISPATCH_TIME_NOW,
                                         (int64_t)(0.8 * NSEC_PER_SEC)),
                                     dispatch_get_main_queue(), ^{
                                       // Re-fetch process to ensure we have
                                       // latest physical PID
                                       HIAHProcess *updatedProcess =
                                           [kernel processForPID:spawnedPID];
                                       if (updatedProcess &&
                                           updatedProcess.physicalPid > 0) {
                                         session.process = updatedProcess;
                                       }

                                       // Open the window session to capture the
                                       // app's scene
                                       UIWindowScene *windowScene =
                                           self.view.window.windowScene;
                                       BOOL opened = [session
                                             openWindowWithScene:windowScene
                                           withSessionIdentifier:wid];

                                       if (opened) {
                                         HIAHLogInfo(
                                             HIAHLogWindowServer,
                                             "Window capture successful for %s "
                                             "(PID %d)",
                                             [name UTF8String], spawnedPID);
                                       } else {
                                         HIAHLogError(
                                             HIAHLogWindowServer,
                                             "Window capture failed for %s "
                                             "(PID %d) - process may not be "
                                             "ready",
                                             [name UTF8String], spawnedPID);
                                       }
                                     });
                               }
                             }
                           });
                         }];

    // Set placeholder content initially
    UIViewController *placeholderVC = [[UIViewController alloc] init];
    placeholderVC.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    UILabel *loadingLabel = [[UILabel alloc] init];
    loadingLabel.text = [NSString stringWithFormat:@"Starting %@...", name];
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    loadingLabel.textColor = [UIColor whiteColor];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [placeholderVC.view addSubview:loadingLabel];
    [NSLayoutConstraint activateConstraints:@[
      [loadingLabel.centerXAnchor
          constraintEqualToAnchor:placeholderVC.view.centerXAnchor],
      [loadingLabel.centerYAnchor
          constraintEqualToAnchor:placeholderVC.view.centerYAnchor]
    ]];
    [w setContentViewController:placeholderVC];
  }

  // IMPORTANT: Store window in dictionary BEFORE focusing so delegate callback
  // can find it
  self.windows[@(wid)] = w;

  [self.stateMachine registerWindowWithID:wid];
  [self.stateMachine focusWindowWithID:wid];

  w.alpha = 0;
  w.transform = CGAffineTransformMakeScale(0.8, 0.8);
  [self.desktop addSubview:w];
  [UIView animateWithDuration:0.3
                        delay:0
       usingSpringWithDamping:0.8
        initialSpringVelocity:0.5
                      options:0
                   animations:^{
                     w.alpha = 1;
                     w.transform = CGAffineTransformIdentity;
                   }
                   completion:nil];
  [self updateStatus];
}

- (UIViewController *)createProcessOutputViewControllerForApp:(NSString *)name
                                               executablePath:
                                                   (NSString *)execPath {
  // Create a view controller that will spawn and display the process
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];

  // Create a text view for output
  UITextView *outputView = [[UITextView alloc] init];
  outputView.backgroundColor = [UIColor blackColor];
  outputView.textColor = [UIColor greenColor];
  outputView.font = [UIFont monospacedSystemFontOfSize:12
                                                weight:UIFontWeightRegular];
  outputView.editable = NO;
  outputView.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:outputView];

  [NSLayoutConstraint activateConstraints:@[
    [outputView.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
    [outputView.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
    [outputView.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
    [outputView.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
  ]];

  // Spawn the process through HIAH Kernel
  HIAHKernel *kernel = [HIAHKernel sharedKernel];

  outputView.text =
      [NSString stringWithFormat:@"[HIAH Kernel] Spawning %@...\n", name];
  outputView.text =
      [outputView.text stringByAppendingFormat:@"Executable: %@\n\n", execPath];

  [kernel
      spawnVirtualProcessWithPath:execPath
                        arguments:@[]
                      environment:@{}
                       completion:^(pid_t pid, NSError *error) {
                         dispatch_async(dispatch_get_main_queue(), ^{
                           if (error) {
                             outputView.text = [outputView.text
                                 stringByAppendingFormat:
                                     @"Failed to spawn: %@\n\n",
                                     error.localizedDescription];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"This may be because:\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • The app requires a separate process "
                                     @"(not yet supported)\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • The app creates its own windows "
                                     @"(UIKit apps)\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • The binary is incompatible\n\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"HIAH Kernel currently supports:\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • Command-line tools\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • Dylib-based apps\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"  • Console applications\n"];
                           } else {
                             outputView.text = [outputView.text
                                 stringByAppendingFormat:
                                     @"Process spawned with PID %d\n\n", pid];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"--- Process Output ---\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"(Waiting for output...)\n\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"Note: UIKit apps won't display here.\n"];
                             outputView.text = [outputView.text
                                 stringByAppendingString:
                                     @"They need window capture hooks to be "
                                     @"visible.\n"];
                           }
                         });
                       }];

  return vc;
}

- (UIColor *)colorFor:(NSString *)name {
  // Default dark color for all windows
  return [UIColor colorWithWhite:0.15 alpha:0.98];
}

- (UIViewController *)contentFor:(NSString *)name bundleID:(NSString *)bid {
  // Built-in apps use embedded view controllers
  if ([bid isEqualToString:@"com.aspauldingcode.HIAHTop"]) {
    return [[HIAHTopViewController alloc] init];
  }

  if ([bid isEqualToString:@"com.aspauldingcode.HIAHInstaller"]) {
    return [[HIAHInstallerViewController alloc] init];
  }

  // Use Swift bridge for SwiftUI apps (Notes, Calculator, Timer, Weather,
  // Canvas, Terminal) The Swift bridge returns UIHostingController for these
  // apps
  Class BridgeClass = NSClassFromString(@"HIAHDesktop.HIAHSwiftBridge");
  if (!BridgeClass) {
    // Try without module prefix
    BridgeClass = NSClassFromString(@"HIAHSwiftBridge");
  }
  NSLog(@"[Desktop] Swift bridge class: %@", BridgeClass);

  if (BridgeClass) {
    SEL selector = NSSelectorFromString(@"viewControllerForBundleID:");
    if ([BridgeClass respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      UIViewController *swiftVC = [BridgeClass performSelector:selector
                                                    withObject:bid];
#pragma clang diagnostic pop
      NSLog(@"[Desktop] Swift bridge returned: %@ for bundleID: %@", swiftVC,
            bid);
      if (swiftVC) {
        return swiftVC;
      }
    } else {
      NSLog(@"[Desktop] Swift bridge does not respond to selector: "
            @"viewControllerForBundleID:");
    }
  }

  // For known SwiftUI apps that should have loaded via bridge, don't try bundle
  // loading
  if ([bid containsString:@"Notes"] || [bid containsString:@"Calculator"] ||
      [bid containsString:@"Timer"] || [bid containsString:@"Weather"] ||
      [bid containsString:@"Canvas"] || [bid containsString:@"Terminal"] ||
      [bid containsString:@"HIAHTerminal"]) {
    NSLog(@"[Desktop] SwiftUI app %@ - bridge failed, showing error", bid);
    UIViewController *errorVC = [[UIViewController alloc] init];
    errorVC.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString
        stringWithFormat:
            @"Failed to load SwiftUI app:\n%@\n\nSwift bridge not found.",
            name];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor orangeColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [errorVC.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [label.centerXAnchor constraintEqualToAnchor:errorVC.view.centerXAnchor],
      [label.centerYAnchor constraintEqualToAnchor:errorVC.view.centerYAnchor],
      [label.leadingAnchor constraintEqualToAnchor:errorVC.view.leadingAnchor
                                          constant:20],
      [label.trailingAnchor constraintEqualToAnchor:errorVC.view.trailingAnchor
                                           constant:-20]
    ]];
    return errorVC;
  }

  // Try to load other apps from Applications folder (for .ipa apps)
  NSString *appPath = nil;
  for (NSDictionary *app in self.dock.availableApps) {
    if ([app[@"bundleID"] isEqualToString:bid]) {
      appPath = app[@"path"];
      break;
    }
  }

  if (appPath) {
    UIViewController *loadedVC = [[self class] loadAppFromBundle:appPath];
    if (loadedVC) {
      return loadedVC;
    }
  }

  // Fallback: Loading placeholder
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];

  UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
  spinner.color = [UIColor whiteColor];
  spinner.translatesAutoresizingMaskIntoConstraints = NO;
  [spinner startAnimating];
  [vc.view addSubview:spinner];

  UILabel *lbl = [[UILabel alloc] init];
  lbl.text = [NSString stringWithFormat:@"Starting %@...", name];
  lbl.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
  lbl.textColor = [UIColor colorWithWhite:0.6 alpha:1];
  lbl.textAlignment = NSTextAlignmentCenter;
  lbl.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:lbl];

  [NSLayoutConstraint activateConstraints:@[
    [spinner.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [spinner.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor
                                          constant:-20],
    [lbl.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:16],
    [lbl.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor]
  ]];

  return vc;
}

- (void)updateStatus {
  UILabel *s = [self.desktop viewWithTag:100];
  if (s)
    s.text = [NSString
        stringWithFormat:@"%lu windows", (unsigned long)self.windows.count];
  [self updateDock];
}

- (void)updateDock {
  NSMutableArray<NSValue *> *frames = [NSMutableArray array];
  for (HIAHFloatingWindow *w in self.windows.allValues) {
    if (!w.hidden && w.alpha > 0.1 &&
        (w.superview == self.desktop ||
         [w.superview isDescendantOfView:self.view])) {
      [frames addObject:[NSValue valueWithCGRect:w.frame]];
    }
  }
  [self.stateMachine updateDockForWindowFrames:frames
                                      inBounds:self.desktop.bounds];
}

#pragma mark - HIAHFloatingWindowDelegate

- (void)floatingWindowDidClose:(HIAHFloatingWindow *)w {
  NSLog(@"[Desktop] Window %ld closed, unregistering process",
        (long)w.windowID);

  // Unregister the windowed app process from HIAH Kernel
  pid_t appPID = (pid_t)(1000 + w.windowID);
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  [kernel unregisterProcessWithPID:appPID];

  [self.stateMachine unregisterWindowWithID:w.windowID];
  [self.windows removeObjectForKey:@(w.windowID)];
  [self updateStatus];
}

- (void)floatingWindowDidBecomeActive:(HIAHFloatingWindow *)w {
  [self.view bringSubviewToFront:self.dock];
  [self.stateMachine focusWindowWithID:w.windowID];
  [self updateDock];
}

- (void)floatingWindowDidMinimize:(HIAHFloatingWindow *)w {
  [self.dock addMinimizedWindow:w.windowID
                          title:w.windowTitle
                       snapshot:[w captureSnapshot]];
  [self updateDock];
}

- (void)floatingWindowDidChangeFrame:(HIAHFloatingWindow *)w {
  [self updateDock];
}
- (void)floatingWindowDidUpdateFrameDuringDrag:(HIAHFloatingWindow *)w {
  [self updateDock];
}
- (void)floatingWindowDidEndDrag:(HIAHFloatingWindow *)w {
  [self updateDock];
}
- (void)floatingWindow:(HIAHFloatingWindow *)w isDraggingNearNotch:(BOOL)near {
}

- (void)ensureWindowInSafeArea:(HIAHFloatingWindow *)w {
  if (!w.superview)
    return;
  UIEdgeInsets s = UIEdgeInsetsZero;
  if (@available(iOS 11.0, *))
    s = w.superview.safeAreaInsets;
  CGRect safe = UIEdgeInsetsInsetRect(w.superview.bounds, s);
  CGRect f = w.frame;
  f.origin.x =
      MAX(safe.origin.x, MIN(f.origin.x, CGRectGetMaxX(safe) - f.size.width));
  f.origin.y =
      MAX(safe.origin.y,
          MIN(f.origin.y, CGRectGetMaxY(safe) - (w.isRolledUp ? 44 : 150)));
  if (!CGRectEqualToRect(f, w.frame))
    [UIView animateWithDuration:0.2
                     animations:^{
                       w.frame = f;
                     }];
}

#pragma mark - HIAHStateMachineDelegate

- (void)stateMachine:(HIAHStateMachine *)sm
    dockStateDidChange:(HIAHDockState)newState {
  [self.dock applyDockState:newState animated:YES];
}

- (void)stateMachine:(HIAHStateMachine *)sm
    windowFocusDidChange:(NSInteger)windowID
                 toState:(HIAHWindowFocusState)state {
  HIAHFloatingWindow *w = self.windows[@(windowID)];
  if (w) {
    [w setFocused:(state == HIAHWindowFocusStateFocused) animated:YES];
    if (state == HIAHWindowFocusStateFocused)
      [self.desktop bringSubviewToFront:w];
  }
}

- (void)stateMachine:(HIAHStateMachine *)sm
    windowDisplayDidChange:(NSInteger)windowID
                   toState:(HIAHWindowDisplayState)state {
  HIAHFloatingWindow *w = self.windows[@(windowID)];
  if (!w)
    return;
  switch (state) {
  case HIAHWindowDisplayStateMinimized:
    [w minimize];
    break;
  case HIAHWindowDisplayStateMaximized:
    if (!w.isMaximized)
      [w toggleMaximize];
    break;
  case HIAHWindowDisplayStateNormal:
    if (w.isMaximized)
      [w toggleMaximize];
    if (w.isMinimized)
      [w restore];
    break;
  case HIAHWindowDisplayStateRolledUp:
    if (!w.isRolledUp)
      [w toggleRollup];
    break;
  case HIAHWindowDisplayStateTiledLeft:
    [w tileLeft];
    break;
  case HIAHWindowDisplayStateTiledRight:
    [w tileRight];
    break;
  }
}

- (void)stateMachineDidRequestDockUpdate:(HIAHStateMachine *)sm {
}

@end

#pragma mark - AppDelegate

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface AppDelegate
    : UIResponder <UIApplicationDelegate, CPApplicationDelegate,
                   HIAHeDisplayModeDelegate, HIAHLoginViewControllerDelegate,
                   HIAHVPNReminderDelegate,
                   HIAHLocalDevVPNSetupDelegate>
#pragma clang diagnostic pop
@property(strong, nonatomic)
    NSMutableDictionary<NSValue *, UIWindow *> *windowsByScreen;
@property(strong, nonatomic)
    NSMutableDictionary<NSValue *, DesktopViewController *> *desktopsByScreen;
@property(strong, nonatomic) NSMutableSet<NSValue *> *managedScreens;
@property(strong, nonatomic) HIAHCarPlayController *carPlayController;
@property(strong, nonatomic) HIAHeDisplayMode *eDisplayMode;
@property(weak, nonatomic) DesktopViewController *activeDesktop;
@property(strong, nonatomic) UIWindow *window;  // Required by UIApplicationDelegate
@property(strong, nonatomic) UIWindow *mainWindow;
@property(strong, nonatomic) UIWindow *externalDisplayWindow;
@end

@implementation AppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
  NSLog(@"[AppDelegate] 🔵 Creating scene configuration for session: %@",
        session.role);

  UISceneConfiguration *config =
      [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                     sessionRole:session.role];
  config.delegateClass = NSClassFromString(@"SceneDelegate");

  NSLog(@"[AppDelegate] Scene config created, delegate class: %@",
        config.delegateClass);

  return config;
}

- (void)loginDidSucceed {
  NSLog(@"[AppDelegate] 🎉 loginDidSucceed delegate called");
  
  UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication]
                             .connectedScenes.anyObject;
  
  if (!windowScene) {
    NSLog(@"[AppDelegate] ❌ No window scene available");
    return;
  }
  
  // Start VPN state machine (starts em_proxy)
  HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
  [vpnSM sendEvent:HIAHVPNEventStart];
  
  // Always check VPN state after login (even if it was connected before)
  // This ensures we detect the current state, not a stale cached state
  
  // Wait a moment for state machine to update, then check
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    // Check VPN state - determines what screen to show
    NSInteger vpnState = [HIAHVPNReminderViewController checkVPNState];
    
    // Get the root view controller to present from
    UIViewController *rootVC = windowScene.windows.firstObject.rootViewController;
    UIViewController *presenterVC = rootVC.presentedViewController ?: rootVC;
    
    switch (vpnState) {
      case 0: // HIAHVPNCheckResultConnected
        NSLog(@"[AppDelegate] ✅ VPN connected - proceeding to Desktop");
        [self proceedToDesktopAfterLogin];
        break;
        
      case 1: // HIAHVPNCheckResultNeedsReminder
        NSLog(@"[AppDelegate] 📱 VPN setup done but disconnected - showing reminder");
        [HIAHVPNReminderViewController presentFrom:presenterVC delegate:self];
        break;
        
      case 2: // HIAHVPNCheckResultNeedsSetup
        NSLog(@"[AppDelegate] 🔧 VPN never configured - showing full setup wizard");
        [HIAHLocalDevVPNSetupViewController presentSetupFromViewController:presenterVC delegate:self];
        break;
        
      default:
        NSLog(@"[AppDelegate] ⚠️ Unknown VPN state %ld - proceeding anyway", (long)vpnState);
        [self proceedToDesktopAfterLogin];
        break;
    }
  });
}

// HIAHVPNSetupDelegate removed - using HIAHLocalDevVPNSetupDelegate instead

#pragma mark - HIAHVPNReminderDelegate

- (void)vpnReminderDidConnect {
  NSLog(@"[AppDelegate] ✅ VPN connected from reminder - transitioning to Desktop");
  [self proceedToDesktopAfterLogin];
}

- (void)vpnReminderDidSkip {
  NSLog(@"[AppDelegate] ⏭️ VPN reminder skipped - transitioning to Desktop anyway");
  NSLog(@"[AppDelegate] ⚠️ Some features (JIT, unsigned apps) may not work without VPN");
  [self proceedToDesktopAfterLogin];
}

- (void)vpnReminderRequestsFullSetup {
  NSLog(@"[AppDelegate] 🔧 User requested full VPN setup - showing wizard");
  
  UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication]
                             .connectedScenes.anyObject;
  if (!windowScene) return;
  
  UIViewController *rootVC = windowScene.windows.firstObject.rootViewController;
  UIViewController *presenterVC = rootVC.presentedViewController ?: rootVC;
  
  // If we have a presented VC, dismiss it first then present setup
  if (rootVC.presentedViewController) {
    [rootVC dismissViewControllerAnimated:YES completion:^{
      [HIAHLocalDevVPNSetupViewController presentSetupFromViewController:rootVC delegate:self];
    }];
  } else {
    [HIAHLocalDevVPNSetupViewController presentSetupFromViewController:presenterVC delegate:self];
  }
}

#pragma mark - HIAHLocalDevVPNSetupDelegate

- (void)localDevVPNSetupDidComplete {
  NSLog(@"[AppDelegate] ✅ LocalDevVPN setup completed - transitioning to Desktop");
  [self proceedToDesktopAfterLogin];
}

- (void)localDevVPNSetupDidCancel {
  NSLog(@"[AppDelegate] ⏭️ LocalDevVPN setup cancelled - transitioning to Desktop anyway");
  NSLog(@"[AppDelegate] ⚠️ Some features (JIT, unsigned apps) may not work without VPN");
  [self proceedToDesktopAfterLogin];
}

- (void)proceedToDesktopAfterLogin {
  UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication]
                             .connectedScenes.anyObject;
  
  if (!windowScene) {
    NSLog(@"[AppDelegate] ❌ No window scene available");
    return;
  }
  
  // Dismiss any presented view controller (login or setup)
  UIViewController *rootVC = windowScene.windows.firstObject.rootViewController;
  if (rootVC.presentedViewController) {
    [rootVC dismissViewControllerAnimated:YES completion:^{
      [self transitionToDesktop:windowScene];
    }];
  } else {
    [self transitionToDesktop:windowScene];
  }
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  NSLog(@"[AppDelegate] didFinishLaunchingWithOptions");

  // Initialize Filesystem & Kernel
  [[HIAHFilesystem shared] initialize];
  [HIAHKernel sharedKernel];
  
  // Initialize RefreshService for automatic certificate refresh
  // This handles the 7-day renewal and expiration notifications
  Class refreshServiceClass = NSClassFromString(@"HIAHDesktop.RefreshService");
  if (refreshServiceClass) {
    SEL sharedSel = NSSelectorFromString(@"shared");
    if ([refreshServiceClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      [refreshServiceClass performSelector:sharedSel];
#pragma clang diagnostic pop
      NSLog(@"[AppDelegate] RefreshService initialized for certificate auto-refresh");
    }
  }

  // Initialize signature bypass system (VPN + JIT) for dylib loading
  // This enables unsigned .ipa apps to run inside HIAH Desktop
  HIAHLogEx(HIAH_LOG_INFO, @"AppDelegate", @"Initializing signature bypass system...");
  HIAHSignatureBypass *bypass = [HIAHSignatureBypass sharedBypass];
  [bypass ensureBypassReadyWithCompletion:^(BOOL success, NSError * _Nullable error) {
    if (success) {
      HIAHLogEx(HIAH_LOG_INFO, @"AppDelegate", @"Signature bypass system ready - unsigned apps can now run");
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"AppDelegate", @"Signature bypass initialization failed: %@", error);
      HIAHLogEx(HIAH_LOG_INFO, @"AppDelegate", @"Apps will need to be signed before loading");
    }
  }];

  // Register HIAH Desktop itself as a process
  HIAHProcess *desktopProcess =
      [HIAHProcess processWithPath:[[NSBundle mainBundle] executablePath]
                         arguments:@[]
                       environment:@{}];
  desktopProcess.pid = getpid();
  desktopProcess.physicalPid = getpid();
  [[HIAHKernel sharedKernel] registerProcess:desktopProcess];
  NSLog(@"[AppDelegate] Registered HIAH Desktop as PID %d", getpid());

  self.windowsByScreen = [NSMutableDictionary dictionary];
  self.desktopsByScreen = [NSMutableDictionary dictionary];
  self.managedScreens = [NSMutableSet set];

  // Listen for session validation failures - show login screen if session expires
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSessionValidationFailed:)
                                               name:@"HIAHAccountSessionValidationFailed"
                                             object:nil];
  
  // Listen for process exit notifications
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleProcessExited:)
             name:HIAHKernelProcessExitedNotification
           object:nil];

  self.eDisplayMode = [HIAHeDisplayMode shared];
  self.eDisplayMode.delegate = self;

  if (@available(iOS 12.0, *)) {
    self.carPlayController = [HIAHCarPlayController sharedController];
  }

  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

  // Show Login VC
  HIAHLoginViewController *loginVC = [[HIAHLoginViewController alloc] init];
  loginVC.delegate = self;
  self.window.rootViewController = loginVC;
  [self.window makeKeyAndVisible];

  return YES;
}

- (void)handleSessionValidationFailed:(NSNotification *)notification {
  NSLog(@"[AppDelegate] ⚠️ Session validation failed - user must re-authenticate");
  
  // Dismiss desktop and show login screen
  dispatch_async(dispatch_get_main_queue(), ^{
    // Find the main window scene
    UIWindowScene *mainScene = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.screen == [UIScreen mainScreen] || mainScene == nil) {
          mainScene = ws;
        }
      }
    }
    
    if (mainScene) {
      // Get SceneDelegate to show login gate
      id sceneDelegate = mainScene.delegate;
      if (sceneDelegate && [sceneDelegate respondsToSelector:@selector(showLoginGate:appDelegate:)]) {
        [sceneDelegate performSelector:@selector(showLoginGate:appDelegate:) withObject:mainScene withObject:self];
        NSLog(@"[AppDelegate] ✅ Login gate shown after session validation failure");
      } else {
        // Fallback: Create new login window
        UIWindow *loginWindow = [[UIWindow alloc] initWithWindowScene:mainScene];
        HIAHLoginViewController *loginVC = [[HIAHLoginViewController alloc] init];
        loginVC.delegate = self;
        loginWindow.rootViewController = loginVC;
        [loginWindow makeKeyAndVisible];
        NSLog(@"[AppDelegate] ✅ Login window shown after session validation failure");
      }
    } else {
      NSLog(@"[AppDelegate] ⚠️ Could not find window scene to show login");
    }
  });
}

- (void)handleProcessExited:(NSNotification *)notification {
  // Process was killed - close its window
  NSNumber *pidNum = notification.userInfo[@"pid"];
  if (!pidNum)
    return;

  pid_t exitedPID = pidNum.intValue;

  // Windowed apps: PID = 1000 + windowID
  if (exitedPID >= 1000 && exitedPID < 10000) {
    NSInteger windowID = exitedPID - 1000;

    for (DesktopViewController *desktop in self.desktopsByScreen.allValues) {
      HIAHFloatingWindow *window = desktop.windows[@(windowID)];
      if (window) {
        NSLog(@"[AppDelegate] Process %d killed, closing window '%@'",
              exitedPID, window.windowTitle);
        dispatch_async(dispatch_get_main_queue(), ^{
          [window close];
        });
        return;
      }
    }
  }
}

- (void)application:(UIApplication *)app
    didConnectCarInterfaceController:(CPInterfaceController *)ic
                            toWindow:(CPWindow *)w API_AVAILABLE(ios(12.0)) {
  if (!self.carPlayController)
    self.carPlayController = [HIAHCarPlayController sharedController];
  // Get main screen from connected scenes
  UIScreen *mainScreen = [UIScreen mainScreen]; // Fallback
  for (UIScene *scene in app.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *ws = (UIWindowScene *)scene;
      if (ws.screen) {
        mainScreen = ws.screen;
        break;
      }
    }
  }
  NSValue *k = [NSValue valueWithNonretainedObject:mainScreen];
  self.carPlayController.mainDesktop = self.desktopsByScreen[k];
  [self.carPlayController application:app
      didConnectCarInterfaceController:ic
                              toWindow:w];
}

- (void)application:(UIApplication *)app
    didDisconnectCarInterfaceController:(CPInterfaceController *)ic
                             fromWindow:(CPWindow *)w API_AVAILABLE(ios(12.0)) {
  [self.carPlayController application:app
      didDisconnectCarInterfaceController:ic
                               fromWindow:w];
}

#pragma mark - HIAHeDisplayModeDelegate

- (void)eDisplayMode:(HIAHeDisplayMode *)mode
    willActivateOnScreen:(UIScreen *)extScreen {
  NSLog(@"[eDisplay] Activating for screen: %@", extScreen);

  // Get existing window/desktop created by SceneDelegate
  NSValue *extKey = [NSValue valueWithNonretainedObject:extScreen];
  // Get main screen from connected scenes
  UIScreen *mainScreen = [UIScreen mainScreen]; // Fallback
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *ws = (UIWindowScene *)scene;
      if (ws.screen && ws.screen != extScreen) {
        mainScreen = ws.screen;
        break;
      }
    }
  }
  NSValue *mainKey = [NSValue valueWithNonretainedObject:mainScreen];

  UIWindow *extWin = self.windowsByScreen[extKey];
  DesktopViewController *extDesktop = self.desktopsByScreen[extKey];
  DesktopViewController *mainDesktop = self.desktopsByScreen[mainKey];

  if (!extWin || !extDesktop) {
    NSLog(@"[eDisplay] ERROR: Scene hasn't created window yet - waiting");
    return;
  }

  // Transfer windows from main to external
  if (mainDesktop && mainDesktop.windows.count > 0) {
    for (NSNumber *wid in [mainDesktop.windows.allKeys copy]) {
      HIAHFloatingWindow *w = mainDesktop.windows[wid];
      [w removeFromSuperview];
      [mainDesktop.windows removeObjectForKey:wid];
      w.delegate = extDesktop;
      [extDesktop.desktop addSubview:w];
      extDesktop.windows[wid] = w;
    }
    [mainDesktop updateStatus];
    [extDesktop updateStatus];
  }

  // Activate eDisplay mode
  [mode activateWithExternalScreen:extScreen
                    existingWindow:extWin
             desktopViewController:extDesktop];

  // Hide main window
  UIWindow *mainWin = self.windowsByScreen[mainKey];
  if (mainWin) {
    mainWin.hidden = YES;
    self.mainWindow = mainWin;
  }

  self.activeDesktop = extDesktop;
  self.externalDisplayWindow = extWin;

  if (@available(iOS 12.0, *)) {
    self.carPlayController.mainDesktop = extDesktop;
  }
}

- (void)eDisplayModeDidActivate:(HIAHeDisplayMode *)mode
                       onScreen:(UIScreen *)s {
  [self.activeDesktop updateStatus];
}

- (void)eDisplayModeDidDeactivate:(HIAHeDisplayMode *)mode {
  NSLog(@"[eDisplay] Deactivated - restoring main screen");

  // Get main screen from connected scenes
  UIScreen *mainScreen = [UIScreen mainScreen]; // Fallback
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *ws = (UIWindowScene *)scene;
      if (ws.screen) {
        mainScreen = ws.screen;
        break;
      }
    }
  }
  NSValue *mainKey = [NSValue valueWithNonretainedObject:mainScreen];
  DesktopViewController *mainDesktop = self.desktopsByScreen[mainKey];
  DesktopViewController *extDesktop = self.activeDesktop;

  // Transfer windows back to main
  if (mainDesktop && extDesktop && extDesktop != mainDesktop) {
    for (NSNumber *wid in [extDesktop.windows.allKeys copy]) {
      HIAHFloatingWindow *w = extDesktop.windows[wid];
      [w removeFromSuperview];
      [extDesktop.windows removeObjectForKey:wid];
      w.delegate = mainDesktop;
      [mainDesktop.desktop addSubview:w];
      mainDesktop.windows[wid] = w;
    }
    [mainDesktop updateStatus];
  }

  // Show main window
  if (self.mainWindow) {
    self.mainWindow.hidden = NO;
    [self.mainWindow makeKeyAndVisible];
  }

  self.activeDesktop = mainDesktop;
  self.externalDisplayWindow = nil;

  if (@available(iOS 12.0, *)) {
    self.carPlayController.mainDesktop = mainDesktop;
  }
}

- (void)eDisplayMode:(HIAHeDisplayMode *)m didReceiveTapAtCursor:(CGPoint)p {
  DesktopViewController *d = self.activeDesktop;
  if (!d)
    return;

  // Tap on window
  for (HIAHFloatingWindow *w in [d.windows.allValues reverseObjectEnumerator]) {
    if (!w.hidden && CGRectContainsPoint(w.frame, p)) {
      [w bringToFront];
      UIView *hit = [w hitTest:[w convertPoint:p fromView:w.superview]
                     withEvent:nil];
      if ([hit isKindOfClass:[UIButton class]]) {
        [(UIButton *)hit
            sendActionsForControlEvents:UIControlEventTouchUpInside];
      }
      return;
    }
  }

  // Tap on dock
  if (CGRectContainsPoint(d.dock.frame, p)) {
    UIView *hit = [d.dock hitTest:[d.dock convertPoint:p
                                              fromView:d.dock.superview]
                        withEvent:nil];
    if ([hit isKindOfClass:[UIButton class]]) {
      [(UIButton *)hit sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else if ([hit isKindOfClass:[UICollectionViewCell class]] &&
               hit.tag < d.dock.availableApps.count) {
      NSDictionary *app = d.dock.availableApps[hit.tag];
      [d launchApp:app[@"name"] bundleID:app[@"bundleID"]];
    }
  }
}

- (void)eDisplayMode:(HIAHeDisplayMode *)m
    didReceiveDoubleTapAtCursor:(CGPoint)p {
  for (HIAHFloatingWindow *w in
       [self.activeDesktop.windows.allValues reverseObjectEnumerator]) {
    if (!w.hidden && CGRectContainsPoint(w.frame, p) &&
        [w convertPoint:p fromView:w.superview].y < 32) {
      [w toggleMaximize];
      return;
    }
  }
}

// MARK: - Authentication Check

- (BOOL)checkAuthentication {
  // CRITICAL: Check actual authentication state from HIAHAccountManager
  // This ensures we check if the session is validated, not just if cached data exists
  // If session validation failed, isAuthenticated will be false even if cached data exists
  
  Class accountManagerClass = NSClassFromString(@"HIAHAccountManager");
  if (accountManagerClass) {
    SEL sharedSel = NSSelectorFromString(@"shared");
    if ([accountManagerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      id accountManager = [accountManagerClass performSelector:sharedSel];
#pragma clang diagnostic pop
      if (accountManager) {
        SEL isAuthenticatedSel = NSSelectorFromString(@"isAuthenticated");
        if ([accountManager respondsToSelector:isAuthenticatedSel]) {
          // Wait a moment for session validation to complete (if in progress)
          // Session restoration happens asynchronously on startup, so we need to give it time
          for (int i = 0; i < 10; i++) {
            NSMethodSignature *sig = [accountManager methodSignatureForSelector:isAuthenticatedSel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:accountManager];
            [inv setSelector:isAuthenticatedSel];
            [inv invoke];
            BOOL isAuthenticated = NO;
            [inv getReturnValue:&isAuthenticated];
            
            if (isAuthenticated) {
              NSLog(@"[Auth] ✅ User is authenticated (session validated)");
              return YES;
            }
            
            // If not authenticated yet, wait a bit (session validation might be in progress)
            if (i < 9) {
              usleep(200000); // 200ms delay
            }
          }
          
          // After waiting, check one more time
          NSMethodSignature *sig = [accountManager methodSignatureForSelector:isAuthenticatedSel];
          NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
          [inv setTarget:accountManager];
          [inv setSelector:isAuthenticatedSel];
          [inv invoke];
          BOOL isAuthenticated = NO;
          [inv getReturnValue:&isAuthenticated];
          
          if (!isAuthenticated) {
            NSLog(@"[Auth] ❌ User is NOT authenticated (no valid session after validation)");
            return NO;
          }
        }
      }
    }
  }
  
  // Fallback: Check for cached session data (for backwards compatibility)
  // But this should not be the primary check - session must be validated
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *appleID = [defaults stringForKey:@"HIAH_Account_AppleID"];
  NSString *dsid = [defaults stringForKey:@"HIAH_Account_DSID"];
  
  if (!appleID || !dsid) {
    NSLog(@"[Auth] No saved Apple Account or DSID found");
    return NO;
  }
  
  // Check keychain for auth token
  NSDictionary *query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : @"com.aspauldingcode.HIAHDesktop.account",
    (__bridge id)kSecAttrAccount : @"authToken",
    (__bridge id)kSecReturnData : @YES
  };

  CFTypeRef result = NULL;
  OSStatus status =
      SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

  if (status == errSecSuccess && result != NULL) {
    CFRelease(result);
    NSLog(@"[Auth] ⚠️ Found cached session data but HIAHAccountManager not available - session may not be validated");
    // Return NO to be safe - we need actual validation
    return NO;
  }

  NSLog(@"[Auth] No auth token found in keychain");
  return NO;
}

- (void)showLoginWindow {
  // Create a blocking login window
  // Get windowScene from connected scenes (AppDelegate doesn't have windowScene
  // property)
  UIWindowScene *windowScene = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      windowScene = (UIWindowScene *)scene;
      break;
    }
  }

  UIWindow *loginWindow = nil;
  if (windowScene) {
    loginWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
  } else {
    // Fallback for iOS < 26.0 or when windowScene is not available
    loginWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  }
  loginWindow.windowLevel = UIWindowLevelAlert + 1;
  loginWindow.backgroundColor = [UIColor systemBackgroundColor];

  // Create login view controller
  UIViewController *loginVC = [[UIViewController alloc] init];
  loginVC.view.backgroundColor = [UIColor systemBackgroundColor];

  // Add message
  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = @"HIAH Desktop";
  titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:titleLabel];

  UILabel *messageLabel = [[UILabel alloc] init];
  messageLabel.text = @"Please sign in with Apple Account\n\nLaunch HIAH "
                      @"LoginWindow to authenticate";
  messageLabel.font = [UIFont systemFontOfSize:16];
  messageLabel.textAlignment = NSTextAlignmentCenter;
  messageLabel.numberOfLines = 0;
  messageLabel.textColor = [UIColor secondaryLabelColor];
  messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:messageLabel];

  UIButton *loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [loginButton setTitle:@"Open HIAH LoginWindow" forState:UIControlStateNormal];
  [loginButton setTitleColor:[UIColor whiteColor]
                    forState:UIControlStateNormal];
  loginButton.backgroundColor = [UIColor systemBlueColor];
  loginButton.layer.cornerRadius = 12;
  loginButton.titleLabel.font = [UIFont systemFontOfSize:18
                                                  weight:UIFontWeightSemibold];
  loginButton.translatesAutoresizingMaskIntoConstraints = NO;
  [loginButton addTarget:self
                  action:@selector(openLoginWindow:)
        forControlEvents:UIControlEventTouchUpInside];
  [loginVC.view addSubview:loginButton];

  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [titleLabel.centerYAnchor constraintEqualToAnchor:loginVC.view.centerYAnchor
                                             constant:-80],

    [messageLabel.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                           constant:20],
    [messageLabel.leadingAnchor
        constraintEqualToAnchor:loginVC.view.leadingAnchor
                       constant:40],
    [messageLabel.trailingAnchor
        constraintEqualToAnchor:loginVC.view.trailingAnchor
                       constant:-40],

    [loginButton.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [loginButton.topAnchor constraintEqualToAnchor:messageLabel.bottomAnchor
                                          constant:40],
    [loginButton.widthAnchor constraintEqualToConstant:250],
    [loginButton.heightAnchor constraintEqualToConstant:50]
  ]];

  loginWindow.rootViewController = loginVC;
  [loginWindow makeKeyAndVisible];

  // Don't set self.window in scene-based apps!

  // Listen for authentication success (from Swift login view)
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleAuthenticationSuccess:)
             name:@"HIAHLoginSuccess"
           object:nil];
  
  // Also listen for the legacy notification name
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleAuthenticationSuccess:)
             name:@"HIAHAuthenticationSuccess"
           object:nil];
}

- (void)openLoginWindow:(id)sender {
  NSLog(@"[AppDelegate] Showing HIAH LoginWindow");

  // Present the actual HIAHLoginViewController
  Class loginVCClass = NSClassFromString(@"HIAHDesktop.HIAHLoginViewController");
  if (!loginVCClass) {
    // Try without module prefix
    loginVCClass = NSClassFromString(@"HIAHLoginViewController");
  }
  
  UIViewController *loginVC = nil;
  if (loginVCClass) {
    loginVC = [[loginVCClass alloc] init];
    NSLog(@"[AppDelegate] Created HIAHLoginViewController");
    
    // Set delegate for login success callback
    if ([loginVC respondsToSelector:@selector(setDelegate:)]) {
      [loginVC performSelector:@selector(setDelegate:) withObject:self];
      NSLog(@"[AppDelegate] Set delegate on HIAHLoginViewController");
    }
  } else {
    // Fallback: Create a simple login form in Objective-C
    NSLog(@"[AppDelegate] HIAHLoginViewController not found, using fallback");
    loginVC = [self createFallbackLoginViewController];
  }
  
  // Present as full screen modal
  loginVC.modalPresentationStyle = UIModalPresentationFullScreen;

  // Present from any available window scene
  UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication]
                             .connectedScenes.anyObject;
  UIViewController *presenter = scene.windows.firstObject.rootViewController;
  
  if (presenter) {
    [presenter presentViewController:loginVC animated:YES completion:nil];
  } else {
    NSLog(@"[AppDelegate] ❌ No presenter available");
  }
}

- (UIViewController *)createFallbackLoginViewController {
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor systemBackgroundColor];
  
  // Title
  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = @"Sign in with Apple Account";
  titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:titleLabel];
  
  // Email field
  UITextField *emailField = [[UITextField alloc] init];
  emailField.placeholder = @"Apple Account email";
  emailField.borderStyle = UITextBorderStyleRoundedRect;
  emailField.keyboardType = UIKeyboardTypeEmailAddress;
  emailField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  emailField.translatesAutoresizingMaskIntoConstraints = NO;
  emailField.tag = 100;
  [vc.view addSubview:emailField];
  
  // Password field
  UITextField *passwordField = [[UITextField alloc] init];
  passwordField.placeholder = @"Password";
  passwordField.borderStyle = UITextBorderStyleRoundedRect;
  passwordField.secureTextEntry = YES;
  passwordField.translatesAutoresizingMaskIntoConstraints = NO;
  passwordField.tag = 101;
  [vc.view addSubview:passwordField];
  
  // Login button
  UIButton *loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [loginButton setTitle:@"Sign In" forState:UIControlStateNormal];
  [loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  loginButton.backgroundColor = [UIColor systemBlueColor];
  loginButton.layer.cornerRadius = 8;
  loginButton.translatesAutoresizingMaskIntoConstraints = NO;
  [loginButton addTarget:self action:@selector(handleFallbackLogin:) forControlEvents:UIControlEventTouchUpInside];
  [vc.view addSubview:loginButton];
  
  // Status label
  UILabel *statusLabel = [[UILabel alloc] init];
  statusLabel.textAlignment = NSTextAlignmentCenter;
  statusLabel.numberOfLines = 0;
  statusLabel.textColor = [UIColor secondaryLabelColor];
  statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
  statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  statusLabel.tag = 102;
  [vc.view addSubview:statusLabel];
  
  // Close button
  UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [closeButton setTitle:@"Cancel" forState:UIControlStateNormal];
  closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  [closeButton addTarget:vc action:@selector(dismissViewControllerAnimated:completion:) forControlEvents:UIControlEventTouchUpInside];
  [vc.view addSubview:closeButton];
  
  // Layout
  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [titleLabel.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:60],
    
    [emailField.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [emailField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:40],
    [emailField.widthAnchor constraintEqualToConstant:280],
    [emailField.heightAnchor constraintEqualToConstant:44],
    
    [passwordField.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [passwordField.topAnchor constraintEqualToAnchor:emailField.bottomAnchor constant:16],
    [passwordField.widthAnchor constraintEqualToConstant:280],
    [passwordField.heightAnchor constraintEqualToConstant:44],
    
    [loginButton.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [loginButton.topAnchor constraintEqualToAnchor:passwordField.bottomAnchor constant:24],
    [loginButton.widthAnchor constraintEqualToConstant:280],
    [loginButton.heightAnchor constraintEqualToConstant:44],
    
    [statusLabel.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [statusLabel.topAnchor constraintEqualToAnchor:loginButton.bottomAnchor constant:16],
    [statusLabel.widthAnchor constraintEqualToConstant:280],
    
    [closeButton.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [closeButton.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor constant:24],
  ]];
  
  return vc;
}

- (void)handleFallbackLogin:(UIButton *)sender {
  UIViewController *vc = sender.superview.superview.nextResponder;
  while (vc && ![vc isKindOfClass:[UIViewController class]]) {
    vc = (UIViewController *)[(UIView *)vc nextResponder];
  }
  
  UITextField *emailField = [sender.superview viewWithTag:100];
  UITextField *passwordField = [sender.superview viewWithTag:101];
  UILabel *statusLabel = [sender.superview viewWithTag:102];
  
  NSString *email = emailField.text;
  NSString *password = passwordField.text;
  
  if (email.length == 0 || password.length == 0) {
    statusLabel.text = @"Please enter both email and password.";
    statusLabel.textColor = [UIColor systemRedColor];
    return;
  }
  
  statusLabel.text = @"Authenticating...";
  statusLabel.textColor = [UIColor secondaryLabelColor];
  sender.enabled = NO;
  
  // Call into Swift authentication via notification or direct call
  // For now, we'll use NSClassFromString to get the Swift singleton
  Class accountManagerClass = NSClassFromString(@"HIAHDesktop.HIAHAccountManager");
  if (accountManagerClass) {
    // The Swift code will handle authentication
    [[NSNotificationCenter defaultCenter] 
        postNotificationName:@"HIAHLoginAttempt" 
                      object:nil 
                    userInfo:@{@"email": email, @"password": password, @"statusLabel": statusLabel, @"button": sender}];
  } else {
    statusLabel.text = @"❌ Account manager not available";
    statusLabel.textColor = [UIColor systemRedColor];
    sender.enabled = YES;
  }
}

- (void)handleAuthenticationSuccess:(NSNotification *)notification {
  NSLog(@"[AppDelegate] 🎉 Authentication successful - transitioning to desktop");

  // Get the current window scene
  UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication]
                             .connectedScenes.anyObject;
  
  if (!windowScene) {
    NSLog(@"[AppDelegate] ❌ No window scene available");
    return;
  }
  
  // Dismiss any presented view controller (the login window)
  UIViewController *rootVC = windowScene.windows.firstObject.rootViewController;
  if (rootVC.presentedViewController) {
    [rootVC dismissViewControllerAnimated:YES completion:^{
      [self transitionToDesktop:windowScene];
    }];
  } else {
    [self transitionToDesktop:windowScene];
  }
}

- (void)transitionToDesktop:(UIWindowScene *)windowScene {
  NSLog(@"[AppDelegate] Creating desktop view");
  
  // Hide all existing windows in this scene (login gate, temp windows, etc.)
  NSArray *existingWindows = [windowScene.windows copy];
  for (UIWindow *oldWindow in existingWindows) {
    oldWindow.hidden = YES;
  }
  
  // Create the desktop window
  UIWindow *desktopWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
  desktopWindow.backgroundColor = [UIColor systemBackgroundColor];
  
  // Create the desktop view controller
  DesktopViewController *desktopVC = [[DesktopViewController alloc] init];
  desktopWindow.rootViewController = desktopVC;
  
  // Animate transition
  desktopWindow.alpha = 0;
  [desktopWindow makeKeyAndVisible];
  
  [UIView animateWithDuration:0.3 animations:^{
    desktopWindow.alpha = 1;
  } completion:^(BOOL finished) {
    NSLog(@"[AppDelegate] ✅ Desktop shown!");
  }];
  
  // Update the window property if SceneDelegate has it
  for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
    if ([scene.delegate respondsToSelector:@selector(setWindow:)]) {
      [(id)scene.delegate setWindow:desktopWindow];
    }
  }
}

@end

#pragma mark - SceneDelegate

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@end

@implementation SceneDelegate

- (void)showLoginGate:(UIWindowScene *)windowScene
          appDelegate:(AppDelegate *)appDelegate {
  NSLog(@"[SceneDelegate] Creating login gate window");

  // Create window for login gate
  UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
  window.backgroundColor = [UIColor systemBackgroundColor];

  // Create login gate view controller
  UIViewController *loginVC = [[UIViewController alloc] init];
  loginVC.view.backgroundColor = [UIColor systemBackgroundColor];

  // Title
  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = @"HIAH Desktop";
  titleLabel.font = [UIFont systemFontOfSize:40 weight:UIFontWeightBold];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:titleLabel];

  // House icon
  UIImageView *iconView = [[UIImageView alloc]
      initWithImage:[UIImage systemImageNamed:@"house.fill"]];
  iconView.tintColor = [UIColor systemBlueColor];
  iconView.contentMode = UIViewContentModeScaleAspectFit;
  iconView.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:iconView];

  // Message
  UILabel *messageLabel = [[UILabel alloc] init];
  messageLabel.text =
      @"Sign in with Apple Account to enable HIAH Desktop\n\nAuthentication "
      @"enables:\n• 7-day auto-refresh for HIAH Desktop\n• JIT via SideStore "
      @"VPN (like LiveProcess)\n• Bypass dyld signature validation\n• Run "
      @"extracted .ipa apps without re-signing";
  messageLabel.font = [UIFont systemFontOfSize:14];
  messageLabel.textAlignment = NSTextAlignmentCenter;
  messageLabel.numberOfLines = 0;
  messageLabel.textColor = [UIColor secondaryLabelColor];
  messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:messageLabel];

  // Login button
  UIButton *loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [loginButton setTitle:@"Sign In with Apple Account"
               forState:UIControlStateNormal];
  [loginButton setTitleColor:[UIColor whiteColor]
                    forState:UIControlStateNormal];
  loginButton.backgroundColor = [UIColor systemBlueColor];
  loginButton.layer.cornerRadius = 12;
  loginButton.titleLabel.font = [UIFont systemFontOfSize:18
                                                  weight:UIFontWeightSemibold];
  loginButton.translatesAutoresizingMaskIntoConstraints = NO;
  [loginButton addTarget:appDelegate
                  action:@selector(openLoginWindow:)
        forControlEvents:UIControlEventTouchUpInside];
  [loginVC.view addSubview:loginButton];

  // Footer
  UILabel *footerLabel = [[UILabel alloc] init];
  footerLabel.text = @"Powered by SideStore • AGPLv3";
  footerLabel.font = [UIFont systemFontOfSize:12];
  footerLabel.textColor = [UIColor tertiaryLabelColor];
  footerLabel.textAlignment = NSTextAlignmentCenter;
  footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [loginVC.view addSubview:footerLabel];

  // Layout
  [NSLayoutConstraint activateConstraints:@[
    [iconView.centerXAnchor constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [iconView.centerYAnchor constraintEqualToAnchor:loginVC.view.centerYAnchor
                                           constant:-120],
    [iconView.widthAnchor constraintEqualToConstant:100],
    [iconView.heightAnchor constraintEqualToConstant:100],

    [titleLabel.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor
                                         constant:20],

    [messageLabel.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                           constant:20],
    [messageLabel.leadingAnchor
        constraintEqualToAnchor:loginVC.view.leadingAnchor
                       constant:40],
    [messageLabel.trailingAnchor
        constraintEqualToAnchor:loginVC.view.trailingAnchor
                       constant:-40],

    [loginButton.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [loginButton.topAnchor constraintEqualToAnchor:messageLabel.bottomAnchor
                                          constant:40],
    [loginButton.widthAnchor constraintEqualToConstant:280],
    [loginButton.heightAnchor constraintEqualToConstant:54],

    [footerLabel.centerXAnchor
        constraintEqualToAnchor:loginVC.view.centerXAnchor],
    [footerLabel.bottomAnchor
        constraintEqualToAnchor:loginVC.view.safeAreaLayoutGuide.bottomAnchor
                       constant:-20]
  ]];

  window.rootViewController = loginVC;
  [window makeKeyAndVisible];
  self.window = window;

  NSLog(@"[SceneDelegate] Login gate shown");
}

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)opts {
  NSLog(@"[SceneDelegate] 🟢 scene:willConnectToSession called!");
  NSLog(@"[SceneDelegate] Scene: %@, class: %@", scene,
        NSStringFromClass([scene class]));

  if (![scene isKindOfClass:[UIWindowScene class]]) {
    HIAHLogError(HIAHLogWindowServer, "Not a UIWindowScene, skipping");
    return;
  }

  UIWindowScene *ws = (UIWindowScene *)scene;
  AppDelegate *ad = (AppDelegate *)[UIApplication sharedApplication].delegate;

  // CRITICAL: Check authentication BEFORE showing desktop
  if (![ad checkAuthentication]) {
    NSLog(@"[SceneDelegate] ❌ User not authenticated - showing login gate");
    [self showLoginGate:ws appDelegate:ad];
    return; // Don't create desktop
  }

  NSLog(@"[SceneDelegate] ✅ User authenticated");

  // Start VPN state machine
  [[HIAHVPNStateMachine shared] sendEvent:HIAHVPNEventStart];
  
  // Check if VPN setup is needed (for VPN/JIT features)
  if ([HIAHLocalDevVPNSetupViewController isSetupNeeded]) {
    NSLog(@"[SceneDelegate] 📱 VPN setup needed - showing setup wizard");
    
    // Create a temporary window to present from
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    UIViewController *tempVC = [[UIViewController alloc] init];
    tempVC.view.backgroundColor = [UIColor systemBackgroundColor];
    self.window.rootViewController = tempVC;
    [self.window makeKeyAndVisible];
    
    // Present setup wizard
    [HIAHLocalDevVPNSetupViewController presentSetupFromViewController:tempVC delegate:ad];
    return; // Setup wizard will trigger desktop creation when done
  }

  NSLog(@"[SceneDelegate] ✅ VPN ready - creating desktop");

  // Determine if this is the main screen or external screen
  // In iOS 26.0+, compare with first connected scene's screen
  UIScreen *mainScreen = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *firstWS = (UIWindowScene *)scene;
      if (firstWS.screen) {
        mainScreen = firstWS.screen;
        break;
      }
    }
  }
  if (!mainScreen) {
    mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
  }
  BOOL isExternal = (ws.screen != mainScreen);
  NSLog(@"[Scene] Connecting %@ screen: %@", isExternal ? @"EXTERNAL" : @"MAIN",
        ws.screen);

  // Create window and desktop
  NSLog(@"[Scene] Creating UIWindow...");
  self.window = [[UIWindow alloc] initWithWindowScene:ws];
  self.window.backgroundColor =
      [UIColor systemBlueColor]; // Debug: Should see blue
  NSLog(@"[Scene] Window created: %@", self.window);
  NSLog(@"[Scene] Creating DesktopViewController...");
  DesktopViewController *dvc = [[DesktopViewController alloc] init];
  dvc.screen = ws.screen;
  dvc.windowScene = ws;
  NSLog(@"[Scene] DesktopViewController created, setting as root...");

  self.window.rootViewController = dvc;
  NSLog(@"[Scene] Making window key and visible...");

  [self.window makeKeyAndVisible];
  HIAHLogDebug(HIAHLogWindowServer,
               "Window visible (Hidden:%d Alpha:%.2f Frame:%s)",
               self.window.hidden, self.window.alpha,
               [NSStringFromCGRect(self.window.frame) UTF8String]);

  // Store in AppDelegate
  NSValue *k = [NSValue valueWithNonretainedObject:ws.screen];
  ad.windowsByScreen[k] = self.window;
  ad.desktopsByScreen[k] = dvc;
  [ad.managedScreens addObject:k];

  // If external screen, activate eDisplay mode
  if (isExternal) {
    NSLog(@"[Scene] Activating eDisplay mode for external screen");

    // Transfer windows from main to external
    // Get main screen from connected scenes (excluding the current external
    // screen)
    UIScreen *externalScreen = ws.screen;         // Current external screen
    UIScreen *mainScreen = [UIScreen mainScreen]; // Fallback
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *sceneWS = (UIWindowScene *)scene;
        if (sceneWS.screen && sceneWS.screen != externalScreen) {
          mainScreen = sceneWS.screen;
          break;
        }
      }
    }
    NSValue *mainKey = [NSValue valueWithNonretainedObject:mainScreen];
    DesktopViewController *mainDesktop = ad.desktopsByScreen[mainKey];
    if (mainDesktop) {
      for (NSNumber *wid in [mainDesktop.windows.allKeys copy]) {
        HIAHFloatingWindow *w = mainDesktop.windows[wid];
        [w removeFromSuperview];
        [mainDesktop.windows removeObjectForKey:wid];
        w.delegate = dvc;
        [dvc.desktop addSubview:w];
        dvc.windows[wid] = w;
      }
    }

    // Activate eDisplay mode
    [ad.eDisplayMode activateWithExternalScreen:ws.screen
                                 existingWindow:self.window
                          desktopViewController:dvc];

    // Hide main window
    UIWindow *mainWin = ad.windowsByScreen[mainKey];
    if (mainWin) {
      mainWin.hidden = YES;
      ad.mainWindow = mainWin;
    }

    ad.activeDesktop = dvc;
    ad.externalDisplayWindow = self.window;
  } else {
    ad.activeDesktop = dvc;
    if (@available(iOS 12.0, *)) {
      ad.carPlayController.mainDesktop = dvc;
    }
  }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;
  UIWindowScene *ws = (UIWindowScene *)scene;

  // If external screen disconnected, deactivate eDisplay mode
  // Get main screen from connected scenes
  UIScreen *mainScreen = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *firstWS = (UIWindowScene *)scene;
      if (firstWS.screen && firstWS.screen != ws.screen) {
        mainScreen = firstWS.screen;
        break;
      }
    }
  }
  if (!mainScreen) {
    mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
  }
  if (ws.screen != mainScreen) {
    NSLog(@"[Scene] External screen disconnected");
    AppDelegate *ad = (AppDelegate *)[UIApplication sharedApplication].delegate;
    [ad.eDisplayMode deactivate];
  } else {
    // Main screen disconnected - cleanup all FrontBoard scenes
    NSLog(@"[Scene] Main screen disconnected - cleaning up all scenes");
    HIAHWindowServer *server = [HIAHWindowServer sharedWithWindowScene:ws];
    if (server) {
      [server closeAllWindows];
    }
  }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
  NSLog(@"[SceneDelegate] Scene became active");
  
  // Notify RefreshService that app is active - checks for refresh needs
  Class refreshServiceClass = NSClassFromString(@"HIAHDesktop.RefreshService");
  if (refreshServiceClass) {
    SEL sharedSel = NSSelectorFromString(@"shared");
    if ([refreshServiceClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      id refreshService = [refreshServiceClass performSelector:sharedSel];
#pragma clang diagnostic pop
      if (refreshService) {
        SEL activeSel = NSSelectorFromString(@"appDidBecomeActive");
        if ([refreshService respondsToSelector:activeSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          [refreshService performSelector:activeSel];
#pragma clang diagnostic pop
        }
      }
    }
  }
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
  NSLog(@"[SceneDelegate] Scene entered background");
  
  // Notify RefreshService to schedule notifications
  Class refreshServiceClass = NSClassFromString(@"HIAHDesktop.RefreshService");
  if (refreshServiceClass) {
    SEL sharedSel = NSSelectorFromString(@"shared");
    if ([refreshServiceClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      id refreshService = [refreshServiceClass performSelector:sharedSel];
#pragma clang diagnostic pop
      if (refreshService) {
        SEL backgroundSel = NSSelectorFromString(@"appDidEnterBackground");
        if ([refreshService respondsToSelector:backgroundSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          [refreshService performSelector:backgroundSel];
#pragma clang diagnostic pop
        }
      }
    }
  }
}

- (void)sceneWillResignActive:(UIScene *)scene {
}

@end

#pragma mark - CarPlay Scene

API_AVAILABLE(ios(14.0))
@interface HIAHCarPlaySceneDelegate
    : UIResponder <CPTemplateApplicationSceneDelegate>
@property(strong) CPInterfaceController *ic;
@property(strong) CPWindow *cw;
@end

@implementation HIAHCarPlaySceneDelegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)s
    didConnectInterfaceController:(CPInterfaceController *)ic {
  self.ic = ic;
  HIAHCarPlayController *cp = [HIAHCarPlayController sharedController];
  cp.interfaceController = ic;
  AppDelegate *ad = (AppDelegate *)[UIApplication sharedApplication].delegate;
  NSValue *k = [NSValue valueWithNonretainedObject:[UIScreen mainScreen]];
  cp.mainDesktop = ad.desktopsByScreen[k];
  [cp setupCarPlayInterface];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)s
    didDisconnectInterfaceController:(CPInterfaceController *)ic {
  self.ic = nil;
  HIAHCarPlayController *cp = [HIAHCarPlayController sharedController];
  cp.interfaceController = nil;
  cp.carWindow = nil;
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)s
    didConnectInterfaceController:(CPInterfaceController *)ic
                         toWindow:(CPWindow *)w API_AVAILABLE(ios(14.0)) {
  self.ic = ic;
  self.cw = w;
  HIAHCarPlayController *cp = [HIAHCarPlayController sharedController];
  cp.interfaceController = ic;
  cp.carWindow = w;
  AppDelegate *ad = (AppDelegate *)[UIApplication sharedApplication].delegate;
  NSValue *k = [NSValue valueWithNonretainedObject:[UIScreen mainScreen]];
  cp.mainDesktop = ad.desktopsByScreen[k];
  [cp setupCarPlayInterface];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)s
    didDisconnectInterfaceController:(CPInterfaceController *)ic
                          fromWindow:(CPWindow *)w API_AVAILABLE(ios(14.0)) {
  self.ic = nil;
  self.cw = nil;
  HIAHCarPlayController *cp = [HIAHCarPlayController sharedController];
  cp.interfaceController = nil;
  cp.carWindow = nil;
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([AppDelegate class]));
  }
}
