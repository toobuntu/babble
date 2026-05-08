// SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa
import Foundation

func printError(_ message: String) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func getAppearanceMode() -> String {
    let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
    return appleInterfaceStyle
}

let lightModeIconBase64 = """
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGNsYXNzPSJpY29uIGljb24tdGFibGVyIGljb24tdGFibGVyLXJlZnJlc2gtZG90IiB3aWR0aD0iMTI4IiBoZWlnaHQ9IjEyOCIgdmlld0JveD0iMCAwIDI0IDI0IiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZT0iYmxhY2siIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggc3Ryb2tlPSJub25lIiBkPSJNMCAwaDI0djI0SDB6IiBmaWxsPSJub25lIi8+PHBhdGggZD0iTTIwIDExYTguMSA4LjEgMCAwIDAgLTE1LjUgLTJtLS41IC00djRoNCIgLz48cGF0aCBkPSJNNCAxM2E4LjEgOC4xIDAgMCAwIDE1LjUgMm0uNSA0di00aC00IiAvPjxwYXRoIGQ9Ik0xMiAxMm0tMSAwYTEgMSAwIDEgMCAyIDBhMSAxIDAgMSAwIC0yIDAiIC8+PC9zdmc+Cg==
"""

let darkModeIconBase64 = """
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGNsYXNzPSJpY29uIGljb24tdGFibGVyIGljb24tdGFibGVyLXJlZnJlc2gtZG90IiB3aWR0aD0iMTI4IiBoZWlnaHQ9IjEyOCIgdmlld0JveD0iMCAwIDI0IDI0IiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZT0id2hpdGUiIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggc3Ryb2tlPSJub25lIiBkPSJNMCAwaDI0djI0SDB6IiBmaWxsPSJub25lIi8+PHBhdGggZD0iTTIwIDExYTguMSA4LjEgMCAwIDAgLTE1LjUgLTJtLS41IC00djRoNCIgLz48cGF0aCBkPSJNNCAxM2E4LjEgOC4xIDAgMCAwIDE1LjUgMm0uNSA0di00aC00IiAvPjxwYXRoIGQ9Ik0xMiAxMm0tMSAwYTEgMSAwIDEgMCAyIDBhMSAxIDAgMSAwIC0yIDAiIC8+PC9zdmc+Cg==
"""

@MainActor
func displayQuitAlert(appName: String) {
    let appearanceMode = getAppearanceMode()
    let iconBase64: String = switch appearanceMode {
    case "Dark":
        darkModeIconBase64
    default:
        lightModeIconBase64
    }

    if let iconData = Data(base64Encoded: iconBase64),
       let iconImage = NSImage(data: iconData)
    {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(appName) cannot be open during installation."
        alert.informativeText = "Click Continue to quit \"\(appName)\" and begin the update. The application will open when the update is complete."
        alert.icon = iconImage

        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))

        let response = alert.runModal()
        exit(response == .alertSecondButtonReturn ? 0 : 1)
    } else {
        printError("Failed to decode icon for \(appearanceMode) mode.")
        exit(2)
    }
}

guard CommandLine.arguments.count == 2 else {
    printError("Usage: \(CommandLine.arguments[0]) <app_name>")
    exit(3)
}

let appName = CommandLine.arguments[1]
displayQuitAlert(appName: appName)
