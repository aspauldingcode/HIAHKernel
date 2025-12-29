/**
 * HIAHTopViewController.m
 * HIAH Top - Main Process Management UI Implementation
 */

#import "HIAHTopViewController.h"
#import "../HIAHLoginWindow/VPN/HIAHVPNManager.h"
#import "HIAHKernel.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const kProcessCellIdentifier = @"ProcessCell";

#pragma mark - Process Cell

@interface HIAHProcessCell : UITableViewCell
@property(nonatomic, strong) UILabel *pidLabel;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *cpuLabel;
@property(nonatomic, strong) UILabel *memoryLabel;
@property(nonatomic, strong) UILabel *stateLabel;
@property(nonatomic, strong) UIView *stateIndicator;
@property(nonatomic, strong) UILabel *deltaIndicator;

- (void)configureWithProcess:(HIAHManagedProcess *)process;
@end

@implementation HIAHProcessCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    [self setupSubviews];
  }
  return self;
}

- (void)setupSubviews {
  self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
  self.selectionStyle = UITableViewCellSelectionStyleNone;

  // State indicator (colored dot)
  self.stateIndicator = [[UIView alloc] init];
  self.stateIndicator.layer.cornerRadius = 4;
  self.stateIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.stateIndicator];

  // PID label
  self.pidLabel = [[UILabel alloc] init];
  self.pidLabel.font = [UIFont monospacedSystemFontOfSize:12
                                                   weight:UIFontWeightMedium];
  self.pidLabel.textColor = [UIColor colorWithRed:0.4
                                            green:0.8
                                             blue:1.0
                                            alpha:1.0];
  self.pidLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.pidLabel];

  // Name label
  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = [UIFont systemFontOfSize:14
                                          weight:UIFontWeightSemibold];
  self.nameLabel.textColor = [UIColor whiteColor];
  self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.nameLabel];

  // State label
  self.stateLabel = [[UILabel alloc] init];
  self.stateLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
  self.stateLabel.textColor = [UIColor lightGrayColor];
  self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.stateLabel];

  // CPU label
  self.cpuLabel = [[UILabel alloc] init];
  self.cpuLabel.font = [UIFont monospacedSystemFontOfSize:12
                                                   weight:UIFontWeightRegular];
  self.cpuLabel.textColor = [UIColor colorWithRed:1.0
                                            green:0.8
                                             blue:0.3
                                            alpha:1.0];
  self.cpuLabel.textAlignment = NSTextAlignmentRight;
  self.cpuLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.cpuLabel];

  // Memory label
  self.memoryLabel = [[UILabel alloc] init];
  self.memoryLabel.font =
      [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
  self.memoryLabel.textColor = [UIColor colorWithRed:0.6
                                               green:0.9
                                                blue:0.6
                                               alpha:1.0];
  self.memoryLabel.textAlignment = NSTextAlignmentRight;
  self.memoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.memoryLabel];

  // Delta indicator
  self.deltaIndicator = [[UILabel alloc] init];
  self.deltaIndicator.font = [UIFont systemFontOfSize:10
                                               weight:UIFontWeightBold];
  self.deltaIndicator.textColor = [UIColor redColor];
  self.deltaIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  self.deltaIndicator.hidden = YES;
  [self.contentView addSubview:self.deltaIndicator];

  // Make labels adjust font size for mobile
  self.nameLabel.adjustsFontSizeToFitWidth = YES;
  self.nameLabel.minimumScaleFactor = 0.8;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.stateLabel.adjustsFontSizeToFitWidth = YES;
  self.stateLabel.minimumScaleFactor = 0.8;
  self.cpuLabel.adjustsFontSizeToFitWidth = YES;
  self.cpuLabel.minimumScaleFactor = 0.7;
  self.memoryLabel.adjustsFontSizeToFitWidth = YES;
  self.memoryLabel.minimumScaleFactor = 0.7;

  // Clean fixed-width column layout (aligned like a proper table)
  // Layout: [●] PID    Name            CPU    Memory
  //         8   50     (flexible)      50     60

  [NSLayoutConstraint activateConstraints:@[
    // State indicator (dot) - left edge
    [self.stateIndicator.leadingAnchor
        constraintEqualToAnchor:self.contentView.leadingAnchor
                       constant:8],
    [self.stateIndicator.centerYAnchor
        constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.stateIndicator.widthAnchor constraintEqualToConstant:8],
    [self.stateIndicator.heightAnchor constraintEqualToConstant:8],

    // PID - fixed 50px column after dot
    [self.pidLabel.leadingAnchor
        constraintEqualToAnchor:self.contentView.leadingAnchor
                       constant:22],
    [self.pidLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                            constant:8],
    [self.pidLabel.widthAnchor constraintEqualToConstant:50],

    // Name - fills remaining space
    [self.nameLabel.leadingAnchor
        constraintEqualToAnchor:self.contentView.leadingAnchor
                       constant:78],
    [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                             constant:8],
    [self.nameLabel.trailingAnchor
        constraintEqualToAnchor:self.contentView.trailingAnchor
                       constant:-124],

    // State below name
    [self.stateLabel.leadingAnchor
        constraintEqualToAnchor:self.nameLabel.leadingAnchor],
    [self.stateLabel.topAnchor
        constraintEqualToAnchor:self.nameLabel.bottomAnchor
                       constant:2],
    [self.stateLabel.bottomAnchor
        constraintEqualToAnchor:self.contentView.bottomAnchor
                       constant:-8],
    [self.stateLabel.trailingAnchor
        constraintEqualToAnchor:self.nameLabel.trailingAnchor],

    // CPU - fixed 50px from right
    [self.cpuLabel.trailingAnchor
        constraintEqualToAnchor:self.contentView.trailingAnchor
                       constant:-66],
    [self.cpuLabel.centerYAnchor
        constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.cpuLabel.widthAnchor constraintEqualToConstant:50],

    // Memory - fixed 60px at right edge
    [self.memoryLabel.trailingAnchor
        constraintEqualToAnchor:self.contentView.trailingAnchor
                       constant:-6],
    [self.memoryLabel.centerYAnchor
        constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.memoryLabel.widthAnchor constraintEqualToConstant:60],

    // Delta indicator next to CPU
    [self.deltaIndicator.trailingAnchor
        constraintEqualToAnchor:self.cpuLabel.leadingAnchor
                       constant:-2],
    [self.deltaIndicator.centerYAnchor
        constraintEqualToAnchor:self.cpuLabel.centerYAnchor],
  ]];
}

- (void)configureWithProcess:(HIAHManagedProcess *)process {
  self.pidLabel.text = [NSString stringWithFormat:@"%d", process.pid];
  self.nameLabel.text = process.name;
  self.stateLabel.text =
      [NSString stringWithFormat:@"%@ • %.1fs uptime", [process stateString],
                                 process.uptime];
  self.cpuLabel.text =
      [NSString stringWithFormat:@"%.1f%%", process.cpu.totalUsagePercent];
  self.memoryLabel.text = [process.memory formattedResidentSize];

  // Add visual indicator for tree mode (indent children)
  // This will be set by the view controller based on grouping mode

  // State indicator color
  UIColor *stateColor;
  switch (process.state) {
  case HIAHProcessStateRunning:
    stateColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0];
    break;
  case HIAHProcessStateSleeping:
    stateColor = [UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0];
    break;
  case HIAHProcessStateStopped:
    stateColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0];
    break;
  case HIAHProcessStateZombie:
    stateColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.2 alpha:1.0];
    break;
  case HIAHProcessStateDead:
    stateColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
    break;
  default:
    stateColor = [UIColor grayColor];
    break;
  }
  self.stateIndicator.backgroundColor = stateColor;

  // Delta indicator (highlight spikes - Section 10)
  if (process.cpu.deltaPercent > 5.0) {
    self.deltaIndicator.hidden = NO;
    self.deltaIndicator.text = @"^";
    self.deltaIndicator.textColor = [UIColor colorWithRed:1.0
                                                    green:0.3
                                                     blue:0.3
                                                    alpha:1.0];
  } else if (process.memory.deltaResident > 1024 * 1024) {
    self.deltaIndicator.hidden = NO;
    self.deltaIndicator.text = @"^";
    self.deltaIndicator.textColor = [UIColor colorWithRed:1.0
                                                    green:0.6
                                                     blue:0.2
                                                    alpha:1.0];
  } else {
    self.deltaIndicator.hidden = YES;
  }

  // Limited access indicator
  if (process.hasLimitedAccess) {
    self.nameLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  } else {
    self.nameLabel.textColor = [UIColor whiteColor];
  }
}

@end

#pragma mark - HIAHTopViewController

@interface HIAHTopViewController ()
@property(nonatomic, strong) NSArray<HIAHManagedProcess *> *displayedProcesses;
@property(nonatomic, strong) NSDateFormatter *dateFormatter;
@property(nonatomic, assign) BOOL isUserInteracting;
@property(nonatomic, strong)
    NSArray<HIAHManagedProcess *> *lastDisplayedProcesses;
@property(nonatomic, strong) NSTimer *updateThrottleTimer;
@property(nonatomic, assign) BOOL isScrolling;
@property(nonatomic, assign) BOOL isSwiping;
@property(nonatomic, assign) BOOL viewHasAppeared;
@property(nonatomic, strong) UILabel *vpnStatusLabel;
@property(nonatomic, strong) UILabel *jitStatusLabel;
@end

@implementation HIAHTopViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.backgroundColor = [UIColor blackColor];
  self.title = @"HIAH Top";

  // Initialize formatters
  self.dateFormatter = [[NSDateFormatter alloc] init];
  self.dateFormatter.dateFormat = @"HH:mm:ss";

  // Initialize process manager
  self.processManager = [HIAHProcessManager sharedManager];
  // Don't set delegate yet - will set in viewDidAppear to avoid early callbacks
  self.processManager.refreshInterval = 1.0;

  // Ensure kernel is connected and processes are loaded
  // This is critical for nested processes (like HIAHTop running inside HIAH
  // Desktop)
  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  if (kernel) {
    // Force immediate sync before starting sampling to populate initial process
    // list Note: reloadProcessList will check if view is in window hierarchy
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          [self.processManager syncWithKernel];
          dispatch_async(dispatch_get_main_queue(), ^{
            // Only reload if view is already in window hierarchy
            if (self.view.window) {
              [self reloadProcessList];
            }
          });
        });
  } else {
    NSLog(@"[HIAHTop] WARNING: Kernel not available yet");
  }

  // Setup UI
  [self setupStatsHeader];
  [self setupToolbar];
  [self setupTableView];
  [self setupNavigationBar];

  // Don't reload here - wait until viewDidAppear when view is in window
  // hierarchy Initial load will happen in viewDidAppear

  // Force immediate sync with kernel (on main thread after UI is set up)
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self.processManager sample];
      });

  // Start sampling - only show real processes from HIAHKernel
  // Start sampling - only show real processes from HIAHKernel
  [self.processManager startSampling];

  // Check VPN status periodically
  [NSTimer scheduledTimerWithTimeInterval:2.0
                                   target:self
                                 selector:@selector(updateStatusIndicators)
                                 userInfo:nil
                                  repeats:YES];
}

- (void)updateStatusIndicators {
  BOOL vpnActive = [HIAHVPNManager sharedManager].isVPNActive;

  if (vpnActive) {
    self.vpnStatusLabel.text = @"VPN: ON";
    self.vpnStatusLabel.textColor = [UIColor colorWithRed:0.3
                                                    green:0.9
                                                     blue:0.3
                                                    alpha:1.0];
    self.jitStatusLabel.text = @"JIT: READY";
    self.jitStatusLabel.textColor = [UIColor colorWithRed:0.4
                                                    green:0.8
                                                     blue:1.0
                                                    alpha:1.0];
  } else {
    self.vpnStatusLabel.text = @"VPN: OFF";
    self.vpnStatusLabel.textColor = [UIColor grayColor];
    self.jitStatusLabel.text = @"JIT: OFF";
    self.jitStatusLabel.textColor = [UIColor grayColor];
  }
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  // Mark that view has appeared
  self.viewHasAppeared = YES;

  // NOW add table view to hierarchy and activate constraints
  // This ensures the table view is only laid out when the view controller is in
  // the window
  if (!self.tableView.superview) {
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
      [self.tableView.topAnchor
          constraintEqualToAnchor:self.toolbar.bottomAnchor],
      [self.tableView.leadingAnchor
          constraintEqualToAnchor:self.view.leadingAnchor],
      [self.tableView.trailingAnchor
          constraintEqualToAnchor:self.view.trailingAnchor],
      [self.tableView.bottomAnchor
          constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
  }

  // NOW set the table view data source/delegate - after view is in hierarchy
  // This prevents immediate layout before view is ready
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  // NOW set the process manager delegate - after view is in hierarchy
  // This prevents delegate callbacks during setup
  self.processManager.delegate = self;

  // Now that view is in window hierarchy, do initial load
  [self reloadProcessList];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  self.viewHasAppeared = NO; // Reset flag when view disappears

  // Remove delegate to prevent callbacks when view isn't visible
  self.processManager.delegate = nil;

  [self.processManager stopSampling];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  // Update table header view size after layout - ensure full width
  if (self.tableView.tableHeaderView) {
    UIView *headerView = self.tableView.tableHeaderView;
    CGRect headerFrame = headerView.frame;
    CGFloat tableWidth = self.tableView.bounds.size.width;
    if (headerFrame.size.width != tableWidth) {
      headerFrame.size.width = tableWidth;
      headerFrame.size.height = 28;
      headerView.frame = headerFrame;
      [headerView setNeedsLayout];
      [headerView layoutIfNeeded];
      // Reassign to trigger layout update
      self.tableView.tableHeaderView = nil;
      self.tableView.tableHeaderView = headerView;
    }
  }
}

#pragma mark - Setup

- (void)setupNavigationBar {
  self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
  self.navigationController.navigationBar.tintColor =
      [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];

  // Search
  self.searchController =
      [[UISearchController alloc] initWithSearchResultsController:nil];
  self.searchController.searchResultsUpdater =
      (id<UISearchResultsUpdating>)self;
  self.searchController.obscuresBackgroundDuringPresentation = NO;
  self.searchController.searchBar.placeholder = @"Filter by name or PID";
  self.searchController.searchBar.barStyle = UIBarStyleBlack;
  self.navigationItem.searchController = self.searchController;
  self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupStatsHeader {
  self.statsHeaderView = [[UIView alloc] init];
  self.statsHeaderView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
  self.statsHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.statsHeaderView];

  // Title label at top
  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = @"HIAH Top";
  titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
  titleLabel.textColor = [UIColor whiteColor];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.statsHeaderView addSubview:titleLabel];

  // Create a container stack view for better mobile layout
  UIStackView *statsStack = [[UIStackView alloc] init];
  statsStack.axis = UILayoutConstraintAxisVertical;
  statsStack.distribution = UIStackViewDistributionFillEqually;
  statsStack.spacing = 8;
  statsStack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.statsHeaderView addSubview:statsStack];

  // Top row: CPU and Memory side by side
  UIStackView *topRow = [[UIStackView alloc] init];
  topRow.axis = UILayoutConstraintAxisHorizontal;
  topRow.distribution = UIStackViewDistributionFillEqually;
  topRow.spacing = 12;
  topRow.translatesAutoresizingMaskIntoConstraints = NO;

  // CPU Section
  UIView *cpuContainer = [[UIView alloc] init];
  cpuContainer.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel *cpuTitle = [[UILabel alloc] init];
  cpuTitle.text = @"CPU";
  cpuTitle.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
  cpuTitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  cpuTitle.translatesAutoresizingMaskIntoConstraints = NO;
  [cpuContainer addSubview:cpuTitle];

  self.cpuLabel = [[UILabel alloc] init];
  self.cpuLabel.text = @"0.0%";
  self.cpuLabel.font = [UIFont monospacedSystemFontOfSize:16
                                                   weight:UIFontWeightBold];
  self.cpuLabel.textColor = [UIColor colorWithRed:1.0
                                            green:0.8
                                             blue:0.3
                                            alpha:1.0];
  self.cpuLabel.adjustsFontSizeToFitWidth = YES;
  self.cpuLabel.minimumScaleFactor = 0.7;
  self.cpuLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [cpuContainer addSubview:self.cpuLabel];

  self.cpuProgressView = [[UIProgressView alloc]
      initWithProgressViewStyle:UIProgressViewStyleDefault];
  self.cpuProgressView.progressTintColor = [UIColor colorWithRed:1.0
                                                           green:0.8
                                                            blue:0.3
                                                           alpha:1.0];
  self.cpuProgressView.trackTintColor = [UIColor colorWithWhite:0.2 alpha:1.0];
  self.cpuProgressView.translatesAutoresizingMaskIntoConstraints = NO;
  [cpuContainer addSubview:self.cpuProgressView];

  [NSLayoutConstraint activateConstraints:@[
    [cpuTitle.topAnchor constraintEqualToAnchor:cpuContainer.topAnchor
                                       constant:8],
    [cpuTitle.leadingAnchor constraintEqualToAnchor:cpuContainer.leadingAnchor],
    [cpuTitle.trailingAnchor
        constraintEqualToAnchor:cpuContainer.trailingAnchor],

    [self.cpuLabel.topAnchor constraintEqualToAnchor:cpuTitle.bottomAnchor
                                            constant:4],
    [self.cpuLabel.leadingAnchor
        constraintEqualToAnchor:cpuContainer.leadingAnchor],
    [self.cpuLabel.trailingAnchor
        constraintEqualToAnchor:cpuContainer.trailingAnchor],

    [self.cpuProgressView.topAnchor
        constraintEqualToAnchor:self.cpuLabel.bottomAnchor
                       constant:6],
    [self.cpuProgressView.leadingAnchor
        constraintEqualToAnchor:cpuContainer.leadingAnchor],
    [self.cpuProgressView.trailingAnchor
        constraintEqualToAnchor:cpuContainer.trailingAnchor],
    [self.cpuProgressView.bottomAnchor
        constraintEqualToAnchor:cpuContainer.bottomAnchor
                       constant:-4],
  ]];

  // Memory Section
  UIView *memContainer = [[UIView alloc] init];
  memContainer.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel *memTitle = [[UILabel alloc] init];
  memTitle.text = @"MEMORY";
  memTitle.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
  memTitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  memTitle.translatesAutoresizingMaskIntoConstraints = NO;
  [memContainer addSubview:memTitle];

  self.memoryLabel = [[UILabel alloc] init];
  self.memoryLabel.text = @"0 MB";
  self.memoryLabel.font = [UIFont monospacedSystemFontOfSize:16
                                                      weight:UIFontWeightBold];
  self.memoryLabel.textColor = [UIColor colorWithRed:0.6
                                               green:0.9
                                                blue:0.6
                                               alpha:1.0];
  self.memoryLabel.adjustsFontSizeToFitWidth = YES;
  self.memoryLabel.minimumScaleFactor = 0.7;
  self.memoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [memContainer addSubview:self.memoryLabel];

  self.memoryProgressView = [[UIProgressView alloc]
      initWithProgressViewStyle:UIProgressViewStyleDefault];
  self.memoryProgressView.progressTintColor = [UIColor colorWithRed:0.6
                                                              green:0.9
                                                               blue:0.6
                                                              alpha:1.0];
  self.memoryProgressView.trackTintColor = [UIColor colorWithWhite:0.2
                                                             alpha:1.0];
  self.memoryProgressView.translatesAutoresizingMaskIntoConstraints = NO;
  [memContainer addSubview:self.memoryProgressView];

  [NSLayoutConstraint activateConstraints:@[
    [memTitle.topAnchor constraintEqualToAnchor:memContainer.topAnchor
                                       constant:8],
    [memTitle.leadingAnchor constraintEqualToAnchor:memContainer.leadingAnchor],
    [memTitle.trailingAnchor
        constraintEqualToAnchor:memContainer.trailingAnchor],

    [self.memoryLabel.topAnchor constraintEqualToAnchor:memTitle.bottomAnchor
                                               constant:4],
    [self.memoryLabel.leadingAnchor
        constraintEqualToAnchor:memContainer.leadingAnchor],
    [self.memoryLabel.trailingAnchor
        constraintEqualToAnchor:memContainer.trailingAnchor],

    [self.memoryProgressView.topAnchor
        constraintEqualToAnchor:self.memoryLabel.bottomAnchor
                       constant:6],
    [self.memoryProgressView.leadingAnchor
        constraintEqualToAnchor:memContainer.leadingAnchor],
    [self.memoryProgressView.trailingAnchor
        constraintEqualToAnchor:memContainer.trailingAnchor],
    [self.memoryProgressView.bottomAnchor
        constraintEqualToAnchor:memContainer.bottomAnchor
                       constant:-4],
  ]];

  [topRow addArrangedSubview:cpuContainer];
  [topRow addArrangedSubview:memContainer];

  // Bottom row: Process count and load
  UIView *bottomRow = [[UIView alloc] init];
  bottomRow.translatesAutoresizingMaskIntoConstraints = NO;

  self.processCountLabel = [[UILabel alloc] init];
  self.processCountLabel.text = @"0 processes • 0 threads";
  self.processCountLabel.font = [UIFont systemFontOfSize:10
                                                  weight:UIFontWeightMedium];
  self.processCountLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  self.processCountLabel.adjustsFontSizeToFitWidth = YES;
  self.processCountLabel.minimumScaleFactor = 0.8;
  self.processCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [bottomRow addSubview:self.processCountLabel];

  self.loadLabel = [[UILabel alloc] init];
  self.loadLabel.text = @"Load: 0.00 0.00 0.00";
  self.loadLabel.font = [UIFont monospacedSystemFontOfSize:10
                                                    weight:UIFontWeightRegular];
  self.loadLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  self.loadLabel.textAlignment = NSTextAlignmentRight;
  self.loadLabel.adjustsFontSizeToFitWidth = YES;
  self.loadLabel.minimumScaleFactor = 0.8;
  self.loadLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [bottomRow addSubview:self.loadLabel];

  // Status Indicators (VPN & JIT)
  self.vpnStatusLabel = [[UILabel alloc] init];
  self.vpnStatusLabel.font = [UIFont systemFontOfSize:10
                                               weight:UIFontWeightBold];
  self.vpnStatusLabel.text = @"VPN: OFF";
  self.vpnStatusLabel.textColor = [UIColor grayColor];
  self.vpnStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [bottomRow addSubview:self.vpnStatusLabel];

  self.jitStatusLabel = [[UILabel alloc] init];
  self.jitStatusLabel.font = [UIFont systemFontOfSize:10
                                               weight:UIFontWeightBold];
  self.jitStatusLabel.text = @"JIT: OFF";
  self.jitStatusLabel.textColor = [UIColor grayColor];
  self.jitStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [bottomRow addSubview:self.jitStatusLabel];

  [NSLayoutConstraint activateConstraints:@[
    [self.processCountLabel.leadingAnchor
        constraintEqualToAnchor:bottomRow.leadingAnchor
                       constant:12],
    [self.processCountLabel.centerYAnchor
        constraintEqualToAnchor:bottomRow.centerYAnchor],

    [self.vpnStatusLabel.leadingAnchor
        constraintEqualToAnchor:self.processCountLabel.trailingAnchor
                       constant:12],
    [self.vpnStatusLabel.centerYAnchor
        constraintEqualToAnchor:bottomRow.centerYAnchor],

    [self.jitStatusLabel.leadingAnchor
        constraintEqualToAnchor:self.vpnStatusLabel.trailingAnchor
                       constant:12],
    [self.jitStatusLabel.centerYAnchor
        constraintEqualToAnchor:bottomRow.centerYAnchor],

    [self.loadLabel.trailingAnchor
        constraintEqualToAnchor:bottomRow.trailingAnchor
                       constant:-12],
    [self.loadLabel.centerYAnchor
        constraintEqualToAnchor:bottomRow.centerYAnchor],
  ]];

  [self updateStatusIndicators];

  [statsStack addArrangedSubview:topRow];
  [statsStack addArrangedSubview:bottomRow];

  // Layout header
  [NSLayoutConstraint activateConstraints:@[
    [self.statsHeaderView.topAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.statsHeaderView.leadingAnchor
        constraintEqualToAnchor:self.view.leadingAnchor],
    [self.statsHeaderView.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor],
    [self.statsHeaderView.heightAnchor
        constraintEqualToConstant:130], // Taller for title

    // Title at top, full width
    [titleLabel.topAnchor constraintEqualToAnchor:self.statsHeaderView.topAnchor
                                         constant:8],
    [titleLabel.leadingAnchor
        constraintEqualToAnchor:self.statsHeaderView.leadingAnchor
                       constant:12],
    [titleLabel.trailingAnchor
        constraintEqualToAnchor:self.statsHeaderView.trailingAnchor
                       constant:-12],
    [titleLabel.heightAnchor constraintEqualToConstant:24],

    // Stats below title
    [statsStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                         constant:4],
    [statsStack.leadingAnchor
        constraintEqualToAnchor:self.statsHeaderView.leadingAnchor
                       constant:12],
    [statsStack.trailingAnchor
        constraintEqualToAnchor:self.statsHeaderView.trailingAnchor
                       constant:-12],
    [statsStack.bottomAnchor
        constraintEqualToAnchor:self.statsHeaderView.bottomAnchor
                       constant:-4],
  ]];
}

- (void)setupToolbar {
  // Create a container view for better mobile layout
  UIView *toolbarContainer = [[UIView alloc] init];
  toolbarContainer.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
  toolbarContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:toolbarContainer];

  // View mode segment - make it smaller and more mobile-friendly
  self.viewModeSegment =
      [[UISegmentedControl alloc] initWithItems:@[ @"Flat", @"Tree", @"User" ]];
  self.viewModeSegment.selectedSegmentIndex = 0;
  self.viewModeSegment.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
  self.viewModeSegment.selectedSegmentTintColor = [UIColor colorWithRed:0.4
                                                                  green:0.8
                                                                   blue:1.0
                                                                  alpha:1.0];
  [self.viewModeSegment setTitleTextAttributes:@{
    NSForegroundColorAttributeName : [UIColor whiteColor],
    NSFontAttributeName : [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]
  }
                                      forState:UIControlStateNormal];
  [self.viewModeSegment setTitleTextAttributes:@{
    NSForegroundColorAttributeName : [UIColor whiteColor],
    NSFontAttributeName : [UIFont systemFontOfSize:12 weight:UIFontWeightBold]
  }
                                      forState:UIControlStateSelected];
  [self.viewModeSegment addTarget:self
                           action:@selector(viewModeChanged:)
                 forControlEvents:UIControlEventValueChanged];
  self.viewModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
  [toolbarContainer addSubview:self.viewModeSegment];

  // Create a scrollable container for buttons
  UIScrollView *buttonScrollView = [[UIScrollView alloc] init];
  buttonScrollView.showsHorizontalScrollIndicator = NO;
  buttonScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  [toolbarContainer addSubview:buttonScrollView];

  UIStackView *buttonStack = [[UIStackView alloc] init];
  buttonStack.axis = UILayoutConstraintAxisHorizontal;
  buttonStack.distribution = UIStackViewDistributionEqualSpacing;
  buttonStack.spacing = 12;
  buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
  [buttonScrollView addSubview:buttonStack];

  // Create buttons with proper sizing
  self.pauseButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"pause.fill"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(togglePause:)];
  self.pauseButton.tintColor = [UIColor colorWithRed:0.4
                                               green:0.8
                                                blue:1.0
                                               alpha:1.0];

  self.sortButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(showSortOptions:)];
  self.sortButton.tintColor = [UIColor colorWithRed:0.4
                                              green:0.8
                                               blue:1.0
                                              alpha:1.0];

  self.filterButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(showFilterOptions:)];
  self.filterButton.tintColor = [UIColor colorWithRed:0.4
                                                green:0.8
                                                 blue:1.0
                                                alpha:1.0];

  self.exportButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(exportProcessList:)];
  self.exportButton.tintColor = [UIColor colorWithRed:0.4
                                                green:0.8
                                                 blue:1.0
                                                alpha:1.0];

  // Create custom button views for better control
  UIButton *pauseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  [pauseBtn setImage:[UIImage systemImageNamed:@"pause.fill"]
            forState:UIControlStateNormal];
  pauseBtn.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
  [pauseBtn addTarget:self
                action:@selector(togglePause:)
      forControlEvents:UIControlEventTouchUpInside];
  pauseBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [pauseBtn.widthAnchor constraintEqualToConstant:44].active = YES;
  [pauseBtn.heightAnchor constraintEqualToConstant:44].active = YES;

  UIButton *sortBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  [sortBtn setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
           forState:UIControlStateNormal];
  sortBtn.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
  [sortBtn addTarget:self
                action:@selector(showSortOptions:)
      forControlEvents:UIControlEventTouchUpInside];
  sortBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [sortBtn.widthAnchor constraintEqualToConstant:44].active = YES;
  [sortBtn.heightAnchor constraintEqualToConstant:44].active = YES;

  UIButton *filterBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  [filterBtn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease"]
             forState:UIControlStateNormal];
  filterBtn.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
  [filterBtn addTarget:self
                action:@selector(showFilterOptions:)
      forControlEvents:UIControlEventTouchUpInside];
  filterBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [filterBtn.widthAnchor constraintEqualToConstant:44].active = YES;
  [filterBtn.heightAnchor constraintEqualToConstant:44].active = YES;

  // Test spawn button (for debugging)
  UIButton *testSpawnBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  [testSpawnBtn setImage:[UIImage systemImageNamed:@"plus.app.fill"]
                forState:UIControlStateNormal];
  testSpawnBtn.tintColor = [UIColor colorWithRed:0.3
                                           green:0.8
                                            blue:0.3
                                           alpha:1.0];
  [testSpawnBtn addTarget:self
                   action:@selector(testSpawnProcess:)
         forControlEvents:UIControlEventTouchUpInside];
  testSpawnBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [testSpawnBtn.widthAnchor constraintEqualToConstant:44].active = YES;
  [testSpawnBtn.heightAnchor constraintEqualToConstant:44].active = YES;

  UIButton *exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  [exportBtn setImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
             forState:UIControlStateNormal];
  exportBtn.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
  [exportBtn addTarget:self
                action:@selector(exportProcessList:)
      forControlEvents:UIControlEventTouchUpInside];
  exportBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [exportBtn.widthAnchor constraintEqualToConstant:44].active = YES;
  [exportBtn.heightAnchor constraintEqualToConstant:44].active = YES;

  // Store button references
  self.pauseButton.customView = pauseBtn;
  self.sortButton.customView = sortBtn;
  self.filterButton.customView = filterBtn;
  self.exportButton.customView = exportBtn;

  [buttonStack addArrangedSubview:pauseBtn];
  [buttonStack addArrangedSubview:testSpawnBtn]; // Add test spawn button
  [buttonStack addArrangedSubview:sortBtn];
  [buttonStack addArrangedSubview:filterBtn];
  [buttonStack addArrangedSubview:exportBtn];

  // Layout constraints
  [NSLayoutConstraint activateConstraints:@[
    [toolbarContainer.topAnchor
        constraintEqualToAnchor:self.statsHeaderView.bottomAnchor],
    [toolbarContainer.leadingAnchor
        constraintEqualToAnchor:self.view.leadingAnchor],
    [toolbarContainer.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor],
    [toolbarContainer.heightAnchor constraintEqualToConstant:88],

    // Segment control
    [self.viewModeSegment.topAnchor
        constraintEqualToAnchor:toolbarContainer.topAnchor
                       constant:8],
    [self.viewModeSegment.leadingAnchor
        constraintEqualToAnchor:toolbarContainer.leadingAnchor
                       constant:12],
    [self.viewModeSegment.trailingAnchor
        constraintEqualToAnchor:toolbarContainer.trailingAnchor
                       constant:-12],
    [self.viewModeSegment.heightAnchor constraintEqualToConstant:32],

    // Button scroll view
    [buttonScrollView.topAnchor
        constraintEqualToAnchor:self.viewModeSegment.bottomAnchor
                       constant:4],
    [buttonScrollView.leadingAnchor
        constraintEqualToAnchor:toolbarContainer.leadingAnchor],
    [buttonScrollView.trailingAnchor
        constraintEqualToAnchor:toolbarContainer.trailingAnchor],
    [buttonScrollView.bottomAnchor
        constraintEqualToAnchor:toolbarContainer.bottomAnchor],
    [buttonScrollView.heightAnchor constraintEqualToConstant:44],

    // Button stack
    [buttonStack.topAnchor constraintEqualToAnchor:buttonScrollView.topAnchor],
    [buttonStack.leadingAnchor
        constraintEqualToAnchor:buttonScrollView.leadingAnchor
                       constant:12],
    [buttonStack.trailingAnchor
        constraintEqualToAnchor:buttonScrollView.trailingAnchor
                       constant:-12],
    [buttonStack.bottomAnchor
        constraintEqualToAnchor:buttonScrollView.bottomAnchor],
    [buttonStack.heightAnchor constraintEqualToConstant:44],
  ]];

  // Store reference for later updates
  self.toolbar = toolbarContainer;
}

- (void)setupTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                style:UITableViewStylePlain];
  // DON'T set dataSource/delegate yet - will set in viewDidAppear
  // Setting them here can trigger immediate layout before view is in window
  self.tableView.backgroundColor = [UIColor blackColor];
  self.tableView.separatorColor = [UIColor colorWithWhite:0.15 alpha:1.0];
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 56;
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.tableView registerClass:[HIAHProcessCell class]
         forCellReuseIdentifier:kProcessCellIdentifier];
  // DON'T add as subview yet - will add in viewDidAppear to prevent premature
  // layout

  // Pull to refresh
  self.refreshControl = [[UIRefreshControl alloc] init];
  self.refreshControl.tintColor = [UIColor colorWithRed:0.4
                                                  green:0.8
                                                   blue:1.0
                                                  alpha:1.0];
  [self.refreshControl addTarget:self
                          action:@selector(refresh:)
                forControlEvents:UIControlEventValueChanged];
  self.tableView.refreshControl = self.refreshControl;

  // Column header - aligned with table columns
  UIView *headerView = [[UIView alloc] init];
  headerView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
  headerView.translatesAutoresizingMaskIntoConstraints = NO;

  // Create labels that match column positions exactly
  UILabel *pidHeader = [[UILabel alloc] init];
  pidHeader.text = @"PID";
  pidHeader.font = [UIFont monospacedSystemFontOfSize:9
                                               weight:UIFontWeightBold];
  pidHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  pidHeader.translatesAutoresizingMaskIntoConstraints = NO;
  [headerView addSubview:pidHeader];

  UILabel *nameHeader = [[UILabel alloc] init];
  nameHeader.text = @"NAME";
  nameHeader.font = [UIFont monospacedSystemFontOfSize:9
                                                weight:UIFontWeightBold];
  nameHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  nameHeader.translatesAutoresizingMaskIntoConstraints = NO;
  [headerView addSubview:nameHeader];

  UILabel *cpuHeader = [[UILabel alloc] init];
  cpuHeader.text = @"CPU";
  cpuHeader.font = [UIFont monospacedSystemFontOfSize:9
                                               weight:UIFontWeightBold];
  cpuHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  cpuHeader.textAlignment = NSTextAlignmentRight;
  cpuHeader.translatesAutoresizingMaskIntoConstraints = NO;
  [headerView addSubview:cpuHeader];

  UILabel *memHeader = [[UILabel alloc] init];
  memHeader.text = @"MEMORY";
  memHeader.font = [UIFont monospacedSystemFontOfSize:9
                                               weight:UIFontWeightBold];
  memHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  memHeader.textAlignment = NSTextAlignmentRight;
  memHeader.translatesAutoresizingMaskIntoConstraints = NO;
  [headerView addSubview:memHeader];

  // Position headers to match cell columns exactly
  [NSLayoutConstraint activateConstraints:@[
    [headerView.heightAnchor constraintEqualToConstant:24],

    // PID column (starts at 22, width 50)
    [pidHeader.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                            constant:22],
    [pidHeader.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
    [pidHeader.widthAnchor constraintEqualToConstant:50],

    // NAME column (starts at 78, flexible width)
    [nameHeader.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                             constant:78],
    [nameHeader.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],

    // CPU column (50px width, 66px from right)
    [cpuHeader.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                             constant:-66],
    [cpuHeader.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
    [cpuHeader.widthAnchor constraintEqualToConstant:50],

    // MEM column (60px width, 6px from right)
    [memHeader.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                             constant:-6],
    [memHeader.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
    [memHeader.widthAnchor constraintEqualToConstant:60],
  ]];

  self.tableView.tableHeaderView = headerView;

  // DON'T activate constraints yet - will activate in viewDidAppear
  // This prevents Auto Layout from laying out the table view before it's in the
  // window
}

#pragma mark - Actions

- (void)testSpawnProcess:(id)sender {
  NSLog(@"[HIAHTop] 🧪 Test Spawn button tapped");

  HIAHKernel *kernel = [HIAHKernel sharedKernel];
  if (!kernel) {
    NSLog(@"[HIAHTop] ❌ Kernel not available");
    return;
  }

  // Spawn a test dummy process
  NSString *testPath = @"/test/dummy-process";

  NSLog(@"[HIAHTop] Spawning test process: %@", testPath);

  [kernel
      spawnVirtualProcessWithPath:testPath
                        arguments:@[ @"dummy", @"--test" ]
                      environment:@{@"TEST" : @"1"}
                       completion:^(pid_t pid, NSError *error) {
                         dispatch_async(dispatch_get_main_queue(), ^{
                           if (error) {
                             NSLog(@"[HIAHTop] Spawn error: %@", error);
                           } else {
                             NSLog(@"[HIAHTop] ✅ Test process spawned: PID %d",
                                   pid);
                             NSLog(@"[HIAHTop] Kernel now has %lu processes",
                                   (unsigned long)[kernel allProcesses].count);

                             // Force immediate refresh
                             [self.processManager syncWithKernel];
                             [self reloadProcessList];
                           }
                         });
                       }];
}

- (IBAction)togglePause:(id)sender {
  self.isPaused = !self.isPaused;

  if (self.isPaused) {
    [self.processManager pause];
    if ([sender isKindOfClass:[UIButton class]]) {
      [(UIButton *)sender setImage:[UIImage systemImageNamed:@"play.fill"]
                          forState:UIControlStateNormal];
    } else {
      self.pauseButton.image = [UIImage systemImageNamed:@"play.fill"];
    }
  } else {
    [self.processManager resume];
    if ([sender isKindOfClass:[UIButton class]]) {
      [(UIButton *)sender setImage:[UIImage systemImageNamed:@"pause.fill"]
                          forState:UIControlStateNormal];
    } else {
      self.pauseButton.image = [UIImage systemImageNamed:@"pause.fill"];
    }
  }
}

- (IBAction)showSortOptions:(id)sender {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Sort By"
                       message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];

  NSArray *options = @[
    @{@"title" : @"PID", @"field" : @(HIAHSortFieldPID)},
    @{@"title" : @"Name", @"field" : @(HIAHSortFieldName)},
    @{@"title" : @"CPU %", @"field" : @(HIAHSortFieldCPU)},
    @{@"title" : @"Memory", @"field" : @(HIAHSortFieldMemory)},
    @{@"title" : @"State", @"field" : @(HIAHSortFieldState)},
    @{@"title" : @"Start Time", @"field" : @(HIAHSortFieldStartTime)},
    @{@"title" : @"Threads", @"field" : @(HIAHSortFieldThreads)},
  ];

  for (NSDictionary *opt in options) {
    BOOL isSelected =
        self.processManager.sortField == [opt[@"field"] integerValue];
    NSString *title = isSelected
                          ? [NSString stringWithFormat:@"[x] %@", opt[@"title"]]
                          : opt[@"title"];

    [alert addAction:[UIAlertAction
                         actionWithTitle:title
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *action) {
                                   HIAHSortField field =
                                       [opt[@"field"] integerValue];
                                   BOOL ascending =
                                       (field == self.processManager.sortField)
                                           ? !self.processManager.sortAscending
                                           : YES;
                                   [self.processManager sortByField:field
                                                          ascending:ascending];
                                   [self reloadProcessList];
                                 }]];
  }

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPad) {
    alert.popoverPresentationController.barButtonItem = self.sortButton;
  }

  [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)showFilterOptions:(id)sender {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Filter"
                       message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];

  [alert
      addAction:[UIAlertAction actionWithTitle:@"Show All"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                         self.processManager.filter =
                                             [HIAHProcessFilter defaultFilter];
                                         [self reloadProcessList];
                                       }]];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Running Only"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 HIAHProcessFilter *filter =
                                     [HIAHProcessFilter defaultFilter];
                                 filter.stateFilter = HIAHProcessStateRunning;
                                 self.processManager.filter = filter;
                                 [self reloadProcessList];
                               }]];

  [alert
      addAction:[UIAlertAction actionWithTitle:@"Alive Only"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                         HIAHProcessFilter *filter =
                                             [HIAHProcessFilter defaultFilter];
                                         filter.aliveOnly = YES;
                                         self.processManager.filter = filter;
                                         [self reloadProcessList];
                                       }]];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPad) {
    alert.popoverPresentationController.barButtonItem = self.filterButton;
  }

  [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)exportProcessList:(id)sender {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Export"
                       message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Copy as Text"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 NSString *text =
                                     [self.processManager exportAsText];
                                 [UIPasteboard generalPasteboard].string = text;
                                 [self showToast:@"Copied to clipboard"];
                               }]];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Copy as JSON"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 NSData *json =
                                     [self.processManager exportAsJSON];
                                 NSString *jsonString = [[NSString alloc]
                                     initWithData:json
                                         encoding:NSUTF8StringEncoding];
                                 [UIPasteboard generalPasteboard].string =
                                     jsonString;
                                 [self showToast:@"Copied to clipboard"];
                               }]];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Share Snapshot"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 NSData *json =
                                     [self.processManager exportAsJSON];
                                 NSString *jsonString = [[NSString alloc]
                                     initWithData:json
                                         encoding:NSUTF8StringEncoding];
                                 UIActivityViewController *activityVC =
                                     [[UIActivityViewController alloc]
                                         initWithActivityItems:@[ jsonString ]
                                         applicationActivities:nil];
                                 [self presentViewController:activityVC
                                                    animated:YES
                                                  completion:nil];
                               }]];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPad) {
    alert.popoverPresentationController.barButtonItem = self.exportButton;
  }

  [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)refresh:(id)sender {
  // Force immediate sample (which includes syncWithKernel internally)
  [self.processManager sample];

  // Reload UI after a brief delay to allow sample to complete
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self reloadProcessList];
        [self.refreshControl endRefreshing];
      });
}

- (void)viewModeChanged:(UISegmentedControl *)sender {
  HIAHGroupingMode newMode;
  NSString *modeName;

  switch (sender.selectedSegmentIndex) {
  case 0:
    newMode = HIAHGroupingModeFlat;
    modeName = @"Flat";
    break;
  case 1:
    newMode = HIAHGroupingModeTree;
    modeName = @"Tree";
    break;
  case 2:
    newMode = HIAHGroupingModeUser;
    modeName = @"User";
    break;
  default:
    newMode = HIAHGroupingModeFlat;
    modeName = @"Flat";
    break;
  }

  self.processManager.groupingMode = newMode;

  // Show feedback
  [self showToast:[NSString stringWithFormat:@"Grouping: %@", modeName]];

  // Reload with animation
  [self reloadProcessList];

  NSLog(@"[HIAHTop] Grouping mode changed to: %@ (%ld processes)", modeName,
        (long)self.displayedProcesses.count);
}

#pragma mark - Process Details

- (void)showDetailsForProcess:(HIAHManagedProcess *)process {
  NSString *details = [process toDetailedText];

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:process.name
                                          message:details
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Copy"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 [UIPasteboard generalPasteboard].string =
                                     details;
                               }]];

  [alert addAction:[UIAlertAction actionWithTitle:@"Close"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showActionsForProcess:(HIAHManagedProcess *)process {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:[NSString stringWithFormat:@"%@ (PID %d)",
                                                          process.name,
                                                          process.pid]
                       message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];

  // Info action
  [alert addAction:[UIAlertAction actionWithTitle:@"View Details"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *action) {
                                            [self
                                                showDetailsForProcess:process];
                                          }]];

  // Signal actions (Section 5)
  if (process.canSignal) {
    if (process.state == HIAHProcessStateStopped) {
      [alert addAction:[UIAlertAction actionWithTitle:@"Continue (SIGCONT)"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
                                                [self.processManager
                                                    continueProcess:process.pid
                                                              error:nil];
                                              }]];
    } else {
      [alert addAction:[UIAlertAction actionWithTitle:@"Stop (SIGSTOP)"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
                                                [self.processManager
                                                    stopProcess:process.pid
                                                          error:nil];
                                              }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Terminate (SIGTERM)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              [self.processManager
                                                  terminateProcess:process.pid
                                                             error:nil];
                                            }]];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Kill (SIGKILL)"
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *action) {
                                   [self.processManager killProcess:process.pid
                                                              error:nil];
                                 }]];

    // Tree control
    NSArray *children = [self.processManager childrenOfProcess:process.pid];
    if (children.count > 0) {
      [alert
          addAction:[UIAlertAction
                        actionWithTitle:
                            [NSString
                                stringWithFormat:@"Kill Tree (%lu children)",
                                                 (unsigned long)children.count]
                                  style:UIAlertActionStyleDestructive
                                handler:^(UIAlertAction *action) {
                                  [self.processManager
                                      killProcessTree:process.pid
                                                error:nil];
                                }]];
    }
  }

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UI Helpers

- (void)showToast:(NSString *)message {
  UILabel *toast = [[UILabel alloc] init];
  toast.text = message;
  toast.textColor = [UIColor whiteColor];
  toast.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
  toast.textAlignment = NSTextAlignmentCenter;
  toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  toast.layer.cornerRadius = 8;
  toast.clipsToBounds = YES;
  toast.alpha = 0;

  [toast sizeToFit];
  CGRect frame = toast.frame;
  frame.size.width += 32;
  frame.size.height += 16;
  toast.frame = frame;
  toast.center =
      CGPointMake(self.view.center.x, self.view.bounds.size.height - 100);

  [self.view addSubview:toast];

  [UIView animateWithDuration:0.3
      animations:^{
        toast.alpha = 1;
      }
      completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                         [UIView animateWithDuration:0.3
                             animations:^{
                               toast.alpha = 0;
                             }
                             completion:^(BOOL finished) {
                               [toast removeFromSuperview];
                             }];
                       });
      }];
}

- (void)reloadProcessList {
  // Don't reload if view hasn't appeared yet or isn't in window hierarchy
  if (!self.viewHasAppeared || !self.view.window) {
    return;
  }

  // Always get fresh data - real-time updates should continue
  NSArray<HIAHManagedProcess *> *newProcesses = self.processManager.processes;

  // Check if structure changed (processes added/removed/reordered)
  BOOL structureChanged = NO;
  if (self.lastDisplayedProcesses.count != newProcesses.count) {
    structureChanged = YES;
  } else {
    // Compare PIDs to detect additions/removals/reordering
    NSMutableSet<NSNumber *> *oldPIDs = [NSMutableSet set];
    NSMutableSet<NSNumber *> *newPIDs = [NSMutableSet set];
    for (HIAHManagedProcess *proc in self.lastDisplayedProcesses) {
      [oldPIDs addObject:@(proc.pid)];
    }
    for (HIAHManagedProcess *proc in newProcesses) {
      [newPIDs addObject:@(proc.pid)];
    }
    if (![oldPIDs isEqualToSet:newPIDs]) {
      structureChanged = YES;
    } else {
      // Check if order changed
      for (NSUInteger i = 0; i < newProcesses.count; i++) {
        if (newProcesses[i].pid != self.lastDisplayedProcesses[i].pid) {
          structureChanged = YES;
          break;
        }
      }
    }
  }

  // Store previous state
  self.lastDisplayedProcesses = [self.displayedProcesses copy];
  self.displayedProcesses = newProcesses;

  // If user is actively swiping, don't do any updates
  if (self.isSwiping) {
    return;
  }

  // If structure changed, we need a full reload (but only if not scrolling)
  if (structureChanged) {
    if (!self.isScrolling && !self.tableView.isDragging &&
        !self.tableView.isDecelerating) {
      [self.tableView reloadData];
    } else {
      // Schedule reload after scrolling stops
      [NSObject cancelPreviousPerformRequestsWithTarget:self
                                               selector:@selector
                                               (delayedStructureReload)
                                                 object:nil];
      [self performSelector:@selector(delayedStructureReload)
                 withObject:nil
                 afterDelay:0.3];
    }
  } else {
    // Structure unchanged, just update visible cells with new data
    // This won't interrupt gestures
    [self updateVisibleCellsSafely];
  }
}

- (void)delayedStructureReload {
  if (!self.isSwiping && !self.isScrolling && !self.tableView.isDragging &&
      !self.tableView.isDecelerating) {
    [self.tableView reloadData];
  }
}

- (void)updateVisibleCellsSafely {
  // Update only visible cells without interrupting gestures
  // This is safe to call during scrolling/swiping - just updates cell content
  NSArray<NSIndexPath *> *visiblePaths =
      [self.tableView indexPathsForVisibleRows];
  if (visiblePaths.count == 0)
    return;

  // Directly update cell content - no table view operations that interrupt
  // gestures
  for (NSIndexPath *indexPath in visiblePaths) {
    if (indexPath.row < self.displayedProcesses.count) {
      HIAHProcessCell *cell =
          (HIAHProcessCell *)[self.tableView cellForRowAtIndexPath:indexPath];
      if (cell && [cell isKindOfClass:[HIAHProcessCell class]]) {
        HIAHManagedProcess *process = self.displayedProcesses[indexPath.row];
        // Update cell content directly - this doesn't interrupt gestures
        [cell configureWithProcess:process];
      }
    }
  }
}

- (void)updateStatsHeader {
  HIAHSystemStats *stats = self.processManager.systemStats;

  // CPU
  self.cpuLabel.text =
      [NSString stringWithFormat:@"%.1f%%", stats.cpuUsagePercent];
  [self.cpuProgressView setProgress:stats.cpuUsagePercent / 100.0 animated:YES];

  // Memory
  double memPercent = (stats.totalMemory > 0)
                          ? (double)stats.usedMemory / stats.totalMemory
                          : 0;
  NSString *memString = [self formatBytes:stats.usedMemory];
  self.memoryLabel.text = memString;
  [self.memoryProgressView setProgress:memPercent animated:YES];

  // Counts
  self.processCountLabel.text = [NSString
      stringWithFormat:@"%lu processes • %lu threads",
                       (unsigned long)self.processManager.processCount,
                       (unsigned long)self.processManager.threadCount];

  // Load
  self.loadLabel.text =
      [NSString stringWithFormat:@"Load: %.2f %.2f %.2f", stats.loadAverage1,
                                 stats.loadAverage5, stats.loadAverage15];
}

- (NSString *)formatBytes:(uint64_t)bytes {
  if (bytes < 1024) {
    return [NSString stringWithFormat:@"%llu B", bytes];
  } else if (bytes < 1024 * 1024) {
    return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
  } else if (bytes < 1024 * 1024 * 1024) {
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
  } else {
    return [NSString
        stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
  }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  // Show at least 1 row for empty state message
  return MAX(1, self.displayedProcesses.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  // Show empty state if no processes
  if (self.displayedProcesses.count == 0) {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    cell.textLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    cell.textLabel.font = [UIFont systemFontOfSize:16
                                            weight:UIFontWeightMedium];
    cell.textLabel.text = @"No Processes Running";
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.text = @"Tap the green + button to test spawn";
    cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
  }

  // Show actual process data
  HIAHProcessCell *cell =
      [tableView dequeueReusableCellWithIdentifier:kProcessCellIdentifier
                                      forIndexPath:indexPath];

  if (indexPath.row < self.displayedProcesses.count) {
    HIAHManagedProcess *process = self.displayedProcesses[indexPath.row];
    [cell configureWithProcess:process];
  }

  return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  if (indexPath.row < self.displayedProcesses.count) {
    HIAHManagedProcess *process = self.displayedProcesses[indexPath.row];
    [self showActionsForProcess:process];
  }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:
        (NSIndexPath *)indexPath {

  if (indexPath.row >= self.displayedProcesses.count)
    return nil;

  // Mark that user is swiping - prevent structure changes during swipe
  self.isSwiping = YES;

  HIAHManagedProcess *process = self.displayedProcesses[indexPath.row];

  // Kill action
  UIContextualAction *killAction = [UIContextualAction
      contextualActionWithStyle:UIContextualActionStyleDestructive
                          title:@"Kill"
                        handler:^(UIContextualAction *action,
                                  UIView *sourceView,
                                  void (^completionHandler)(BOOL)) {
                          [self.processManager killProcess:process.pid
                                                     error:nil];
                          // Reset swipe flag after a short delay to allow
                          // action to complete
                          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                       0.3 * NSEC_PER_SEC),
                                         dispatch_get_main_queue(), ^{
                                           self.isSwiping = NO;
                                         });
                          completionHandler(YES);
                        }];
  killAction.backgroundColor = [UIColor systemRedColor];

  // Stop/Continue action
  UIContextualAction *stopAction;
  if (process.state == HIAHProcessStateStopped) {
    stopAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@"Resume"
                          handler:^(UIContextualAction *action,
                                    UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [self.processManager continueProcess:process.pid
                                                           error:nil];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                         0.3 * NSEC_PER_SEC),
                                           dispatch_get_main_queue(), ^{
                                             self.isSwiping = NO;
                                           });
                            completionHandler(YES);
                          }];
    stopAction.backgroundColor = [UIColor systemGreenColor];
  } else {
    stopAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@"Stop"
                          handler:^(UIContextualAction *action,
                                    UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [self.processManager stopProcess:process.pid
                                                       error:nil];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                         0.3 * NSEC_PER_SEC),
                                           dispatch_get_main_queue(), ^{
                                             self.isSwiping = NO;
                                           });
                            completionHandler(YES);
                          }];
    stopAction.backgroundColor = [UIColor systemOrangeColor];
  }

  UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration
      configurationWithActions:@[ killAction, stopAction ]];
  config.performsFirstActionWithFullSwipe = NO; // Prevent accidental full swipe

  return config;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:
    (UISearchController *)searchController {
  // Don't update if view hasn't appeared or isn't in window hierarchy yet
  if (!self.viewHasAppeared || !self.view.window) {
    return;
  }

  self.searchText = searchController.searchBar.text;

  if (self.searchText.length > 0) {
    HIAHProcessFilter *filter = [HIAHProcessFilter defaultFilter];
    filter.namePattern = self.searchText;
    self.displayedProcesses =
        [self.processManager filteredProcesses:self.processManager.allProcesses
                                    withFilter:filter];
  } else {
    self.displayedProcesses = self.processManager.processes;
  }

  [self.tableView reloadData];
}

#pragma mark - HIAHProcessManagerDelegate

- (void)processManagerDidUpdateProcesses:(HIAHProcessManager *)manager {
  // Always update - real-time updates should continue
  // Use a small throttle to batch rapid updates
  // Only schedule reload if view has appeared and is in window hierarchy
  if (!self.viewHasAppeared || !self.view.window) {
    return;
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(reloadProcessList)
                                             object:nil];
  [self performSelector:@selector(reloadProcessList)
             withObject:nil
             afterDelay:0.05];
}

- (void)processManagerDidUpdateSystemStats:(HIAHProcessManager *)manager {
  // Always update stats header - this doesn't interrupt gestures
  [self updateStatsHeader];
}

- (void)processManager:(HIAHProcessManager *)manager
       didSpawnProcess:(HIAHManagedProcess *)process {
  // Process spawned - update immediately (structure changed)
  // Only reload if view has appeared and is in window hierarchy
  if (self.viewHasAppeared && self.view.window) {
    [self reloadProcessList];
  }
}

- (void)processManager:(HIAHProcessManager *)manager
    didTerminateProcess:(HIAHManagedProcess *)process {
  // Process terminated - update immediately (structure changed)
  // Only reload if view has appeared and is in window hierarchy
  if (self.viewHasAppeared && self.view.window) {
    [self reloadProcessList];
  }
}

- (void)processManager:(HIAHProcessManager *)manager
     didEncounterError:(NSError *)error {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Error"
                                          message:error.localizedDescription
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  self.isScrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
                  willDecelerate:(BOOL)decelerate {
  if (!decelerate) {
    // Scrolling stopped immediately
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     self.isScrolling = NO;
                   });
  }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  // Scrolling stopped
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                 dispatch_get_main_queue(), ^{
                   self.isScrolling = NO;
                 });
}

@end
