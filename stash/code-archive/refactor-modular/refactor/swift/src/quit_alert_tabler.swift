// SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa
import Foundation

// Function to print errors to stderr
func printError(_ message: String) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func printDebug(_ message: String) {
    // Check if debugging is enabled via --debug or DEBUG_MODE environment variable
    let isDebugMode = CommandLine.arguments.contains("--debug") ||
        ProcessInfo.processInfo.environment["DEBUG_MODE"] != nil

    if isDebugMode {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

// Base64-encoded strings for the SVG icons
// Use refresh-dot-dark.svg for light mode
let lightModeIconBase64 = """
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGNsYXNzPSJpY29uIGljb24tdGFibGVyIGljb24tdGFibGVyLXJlZnJlc2gtZG90IiB3aWR0aD0iMTI4IiBoZWlnaHQ9IjEyOCIgdmlld0JveD0iMCAwIDI0IDI0IiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZT0iYmxhY2siIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggc3Ryb2tlPSJub25lIiBkPSJNMCAwaDI0djI0SDB6IiBmaWxsPSJub25lIi8+PHBhdGggZD0iTTIwIDExYTguMSA4LjEgMCAwIDAgLTE1LjUgLTJtLS41IC00djRoNCIgLz48cGF0aCBkPSJNNCAxM2E4LjEgOC4xIDAgMCAwIDE1LjUgMm0uNSA0di00aC00IiAvPjxwYXRoIGQ9Ik0xMiAxMm0tMSAwYTEgMSAwIDEgMCAyIDBhMSAxIDAgMSAwIC0yIDAiIC8+PC9zdmc+Cg==
"""

// Use refresh-dot-light.svg for dark mode
let darkModeIconBase64 = """
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGNsYXNzPSJpY29uIGljb24tdGFibGVyIGljb24tdGFibGVyLXJlZnJlc2gtZG90IiB3aWR0aD0iMTI4IiBoZWlnaHQ9IjEyOCIgdmlld0JveD0iMCAwIDI0IDI0IiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZT0id2hpdGUiIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggc3Ryb2tlPSJub25lIiBkPSJNMCAwaDI0djI0SDB6IiBmaWxsPSJub25lIi8+PHBhdGggZD0iTTIwIDExYTguMSA4LjEgMCAwIDAgLTE1LjUgLTJtLS41IC00djRoNCIgLz48cGF0aCBkPSJNNCAxM2E4LjEgOC4xIDAgMCAwIDE1LjUgMm0uNSA0di00aC00IiAvPjxwYXRoIGQ9Ik0xMiAxMm0tMSAwYTEgMSAwIDEgMCAyIDBhMSAxIDAgMSAwIC0yIDAiIC8+PC9zdmc+Cg==
"""

// Function to determine the current appearance mode
func getAppearanceMode() -> String {
    let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
    return appleInterfaceStyle
}

@MainActor
// Main function to display the quit alert
func displayQuitAlert(appName: String) {
    // Detect the current appearance mode
    let appearanceMode = getAppearanceMode()
    let iconBase64: String = switch appearanceMode {
    case "Dark":
        darkModeIconBase64
    default:
        lightModeIconBase64
    }

    // Decode the base64 string directly into an NSImage
    if let iconData = Data(base64Encoded: iconBase64),
       let iconImage = NSImage(data: iconData)
    {
        printDebug("Icon successfully decoded for \(appearanceMode) mode.")

        // Configure and display the alert
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(appName) cannot be open during installation."
        alert.informativeText = "Click Continue to quit \"\(appName)\" and begin the update. The application will open when the update is complete."
        alert.icon = iconImage

        // Add system-localized buttons
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))

        // Display the alert and handle the user's response
        let response = alert.runModal()
        exit(response == .alertSecondButtonReturn ? 0 : 1)
    } else {
        // Handle icon decoding failure
        printError("Failed to decode icon for \(appearanceMode) mode.")
        exit(2) // Icon load failure
    }
}

// Check for optional --debug flag
let isDebugMode = CommandLine.arguments.contains("--debug")

// Filter out the optional flags to isolate positional arguments
let positionalArgs = CommandLine.arguments.filter { !$0.hasPrefix("--") }

// Ensure exactly 1 positional argument is provided: app_name
guard positionalArgs.count == 2 else {
    printError("Usage: \(CommandLine.arguments[0]) [--debug] <app_name>")
    exit(3) // General error
}

let appName = positionalArgs[1]
displayQuitAlert(appName: appName)
