/**
 * HIAHLocalDevVPNSetupViewController.h
 * HIAH LoginWindow - LocalDevVPN Setup Guide
 *
 * Guides users through LocalDevVPN installation and activation
 * for enabling JIT and signature bypass features.
 *
 * Based on SideStore's official approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HIAHLocalDevVPNSetupDelegate <NSObject>
@optional
- (void)localDevVPNSetupDidComplete;
- (void)localDevVPNSetupDidCancel;
@end

typedef NS_ENUM(NSInteger, HIAHLocalDevVPNSetupStep) {
    HIAHLocalDevVPNSetupStepInstall = 0,
    HIAHLocalDevVPNSetupStepActivate,
    HIAHLocalDevVPNSetupStepComplete
};

@interface HIAHLocalDevVPNSetupViewController : UIViewController

@property (nonatomic, weak, nullable) id<HIAHLocalDevVPNSetupDelegate> delegate;
@property (nonatomic, assign, readonly) HIAHLocalDevVPNSetupStep currentStep;

/// Check if setup is needed (LocalDevVPN not installed or VPN not active)
+ (BOOL)isSetupNeeded;

/// Present the setup flow modally from a view controller
+ (void)presentSetupFromViewController:(UIViewController *)presenter
                              delegate:(nullable id<HIAHLocalDevVPNSetupDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END

