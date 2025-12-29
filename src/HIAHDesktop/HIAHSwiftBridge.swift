/**
 * HIAHSwiftBridge.swift
 * Bridge between Objective-C HIAHDesktop and SwiftUI Sample Apps
 */

import SwiftUI
import UIKit

/// Bridge class to instantiate SwiftUI apps from Objective-C
/// Use `[HIAHSwiftBridge viewControllerForBundleID:@"..."]` from ObjC
@objc(HIAHSwiftBridge)
@objcMembers
public class HIAHSwiftBridge: NSObject {
    
    /// Returns a UIViewController for the given bundle ID, or nil if not found
    public static func viewController(forBundleID bid: String) -> UIViewController? {
        print("[SwiftBridge] Looking up bundleID: \(bid)")
        
        if bid.contains("Terminal") || bid.contains("HIAHTerminal") {
            print("[SwiftBridge] Creating TerminalView")
            return UIHostingController(rootView: TerminalView())
        }
        if bid.contains("Calculator") {
            print("[SwiftBridge] Creating CalculatorView")
            return UIHostingController(rootView: CalculatorView())
        }
        if bid.contains("Notes") {
            print("[SwiftBridge] Creating NotesView")
            return UIHostingController(rootView: NotesView())
        }
        if bid.contains("Weather") {
            print("[SwiftBridge] Creating WeatherView")
            return UIHostingController(rootView: WeatherView())
        }
        if bid.contains("Timer") {
            print("[SwiftBridge] Creating TimerView")
            return UIHostingController(rootView: TimerView())
        }
        if bid.contains("Canvas") {
            print("[SwiftBridge] Creating CanvasView")
            return UIHostingController(rootView: CanvasView())
        }
        
        print("[SwiftBridge] No match for bundleID: \(bid)")
        return nil
    }
}

