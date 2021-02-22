// Chai - Don't let your Mac fall asleep, like a sir
// Copyright (C) 2020 Lorenzo Villani
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Cocoa
import ServiceManagement
import os

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, StoreDelegate {
  // Globals
  static let appName =
    Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String

  var powerAssertion: PowerAssertion?
  var timer: Timer?

  // UI
  let iconOff = NSImage(imageLiteralResourceName: "Mug-Empty")
  let iconOn = NSImage(imageLiteralResourceName: "Mug")
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  let statusMenu = NSMenu(title: appName)

  let headerItem = NSMenuItem(title: "Keep This Mac Awake", action: nil, keyEquivalent: "")

  let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(launchAtLoginAction), keyEquivalent: "")
  let lauchEnabledItem = NSMenuItem(
    title: "Use Last Session", action: #selector(lauchEnabledAction), keyEquivalent: "")

  let preferences = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
  let disableAfterSuspend = NSMenuItem(
    title: "Disable After Suspend", action: #selector(disableAfterSuspendAction), keyEquivalent: "")

  var activationItems: [MenuItem] = []

  func applicationWillTerminate(_ notification: Notification) {
    globalStore.unsubscribe(storeDelegate: self)
  }

  func applicationDidFinishLaunching(_: Notification) {
    initUi()

    registerDidWakeNotification()

    globalStore.dispatch(action: .initialize)
    globalStore.subscribe(storeDelegate: self)
  }

  func initUi() {
    iconOff.isTemplate = true
    iconOn.isTemplate = true

    headerItem.isEnabled = false

    statusItem.action = #selector(statusItemClicked)
    statusItem.sendAction(on: [.leftMouseUp, .rightMouseDown])

    // Timers
    statusMenu.addItem(headerItem)
    initMenuItems()

    // Preferences
    preferences.submenu = NSMenu(title: "Preferences")
    preferences.submenu?.addItem(disableAfterSuspend)

    statusMenu.addItem(NSMenuItem.separator())
    statusMenu.addItem(preferences)

    // Lauch At Login
    launchAtLoginItem.submenu = NSMenu(title: "Launch at Login")
    launchAtLoginItem.submenu?.addItem(lauchEnabledItem)

    // Global
    statusMenu.addItem(NSMenuItem.separator())
    statusMenu.addItem(launchAtLoginItem)
    statusMenu.addItem(
      withTitle: "Quit \(AppDelegate.appName)", action: #selector(quitAction), keyEquivalent: "q")
  }

  @objc func statusItemClicked() {
    guard let eventType = NSApp.currentEvent?.type else {
      return
    }

    if eventType == .leftMouseUp {
      // HACK: item at 1 is
      activateAction(sender: statusMenu.item(at: 1) as! MenuItem)
    } else if eventType == .rightMouseDown {
      // HACK: This allows showing the menu on right click.
      statusItem.menu = statusMenu
      statusItem.button?.performClick(nil)
      statusItem.menu = nil  // NOTE: Must set to nil to be able to handle left clicks again
    }
  }

  func initMenuItems() {
    ActivationSpecs.allCases.forEach { itemSpec in
      let item = MenuItem(
        title: itemSpec.spec.title, action: #selector(activateAction(sender:)), keyEquivalent: itemSpec.spec.label)
        item.timerDuration = itemSpec.spec.timeInterval

      activationItems.append(item)
      statusMenu.addItem(item)
    }
  }

  func registerDidWakeNotification() {
    os_log("Registering system wakeup notification handler")

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(receiveDidWakeNotification),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
  }

  @objc func receiveDidWakeNotification() {
    if !globalStore.state.isDisableAfterSuspendEnabled {
      return
    }

    os_log("System wakeup detected, disabling according to config")
    deactivate()
  }

  func stateChanged(state: State) {
    // Icon
    statusItem.image = state.active ? iconOn : iconOff

    // Timers
    for item in activationItems {
      item.state = .off
    }

    activationItems.first { menu in
        menu.title == state.activeItem?.title
    }?.state = .on

    // Disable after suspend
    disableAfterSuspend.state = state.isDisableAfterSuspendEnabled ? .on : .off

    // Login Item
    launchAtLoginItem.state = state.isLoginItemEnabled ? .on : .off
    lauchEnabledItem.state = state.isEnabledByDefault ? .on : .off
  }

  @objc func activateAction(sender: MenuItem) {
    var newActivationState = !globalStore.state.active
    if globalStore.state.activeItem?.title != sender.title {
      newActivationState = true
    }

    deactivate()
    if !newActivationState {
      return
    }

    powerAssertion = PowerAssertion(named: "Brewing Tea")

    if sender.timerDuration > 0 {
      os_log("Scheduling deactivation in %f seconds", sender.timerDuration)
      timer = Timer.scheduledTimer(
        withTimeInterval: sender.timerDuration, repeats: false,
        block: { (_) in
          self.deactivate()
        })
    }

    globalStore.dispatch(action: .activate(sender.title))
    os_log("Activated")
  }

  func deactivate() {
    if let _ = powerAssertion {
      powerAssertion = nil
    }

    if let t = timer {
      t.invalidate()
      timer = nil
    }

    globalStore.dispatch(action: .deactivate)
    os_log("Deactivated")
  }

  @objc func disableAfterSuspendAction() {
    globalStore.dispatch(
      action: .setDisableAfterSuspendEnabled(!globalStore.state.isDisableAfterSuspendEnabled))
  }

  @objc func launchAtLoginAction() {
    let newState = !globalStore.state.isLoginItemEnabled

    if !SMLoginItemSetEnabled("me.villani.lorenzo.ChaiHelper" as CFString, newState) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Cannot start Chai on login"
      alert.runModal()

      return
    }

    globalStore.dispatch(action: .setLoginItemEnabled(newState))
    os_log("Launch at login: %{public}s", newState ? "enabled" : "disabled")
  }

  @objc func lauchEnabledAction() {
    globalStore.dispatch(action: .setIsEnabledByDefault(!globalStore.state.isEnabledByDefault))
  }

  @objc func quitAction() {
    NSRunningApplication.current.terminate()
  }
}
