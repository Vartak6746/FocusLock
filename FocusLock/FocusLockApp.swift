import SwiftUI
import AppKit
import Combine
import ServiceManagement

@main
struct FocusLockApp: App {
    @StateObject private var focusManager = FocusManager()

    var body: some Scene {
        MenuBarExtra {
            
            // --- UI WHEN LOCKED ---
            if focusManager.isLocked {
                Text("Locked to: \(focusManager.targetAppName)")
                
                if !focusManager.allowedApps.isEmpty {
                    Text("Allowed: \(focusManager.allowedApps.joined(separator: ", "))")
                        .font(.caption)
                }
                
                Divider()
                
                Button("Unlock (Stop Focus)") {
                    focusManager.attemptUnlock()
                }
                
                if focusManager.strictMode {
                    Text("Strict Mode Active: Typing Required")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
            // --- UI WHEN UNLOCKED ---
            } else {
                Button("Lock to Current Active App") {
                    focusManager.startFocusOnCurrentApp()
                }
                
                Divider()
                
                // NEW: Power User Settings
                Text("Power User Settings").font(.headline)
                
                Toggle("Strict Mode (Rage-Quit Protection)", isOn: $focusManager.strictMode)
                Toggle("Auto-Trigger Do Not Disturb", isOn: $focusManager.autoDND)
                
                Divider()
                
                Text("Allow-List (\(focusManager.allowedApps.count) apps)")
                
                Button("Add Current App to Allow-List") {
                    focusManager.addCurrentAppToAllowList()
                }
                
                if !focusManager.allowedApps.isEmpty {
                    Button("Clear Allow-List") {
                        focusManager.clearAllowList()
                    }
                }
            }
            
            Divider()
            
            Button(focusManager.launchAtLogin ? "Disable Launch at Login" : "Enable Launch at Login") {
                focusManager.toggleLaunchAtLogin()
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            
        } label: {
            Image(systemName: focusManager.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

class FocusManager: ObservableObject {
    @Published var isLocked = false
    @Published var targetAppName = ""
    @Published var allowedApps: Set<String> = []
    
    // NEW: Toggles for our power user features
    @Published var strictMode = false
    @Published var autoDND = false
    
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    private var isAttemptingUnlock = false
    private var workspaceObserver: NSObjectProtocol?
    private var globalKeyMonitor: Any?

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            }
        } catch {
            print("Failed to toggle Launch at Login: \(error.localizedDescription)")
        }
    }

    func addCurrentAppToAllowList() {
        guard let currentApp = NSWorkspace.shared.frontmostApplication,
              let appName = currentApp.localizedName else { return }
        allowedApps.insert(appName)
    }
    
    func clearAllowList() {
        allowedApps.removeAll()
    }

    func startFocusOnCurrentApp() {
        guard let currentApp = NSWorkspace.shared.frontmostApplication,
              let appName = currentApp.localizedName else { return }
        
        targetAppName = appName
        isLocked = true
        
        // Trigger DND if enabled
        if autoDND { triggerShortcut(named: "Toggle DND") }
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enforceFocus()
        }
        
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only allow the keyboard shortcut if Strict Mode is OFF
            guard let self = self, !self.strictMode else { return }
            
            if event.modifierFlags.contains([.command, .shift]), event.keyCode == 14 {
                self.stopFocus()
            }
        }
    }

    // NEW: Handles the logic when the user clicks "Unlock"
    func attemptUnlock() {
        if strictMode {
            isAttemptingUnlock = true
            
            // Pop an alert window requiring them to type
            let alert = NSAlert()
            alert.messageText = "Strict Mode Active"
            alert.informativeText = "To unlock, type exactly: 'I am breaking my focus'"
            alert.addButton(withTitle: "Unlock")
            alert.addButton(withTitle: "Cancel")
            
            let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
            alert.accessoryView = inputTextField
            
            // Force the alert to the front
            NSApp.activate(ignoringOtherApps: true)
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn && inputTextField.stringValue == "I am breaking my focus" {
                stopFocus()
            } else {
                // They typed it wrong or hit cancel! Keep them locked.
                enforceFocus()
            }
        } else {
            // Standard unlock
            stopFocus()
        }
    }

    private func stopFocus() {
        isLocked = false
        targetAppName = ""
        
        // Turn off DND if it was enabled
        if autoDND { triggerShortcut(named: "Toggle DND") }
        
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func enforceFocus() {
        guard isLocked else { return }
        
        guard !isAttemptingUnlock else { return }
        
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let activeAppName = activeApp.localizedName else { return }
        
        if activeAppName == targetAppName || allowedApps.contains(activeAppName) {
            return
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        if let target = runningApps.first(where: { $0.localizedName == targetAppName }) {
            
            if let appURL = target.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
            }
        }
    }
    
    // NEW: Helper function to silently run Apple Shortcuts via Terminal
    private func triggerShortcut(named shortcutName: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", shortcutName]
        try? task.run()
    }
}
