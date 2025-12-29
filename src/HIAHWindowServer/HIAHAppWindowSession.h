/**
 * HIAHAppWindowSession.h
 * Window session for application processes spawned via HIAHKernel
 */

#import <UIKit/UIKit.h>
#import "HIAHWindowSession.h"
#import "HIAHKernel.h"
#import "UIKitPrivate+MultitaskSupport.h"

NS_ASSUME_NONNULL_BEGIN

@class HIAHProcess;

@interface HIAHAppWindowSession : UIViewController <HIAHWindowSession, _UISceneSettingsDiffAction>

@property (nonatomic, weak) HIAHProcess *process;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong, nullable) id presenter; // _UIScenePresenter
@property (nonatomic, copy, nullable) NSString *sceneID;

// HIAHWindowSession properties (readonly in protocol, readwrite here)
// Note: Protocol declares these as readonly without copy, but we need copy for our implementation
@property (nonatomic, readwrite) NSString *windowName;
@property (nonatomic, assign, readwrite) pid_t processPID;
@property (nonatomic, readwrite) NSString *executablePath;
@property (nonatomic, assign, readwrite) BOOL isFullscreen;

- (instancetype)initWithProcess:(HIAHProcess *)process kernel:(HIAHKernel *)kernel;

@end

NS_ASSUME_NONNULL_END

