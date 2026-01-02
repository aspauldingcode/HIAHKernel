/**
 * HIAHLogging.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Centralized logging implementation.
 * All logs output to stdout.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHLogging.h"
#import <stdarg.h>

HIAHLogSubsystem HIAHLogKernel(void) {
    return "HIAHKernel";
}

HIAHLogSubsystem HIAHLogExtension(void) {
    return "HIAHExtension";
}

HIAHLogSubsystem HIAHLogFilesystem(void) {
    return "HIAHFilesystem";
}

HIAHLogSubsystem HIAHLogWindowServer(void) {
    return "HIAHWindowServer";
}

HIAHLogSubsystem HIAHLogProcessManager(void) {
    return "HIAHProcessManager";
}

