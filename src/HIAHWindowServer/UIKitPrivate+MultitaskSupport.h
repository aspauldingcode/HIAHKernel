/**
 * UIKitPrivate+MultitaskSupport.h
 * Private UIKit APIs for windowed multitasking
 * Private UIKit APIs for multitasking support
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/types.h>
#import <mach/message.h>  // Provides audit_token_t definition

// audit_token_t is now available from mach/message.h
// No need to redefine it

// Forward declarations for private classes
#define PrivClass(NAME) NSClassFromString(@#NAME)

// RunningBoardServices
@class RBSProcessIdentity, RBSProcessPredicate, RBSProcessHandle;

@interface RBSProcessIdentity : NSObject
+ (instancetype)identityForEmbeddedApplicationIdentifier:(NSString *)identifier;
+ (instancetype)identityForProcessIdentity:(RBSProcessIdentity *)identity;
@end

@interface RBSProcessPredicate : NSObject
+ (instancetype)predicateMatchingIdentifier:(NSNumber *)pid;
@end

@interface RBSProcessHandle : NSObject
@property(nonatomic, strong, readonly) RBSProcessIdentity *identity;
+ (instancetype)handleForPredicate:(RBSProcessPredicate *)predicate error:(NSError **)error;
- (audit_token_t)auditToken;
@end

// Forward declarations
@class FBScene, FBSceneManager, FBSMutableSceneDefinition, FBSSceneIdentity, FBSSceneClientIdentity;
@class FBSSceneSpecification, FBSSceneParameters, FBProcessManager, FBProcess;
@class UIScenePresentationManager, _UIScenePresenter;
@class UIMutableScenePresentationContext, FBSSceneSettingsDiff;
@class BSCornerRadiusConfiguration;

// Forward declare settings classes
@class UIApplicationSceneSettings;
@class UIMutableApplicationSceneSettings;
@class UIMutableApplicationSceneClientSettings;

@interface FBProcessManager : NSObject
+ (instancetype)sharedInstance;
- (void)registerProcessForAuditToken:(audit_token_t)token;
@end

@interface FBProcess : NSObject
- (id)name;
@end

@interface FBScene : NSObject
- (FBProcess *)clientProcess;
- (UIScenePresentationManager *)uiPresentationManager;
- (void)updateSettings:(id)settings withTransitionContext:(id)context completion:(id)completion;
- (void)updateSettingsWithBlock:(void(^)(id settings))block;
- (id)settings;
@end

@interface FBSSceneClientIdentity : NSObject
+ (instancetype)identityForBundleID:(NSString *)bundleID;
+ (instancetype)identityForProcessIdentity:(RBSProcessIdentity *)identity;
+ (instancetype)localIdentity;
@end

@interface FBSSceneIdentity : NSObject
+ (instancetype)identityForIdentifier:(NSString *)identifier;
@end

@interface FBSSceneSpecification : NSObject
+ (instancetype)specification;
@end

@interface UIApplicationSceneSpecification : FBSSceneSpecification
@end

@interface FBSMutableSceneDefinition : NSObject
@property(nonatomic, copy) FBSSceneClientIdentity *clientIdentity;
@property(nonatomic, copy) FBSSceneIdentity *identity;
@property(nonatomic, copy) FBSSceneSpecification *specification;
+ (instancetype)definition;
@end

@interface FBSSceneParameters : NSObject
@property(nonatomic, strong) UIMutableApplicationSceneSettings *settings;
@property(nonatomic, strong) id clientSettings;
+ (instancetype)parametersForSpecification:(FBSSceneSpecification *)spec;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (FBScene *)createSceneWithDefinition:(FBSMutableSceneDefinition *)def initialParameters:(FBSSceneParameters *)params;
- (void)destroyScene:(NSString *)sceneID withTransitionContext:(id)context;
@end

@interface FBSSceneSettingsDiff : NSObject
- (id)settingsByApplyingToMutableCopyOfSettings:(id)settings;
@end

@interface UIApplicationSceneSettings : NSObject
- (BOOL)isForeground;
- (CGRect)frame;
- (NSInteger)interfaceOrientation;
- (id)mutableCopy;
@end

@interface UIMutableApplicationSceneSettings : NSObject
- (void)setCanShowAlerts:(BOOL)value;
- (void)setForeground:(BOOL)value;
- (void)setFrame:(CGRect)frame;
- (void)setDeviceOrientation:(UIDeviceOrientation)orientation;
- (void)setInterfaceOrientation:(NSInteger)orientation;
- (void)setLevel:(NSInteger)level;
- (void)setPersistenceIdentifier:(NSString *)identifier;
- (void)setStatusBarDisabled:(BOOL)disabled;
- (void)setCornerRadiusConfiguration:(id)config;
- (void)setSafeAreaInsetsPortrait:(UIEdgeInsets)insets;
- (void)setSafeAreaInsetsLandscapeLeft:(UIEdgeInsets)insets;
- (void)setSafeAreaInsetsLandscapeRight:(UIEdgeInsets)insets;
- (void)setUserInterfaceStyle:(UIUserInterfaceStyle)style;
- (NSInteger)interfaceOrientation;
- (id)displayConfiguration;
- (void)setDisplayConfiguration:(id)config;
@end

@interface UIMutableApplicationSceneClientSettings : NSObject
@property(nonatomic, assign) UIInterfaceOrientation interfaceOrientation;
@property(nonatomic, assign) NSInteger statusBarStyle;
@end

@interface UIScenePresentationManager : NSObject
- (_UIScenePresenter *)createPresenterWithIdentifier:(NSString *)identifier;
@end

@interface _UIScenePresenter : NSObject
@property(nonatomic, readonly) UIView *presentationView;
@property(nonatomic, readonly) FBScene *scene;
- (void)modifyPresentationContext:(void(^)(UIMutableScenePresentationContext *context))block;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
@end

@interface UIMutableScenePresentationContext : NSObject
@property(nonatomic, assign) NSUInteger appearanceStyle;
@end

@protocol _UISceneSettingsDiffAction <NSObject>
- (void)_performActionsForUIScene:(UIScene *)scene 
                withUpdatedFBSScene:(id)fbsScene 
                        settingsDiff:(FBSSceneSettingsDiff *)diff 
                         fromSettings:(id)settings 
                    transitionContext:(id)context 
                  lifecycleActionType:(uint32_t)actionType;
@end

@interface UIWindowScene (Private)
- (void)_registerSettingsDiffActionArray:(NSArray<id<_UISceneSettingsDiffAction>> *)array forKey:(NSString *)key;
- (void)_unregisterSettingsDiffActionArrayForKey:(NSString *)key;
@end

@interface BSCornerRadiusConfiguration : NSObject
- (instancetype)initWithTopLeft:(CGFloat)tl bottomLeft:(CGFloat)bl bottomRight:(CGFloat)br topRight:(CGFloat)tr;
@end

