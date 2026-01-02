/**
 * HIAHLogging.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Centralized logging system for HIAH components.
 * All logs go to stdout for visibility.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>
#import <stdio.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Logging subsystem identifiers (for categorization)
 */
typedef const char *HIAHLogSubsystem;

extern HIAHLogSubsystem HIAHLogKernel(void);
extern HIAHLogSubsystem HIAHLogExtension(void);
extern HIAHLogSubsystem HIAHLogFilesystem(void);
extern HIAHLogSubsystem HIAHLogWindowServer(void);
extern HIAHLogSubsystem HIAHLogProcessManager(void);

/**
 * Log levels
 */
typedef NS_ENUM(NSInteger, HIAHLogLevel) {
  HIAHLogLevelDebug = 0,
  HIAHLogLevelInfo,
  HIAHLogLevelWarning,
  HIAHLogLevelError,
  HIAHLogLevelFault
};

/**
 * Helper to convert NSString to C string for logging
 */
static inline const char *_HIAHLogString(NSString *str) {
  return str ? [str UTF8String] : "(null)";
}

/**
 * Internal logging function
 */
static inline void _HIAHLogPrint(HIAHLogSubsystem subsystem, HIAHLogLevel level,
                                 const char *fmt, ...) {
  const char *levelStr = "DEBUG";
  switch (level) {
  case HIAHLogLevelInfo:
    levelStr = "INFO";
    break;
  case HIAHLogLevelWarning:
    levelStr = "WARNING";
    break;
  case HIAHLogLevelError:
    levelStr = "ERROR";
    break;
  case HIAHLogLevelFault:
    levelStr = "FAULT";
    break;
  default:
    break;
  }

  fprintf(stdout, "[%s][%s] ", subsystem, levelStr);

  va_list args;
  va_start(args, fmt);
  vfprintf(stdout, fmt, args);
  va_end(args);

  fprintf(stdout, "\n");
  fflush(stdout);
}

/**
 * Structured logging macros (all output to stdout)
 * Note: For NSString objects, use %s and pass [string UTF8String] or use
 * HIAHLogString() helper
 */
#define HIAHLogDebug(subsystem, fmt, ...)                                      \
  _HIAHLogPrint(subsystem(), HIAHLogLevelDebug, fmt, ##__VA_ARGS__)

#define HIAHLogInfo(subsystem, fmt, ...)                                       \
  _HIAHLogPrint(subsystem(), HIAHLogLevelInfo, fmt, ##__VA_ARGS__)

#define HIAHLogWarning(subsystem, fmt, ...)                                    \
  _HIAHLogPrint(subsystem(), HIAHLogLevelWarning, fmt, ##__VA_ARGS__)

#define HIAHLogError(subsystem, fmt, ...)                                      \
  _HIAHLogPrint(subsystem(), HIAHLogLevelError, fmt, ##__VA_ARGS__)

#define HIAHLogFault(subsystem, fmt, ...)                                      \
  _HIAHLogPrint(subsystem(), HIAHLogLevelFault, fmt, ##__VA_ARGS__)

/**
 * Convenience macro for logging NSString objects
 */
#define HIAHLogString(str) _HIAHLogString(str)

// Compatibility Defines
#define HIAH_LOG_DEBUG HIAHLogLevelDebug
#define HIAH_LOG_INFO HIAHLogLevelInfo
#define HIAH_LOG_WARNING HIAHLogLevelWarning
#define HIAH_LOG_ERROR HIAHLogLevelError
#define HIAH_LOG_FAULT HIAHLogLevelFault

/**
 * Extended logging macro supporting NSString format and dynamic subsystem
 * strings.
 */
#define HIAHLogEx(level, subsystem, fmt, ...)                                  \
  do {                                                                         \
    if ((level) >= HIAHLogLevelDebug) {                                        \
      NSString *_msg = [NSString stringWithFormat:(fmt), ##__VA_ARGS__];       \
      const char *_sub = [(subsystem) UTF8String];                             \
      _HIAHLogPrint(_sub, (level), "%s", [_msg UTF8String]);                   \
    }                                                                          \
  } while (0)

NS_ASSUME_NONNULL_END
