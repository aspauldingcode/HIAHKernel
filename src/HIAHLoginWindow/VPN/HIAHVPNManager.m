#import "../../HIAHDesktop/HIAHLogging.h"
#import "EMProxyBridge.h"
#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

@interface HIAHVPNManager : NSObject

@property(nonatomic, assign, readonly) BOOL isVPNActive;
@property(nonatomic, strong, readonly) NEVPNManager *vpnManager;

+ (instancetype)sharedManager;
- (void)setupVPNManager;
- (void)startVPNWithCompletion:(void (^)(NSError *_Nullable error))completion;
- (void)stopVPN;

@end

@implementation HIAHVPNManager

+ (instancetype)sharedManager {
  static HIAHVPNManager *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _isVPNActive = NO;
    [self setupVPNManager];
  }
  return self;
}

- (void)setupVPNManager {
  [NETunnelProviderManager
      loadAllFromPreferencesWithCompletionHandler:^(
          NSArray<NETunnelProviderManager *> *_Nullable managers,
          NSError *_Nullable error) {
        if (error) {
          HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to load VPN managers: %@",
                    error);
          return;
        }

        if (managers.count > 0) {
          self->_vpnManager = managers.firstObject;
          [self observeVPNStatus];
        } else {
          [self createVPNConfiguration];
        }
      }];
}

- (void)createVPNConfiguration {
  NETunnelProviderManager *manager = [[NETunnelProviderManager alloc] init];
  manager.localizedDescription = @"HIAH Desktop VPN";

  NETunnelProviderProtocol *proto = [[NETunnelProviderProtocol alloc] init];
  proto.providerBundleIdentifier =
      @"com.aspauldingcode.HIAHDesktop.VPNExtension";
  proto.serverAddress = @"127.0.0.1";

  manager.protocolConfiguration = proto;
  manager.enabled = YES;

  [manager saveToPreferencesWithCompletionHandler:^(NSError *_Nullable error) {
    if (error) {
      HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to save VPN config: %@",
                error);
      return;
    }

    self->_vpnManager = manager;
    [self observeVPNStatus];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"VPN configuration created");
  }];
}

- (void)observeVPNStatus {
  if (!_vpnManager)
    return;

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(updateVPNStatus)
             name:NEVPNStatusDidChangeNotification
           object:_vpnManager.connection];
  [self updateVPNStatus];
}

- (void)updateVPNStatus {
  if (!_vpnManager)
    return;
  NEVPNStatus status = _vpnManager.connection.status;
  _isVPNActive = (status == NEVPNStatusConnected);
  HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Status changed: %ld", (long)status);
}

- (void)startVPNWithCompletion:(void (^)(NSError *_Nullable error))completion {
  HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting VPN tunnel...");

  // Start em-proxy
  int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
  if (result != 0) {
    if (completion)
      completion([NSError
          errorWithDomain:@"VPNManager"
                     code:result
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to spawn em_proxy"
                 }]);
    return;
  }

  // Start Tunnel
  NSError *startError = nil;
  [_vpnManager.connection startVPNTunnelAndReturnError:&startError];
  if (startError) {
    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to start tunnel: %@",
              startError);
    [EMProxyBridge stopVPN];
    if (completion)
      completion(startError);
  } else {
    if (completion)
      completion(nil);
  }
}

- (void)stopVPN {
  HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Stopping VPN tunnel...");
  [_vpnManager.connection stopVPNTunnel];
  [EMProxyBridge stopVPN];
}

@end
