/**
 * HIAHVPNReminderViewController.m
 * Simple reminder screen for VPN enablement
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import "HIAHVPNReminderViewController.h"
#import "HIAHVPNStateMachine.h"
#import "HIAHPrivateAppLauncher.h"
#import "LocalDevVPN/HIAHLocalDevVPNManager.h"
#import "LocalDevVPN/HIAHLocalDevVPNSetupViewController.h"
#import "EMProxyBridge.h"
#import "../HIAHDesktop/HIAHLogging.h"
#import <ifaddrs.h>
#import <net/if.h>

/// VPN state check results
typedef NS_ENUM(NSInteger, HIAHVPNCheckResult) {
    HIAHVPNCheckResultConnected = 0,     // VPN is connected, no action needed
    HIAHVPNCheckResultNeedsReminder = 1, // Show reminder to enable VPN
    HIAHVPNCheckResultNeedsSetup = 2,    // Show full setup wizard
};

@interface HIAHVPNReminderViewController ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *instructionsLabel;
@property (nonatomic, strong) UIButton *verifyButton;
@property (nonatomic, strong) UIButton *openLocalDevVPNButton;
@property (nonatomic, strong) UIButton *skipButton;
@property (nonatomic, strong) UIButton *resetSetupButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSTimer *statusTimer;
@end

@implementation HIAHVPNReminderViewController

#pragma mark - Class Methods

+ (NSInteger)checkVPNState {
    HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
    HIAHLocalDevVPNManager *vpnManager = [HIAHLocalDevVPNManager sharedManager];
    
    // Start em_proxy if not running
    if (![EMProxyBridge isRunning]) {
        [vpnManager startEMProxy];
    }
    
    // Check 1: Is VPN already connected?
    // Use the reliable detectHIAHVPNConnected method instead of isVPNInterfaceActive
    // which checks for any utun/ipsec interface (always present on iOS)
    if ([sm detectHIAHVPNConnected]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"VPN is already connected");
        return HIAHVPNCheckResultConnected;
    }
    
    // Check 2: Was setup completed before?
    if (!sm.isSetupComplete) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"Setup never completed - needs full setup");
        return HIAHVPNCheckResultNeedsSetup;
    }
    
    // Check 3: Setup was completed but VPN is disconnected
    // User just needs to enable it in LocalDevVPN
    HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"Setup completed but VPN disconnected - show reminder");
    return HIAHVPNCheckResultNeedsReminder;
}

+ (BOOL)isVPNInterfaceActive {
    BOOL active = NO;
    struct ifaddrs *interfaces = NULL;
    
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *current = interfaces;
        while (current != NULL) {
            if (current->ifa_name != NULL) {
                NSString *name = [NSString stringWithUTF8String:current->ifa_name];
                if ([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"]) {
                    if ((current->ifa_flags & IFF_UP) && (current->ifa_flags & IFF_RUNNING)) {
                        active = YES;
                        break;
                    }
                }
            }
            current = current->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return active;
}

+ (void)presentFrom:(UIViewController *)presenter
           delegate:(id<HIAHVPNReminderDelegate>)delegate {
    HIAHVPNReminderViewController *vc = [[HIAHVPNReminderViewController alloc] init];
    vc.delegate = delegate;
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                         UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
    
    [presenter presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupUI];
    [self startStatusMonitoring];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopStatusMonitoring];
}

- (void)dealloc {
    [self stopStatusMonitoring];
}

#pragma mark - UI Setup

- (void)setupUI {
    // Icon
    self.iconView = [[UIImageView alloc] init];
    self.iconView.image = [UIImage systemImageNamed:@"wifi.exclamationmark"];
    self.iconView.tintColor = [UIColor systemOrangeColor];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.iconView];
    
    // Title
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"Enable HIAH-VPN";
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleLabel];
    
    // Subtitle
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = @"VPN required for JIT & signature bypass";
    self.subtitleLabel.font = [UIFont systemFontOfSize:15];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.subtitleLabel];
    
    // Instructions
    self.instructionsLabel = [[UILabel alloc] init];
    self.instructionsLabel.text = @"Open LocalDevVPN and enable the VPN.\n\nThis screen will automatically dismiss when connected.";
    self.instructionsLabel.font = [UIFont systemFontOfSize:16];
    self.instructionsLabel.textColor = [UIColor labelColor];
    self.instructionsLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionsLabel.numberOfLines = 0;
    self.instructionsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.instructionsLabel];
    
    // Spinner (for checking status)
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];
    
    // Open LocalDevVPN button
    self.openLocalDevVPNButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.openLocalDevVPNButton setTitle:@"Open LocalDevVPN" forState:UIControlStateNormal];
    self.openLocalDevVPNButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.openLocalDevVPNButton.backgroundColor = [UIColor systemBlueColor];
    [self.openLocalDevVPNButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openLocalDevVPNButton.layer.cornerRadius = 14;
    self.openLocalDevVPNButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openLocalDevVPNButton addTarget:self action:@selector(openLocalDevVPNTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.openLocalDevVPNButton];
    
    // Verify button
    self.verifyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.verifyButton setTitle:@"Check Connection" forState:UIControlStateNormal];
    self.verifyButton.titleLabel.font = [UIFont systemFontOfSize:15];
    self.verifyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.verifyButton addTarget:self action:@selector(verifyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.verifyButton];
    
    // Skip button
    self.skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.skipButton setTitle:@"Continue Without VPN" forState:UIControlStateNormal];
    self.skipButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.skipButton setTitleColor:[UIColor tertiaryLabelColor] forState:UIControlStateNormal];
    self.skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.skipButton addTarget:self action:@selector(skipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.skipButton];
    
    // Reset setup button
    self.resetSetupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetSetupButton setTitle:@"Reconfigure HIAH-VPN" forState:UIControlStateNormal];
    self.resetSetupButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.resetSetupButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.resetSetupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetSetupButton addTarget:self action:@selector(resetSetupTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetSetupButton];
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:80],
        [self.iconView.heightAnchor constraintEqualToConstant:80],
        
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:20],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.instructionsLabel.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:24],
        [self.instructionsLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.instructionsLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        
        [self.spinner.topAnchor constraintEqualToAnchor:self.instructionsLabel.bottomAnchor constant:16],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.openLocalDevVPNButton.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:24],
        [self.openLocalDevVPNButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.openLocalDevVPNButton.widthAnchor constraintEqualToConstant:200],
        [self.openLocalDevVPNButton.heightAnchor constraintEqualToConstant:50],
        
        [self.verifyButton.topAnchor constraintEqualToAnchor:self.openLocalDevVPNButton.bottomAnchor constant:16],
        [self.verifyButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.skipButton.topAnchor constraintEqualToAnchor:self.verifyButton.bottomAnchor constant:24],
        [self.skipButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.resetSetupButton.topAnchor constraintEqualToAnchor:self.skipButton.bottomAnchor constant:8],
        [self.resetSetupButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
}

#pragma mark - Status Monitoring

- (void)startStatusMonitoring {
    // Check status every 2 seconds
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(checkStatus)
                                                      userInfo:nil
                                                       repeats:YES];
    // Check immediately too
    [self checkStatus];
}

- (void)stopStatusMonitoring {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)checkStatus {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Use the reliable detectHIAHVPNConnected method instead of isVPNInterfaceActive
        // which checks for any utun/ipsec interface (always present on iOS)
        HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
        BOOL connected = [sm detectHIAHVPNConnected];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (connected) {
                [self handleVPNConnected];
            }
        });
    });
}

- (void)handleVPNConnected {
    HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"✅ VPN connected - auto-dismissing");
    
    // Stop monitoring
    [self stopStatusMonitoring];
    
    // Update UI
    self.iconView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    self.iconView.tintColor = [UIColor systemGreenColor];
    self.titleLabel.text = @"Connected!";
    self.instructionsLabel.text = @"HIAH-VPN is now active.";
    
    // Notify delegate and dismiss after a moment
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(vpnReminderDidConnect)]) {
            [self.delegate vpnReminderDidConnect];
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - Actions

- (void)openLocalDevVPNTapped {
    HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"Open LocalDevVPN button tapped");
    
    // First, try to open LocalDevVPN using private LSApplicationWorkspace API
    // This works on sideloaded apps (SideStore, AltStore, TrollStore, etc.)
    if ([HIAHPrivateAppLauncher openLocalDevVPN]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPNReminder", @"✅ Opened LocalDevVPN via private API");
        return;
    }
    
    HIAHLogEx(HIAH_LOG_WARNING, @"VPNReminder", @"Private API failed - showing fallback options");
    
    // Fallback: Show options if private API doesn't work (rare on sideloaded apps)
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Open LocalDevVPN"
                                                                   message:@"Could not open LocalDevVPN automatically.\nChoose how to proceed:"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Option 1: Open iOS Settings
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (settingsURL) {
            [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
        }
    }]];
    
    // Option 2: Manual instructions
    [alert addAction:[UIAlertAction actionWithTitle:@"Show Instructions" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showManualInstructions];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.openLocalDevVPNButton;
        alert.popoverPresentationController.sourceRect = self.openLocalDevVPNButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// LocalDevVPN doesn't require config file sharing - removed shareConfigFile method

- (void)showManualInstructions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enable HIAH-VPN"
                                                                   message:@"To enable the VPN:\n\n"
                                                                           @"1. Press Home button or swipe up\n"
                                                                           @"2. Find and open the LocalDevVPN app\n"
                                                                           @"3. Toggle the VPN switch to turn it ON\n"
                                                                           @"4. If prompted, allow VPN configurations and enter your passcode\n"
                                                                           @"5. Return to HIAH Desktop\n\n"
                                                                           @"This screen will automatically detect when VPN is connected."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)verifyTapped {
    [self.spinner startAnimating];
    self.verifyButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL connected = [HIAHVPNReminderViewController isVPNInterfaceActive];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.verifyButton.enabled = YES;
            
            if (connected) {
                [self handleVPNConnected];
            } else {
                // Show error
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VPN Not Connected"
                                                                               message:@"Please enable the VPN in the LocalDevVPN app, then try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

- (void)skipTapped {
    [self stopStatusMonitoring];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Continue Without VPN?"
                                                                   message:@"Without the VPN connected:\n\n• JIT compilation will not work\n• Unsigned apps may not run\n• Signature refresh will fail\n\nAre you sure?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue Anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if ([self.delegate respondsToSelector:@selector(vpnReminderDidSkip)]) {
            [self.delegate vpnReminderDidSkip];
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self startStatusMonitoring];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSetupTapped {
    [self stopStatusMonitoring];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reconfigure HIAH-VPN?"
                                                                   message:@"This will restart the VPN setup wizard. Use this if you need to:\n\n• Set up LocalDevVPN again\n• Fix a broken configuration"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Reconfigure" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Reset setup and notify delegate
        [[HIAHVPNStateMachine shared] resetSetup];
        [[HIAHLocalDevVPNManager sharedManager] resetSetup];
        
        if ([self.delegate respondsToSelector:@selector(vpnReminderRequestsFullSetup)]) {
            [self.delegate vpnReminderRequestsFullSetup];
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self startStatusMonitoring];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end

