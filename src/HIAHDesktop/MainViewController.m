/**
 * MainViewController.m
 * HIAHDesktop - Demonstrates HIAHKernel library usage
 *
 * This view controller shows how to:
 * - Spawn virtual processes
 * - Monitor process output
 * - Manage process lifecycle
 * - Display process table
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "MainViewController.h"
#import "HIAHKernel.h"
#import "HIAHProcess.h"

@interface MainViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) HIAHKernel *kernel;
@property (nonatomic, strong) UITableView *processTableView;
@property (nonatomic, strong) UITextView *outputTextView;
@property (nonatomic, strong) NSMutableString *outputBuffer;
@end

@implementation MainViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"HIAH Desktop";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Get kernel reference
    self.kernel = [HIAHKernel sharedKernel];
    self.outputBuffer = [NSMutableString string];
    
    [self setupUI];
    [self registerNotifications];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Setup

- (void)setupUI {
    // Navigation bar buttons
    UIBarButtonItem *spawnButton = [[UIBarButtonItem alloc]
        initWithTitle:@"Spawn"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(spawnProcess)];
    
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self
                             action:@selector(refreshProcessList)];
    
    self.navigationItem.rightBarButtonItems = @[spawnButton, refreshButton];
    
    // Process table (top half)
    self.processTableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                         style:UITableViewStylePlain];
    self.processTableView.dataSource = self;
    self.processTableView.delegate = self;
    self.processTableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.processTableView registerClass:[UITableViewCell class]
                  forCellReuseIdentifier:@"ProcessCell"];
    [self.view addSubview:self.processTableView];
    
    // Output view (bottom half)
    self.outputTextView = [[UITextView alloc] init];
    self.outputTextView.editable = NO;
    self.outputTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.outputTextView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.outputTextView.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    self.outputTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.outputTextView];
    
    // Section labels
    UILabel *processLabel = [[UILabel alloc] init];
    processLabel.text = @"Processes";
    processLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    processLabel.textColor = [UIColor secondaryLabelColor];
    processLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:processLabel];
    
    UILabel *outputLabel = [[UILabel alloc] init];
    outputLabel.text = @"Output";
    outputLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    outputLabel.textColor = [UIColor secondaryLabelColor];
    outputLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:outputLabel];
    
    // Layout
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [processLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [processLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        
        [self.processTableView.topAnchor constraintEqualToAnchor:processLabel.bottomAnchor constant:4],
        [self.processTableView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.processTableView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.processTableView.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:0.4],
        
        [outputLabel.topAnchor constraintEqualToAnchor:self.processTableView.bottomAnchor constant:8],
        [outputLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        
        [self.outputTextView.topAnchor constraintEqualToAnchor:outputLabel.bottomAnchor constant:4],
        [self.outputTextView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.outputTextView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.outputTextView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}

#pragma mark - Notifications

- (void)registerNotifications {
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(processListChanged:)
               name:HIAHKernelProcessSpawnedNotification
             object:nil];
    
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(processListChanged:)
               name:HIAHKernelProcessExitedNotification
             object:nil];
    
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(outputReceived:)
               name:@"HIAHProcessOutput"
             object:nil];
}

- (void)processListChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.processTableView reloadData];
    });
}

- (void)outputReceived:(NSNotification *)notification {
    NSString *output = notification.userInfo[@"output"];
    pid_t pid = [notification.userInfo[@"pid"] intValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.outputBuffer appendFormat:@"[%d] %@\n", pid, output];
        self.outputTextView.text = self.outputBuffer;
        
        // Scroll to bottom
        if (self.outputTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.outputTextView.text.length - 1, 1);
            [self.outputTextView scrollRangeToVisible:bottom];
        }
    });
}

#pragma mark - Actions

- (void)spawnProcess {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Spawn Process"
                         message:@"Enter executable path"
                  preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"/path/to/binary";
        textField.text = @"/bin/echo";
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Arguments (space separated)";
        textField.text = @"Hello from HIAHKernel!";
    }];
    
    UIAlertAction *spawn = [UIAlertAction
        actionWithTitle:@"Spawn"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
        NSString *path = alert.textFields[0].text;
        NSString *argsStr = alert.textFields[1].text;
        NSArray *args = [argsStr componentsSeparatedByString:@" "];
        
        [self spawnProcessAtPath:path arguments:args];
    }];
    
    UIAlertAction *cancel = [UIAlertAction
        actionWithTitle:@"Cancel"
                  style:UIAlertActionStyleCancel
                handler:nil];
    
    [alert addAction:spawn];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)spawnProcessAtPath:(NSString *)path arguments:(NSArray *)arguments {
    [self appendOutput:[NSString stringWithFormat:@"Spawning: %@ %@\n",
                        path, [arguments componentsJoinedByString:@" "]]];
    
    [self.kernel spawnProcessWithPath:path
                            arguments:arguments
                          environment:nil
                           completion:^(pid_t pid, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self appendOutput:[NSString stringWithFormat:@"Error: %@\n",
                                    error.localizedDescription]];
            } else {
                [self appendOutput:[NSString stringWithFormat:@"Started PID: %d\n", pid]];
            }
        });
    }];
}

- (void)refreshProcessList {
    [self.processTableView reloadData];
}

- (void)appendOutput:(NSString *)text {
    [self.outputBuffer appendString:text];
    self.outputTextView.text = self.outputBuffer;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.kernel allProcesses].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProcessCell"
                                                            forIndexPath:indexPath];
    
    NSArray *processes = [self.kernel allProcesses];
    if (indexPath.row < processes.count) {
        HIAHProcess *process = processes[indexPath.row];
        
        cell.textLabel.text = [NSString stringWithFormat:@"PID %d: %@",
                               process.pid, process.executablePath.lastPathComponent];
        
        NSString *state;
        switch (process.state) {
            case HIAHProcessStateCreated: state = @"Created"; break;
            case HIAHProcessStateRunning: state = @"Running"; break;
            case HIAHProcessStateStopped: state = @"Stopped"; break;
            case HIAHProcessStateZombie: state = @"Zombie"; break;
            case HIAHProcessStateTerminated: state = @"Exited"; break;
        }
        cell.detailTextLabel.text = state;
        
        // Color code by state
        if (process.state == HIAHProcessStateRunning) {
            cell.textLabel.textColor = [UIColor systemGreenColor];
        } else if (process.isExited) {
            cell.textLabel.textColor = [UIColor systemGrayColor];
        } else {
            cell.textLabel.textColor = [UIColor labelColor];
        }
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSArray *processes = [self.kernel allProcesses];
    if (indexPath.row >= processes.count) return;
    
    HIAHProcess *process = processes[indexPath.row];
    
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"PID %d", process.pid]
                         message:process.executablePath
                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (process.state == HIAHProcessStateRunning) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Kill (SIGTERM)"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [self.kernel killProcess:process.pid signal:SIGTERM];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Force Kill (SIGKILL)"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [self.kernel killProcess:process.pid signal:SIGKILL];
        }]];
    }
    
    if (process.isExited) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [self.kernel unregisterProcessWithPID:process.pid];
            [self.processTableView reloadData];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
