# HIAH Process Management Protocol

Integration specification for HIAH Top and HIAH Kernel process management.

## Architecture

HIAH implements a "House in a House" architecture for running multiple iOS applications inside a single sandboxed app:

```
Host iOS Application
├── Documents/                      ← Visible in iOS Files.app
│   └── Applications/               ← Installed .ipa apps
│
├── App Group Container/            ← Shared with extension
│   └── staging/                    ← Temp copies for extension
│
├── HIAHKernel
│   ├── Process Table (virtual PIDs, exit codes)
│   └── Control Socket (IPC: spawn, output relay)
│
├── HIAHWindowServer
│   ├── Window Manager (focus, resize, ordering)
│   └── App Windows (FBScene, _UIScenePresenter)
│
└── HIAHProcessRunner.appex
    ├── litehook (posix_spawn, execve, waitpid interception)
    └── Guest Process Execution (dlopen, stdout/stderr capture)
```

### Components

**HIAHKernel** - Process table management, virtual PID assignment, control socket IPC, NSExtension-based spawning.

**HIAHWindowServer** - Multiple app windows via FrontBoard APIs (FBScene, _UIScenePresenter), window lifecycle, app switcher.

**HIAHAppWindowSession** - Per-process FBScene creation, UIMutableApplicationSceneSettings, foreground/background transitions.

**HIAHProcessRunner.appex** - NSExtension entry point, dlopen for .dylib execution, execve fallback, stdout/stderr redirect to Unix socket.

### Technical Notes

- **NSExtension**: iOS prohibits fork()/posix_spawn() for third-party apps. NSExtension provides separate address spaces within Apple's sandbox model.
- **FBScene**: FrontBoard's scene infrastructure enables per-process window rendering, orientation handling, and foreground/background states.
- **App Groups**: Extensions run in separate sandboxes. App Groups (`group.com.aspauldingcode.HIAHDesktop`) provide shared storage for app staging.
- **Files.app**: Documents folder is exposed via `UIFileSharingEnabled`, allowing users to manage installed apps directly.
- **Jailed**: Works on stock iOS using accessible private APIs (no jailbreak required).

## Data Model

### Process Object (HIAHManagedProcess)
- PID, PPID, PGID, SID, UID, GID
- State, command, start time
- Virtual PID (kernel-assigned) vs Physical PID (system)

### Thread Object (HIAHThread)
- Thread ID, state, CPU time
- Per-thread priority and affinity

## Process Enumeration

| Method | Description |
|--------|-------------|
| `listAllProcesses` | List all managed processes |
| `processesForUser:` | Filter by user |
| `findProcessesWithName:` | Find by name |
| `findProcessesMatchingPattern:` | Regex matching |
| `processTreeForPID:` | Tree reconstruction |
| `childrenOfProcess:` | Direct children |

## Resource Accounting

Real data collection via iOS/macOS APIs:

| Metric | API |
|--------|-----|
| CPU | `proc_pidinfo()` with delta calculation |
| Memory | `task_info()` - RSS, virtual, private/shared |
| I/O | `task_events_info` |
| Energy | Wakeups via context switches |
| Per-thread | `thread_info()` |
| Per-core | `host_processor_info()` |
| Page faults | Minor/major tracking |

## Temporal Model

- Configurable `refreshInterval`
- `pause` / `resume` sampling
- Stable sorting (PID + start_time as secondary key)
- Delta calculation via `calculateDeltasFrom:`

## Control Plane

### Signals
| Method | Signal |
|--------|--------|
| `sendSignal:toProcess:` | Real `kill()` syscall |
| `terminateProcess:` | SIGTERM |
| `killProcess:` | SIGKILL |
| `stopProcess:` | SIGSTOP |
| `continueProcess:` | SIGCONT |

Virtual processes receive signals via control socket IPC.

### Scheduling
- `setNiceValue:` - Real `setpriority()` syscall
- `setCPUAffinity:` - `thread_policy_set()`
- Per-thread priority via `thread_policy_set()`

### Tree Control
- Kill single process
- `killProcessTree:` - Kill subtree
- `detectOrphanedChildren` - Find orphans

## Diagnostics

| Feature | API |
|---------|-----|
| File descriptors | `proc_pidinfo` enumeration |
| Memory maps | `vm_region_64()` |
| Thread enumeration | `task_threads()` + `thread_info()` |
| Stack sampling | Mach thread state APIs, frame walking |

## Aggregation

- System totals (`HIAHSystemStats`)
- Load averages
- Per-user: `userAggregatedStats`
- Per-group: `groupAggregatedStats`
- Orphan detection: `detectOrphanedChildren`

## Query Model

### Sorting
`sortByField:ascending:` - Sort by any numeric field

### Filtering
`HIAHProcessFilter.namePattern` - Regex filtering

### Grouping Modes
| Mode | Description |
|------|-------------|
| `HIAHGroupingModeFlat` | Flat list |
| `HIAHGroupingModeTree` | Process tree |
| `HIAHGroupingModeUser` | By user |
| `HIAHGroupingModeApplication` | By app |

### CLI Output
- `cliOutput` / `cliOutputWithOptions:`
- `nonInteractiveSample` / `printToStdout`

## Export

| Format | Method |
|--------|--------|
| Text | `exportAsText` |
| JSON | `exportAsJSON` |
| Snapshot | `exportSnapshot` |
| File | `exportToFile:format:error:` |

## Security Model

- No process manipulation without explicit user action
- No silent privilege escalation
- Sensitive field redaction via `hasLimitedAccess`
- Clear sandbox boundaries (`physicalPid` vs `pid`)
- Privilege checking: `canAccessProcess:`, `canSignalProcess:`, `canGetTaskPortForProcess:`
- Graceful degradation when access denied
- Access limitation reporting: `privilegeLevelForProcess:`, `accessLimitationsForProcess:`

## Platform APIs

| API | Usage |
|-----|-------|
| `proc_pidinfo()` | Process info, task info |
| `task_info()` | Memory stats, events |
| `thread_info()` | Thread CPU stats |
| `task_threads()` | Thread enumeration |
| `sysctl()` | System stats, kinfo_proc |
| `vm_region_64()` | Memory maps |
| `vm_read_overwrite()` | Stack frame walking |
| `thread_get_state()` | Register state |
| `host_processor_info()` | Per-core CPU |
| `kill()` | Signal delivery |
| `setpriority()` | Nice value |
| `thread_policy_set()` | CPU affinity, thread priority |
| `host_statistics()` | System CPU/memory |

## Usage Example

```objc
HIAHKernel *kernel = [HIAHKernel sharedKernel];
[kernel spawnVirtualProcessWithPath:@"/path/to/app"
                          arguments:@[]
                        environment:@{}
                         completion:^(pid_t pid, NSError *error) {
    if (!error) {
        [[HIAHWindowServer shared] openWindowForPID:pid 
                                     executablePath:@"/path/to/app"];
    }
}];
```

## References

- **POSIX Process Model** - Standard process semantics
- **macOS/iOS Mach APIs** - System integration
- **iOS App Extensions** - Apple's extension architecture for process isolation

## See Also

- [HIAH Kernel Documentation](./HIAHKernel.md) – Core Library
- [HIAH Desktop Documentation](./HIAHDesktop.md) – Desktop Environment
- [HIAH Top Documentation](./HIAHTop.md) – Process Manager
- [HIAHProcessRunner Documentation](./HIAHProcessRunner.md) – Guest App Extension
- [Virtual Filesystem Documentation](./VirtualFilesystem.md) – Storage & Files.app Integration
