# HIAHTop

Process monitor for HIAH - like `top` for virtual processes.

## Overview

HIAHTop displays:
- Running virtual processes
- CPU and memory usage
- Process states
- Output streams

## Usage

### In HIAHDesktop

HIAHTop is embedded as a tab in HIAHDesktop. Shows all processes managed by HIAHKernel.

### Standalone

Can also run as a separate app for debugging:

```objc
#import <HIAHTop/HIAHTop.h>

HIAHTopView *topView = [[HIAHTopView alloc] initWithFrame:bounds];
topView.kernel = [HIAHKernel sharedKernel];
[self.view addSubview:topView];
```

## Features

| Feature | Description |
|---------|-------------|
| Process list | All running virtual processes |
| PID display | Virtual and physical PIDs |
| State indicator | Running, suspended, terminated |
| Memory usage | Per-process memory stats |
| CPU usage | Per-process CPU percentage |
| Kill button | Terminate selected process |
| Refresh | Manual or auto-refresh |

## Display

```
┌──────────────────────────────────────────┐
│ HIAHTop - 3 processes                    │
├──────────────────────────────────────────┤
│ PID   NAME           STATE    MEM   CPU  │
│ 1001  MyApp          Running  45M   12%  │
│ 1002  Helper         Running  12M    2%  │
│ 1003  Background     Suspend   8M    0%  │
├──────────────────────────────────────────┤
│ Total: 65MB          Uptime: 00:15:32    │
└──────────────────────────────────────────┘
```

## Integration

HIAHTop observes HIAHKernel notifications:
- `HIAHKernelProcessSpawnedNotification`
- `HIAHKernelProcessExitedNotification`

Updates automatically when processes change.

## Files

```
src/HIAHTop/
├── HIAHTopView.h      # Main view
├── HIAHTopView.m
├── HIAHProcessCell.h  # Table cell
└── HIAHProcessCell.m
```

## License

MIT
