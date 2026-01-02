/**
 * HIAHLocalDevVPNSetupViewController.m
 * HIAH LoginWindow - LocalDevVPN Setup Guide
 *
 * Simplified setup wizard for LocalDevVPN (official SideStore VPN).
 * Users just need to install from App Store and turn it on.
 *
 * Based on SideStore's official approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHLocalDevVPNSetupViewController.h"
#import "HIAHLocalDevVPNManager.h"
#import "HIAHVPNStateMachine.h"
#import "../../../HIAHDesktop/HIAHLogging.h"
#import "../HIAHPrivateAppLauncher.h"
#import <UIKit/UIKit.h>

@interface HIAHLocalDevVPNSetupViewController ()

@property (nonatomic, assign) HIAHLocalDevVPNSetupStep currentStep;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *stepImageView;
@property (nonatomic, strong) UILabel *instructionsLabel;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSTimer *vpnCheckTimer;

@end

@implementation HIAHLocalDevVPNSetupViewController

#pragma mark - Class Methods

+ (BOOL)isSetupNeeded {
    HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
    HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
    
    // First check: Is the setup flag set?
    if (![manager isHIAHVPNConfigured]) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Setup needed: HIAHVPNSetupCompleted flag not set");
        return YES;  // Setup never completed
    }
    
    // Second check: Is em_proxy actually running?
    if (![manager isEMProxyRunning]) {
        // Try to start it
        if (![manager startEMProxy]) {
            HIAHLogEx(HIAH_LOG_WARNING, @"LocalDevVPN", @"Setup needed: em_proxy failed to start");
            // Reset the setup flag since something is wrong
            [manager resetSetup];
            return YES;
        }
    }
    
    // Third check: Is the full VPN connection actually working?
    // Use the reliable detectHIAHVPNConnected method to verify VPN is truly connected
    [manager refreshVPNStatus];
    if ([vpnSM detectHIAHVPNConnected]) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Setup not needed: VPN is fully connected");
        return NO;  // Everything is working
    }
    
    // VPN is not connected - but setup was completed before
    // This means user needs to enable LocalDevVPN, but we should show reminder, not full setup
    // However, if setup was never completed, we need full setup
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Setup completed but VPN not connected - will show reminder");
    return NO;  // Don't show full setup, show reminder instead
}

+ (void)presentSetupFromViewController:(UIViewController *)presenter
                              delegate:(id<HIAHLocalDevVPNSetupDelegate>)delegate {
    HIAHLocalDevVPNSetupViewController *setupVC = [[HIAHLocalDevVPNSetupViewController alloc] init];
    setupVC.delegate = delegate;
    setupVC.modalPresentationStyle = UIModalPresentationPageSheet;
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = setupVC.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    
    [presenter presentViewController:setupVC animated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupUI];
    [self determineInitialStep];
    [self updateUIForCurrentStep];
    [self startVPNMonitoring];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopVPNMonitoring];
}

- (void)dealloc {
    [self stopVPNMonitoring];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor tertiaryLabelColor];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    // Scroll view for content
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    
    // Content stack
    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.alignment = UIStackViewAlignmentCenter;
    self.contentStack.spacing = 20;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];
    
    // Step icon
    self.stepImageView = [[UIImageView alloc] init];
    self.stepImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.stepImageView.tintColor = [UIColor systemBlueColor];
    self.stepImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.stepImageView];
    
    // Title
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.titleLabel];
    
    // Subtitle
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [UIFont systemFontOfSize:17];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.subtitleLabel];
    
    // Instructions
    self.instructionsLabel = [[UILabel alloc] init];
    self.instructionsLabel.font = [UIFont systemFontOfSize:15];
    self.instructionsLabel.textColor = [UIColor labelColor];
    self.instructionsLabel.textAlignment = NSTextAlignmentLeft;
    self.instructionsLabel.numberOfLines = 0;
    self.instructionsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.instructionsLabel];
    
    // Spinner (for verification)
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.spinner];
    
    // Primary button
    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.primaryButton addTarget:self action:@selector(primaryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.primaryButton];
    
    // Secondary button (for verification)
    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.secondaryButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [self.secondaryButton addTarget:self action:@selector(secondaryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.secondaryButton];
    
    // Page control
    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = 3;
    self.pageControl.currentPage = 0;
    self.pageControl.pageIndicatorTintColor = [UIColor tertiaryLabelColor];
    self.pageControl.currentPageIndicatorTintColor = [UIColor systemBlueColor];
    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.pageControl];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Close button
        [closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        
        // Scroll view
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // Content stack
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:40],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:32],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-32],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-40],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-64],
        
        // Step image
        [self.stepImageView.widthAnchor constraintEqualToConstant:120],
        [self.stepImageView.heightAnchor constraintEqualToConstant:120],
        
        // Primary button
        [self.primaryButton.widthAnchor constraintEqualToConstant:280],
        [self.primaryButton.heightAnchor constraintEqualToConstant:50],
        
        // Secondary button
        [self.secondaryButton.widthAnchor constraintEqualToConstant:280],
        [self.secondaryButton.heightAnchor constraintEqualToConstant:44],
        
        // Instructions (full width)
        [self.instructionsLabel.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor],
    ]];
}

#pragma mark - Step Management

- (void)determineInitialStep {
    HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
    
    if (![manager isLocalDevVPNInstalled]) {
        self.currentStep = HIAHLocalDevVPNSetupStepInstall;
    } else if (!manager.isVPNActive) {
        self.currentStep = HIAHLocalDevVPNSetupStepActivate;
    } else {
        self.currentStep = HIAHLocalDevVPNSetupStepComplete;
    }
}

- (void)updateUIForCurrentStep {
    self.pageControl.currentPage = self.currentStep;
    
    switch (self.currentStep) {
        case HIAHLocalDevVPNSetupStepInstall: {
            self.stepImageView.image = [UIImage systemImageNamed:@"app.badge"];
            self.titleLabel.text = @"Install LocalDevVPN";
            self.subtitleLabel.text = @"LocalDevVPN is required for JIT enablement";
            self.instructionsLabel.text = @"LocalDevVPN is the official VPN used by SideStore. It creates a local network tunnel that allows HIAH Desktop to communicate with iOS services.\n\n1. Tap the button below to open the App Store\n2. Install LocalDevVPN\n3. Return here when installation is complete";
            [self.primaryButton setTitle:@"Open App Store" forState:UIControlStateNormal];
            self.primaryButton.backgroundColor = [UIColor systemBlueColor];
            [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.primaryButton.layer.cornerRadius = 10;
            self.secondaryButton.hidden = YES;
            break;
        }
            
        case HIAHLocalDevVPNSetupStepActivate: {
            self.stepImageView.image = [UIImage systemImageNamed:@"wifi"];
            self.titleLabel.text = @"Enable VPN";
            self.subtitleLabel.text = @"Turn on LocalDevVPN to enable JIT";
            self.instructionsLabel.text = @"Now that LocalDevVPN is installed, you need to turn it on:\n\n1. Tap \"Open LocalDevVPN\" below\n2. Toggle the VPN switch to ON\n3. If prompted, allow VPN configurations and enter your passcode\n4. Return here and tap \"Verify Connection\"";
            [self.primaryButton setTitle:@"Open LocalDevVPN" forState:UIControlStateNormal];
            self.primaryButton.backgroundColor = [UIColor systemBlueColor];
            [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.primaryButton.layer.cornerRadius = 10;
            [self.secondaryButton setTitle:@"Verify Connection" forState:UIControlStateNormal];
            self.secondaryButton.hidden = NO;
            break;
        }
            
        case HIAHLocalDevVPNSetupStepComplete: {
            self.stepImageView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            self.stepImageView.tintColor = [UIColor systemGreenColor];
            self.titleLabel.text = @"Setup Complete!";
            self.subtitleLabel.text = @"VPN is connected and ready";
            self.instructionsLabel.text = @"LocalDevVPN is now active. You can now use JIT enablement and signature bypass features in HIAH Desktop.";
            [self.primaryButton setTitle:@"Continue" forState:UIControlStateNormal];
            self.primaryButton.backgroundColor = [UIColor systemGreenColor];
            [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.primaryButton.layer.cornerRadius = 10;
            self.secondaryButton.hidden = YES;
            break;
        }
    }
}

#pragma mark - Actions

- (void)primaryButtonTapped {
    HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
    
    switch (self.currentStep) {
        case HIAHLocalDevVPNSetupStepInstall: {
            [manager openLocalDevVPNInAppStore];
            // Check if installed after a delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self checkInstallationStatus];
            });
            break;
        }
            
        case HIAHLocalDevVPNSetupStepActivate: {
            [manager openLocalDevVPN];
            break;
        }
            
        case HIAHLocalDevVPNSetupStepComplete: {
            [self completeSetup];
            break;
        }
    }
}

- (void)secondaryButtonTapped {
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"'Verify Connection' button tapped");
    HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
    
    [self.spinner startAnimating];
    self.secondaryButton.enabled = NO;
    
    // Verify the connection using the reliable detectHIAHVPNConnected method
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
        BOOL verified = [vpnSM detectHIAHVPNConnected];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.secondaryButton.enabled = YES;
            
            if (verified) {
                HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"✅ VPN connection verified - marking setup complete");
                [manager markSetupCompleted];
                [[HIAHVPNStateMachine shared] markSetupComplete];
                self.currentStep = HIAHLocalDevVPNSetupStepComplete;
                [self updateUIForCurrentStep];
            } else {
                [self showAlert:@"VPN Not Active"
                        message:@"Please ensure:\n\n1. LocalDevVPN app is installed\n2. The VPN is turned ON in LocalDevVPN\n3. You've allowed VPN configurations if prompted\n\nReturn here and tap \"Verify Connection\" when ready."];
            }
        });
    });
}

- (void)closeTapped {
    if ([self.delegate respondsToSelector:@selector(localDevVPNSetupDidCancel)]) {
        [self.delegate localDevVPNSetupDidCancel];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)completeSetup {
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Setup completed");
    if ([self.delegate respondsToSelector:@selector(localDevVPNSetupDidComplete)]) {
        [self.delegate localDevVPNSetupDidComplete];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Helper Methods

- (void)checkInstallationStatus {
    HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
    if ([manager isLocalDevVPNInstalled]) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"LocalDevVPN installed - moving to activation step");
        self.currentStep = HIAHLocalDevVPNSetupStepActivate;
        [self updateUIForCurrentStep];
    }
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VPN Monitoring

- (void)startVPNMonitoring {
    [self stopVPNMonitoring];
    
    self.vpnCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(checkVPNStatus)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)stopVPNMonitoring {
    if (self.vpnCheckTimer) {
        [self.vpnCheckTimer invalidate];
        self.vpnCheckTimer = nil;
    }
}

- (void)checkVPNStatus {
    // CRITICAL: Run expensive VPN checks on background queue to avoid blocking main thread
    // This prevents text input lag and UI freezing
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        HIAHLocalDevVPNManager *manager = [HIAHLocalDevVPNManager sharedManager];
        HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
        [manager refreshVPNStatus];
        
        // Auto-advance if VPN becomes active
        // Use the reliable detectHIAHVPNConnected method instead of manager.isVPNActive
        // which can be unreliable (based on test_emotional_damage alone)
        BOOL vpnConnected = [vpnSM detectHIAHVPNConnected];
        BOOL localDevVPNInstalled = [manager isLocalDevVPNInstalled];
        
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentStep == HIAHLocalDevVPNSetupStepActivate && vpnConnected) {
                HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"VPN detected as active - auto-advancing to complete step");
                [manager markSetupCompleted];
                [[HIAHVPNStateMachine shared] markSetupComplete];
                self.currentStep = HIAHLocalDevVPNSetupStepComplete;
                [self updateUIForCurrentStep];
            }
            
            // Auto-advance if LocalDevVPN gets installed
            if (self.currentStep == HIAHLocalDevVPNSetupStepInstall && localDevVPNInstalled) {
                HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"LocalDevVPN detected as installed - moving to activation step");
                self.currentStep = HIAHLocalDevVPNSetupStepActivate;
                [self updateUIForCurrentStep];
            }
        });
    });
}

@end

