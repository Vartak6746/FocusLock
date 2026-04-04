import SwiftUI
import AppKit
import Combine
import ServiceManagement // Required for Launch at Login

@main
struct FocusLockApp: App {
    @StateObject private var focusManager = FocusManager()

    var body: some Scene {
        MenuBarExtra {
            
            // --- UI WHEN LOCKED ---
            if focusManager.isLocked {
                Text("🔒 Locked to: \(focusManager.targetAppName)")
                
                if !focusManager.allowedApps.isEmpty {
                    Text("✅ Allowed: \(focusManager.allowedApps.joined(separator: ", "))")
                        .font(.caption)
                }
                
                Divider()
                
                Button("Unlock (Stop Focus)") {
                    focusManager.stopFocus()
                }
                
                
            // --- UI WHEN UNLOCKED ---
            } else {
                Button("Lock to Current Active App") {
                    focusManager.startFocusOnCurrentApp()
                }
                
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
            
            // --- APP SETTINGS ---
            Button(focusManager.launchAtLogin ? "Disable Launch at Login" : "Enable Launch at Login") {
                focusManager.toggleLaunchAtLogin()
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            
        } label: {
            // DYNAMIC ICON LOGIC:
            // Checks if locked, and shows the corresponding Apple SF Symbol
            Image(systemName: focusManager.isLocked ? "lock" : "lock.open")
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

class FocusManager: ObservableObject {
    @Published var isLocked = false
    @Published var targetAppName = ""
    @Published var allowedApps: Set<String> = []
    
    // Checks the system status to see if it is already set to launch at login
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    private var workspaceObserver: NSObjectProtocol?
    private var globalKeyMonitor: Any?

    // --- LAUNCH AT LOGIN LOGIC ---
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

    // --- ALLOW-LIST LOGIC ---
    func addCurrentAppToAllowList() {
        guard let currentApp = NSWorkspace.shared.frontmostApplication,
              let appName = currentApp.localizedName else { return }
        allowedApps.insert(appName)
    }
    
    func clearAllowList() {
        allowedApps.removeAll()
    }

    // --- FOCUS LOGIC ---
    func startFocusOnCurrentApp() {
        guard let currentApp = NSWorkspace.shared.frontmostApplication,
              let appName = currentApp.localizedName else { return }
        
        targetAppName = appName
        isLocked = true
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enforceFocus()
        }
        
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]), event.keyCode == 14 {
                self?.stopFocus()
            }
        }
    }

    func stopFocus() {
        isLocked = false
        targetAppName = ""
        
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func enforceFocus() {
        guard isLocked else { return }
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
}
