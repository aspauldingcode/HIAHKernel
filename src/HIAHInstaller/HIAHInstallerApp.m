/**
 * HIAHInstallerApp.m - HIAH Desktop App Installer
 * Handles .ipa installation to HIAH Desktop Applications folder
 */

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <zlib.h>
#import "../HIAHDesktop/HIAHFilesystem.h"
#import "../HIAHDesktop/HIAHMachOUtils.h"

@interface InstallerViewController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *browseButton;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation InstallerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    
    UILabel *title = [[UILabel alloc] init];
    title.text = @"HIAH Installer";
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Ready to install apps";
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    self.browseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.browseButton setTitle:@"Browse for .ipa" forState:UIControlStateNormal];
    [self.browseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.browseButton.backgroundColor = [UIColor systemBlueColor];
    self.browseButton.layer.cornerRadius = 12;
    self.browseButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    self.browseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.browseButton addTarget:self action:@selector(browseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.browseButton];
    
    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    self.logView.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 8;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];
    
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.browseButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.browseButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.browseButton.widthAnchor constraintEqualToConstant:200],
        [self.browseButton.heightAnchor constraintEqualToConstant:50],
        [self.logView.topAnchor constraintEqualToAnchor:self.browseButton.bottomAnchor constant:20],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]
    ]];
    
    [self log:@"HIAH Installer ready"];
    [self log:[NSString stringWithFormat:@"Install location: %@", [[HIAHFilesystem shared] appsPath]]];
}

- (void)browseTapped {
    UTType *ipaType = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
    NSArray *types = ipaType ? @[ipaType] : @[[UTType typeWithFilenameExtension:@"ipa"]];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
    [self log:@"Opening file picker..."];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSURL *ipaURL = urls.firstObject;
    [self log:[NSString stringWithFormat:@"Selected: %@", ipaURL.lastPathComponent]];
    [self installIPA:ipaURL];
}

- (void)installIPA:(NSURL *)ipaURL {
    self.statusLabel.text = @"Installing...";
    self.browseButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        
        // 1. Create temp directory
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
        [self log:[NSString stringWithFormat:@"Temp dir: %@", tempDir]];
        
        // 2. Copy .ipa to temp
        NSString *tempIPA = [tempDir stringByAppendingPathComponent:@"app.ipa"];
        [[NSFileManager defaultManager] copyItemAtURL:ipaURL toURL:[NSURL fileURLWithPath:tempIPA] error:&error];
        if (error) {
            [self logError:error message:@"Failed to copy .ipa"];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Installation failed";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        // 3. Unzip .ipa
        NSString *unzipDir = [tempDir stringByAppendingPathComponent:@"extracted"];
        [self log:@"Extracting .ipa..."];
        BOOL success = [self unzipFile:tempIPA toDirectory:unzipDir];
        if (!success) {
            [self log:@"ERROR: Failed to extract .ipa"];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Extraction failed";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        // 4. Find .app bundle in Payload folder
        NSString *payloadDir = [unzipDir stringByAppendingPathComponent:@"Payload"];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil];
        NSString *appBundle = nil;
        for (NSString *item in contents) {
            if ([item hasSuffix:@".app"]) {
                appBundle = item;
                break;
            }
        }
        
        if (!appBundle) {
            [self log:@"ERROR: No .app bundle found in .ipa"];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Invalid .ipa";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        [self log:[NSString stringWithFormat:@"Found: %@", appBundle]];
        
        // 5. Get Applications folder from shared App Group container
        NSString *appsFolder = [[HIAHFilesystem shared] appsPath];
        [[NSFileManager defaultManager] createDirectoryAtPath:appsFolder withIntermediateDirectories:YES attributes:nil error:nil];
        
        // 6. Copy .app to Applications
        NSString *sourcePath = [payloadDir stringByAppendingPathComponent:appBundle];
        NSString *destPath = [appsFolder stringByAppendingPathComponent:appBundle];
        
        // Remove existing (with error handling - ignore if doesn't exist)
        NSError *removeError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:&removeError];
        if (removeError && removeError.code != NSFileNoSuchFileError) {
            [self log:[NSString stringWithFormat:@"Warning: Could not remove existing app: %@", removeError.localizedDescription]];
        }
        
        // Copy
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destPath error:&error];
        if (error) {
            [self logError:error message:@"Failed to install"];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Installation failed";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        // Set executable permissions and patch for dynamic loading
        NSString *plist = [destPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
        NSString *exec = info[@"CFBundleExecutable"];
        
        if (!exec || exec.length == 0) {
            [self log:@"ERROR: No CFBundleExecutable in Info.plist"];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Invalid app: No executable specified";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
            NSString *execPath = [destPath stringByAppendingPathComponent:exec];
        
        // Verify executable exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
            [self log:[NSString stringWithFormat:@"ERROR: Executable not found: %@", exec]];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Invalid app: Executable missing";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        [self log:[NSString stringWithFormat:@"Found executable: %@", exec]];
        
        // Set executable permissions
        NSError *permError = nil;
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:execPath error:&permError];
        if (permError) {
            [self log:[NSString stringWithFormat:@"Warning: Could not set permissions: %@", permError.localizedDescription]];
        } else {
            [self log:@"Set executable permissions (0755)"];
        }
        
        // Verify it's a valid Mach-O binary
        NSData *headerData = [[NSFileManager defaultManager] contentsOfFile:execPath];
        if (headerData.length < 4) {
            [self log:@"ERROR: Executable is too small to be a valid binary"];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Invalid executable binary";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        uint32_t magic = *(uint32_t *)[headerData bytes];
        const uint32_t MH_MAGIC_64 = 0xfeedfacf;
        const uint32_t MH_CIGAM_64 = 0xcffaedfe;
        const uint32_t FAT_MAGIC = 0xcafebabe;
        const uint32_t FAT_CIGAM = 0xbebafeca;
        
        if (magic != MH_MAGIC_64 && magic != MH_CIGAM_64 && magic != FAT_MAGIC && magic != FAT_CIGAM) {
            [self log:[NSString stringWithFormat:@"ERROR: Not a valid Mach-O binary (magic: 0x%08x)", magic]];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = @"Invalid binary format";
                self.browseButton.enabled = YES;
            });
            return;
        }
        
        [self log:@"Binary format validated (Mach-O)"];
            
        // CRITICAL: Patch to a dlopen-compatible Mach-O type (MH_BUNDLE)
        [self log:@"Patching binary for dynamic loading..."];
        BOOL patched = [HIAHMachOUtils patchBinaryToDylib:execPath];
        
        if (patched) {
            [self log:[NSString stringWithFormat:@"✓ Successfully patched %@ to MH_BUNDLE", exec]];
        } else {
            // Check if it's already MH_BUNDLE or compatible
            if ([HIAHMachOUtils isMHExecute:execPath]) {
                [self log:@"ERROR: Binary is still MH_EXECUTE after patching!"];
                [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.statusLabel.text = @"Failed to patch binary";
                    self.browseButton.enabled = YES;
                });
                return;
            } else {
                [self log:@"Binary already dlopen-compatible (no patch needed)"];
            }
        }
        
        // IMPORTANT: We DON'T remove or resign here
        // The ProcessRunner extension will handle signing when loading
        // This allows the extension to use its own certificate/provisioning
        [self log:@"Binary prepared for loading (signature will be handled by extension)"];
        
        // Verify bundle is complete
        NSString *bundleID = info[@"CFBundleIdentifier"];
        NSString *bundleName = info[@"CFBundleName"] ?: info[@"CFBundleDisplayName"];
        [self log:[NSString stringWithFormat:@"Bundle ID: %@", bundleID ?: @"(none)"]];
        [self log:[NSString stringWithFormat:@"Bundle Name: %@", bundleName ?: @"(none)"]];
        
        if (!bundleID || bundleID.length == 0) {
            [self log:@"WARNING: No CFBundleIdentifier in Info.plist"];
        }
        
        [self log:[NSString stringWithFormat:@"✓ Installed: %@", [appBundle stringByDeletingPathExtension]]];
        
        // 7. Clean up
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = [NSString stringWithFormat:@"✓ %@ installed successfully!", [appBundle stringByDeletingPathExtension]];
            self.browseButton.enabled = YES;
            
            // Notify HIAH Desktop to refresh (via notification)
            [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHDesktopRefreshApps" object:nil];
        });
    });
}

- (BOOL)unzipFile:(NSString *)zipPath toDirectory:(NSString *)destPath {
    // Pure native ZIP extraction - no external dependencies
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Open zip file
    FILE *zipFile = fopen([zipPath UTF8String], "rb");
    if (!zipFile) {
        [self log:@"ERROR: Could not open .ipa file"];
        return NO;
    }
    
    // Find end of central directory (scan from end)
    fseek(zipFile, -22, SEEK_END);
    uint8_t eocd[22];
    fread(eocd, 1, 22, zipFile);
    
    // Verify EOCD signature: 0x06054b50
    if (!(eocd[0] == 0x50 && eocd[1] == 0x4b && eocd[2] == 0x05 && eocd[3] == 0x06)) {
        [self log:@"ERROR: Invalid ZIP signature"];
        fclose(zipFile);
        return NO;
    }
    
    // Get central directory offset (bytes 16-19 of EOCD, little endian)
    uint32_t cdOffset = eocd[16] | (eocd[17] << 8) | (eocd[18] << 16) | (eocd[19] << 24);
    uint16_t numEntries = eocd[10] | (eocd[11] << 8);
    
    [self log:[NSString stringWithFormat:@"ZIP: %d entries, CD at 0x%x", numEntries, cdOffset]];
    
    // Read each file from central directory
    fseek(zipFile, cdOffset, SEEK_SET);
    
    for (int i = 0; i < numEntries; i++) {
        uint8_t header[46];
        if (fread(header, 1, 46, zipFile) != 46) break;
        
        // Verify central directory signature: 0x02014b50
        if (!(header[0] == 0x50 && header[1] == 0x4b && header[2] == 0x01 && header[3] == 0x02)) break;
        
        // Parse file header
        uint16_t compressionMethod = header[10] | (header[11] << 8);
        uint32_t compressedSize = header[20] | (header[21] << 8) | (header[22] << 16) | (header[23] << 24);
        uint32_t uncompressedSize = header[24] | (header[25] << 8) | (header[26] << 16) | (header[27] << 24);
        uint16_t fileNameLen = header[28] | (header[29] << 8);
        uint16_t extraFieldLen = header[30] | (header[31] << 8);
        uint16_t commentLen = header[32] | (header[33] << 8);
        uint32_t localHeaderOffset = header[42] | (header[43] << 8) | (header[44] << 16) | (header[45] << 24);
        
        // Read filename
        char *fileName = malloc(fileNameLen + 1);
        fread(fileName, 1, fileNameLen, zipFile);
        fileName[fileNameLen] = '\0';
        
        // Skip extra field and comment
        fseek(zipFile, extraFieldLen + commentLen, SEEK_CUR);
        
        // Remember position in central directory
        long currentPos = ftell(zipFile);
        
        // Build output path
        NSString *outPath = [destPath stringByAppendingPathComponent:[NSString stringWithUTF8String:fileName]];
        
        // Handle directories
        if (fileName[fileNameLen - 1] == '/') {
            [fm createDirectoryAtPath:outPath withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            // Create parent directory
            [fm createDirectoryAtPath:[outPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            
            // Seek to local file header
            fseek(zipFile, localHeaderOffset, SEEK_SET);
            
            // Read local file header
            uint8_t localHeader[30];
            fread(localHeader, 1, 30, zipFile);
            uint16_t localExtraLen = localHeader[28] | (localHeader[29] << 8);
            fseek(zipFile, fileNameLen + localExtraLen, SEEK_CUR);
            
            // Read and write file data
            if (compressionMethod == 0) {
                // Stored (no compression)
                void *data = malloc(uncompressedSize);
                fread(data, 1, uncompressedSize, zipFile);
                [[NSData dataWithBytesNoCopy:data length:uncompressedSize] writeToFile:outPath atomically:YES];
            } else if (compressionMethod == 8) {
                // Deflate
                void *compressedData = malloc(compressedSize);
                fread(compressedData, 1, compressedSize, zipFile);
                
                NSData *compressed = [NSData dataWithBytesNoCopy:compressedData length:compressedSize];
                NSData *decompressed = [compressed decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:nil];
                if (decompressed) {
                    [decompressed writeToFile:outPath atomically:YES];
                } else {
                    // Try raw deflate without zlib header
                    z_stream strm = {0};
                    inflateInit2(&strm, -MAX_WBITS);  // Raw deflate
                    
                    strm.next_in = (Bytef *)compressed.bytes;
                    strm.avail_in = (uInt)compressed.length;
                    
                    void *uncompressed = malloc(uncompressedSize);
                    strm.next_out = uncompressed;
                    strm.avail_out = uncompressedSize;
                    
                    inflate(&strm, Z_FINISH);
                    inflateEnd(&strm);
                    
                    [[NSData dataWithBytesNoCopy:uncompressed length:uncompressedSize] writeToFile:outPath atomically:YES];
                }
            }
        }
        
        free(fileName);
        
        // Restore position in central directory
        fseek(zipFile, currentPos, SEEK_SET);
    }
    
    fclose(zipFile);
    [self log:@"ZIP extraction complete"];
    return YES;
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        self.logView.text = [self.logView.text stringByAppendingString:entry];
        
        // Scroll to bottom
        NSRange range = NSMakeRange(self.logView.text.length - 1, 1);
        [self.logView scrollRangeToVisible:range];
    });
}

- (void)logError:(NSError *)error message:(NSString *)msg {
    [self log:[NSString stringWithFormat:@"ERROR: %@ - %@", msg, error.localizedDescription]];
}

@end

@interface InstallerAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation InstallerAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Get windowScene from connected scenes (iOS 26.0+)
    UIWindowScene *windowScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            windowScene = (UIWindowScene *)scene;
            break;
        }
    }
    
    if (windowScene) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    } else {
        // Fallback for iOS < 26.0
        self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    self.window.rootViewController = [[InstallerViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    // Handle .ipa files opened via share sheet
    if ([url.pathExtension isEqualToString:@"ipa"]) {
        InstallerViewController *vc = (InstallerViewController *)[(UINavigationController *)self.window.rootViewController topViewController];
        if ([vc isKindOfClass:[InstallerViewController class]]) {
            [vc installIPA:url];
        }
        return YES;
    }
    return NO;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([InstallerAppDelegate class]));
    }
}

