/**
 * HIAHTopViewController.h
 * HIAH Top - Main Process Management UI
 *
 * A fully-featured process manager UI implementing:
 * - Process list with sorting and filtering
 * - System statistics header
 * - Process control actions
 * - Detail inspection
 * - Export functionality
 *
 * UI/UX Invariants (Section 10):
 * - Units explicitly labeled
 * - Stable row identity (PID + start_time)
 * - Highlight deltas/spikes
 * - Clear privilege boundary indicators
 */

#import <UIKit/UIKit.h>
#import "HIAHProcessManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface HIAHTopViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, HIAHProcessManagerDelegate>

#pragma mark - Header Stats View
@property (nonatomic, strong) UIView *statsHeaderView;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UIProgressView *cpuProgressView;
@property (nonatomic, strong) UILabel *memoryLabel;
@property (nonatomic, strong) UIProgressView *memoryProgressView;
@property (nonatomic, strong) UILabel *loadLabel;
@property (nonatomic, strong) UILabel *processCountLabel;
@property (nonatomic, strong) UILabel *uptimeLabel;

#pragma mark - Toolbar
@property (nonatomic, strong) UIView *toolbar;  // Using UIView for better mobile layout control
@property (nonatomic, strong) UISegmentedControl *viewModeSegment;
@property (nonatomic, strong) UIBarButtonItem *pauseButton;
@property (nonatomic, strong) UIBarButtonItem *sortButton;
@property (nonatomic, strong) UIBarButtonItem *filterButton;
@property (nonatomic, strong) UIBarButtonItem *exportButton;

#pragma mark - Process List
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

#pragma mark - Process Manager
@property (nonatomic, strong) HIAHProcessManager *processManager;

#pragma mark - State
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, copy, nullable) NSString *searchText;
@property (nonatomic, assign) HIAHGroupingMode groupingMode;

#pragma mark - Actions

/// Toggle pause/resume
- (IBAction)togglePause:(nullable id)sender;

/// Show sort options
- (IBAction)showSortOptions:(nullable id)sender;

/// Show filter options
- (IBAction)showFilterOptions:(nullable id)sender;

/// Export process list
- (IBAction)exportProcessList:(nullable id)sender;

/// Refresh manually
- (IBAction)refresh:(nullable id)sender;

/// Show process details
- (void)showDetailsForProcess:(HIAHManagedProcess *)process;

/// Show process actions (kill, stop, etc.)
- (void)showActionsForProcess:(HIAHManagedProcess *)process;

@end

NS_ASSUME_NONNULL_END
