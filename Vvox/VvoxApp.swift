//
//  VvoxApp.swift
//  Vvox
//
//  Created by marcop on 2026-06-27.
//

import SwiftUI

@main
struct VvoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Quit Vvox when the user closes the last window. Without this, the app
    // process lingers (windowless) after Cmd+W, and the next Cmd+R from Xcode
    // produces a second instance alongside the zombie.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
