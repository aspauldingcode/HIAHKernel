/**
 * HIAHVPNReminderViewController.h
 * Simple reminder screen for users who already configured HIAH-VPN
 * but need to enable it in LocalDevVPN.
 *
 * This is shown instead of the full setup wizard when:
 * - User has completed setup before
 * - VPN is currently disconnected
 * - User just needs to enable it in LocalDevVPN
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HIAHVPNReminderDelegate <NSObject>
@optional
/// VPN was successfully connected
- (void)vpnReminderDidConnect;
/// User tapped "Continue Anyway" (without VPN)
- (void)vpnReminderDidSkip;
/// User wants to restart full setup wizard
- (void)vpnReminderRequestsFullSetup;
@end

/**
 * HIAHVPNReminderViewController
 *
 * A simple view that reminds users to enable HIAH-VPN in LocalDevVPN.
 * Shows when setup was completed before but VPN is not currently connected.
 */
@interface HIAHVPNReminderViewController : UIViewController

/// Delegate for callbacks
@property (nonatomic, weak, nullable) id<HIAHVPNReminderDelegate> delegate;

/// Present the reminder from a view controller
+ (void)presentFrom:(UIViewController *)presenter
           delegate:(nullable id<HIAHVPNReminderDelegate>)delegate;

/// Check if a VPN reminder should be shown (vs full setup vs nothing)
/// Returns: 0 = no reminder needed, 1 = show reminder, 2 = needs full setup
+ (NSInteger)checkVPNState;

@end

NS_ASSUME_NONNULL_END

