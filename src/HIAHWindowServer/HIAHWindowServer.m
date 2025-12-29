/**
 * HIAHWindowServer.m
 * Window Server implementation for managing multiple app windows
 */

#import "HIAHWindowServer.h"
#import "HIAHAppWindowSession.h"
#import "HIAHKernel.h"
#import "HIAHProcess.h"
#import "UIKitPrivate+MultitaskSupport.h"

@interface HIAHWindowServer ()
@property (nonatomic, strong) UIWindowScene *serverWindowScene;
@property (nonatomic, assign) HIAHWindowID nextWindowID;
@property (nonatomic, strong) HIAHKernel *kernel;
@end

@implementation HIAHWindowServer

+ (instancetype)sharedWithWindowScene:(UIWindowScene *)windowScene {
    static HIAHWindowServer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HIAHWindowServer alloc] initWithWindowScene:windowScene];
    });
    return shared;
}

+ (instancetype)shared {
    // Get window scene from connected scenes
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) {
        return nil;
    }
    return [self sharedWithWindowScene:scene];
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    if (windowScene) {
        self = [super initWithWindowScene:windowScene];
    } else {
        // Get window scene from connected scenes
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) {
            return nil;
        }
        self = [super initWithWindowScene:scene];
    }
    
    if (self) {
        _windows = [NSMutableDictionary dictionary];
        _windowOrder = [NSMutableArray array];
        _nextWindowID = 1;
        _kernel = [HIAHKernel sharedKernel];
        _serverWindowScene = windowScene ?: self.windowScene;
        
        self.backgroundColor = [UIColor blackColor];
    }
    return self;
}

- (HIAHWindowID)openWindowForProcess:(pid_t)pid 
                        executablePath:(NSString *)executablePath
                      bundleIdentifier:(nullable NSString *)bundleIdentifier
                            completion:(void (^)(HIAHWindowID windowID, NSError * _Nullable error))completion {
    
    // Get process from kernel
    HIAHProcess *process = [self.kernel processForPID:pid];
    if (!process) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"HIAHWindowServer" 
                                                 code:1 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Process not found"}];
            completion(-1, error);
        }
        return -1;
    }
    
    // Create window session
    HIAHAppWindowSession *session = [[HIAHAppWindowSession alloc] initWithProcess:process kernel:self.kernel];
    
    // Assign window ID
    HIAHWindowID windowID = self.nextWindowID++;
    
    // Open window
    BOOL success = [session openWindowWithScene:self.serverWindowScene withSessionIdentifier:windowID];
    
    if (!success) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"HIAHWindowServer" 
                                                 code:2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to open window"}];
            completion(-1, error);
        }
        return -1;
    }
    
    // Store window
    self.windows[@(windowID)] = session;
    [self.windowOrder insertObject:@(windowID) atIndex:0];
    
    // Notify delegate
    if (self.delegate) {
        [self.delegate windowServerDidUpdateWindows];
    }
    
    if (completion) {
        completion(windowID, nil);
    }
    
    NSLog(@"[HIAHWindowServer] Opened window %ld for PID %d (%@)", (long)windowID, pid, executablePath);
    
    return windowID;
}

- (BOOL)closeWindowWithID:(HIAHWindowID)windowID {
    UIViewController *windowVC = self.windows[@(windowID)];
    if (!windowVC) {
        return NO;
    }
    
    if ([windowVC conformsToProtocol:@protocol(HIAHWindowSession)]) {
        id<HIAHWindowSession> session = (id<HIAHWindowSession>)windowVC;
        [session closeWindowWithScene:self.serverWindowScene withFrame:CGRectZero];
    }
    
    [self.windows removeObjectForKey:@(windowID)];
    [self.windowOrder removeObject:@(windowID)];
    
    // Notify delegate
    if (self.delegate) {
        [self.delegate windowServerDidUpdateWindows];
    }
    
    NSLog(@"[HIAHWindowServer] Closed window %ld", (long)windowID);
    
    return YES;
}

- (void)activateWindowWithID:(HIAHWindowID)windowID animated:(BOOL)animated {
    UIViewController *windowVC = self.windows[@(windowID)];
    if ([windowVC conformsToProtocol:@protocol(HIAHWindowSession)]) {
        id<HIAHWindowSession> session = (id<HIAHWindowSession>)windowVC;
        [session activateWindow];
        
        // Move to front
        [self.windowOrder removeObject:@(windowID)];
        [self.windowOrder insertObject:@(windowID) atIndex:0];
        
        // Bring view to front
        [self bringSubviewToFront:windowVC.view];
    }
}

- (void)focusWindowWithID:(HIAHWindowID)windowID {
    [self activateWindowWithID:windowID animated:YES];
}

- (UIViewController *)windowForID:(HIAHWindowID)windowID {
    return self.windows[@(windowID)];
}

- (void)closeAllWindows {
    NSLog(@"[HIAHWindowServer] Closing all windows and destroying scenes...");
    
    // Close all windows (this will destroy their FrontBoard scenes)
    NSArray *windowIDs = [self.windows.allKeys copy];
    for (NSNumber *windowIDNum in windowIDs) {
        HIAHWindowID windowID = windowIDNum.integerValue;
        [self closeWindowWithID:windowID];
    }
    
    NSLog(@"[HIAHWindowServer] All windows closed");
}

@end

