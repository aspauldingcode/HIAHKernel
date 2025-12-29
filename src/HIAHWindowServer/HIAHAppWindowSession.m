/**
 * HIAHAppWindowSession.m
 * Implementation of window session for app processes
 */

#import "HIAHAppWindowSession.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "HIAHKernel.h"
#import "HIAHProcess.h"
#import <objc/runtime.h>

// Forward declarations for private UIKit classes
@class FBSceneManager, FBScene, FBSMutableSceneDefinition, FBSSceneIdentity, FBSSceneClientIdentity;
@class RBSProcessPredicate, RBSProcessHandle, FBProcessManager;
@class UIScenePresentationManager, _UIScenePresenter, UIMutableApplicationSceneSettings;
@class FBSSceneParameters;

@implementation HIAHAppWindowSession

@synthesize windowName;
@synthesize processPID;
@synthesize executablePath;
@synthesize isFullscreen;

- (instancetype)initWithProcess:(HIAHProcess *)process kernel:(HIAHKernel *)kernel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _process = process;
        self.windowName = process.executablePath.lastPathComponent ?: @"Unknown";
        self.processPID = process.pid;
        self.executablePath = process.executablePath;
        self.isFullscreen = NO;
    }
    return self;
}

- (void)loadView {
    // Get screen from window scene if available, otherwise fallback to mainScreen
    UIScreen *screen = nil;
    if (self.viewIfLoaded.window.windowScene) {
        screen = self.viewIfLoaded.window.windowScene.screen;
    } else {
        // Try to get from connected scenes
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                screen = ((UIWindowScene *)scene).screen;
                break;
            }
        }
    }
    if (!screen) {
        screen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    
    self.view = [[UIView alloc] initWithFrame:screen.bounds];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    self.contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.contentView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Ensure content view matches bounds
    self.contentView.frame = self.view.bounds;
    
    // Update presenter view if it exists
    if (self.presenter) {
        UIView *presentationView = [self.presenter performSelector:@selector(presentationView)];
        if (presentationView) {
            presentationView.frame = self.contentView.bounds;
        }
    }
}

- (BOOL)openWindowWithScene:(UIWindowScene *)windowScene withSessionIdentifier:(HIAHWindowID)identifier {
    // Use physical PID if available, otherwise use virtual PID
    pid_t targetPID = (self.process.physicalPid > 0) ? self.process.physicalPid : self.processPID;
    
    if (targetPID <= 0) {
        NSLog(@"[HIAHWindowSession] Error: Invalid target PID %d", targetPID);
        return NO;
    }
    
    // Get process handle for the spawned process
    Class RBSProcessPredicateClass = NSClassFromString(@"RBSProcessPredicate");
    Class RBSProcessHandleClass = NSClassFromString(@"RBSProcessHandle");
    Class FBProcessManagerClass = NSClassFromString(@"FBProcessManager");
    
    if (!RBSProcessPredicateClass || !RBSProcessHandleClass || !FBProcessManagerClass) {
        NSLog(@"[HIAHWindowSession] Error: Required private classes not available");
        return NO;
    }
    
    // Retry getting process handle (process might not be ready immediately)
    RBSProcessHandle *processHandle = nil;
    NSError *error = nil;
    int retries = 5;
    for (int i = 0; i < retries; i++) {
        // Create predicate for our process
        RBSProcessPredicate *predicate = [RBSProcessPredicateClass predicateMatchingIdentifier:@(targetPID)];
        if (!predicate) {
            NSLog(@"[HIAHWindowSession] Error: Failed to create process predicate for PID %d", targetPID);
            if (i < retries - 1) {
                usleep(100000); // Wait 100ms before retry
                continue;
            }
            return NO;
        }
        
        // Get process handle
        error = nil;
        processHandle = [RBSProcessHandleClass handleForPredicate:predicate error:&error];
        if (processHandle && !error) {
            // Validate process handle has identity property
            if ([processHandle respondsToSelector:@selector(identity)]) {
                id identity = [processHandle performSelector:@selector(identity)];
                if (identity) {
                    NSLog(@"[HIAHWindowSession] Got process handle with identity for PID %d", targetPID);
                    break; // Success!
                }
            }
        }
        
        if (i < retries - 1) {
            NSLog(@"[HIAHWindowSession] Retry %d/%d: Process handle not ready for PID %d, waiting...", i+1, retries, targetPID);
            usleep(200000); // Wait 200ms before retry
        }
    }
    
    if (!processHandle || error) {
        NSLog(@"[HIAHWindowSession] Error: Failed to get process handle for PID %d after %d retries: %@", targetPID, retries, error.localizedDescription);
        return NO;
    }
    
    // Get process identity (it's an object property, not a struct)
    id processIdentity = nil;
    if ([processHandle respondsToSelector:@selector(identity)]) {
        // identity is a property that returns RBSProcessIdentity object
        processIdentity = [processHandle performSelector:@selector(identity)];
    }
    
    if (!processIdentity) {
        NSLog(@"[HIAHWindowSession] Error: Process handle has no identity for PID %d", targetPID);
        return NO;
    }
    
    NSLog(@"[HIAHWindowSession] Got process identity: %@ for PID %d", processIdentity, targetPID);
    
    // Register process with FrontBoard
    FBProcessManager *processManager = [FBProcessManagerClass sharedInstance];
    
    // Get audit token using NSInvocation (audit_token_t is a struct)
    audit_token_t auditToken = {0};
    BOOL hasAuditToken = NO;
    if ([processHandle respondsToSelector:@selector(auditToken)]) {
        NSMethodSignature *auditSig = [processHandle methodSignatureForSelector:@selector(auditToken)];
        NSInvocation *auditInv = [NSInvocation invocationWithMethodSignature:auditSig];
        [auditInv setTarget:processHandle];
        [auditInv setSelector:@selector(auditToken)];
        [auditInv invoke];
        
        if (auditSig.methodReturnLength > 0) {
            [auditInv getReturnValue:&auditToken];
            [processManager registerProcessForAuditToken:auditToken];
            hasAuditToken = YES;
            NSLog(@"[HIAHWindowSession] Registered process with FrontBoard for PID %d", targetPID);
        }
    }
    
    if (!hasAuditToken) {
        NSLog(@"[HIAHWindowSession] Warning: Could not get audit token for PID %d", targetPID);
    }
    
    // Check if FBProcess is available
    id fbProcess = nil;
    if ([processManager respondsToSelector:@selector(processForPID:)]) {
        fbProcess = [processManager performSelector:@selector(processForPID:) withObject:@(targetPID)];
        NSLog(@"[HIAHWindowSession] FBProcess for PID %d: %@", targetPID, fbProcess);
    }
    
    // Wait a bit more for FrontBoard to fully process the registration
    // Extension processes especially need time to initialize
    for (int i = 0; i < 10; i++) {
        if (!fbProcess && [processManager respondsToSelector:@selector(processForPID:)]) {
            fbProcess = [processManager performSelector:@selector(processForPID:) withObject:@(targetPID)];
        }
        if (fbProcess) break;
        NSLog(@"[HIAHWindowSession] Waiting for FBProcess for PID %d (retry %d)...", targetPID, i);
        usleep(100000); // 100ms
    }
    
    if (!fbProcess) {
        NSLog(@"[HIAHWindowSession] Warning: FBProcess still not available for PID %d after registration", targetPID);
    }
    
    // Create scene ID
    self.sceneID = [NSString stringWithFormat:@"HIAHKernel:%@-%@", 
                    self.executablePath.lastPathComponent ?: @"app",
                    [NSUUID UUID].UUIDString];
    
    // Create scene definition
    Class FBSMutableSceneDefinitionClass = NSClassFromString(@"FBSMutableSceneDefinition");
    Class FBSSceneIdentityClass = NSClassFromString(@"FBSSceneIdentity");
    Class FBSSceneClientIdentityClass = NSClassFromString(@"FBSSceneClientIdentity");
    Class UIApplicationSceneSpecificationClass = NSClassFromString(@"UIApplicationSceneSpecification");
    
    if (!FBSMutableSceneDefinitionClass || !FBSSceneIdentityClass || !FBSSceneClientIdentityClass || !UIApplicationSceneSpecificationClass) {
        NSLog(@"[HIAHWindowSession] Error: Required scene classes not available");
        return NO;
    }
    
    FBSMutableSceneDefinition *definition = [FBSMutableSceneDefinitionClass definition];
    if (!definition) {
        NSLog(@"[HIAHWindowSession] Error: Failed to create scene definition");
        return NO;
    }
    
    definition.identity = [FBSSceneIdentityClass identityForIdentifier:self.sceneID];
    if (!definition.identity) {
        NSLog(@"[HIAHWindowSession] Error: Failed to create scene identity");
        return NO;
    }
    
    // Create client identity from process identity
    // identityForProcessIdentity: expects RBSProcessIdentity * object (not a struct!)
    id clientIdentity = nil;
    if ([FBSSceneClientIdentityClass respondsToSelector:@selector(identityForProcessIdentity:)]) {
        clientIdentity = [FBSSceneClientIdentityClass identityForProcessIdentity:processIdentity];
    }
    
    // Try other methods if identityForProcessIdentity failed
    if (!clientIdentity && [FBSSceneClientIdentityClass respondsToSelector:@selector(identityForBundleID:)]) {
        // Fallback to bundle ID if we can get it from the process handle
        NSString *bundleID = nil;
        if ([processHandle respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [processHandle performSelector:@selector(bundleIdentifier)];
        }
        if (bundleID) {
            clientIdentity = [FBSSceneClientIdentityClass identityForBundleID:bundleID];
            NSLog(@"[HIAHWindowSession] Fallback: Created client identity using bundleID: %@", bundleID);
        }
    }
    
    if (!clientIdentity) {
        NSLog(@"[HIAHWindowSession] Error: Failed to create client identity for PID %d", targetPID);
        return NO;
    }
    
    NSLog(@"[HIAHWindowSession] Created client identity: %@", clientIdentity);
    definition.clientIdentity = clientIdentity;
    
    // Set specification
    id spec = [UIApplicationSceneSpecificationClass specification];
    if (!spec) {
        NSLog(@"[HIAHWindowSession] Error: UIApplicationSceneSpecification specification is nil");
        return NO;
    }
    definition.specification = spec;
    NSLog(@"[HIAHWindowSession] Set scene specification: %@", spec);
    
    // Create scene parameters
    Class FBSMutableSceneParametersClass = NSClassFromString(@"FBSMutableSceneParameters");
    if (!FBSMutableSceneParametersClass) {
        FBSMutableSceneParametersClass = NSClassFromString(@"FBSSceneParameters");
    }
    id parameters = [FBSMutableSceneParametersClass parametersForSpecification:definition.specification];
    
    // Configure scene settings
    Class UIMutableApplicationSceneSettingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
    if (!UIMutableApplicationSceneSettingsClass) {
        NSLog(@"[HIAHWindowSession] Error: UIMutableApplicationSceneSettings class not available");
        return NO;
    }
    id settings = [[UIMutableApplicationSceneSettingsClass alloc] init];
    [settings setCanShowAlerts:YES];
    [settings setForeground:YES];
    
    // Set display configuration (critical for scene creation)
    id displayConfig = nil;
    UIScreen *targetScreen = windowScene ? windowScene.screen : nil;
    if (!targetScreen) {
        // Fallback: get from connected scenes or mainScreen
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                targetScreen = ((UIWindowScene *)scene).screen;
                break;
            }
        }
    }
    if (!targetScreen) {
        targetScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    
    if ([targetScreen respondsToSelector:@selector(displayConfiguration)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        displayConfig = [targetScreen performSelector:@selector(displayConfiguration)];
#pragma clang diagnostic pop
    } else if ([targetScreen respondsToSelector:NSSelectorFromString(@"_displayConfiguration")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        displayConfig = [targetScreen performSelector:NSSelectorFromString(@"_displayConfiguration")];
#pragma clang diagnostic pop
    }
    
    if (displayConfig && [settings respondsToSelector:@selector(setDisplayConfiguration:)]) {
        [settings setDisplayConfiguration:displayConfig];
        NSLog(@"[HIAHWindowSession] Set display configuration: %@", displayConfig);
    }
    
    // Ensure frame is not empty
    CGRect frame = self.view.bounds;
    if (CGRectIsEmpty(frame) || frame.size.width < 10 || frame.size.height < 10) {
        frame = targetScreen.bounds;
        NSLog(@"[HIAHWindowSession] Warning: View bounds invalid %@, using screen bounds: %@", 
              NSStringFromCGRect(self.view.bounds), NSStringFromCGRect(frame));
    }
    [settings setFrame:frame];
    
    [settings setDeviceOrientation:UIDevice.currentDevice.orientation];
    // Use window scene's effective geometry interface orientation if available
    NSInteger interfaceOrientation = UIInterfaceOrientationPortrait;
    if (windowScene && [windowScene respondsToSelector:@selector(effectiveGeometry)]) {
        id effectiveGeometry = [windowScene performSelector:@selector(effectiveGeometry)];
        if (effectiveGeometry && [effectiveGeometry respondsToSelector:@selector(interfaceOrientation)]) {
            interfaceOrientation = (NSInteger)[effectiveGeometry performSelector:@selector(interfaceOrientation)];
        }
    } else if (windowScene && [windowScene respondsToSelector:@selector(interfaceOrientation)]) {
        // Fallback for iOS < 26.0
        interfaceOrientation = windowScene.interfaceOrientation;
    } else if (UIApplication.sharedApplication.connectedScenes.count > 0) {
        UIScene *scene = UIApplication.sharedApplication.connectedScenes.allObjects.firstObject;
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if ([ws respondsToSelector:@selector(effectiveGeometry)]) {
                id effectiveGeometry = [ws performSelector:@selector(effectiveGeometry)];
                if (effectiveGeometry && [effectiveGeometry respondsToSelector:@selector(interfaceOrientation)]) {
                    interfaceOrientation = (NSInteger)[effectiveGeometry performSelector:@selector(interfaceOrientation)];
                }
            } else if ([ws respondsToSelector:@selector(interfaceOrientation)]) {
                interfaceOrientation = ws.interfaceOrientation;
            }
        }
    }
    [settings setInterfaceOrientation:interfaceOrientation];
    
    // Set level (FBSSceneLevel)
    if ([settings respondsToSelector:@selector(setLevel:)]) {
        [settings setLevel:1];
    }
    
    [settings setPersistenceIdentifier:[NSUUID UUID].UUIDString];
    [settings setStatusBarDisabled:NO];
    
    // Set interruption policy (0 = default/none)
    SEL setInterruptionPolicySel = NSSelectorFromString(@"setInterruptionPolicy:");
    if ([settings respondsToSelector:setInterruptionPolicySel]) {
        // Use NSInvocation to set interruption policy (it might be an enum/int)
        // Set to 0 because FBSceneManager workspace might not support reconnect (2)
        NSInteger policy = 0; 
        NSMethodSignature *sig = [settings methodSignatureForSelector:setInterruptionPolicySel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:settings];
            [inv setSelector:setInterruptionPolicySel];
            [inv setArgument:&policy atIndex:2];
            [inv invoke];
        }
    }
    
    // Set corner radius
    Class BSCornerRadiusConfigurationClass = NSClassFromString(@"BSCornerRadiusConfiguration");
    if (BSCornerRadiusConfigurationClass) {
        id cornerConfig = [[BSCornerRadiusConfigurationClass alloc] 
            initWithTopLeft:10.0 bottomLeft:10.0 bottomRight:10.0 topRight:10.0];
        [settings setCornerRadiusConfiguration:cornerConfig];
    }
    
    if ([parameters respondsToSelector:NSSelectorFromString(@"setSettings:")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [parameters performSelector:NSSelectorFromString(@"setSettings:") withObject:settings];
#pragma clang diagnostic pop
    }
    
    // Create client settings
    Class UIMutableApplicationSceneClientSettingsClass = NSClassFromString(@"UIMutableApplicationSceneClientSettings");
    if (UIMutableApplicationSceneClientSettingsClass) {
        id clientSettings = [[UIMutableApplicationSceneClientSettingsClass alloc] init];
        [clientSettings setInterfaceOrientation:UIInterfaceOrientationPortrait];
        [clientSettings setStatusBarStyle:0];
        if ([parameters respondsToSelector:NSSelectorFromString(@"setClientSettings:")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [parameters performSelector:NSSelectorFromString(@"setClientSettings:") withObject:clientSettings];
#pragma clang diagnostic pop
        }
    }
    
    // Validate all required properties before scene creation
    if (!definition.identity) {
        NSLog(@"[HIAHWindowSession] Error: Scene definition missing identity");
        return NO;
    }
    if (!definition.clientIdentity) {
        NSLog(@"[HIAHWindowSession] Error: Scene definition missing clientIdentity");
        return NO;
    }
    if (!definition.specification) {
        NSLog(@"[HIAHWindowSession] Error: Scene definition missing specification");
        return NO;
    }
    if (!parameters) {
        NSLog(@"[HIAHWindowSession] Error: Scene parameters are nil");
        return NO;
    }
    
    // Use respondsToSelector/performSelector for settings to avoid property errors on 'id'
    id parametersSettings = nil;
    if ([parameters respondsToSelector:NSSelectorFromString(@"settings")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        parametersSettings = [parameters performSelector:NSSelectorFromString(@"settings")];
#pragma clang diagnostic pop
    }
    
    if (!parametersSettings) {
        NSLog(@"[HIAHWindowSession] Error: Scene parameters missing settings");
        return NO;
    }
    
    NSLog(@"[HIAHWindowSession] Scene definition validated:");
    NSLog(@"  Identity: %@", definition.identity);
    NSLog(@"  Client Identity: %@", definition.clientIdentity);
    NSLog(@"  Specification: %@", definition.specification);
    NSLog(@"  Settings: %@", parametersSettings);
    
    // Wait a bit longer for the extension process to fully initialize
    // Extension processes need time to register with FrontBoard
    usleep(500000); // 500ms delay
    
    // Create scene
    Class FBSceneManagerClass = NSClassFromString(@"FBSceneManager");
    FBSceneManager *sceneManager = [FBSceneManagerClass sharedInstance];
    if (!sceneManager) {
        NSLog(@"[HIAHWindowSession] Error: FBSceneManager not available");
        return NO;
    }
    
    NSLog(@"[HIAHWindowSession] Creating scene with manager: %@", sceneManager);
    FBScene *scene = nil;
    @try {
        scene = [sceneManager createSceneWithDefinition:definition initialParameters:parameters];
    } @catch (NSException *exception) {
        NSLog(@"[HIAHWindowSession] Exception creating scene: %@", exception);
        return NO;
    }
    
    if (!scene) {
        NSLog(@"[HIAHWindowSession] Error: Failed to create FBScene (returned nil)");
        return NO;
    }
    
    NSLog(@"[HIAHWindowSession] Successfully created scene: %@", scene);
    
    // Create presenter
    UIScenePresentationManager *presentationManager = [scene uiPresentationManager];
    self.presenter = [presentationManager createPresenterWithIdentifier:self.sceneID];
    
    if (!self.presenter) {
        NSLog(@"[HIAHWindowSession] Error: Failed to create presenter");
        return NO;
    }
    
    // Configure presentation context
    [self.presenter modifyPresentationContext:^(id context) {
        // Set appearance style (2 = normal app appearance)
        [context setAppearanceStyle:2];
    }];
    
    // Activate presenter
    [self.presenter activate];
    
    // Add presentation view to content view
    UIView *presentationView = [self.presenter presentationView];
    if (presentationView) {
        [self.contentView addSubview:presentationView];
        presentationView.frame = self.contentView.bounds;
        presentationView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    } else {
        NSLog(@"[HIAHWindowSession] ⚠️ No presentation view from presenter");
    }
    
    self.contentView.layer.anchorPoint = CGPointMake(0, 0);
    self.contentView.layer.position = CGPointMake(0, 0);
    
    // Register settings diff action (self conforms to _UISceneSettingsDiffAction)
    NSArray *diffActions = @[(id)self];
    [windowScene _registerSettingsDiffActionArray:diffActions forKey:self.sceneID];
    
    // Add placeholder for .ipa apps that may take time to render
    // or may not be able to render at all due to UIApplication limitations
    [self addPlaceholderViewWithMessage:@"Loading app..." showSpinner:YES];
    
    // Check for content after a delay - if still empty, show warning
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkForContentAndUpdatePlaceholder];
    });
    
    NSLog(@"[HIAHWindowSession] Opened window for PID %d (sceneID: %@)", self.processPID, self.sceneID);
    
    return YES;
}

- (void)closeWindowWithScene:(UIWindowScene *)windowScene withFrame:(CGRect)rect {
    if (self.sceneID) {
        [windowScene _unregisterSettingsDiffActionArrayForKey:self.sceneID];
    }
    
    if (self.presenter) {
        [self.presenter deactivate];
        [self.presenter invalidate];
        self.presenter = nil;
    }
    
    // Destroy scene with proper cleanup to prevent reconnect errors
    if (self.sceneID) {
        Class FBSceneManagerClass = NSClassFromString(@"FBSceneManager");
        FBSceneManager *sceneManager = [FBSceneManagerClass sharedInstance];
        
        // Try to get the scene first and invalidate it
        SEL sceneWithIdentitySelector = NSSelectorFromString(@"sceneWithIdentity:");
        if (sceneWithIdentitySelector && [sceneManager respondsToSelector:sceneWithIdentitySelector]) {
            Class FBSSceneIdentityClass = NSClassFromString(@"FBSSceneIdentity");
            if (FBSSceneIdentityClass) {
                id sceneIdentity = [FBSSceneIdentityClass identityForIdentifier:self.sceneID];
                if (sceneIdentity) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id scene = [sceneManager performSelector:sceneWithIdentitySelector withObject:sceneIdentity];
                    if (scene && [scene respondsToSelector:@selector(invalidate)]) {
                        [scene performSelector:@selector(invalidate)];
                    }
                    #pragma clang diagnostic pop
                }
            }
        }
        
        // Destroy the scene (only if sceneID is not nil)
        if (self.sceneID) {
        @try {
            // Try to create an empty transition context if the method requires non-null
            id transitionContext = nil;
            Class FBSSceneTransitionContextClass = NSClassFromString(@"FBSSceneTransitionContext");
            if (FBSSceneTransitionContextClass && [FBSSceneTransitionContextClass respondsToSelector:@selector(alloc)]) {
                transitionContext = [[FBSSceneTransitionContextClass alloc] init];
            }
            
            if (transitionContext) {
                [sceneManager destroyScene:self.sceneID withTransitionContext:transitionContext];
            } else {
                // Fallback: suppress warning if transition context creation fails
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wnonnull"
                [sceneManager destroyScene:self.sceneID withTransitionContext:nil];
                #pragma clang diagnostic pop
            }
            NSLog(@"[HIAHWindowSession] Destroyed scene: %@", self.sceneID);
        } @catch (NSException *exception) {
            NSLog(@"[HIAHWindowSession] Exception destroying scene: %@", exception);
        }
        
        self.sceneID = nil;
        }
    }
    
    NSLog(@"[HIAHWindowSession] Closed window for PID %d", self.processPID);
}

- (UIImage *)snapshotWindow {
    // Return snapshot of the presentation view
    if (self.presenter) {
        UIView *presentationView = [self.presenter presentationView];
        UIGraphicsBeginImageContextWithOptions(presentationView.bounds.size, NO, 0);
        [presentationView.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return snapshot;
    }
    return nil;
}

- (void)activateWindow {
    if (!self.presenter) {
        return;
    }
    
    @try {
        id scene = [self.presenter scene];
        if (scene && [scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
            [scene updateSettingsWithBlock:^(id settings) {
                if ([settings respondsToSelector:@selector(setForeground:)]) {
                    [settings setForeground:YES];
                }
            }];
        }
        [self.presenter activate];
    } @catch (NSException *exception) {
        NSLog(@"[HIAHWindowSession] Error activating window: %@", exception.reason);
        // Still try to activate presenter even if settings update fails
        @try {
            [self.presenter activate];
        } @catch (NSException *e) {
            NSLog(@"[HIAHWindowSession] Error activating presenter: %@", e.reason);
        }
    }
}

- (void)deactivateWindow {
    if (!self.presenter) {
        return;
    }
    
    @try {
        id scene = [self.presenter scene];
        if (scene && [scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
            [scene updateSettingsWithBlock:^(id settings) {
                if ([settings respondsToSelector:@selector(setForeground:)]) {
                    [settings setForeground:NO];
                }
            }];
        }
        [self.presenter deactivate];
    } @catch (NSException *exception) {
        NSLog(@"[HIAHWindowSession] Error deactivating window: %@", exception.reason);
        // Still try to deactivate presenter even if settings update fails
        @try {
            [self.presenter deactivate];
        } @catch (NSException *e) {
            NSLog(@"[HIAHWindowSession] Error deactivating presenter: %@", e.reason);
        }
    }
}

- (void)windowChangesSizeToRect:(CGRect)rect {
    if (!self.presenter) {
        return;
    }
    
    @try {
        id scene = [self.presenter scene];
        if (!scene || ![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
            return;
        }
        
        [scene updateSettingsWithBlock:^(id settings) {
            if (!settings) return;
            
            if ([settings respondsToSelector:@selector(setDeviceOrientation:)]) {
                [settings setDeviceOrientation:UIDevice.currentDevice.orientation];
            }
            
            if ([settings respondsToSelector:@selector(setInterfaceOrientation:)] && 
                self.view.window.windowScene) {
                UIWindowScene *ws = self.view.window.windowScene;
                NSInteger interfaceOrientation = UIInterfaceOrientationPortrait;
                if ([ws respondsToSelector:@selector(effectiveGeometry)]) {
                    id effectiveGeometry = [ws performSelector:@selector(effectiveGeometry)];
                    if (effectiveGeometry && [effectiveGeometry respondsToSelector:@selector(interfaceOrientation)]) {
                        interfaceOrientation = (NSInteger)[effectiveGeometry performSelector:@selector(interfaceOrientation)];
                    }
                } else if ([ws respondsToSelector:@selector(interfaceOrientation)]) {
                    // Fallback for iOS < 26.0
                    interfaceOrientation = ws.interfaceOrientation;
                }
                [settings setInterfaceOrientation:interfaceOrientation];
            }
            
            if ([settings respondsToSelector:@selector(setFrame:)]) {
                NSInteger orientation = UIInterfaceOrientationPortrait;
                if ([settings respondsToSelector:@selector(interfaceOrientation)]) {
                    orientation = [settings interfaceOrientation];
                }
                
                if (UIInterfaceOrientationIsLandscape(orientation)) {
                    [settings setFrame:CGRectMake(rect.origin.x, rect.origin.y, rect.size.height, rect.size.width)];
                } else {
                    [settings setFrame:rect];
                }
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"[HIAHWindowSession] Error updating window size: %@", exception.reason);
    }
}

- (void)_performActionsForUIScene:(UIScene *)scene 
                withUpdatedFBSScene:(id)fbsScene 
                        settingsDiff:(id)diff 
                         fromSettings:(id)settings 
                    transitionContext:(id)context 
                  lifecycleActionType:(uint32_t)actionType {
    // Handle scene settings updates
    // Note: Some scenes don't support reconnect/updates, so we need to be careful
    if (!diff || !self.presenter) {
        return;
    }
    
    @try {
        // Check if diff supports settingsByApplyingToMutableCopyOfSettings
        if (![diff respondsToSelector:@selector(settingsByApplyingToMutableCopyOfSettings:)]) {
            return;
        }
        
        id baseSettings = [diff settingsByApplyingToMutableCopyOfSettings:settings];
        if (!baseSettings) {
            return;
        }
        
        id presenterScene = [self.presenter scene];
        if (!presenterScene) {
            return;
        }
        
        // Check if scene supports updateSettings:withTransitionContext:completion:
        if (![presenterScene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)]) {
            // Try alternative method
            if ([presenterScene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
                [presenterScene updateSettingsWithBlock:^(id mutableSettings) {
                    // Copy relevant settings from baseSettings if possible
                    if ([mutableSettings respondsToSelector:@selector(setForeground:)] && 
                        [baseSettings respondsToSelector:@selector(isForeground)]) {
                        [mutableSettings setForeground:[baseSettings isForeground]];
                    }
                }];
            }
            return;
        }
        
        // Attempt to update settings with error handling
        [presenterScene updateSettings:baseSettings withTransitionContext:context completion:nil];
    } @catch (NSException *exception) {
        // Scene doesn't support reconnect/updates - this is expected for some scene types
        // Silently ignore to prevent crashes
        NSLog(@"[HIAHWindowSession] Scene update failed (scene may not support reconnect): %@", exception.reason);
    }
}

#pragma mark - Placeholder UI

static const NSInteger kPlaceholderTag = 99887766;

- (void)addPlaceholderViewWithMessage:(NSString *)message showSpinner:(BOOL)showSpinner {
    // Remove existing placeholder
    [[self.contentView viewWithTag:kPlaceholderTag] removeFromSuperview];
    
    UIView *placeholder = [[UIView alloc] initWithFrame:self.contentView.bounds];
    placeholder.tag = kPlaceholderTag;
    placeholder.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    placeholder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (showSpinner) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        spinner.color = [UIColor whiteColor];
        [spinner startAnimating];
        [stack addArrangedSubview:spinner];
    }
    
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [stack addArrangedSubview:label];
    
    [placeholder addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:placeholder.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:placeholder.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:placeholder.widthAnchor multiplier:0.9]
    ]];
    
    // Insert at back so presenter view is on top if it exists
    [self.contentView insertSubview:placeholder atIndex:0];
}

- (void)removePlaceholderView {
    [[self.contentView viewWithTag:kPlaceholderTag] removeFromSuperview];
}

- (void)checkForContentAndUpdatePlaceholder {
    // Check if presenter has actual content
    BOOL hasContent = NO;
    
    if (self.presenter) {
        UIView *presentationView = [self.presenter presentationView];
        if (presentationView && presentationView.subviews.count > 0) {
            // Check if any subview has non-zero size
            for (UIView *subview in presentationView.subviews) {
                if (!CGSizeEqualToSize(subview.frame.size, CGSizeZero)) {
                    hasContent = YES;
                    break;
                }
            }
        }
    }
    
    // Try to read the extension's log file from App Group (shared location)
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.com.aspauldingcode.HIAHDesktop"];
    NSString *extLogPath = nil;
    if (groupURL) {
        extLogPath = [groupURL.path stringByAppendingPathComponent:@"HIAHExtension.log"];
    } else {
        extLogPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"HIAHExtension.log"];
    }
    
    NSString *extLog = [NSString stringWithContentsOfFile:extLogPath encoding:NSUTF8StringEncoding error:nil];
    if (extLog.length > 0) {
        NSLog(@"[HIAHWindowSession] Extension log contents:\n%@", extLog);
    } else {
        NSLog(@"[HIAHWindowSession] No extension log found at %@", extLogPath);
        NSLog(@"[HIAHWindowSession] Extension logs also visible in Console.app - search for 'HIAHExtension'");
    }
    
    if (hasContent) {
        [self removePlaceholderView];
        NSLog(@"[HIAHWindowSession] ✅ Content detected, removing placeholder");
    } else {
        // Show warning that .ipa app couldn't render
        NSString *warningMessage = @"⚠️ App window could not be captured\n\n"
            "This .ipa app may not be compatible with\n"
            "the HIAH window capture system.\n\n"
            "Complex apps that require full iOS\n"
            "UIApplication lifecycle may not work\n"
            "in HIAH Desktop's sandboxed environment.\n\n"
            "Check Console.app for extension logs\n"
            "(search: 🔮[HIAHProcess]🔮)";
        
        [self addPlaceholderViewWithMessage:warningMessage showSpinner:NO];
        NSLog(@"[HIAHWindowSession] ⚠️ No content after timeout, showing warning");
    }
}

@end

