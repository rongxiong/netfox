//
//  NFX.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation
import SwiftUI
#if os(OSX)
import Cocoa
#else
import UIKit
#endif

private func podPlistVersion() -> String? {
    guard let path = Bundle(identifier: "com.kasketis.netfox-iOS")?.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
    return path
}

// TODO: Carthage support
let nfxVersion = podPlistVersion() ?? "0"

@objc
open class NFX: NSObject {
    
    // MARK: - Properties
    #if os(OSX)
        var windowController: NFXMacWindowController?
        let mainMenu: NSMenu? = NSApp.mainMenu?.items[1].submenu
        var nfxMenuItem: NSMenuItem = NSMenuItem(title: "netfox", action: #selector(NFX.show), keyEquivalent: String.init(describing: (character: NSF9FunctionKey, length: 1)))
    #endif
    
    #if os(iOS)
        fileprivate var hostingViewController: UIViewController?
    #endif
    
    fileprivate enum Constants: String {
        case alreadyStartedMessage = "Already started!"
        case alreadyStoppedMessage = "Already stopped!"
        case startedMessage = "Started!"
        case stoppedMessage = "Stopped!"
    }
    
    fileprivate var started: Bool = false
    fileprivate var presented: Bool = false
    fileprivate var enabled: Bool = false
    fileprivate var selectedGesture: ENFXGesture = .shake
    fileprivate var ignoredURLs = [String]()
    fileprivate var ignoredURLsRegex = [NSRegularExpression]()
    fileprivate var lastVisitDate: Date = Date()
    
    internal var cacheStoragePolicy = URLCache.StoragePolicy.notAllowed
    
    /// Handles the "redirect requests to a mock server" feature.
    internal let mockServer = NFXMockServer()
    
    // swiftSharedInstance is not accessible from ObjC
    class var swiftSharedInstance: NFX {
        struct Singleton {
            static let instance = NFX()
        }
        return Singleton.instance
    }
    
    // the sharedInstance class method can be reached from ObjC
    @objc open class func sharedInstance() -> NFX {
        return NFX.swiftSharedInstance
    }
    
    @objc public enum ENFXGesture: Int {
        case shake
        case custom
    }

    @objc open func start() {
        guard !started else {
            showMessage(Constants.alreadyStartedMessage.rawValue)
            return
        }

        started = true
        URLSessionConfiguration.implementNetfox()
        register()
        enable()
        fileStorageInit()
        showMessage(Constants.startedMessage.rawValue)
        #if os(OSX)
        addNetfoxToMainMenu()
        #endif
    }
    
    @objc open func stop() {
        guard started else {
            showMessage(Constants.alreadyStoppedMessage.rawValue)
            return
        }
        
        unregister()
        disable()
        clearOldData()
        started = false
        showMessage(Constants.stoppedMessage.rawValue)
        #if os(OSX)
        removeNetfoxFromMainmenu()
        #endif
    }
    
    fileprivate func showMessage(_ msg: String) {
        print("netfox \(nfxVersion) - [https://github.com/rongxiong/netfox]: \(msg)")
    }
    
    internal func isEnabled() -> Bool {
        return enabled
    }
    
    internal func enable() {
        enabled = true
    }
    
    internal func disable() {
        enabled = false
    }
    
    fileprivate func register() {
        URLProtocol.registerClass(NFXProtocol.self)
    }
    
    fileprivate func unregister() {
        URLProtocol.unregisterClass(NFXProtocol.self)
    }
    
    @objc func motionDetected() {
        guard started else { return }
        toggleNFX()
    }
    
    @objc open func isStarted() -> Bool {
        return started
    }
    
    @objc open func setCachePolicy(_ policy: URLCache.StoragePolicy) {
        cacheStoragePolicy = policy
    }
    
    @objc open func setGesture(_ gesture: ENFXGesture) {
        selectedGesture = gesture
        #if os(OSX)
        if gesture == .shake {
            addNetfoxToMainMenu()
        } else {
            removeNetfoxFromMainmenu()
        }
        #endif
    }
    
    @objc open func show() {
        guard started else { return }
        showNFX()
    }
    
    #if os(iOS)
    @objc open func show(on rootViewController: UIViewController) {
        guard started, presented == false else { return }

        showNFX(on: rootViewController)
        presented = true
    }
    #endif
    
    @objc open func hide() {
        guard started else { return }
        hideNFX()
    }

    @objc open func toggle()
    {
        guard self.started else { return }
        toggleNFX()
    }
    
    @objc open func ignoreURL(_ url: String) {
        ignoredURLs.append(url)
    }
    
    @objc open func getSessionLog() -> Data? {
        return try? Data(contentsOf: NFXPath.sessionLogURL)
    }
    
    /// Redirects every intercepted request to the given mock server.
    /// The path and the query of the original request are preserved, only the
    /// scheme, host and port are replaced - e.g. "http://localhost:3000".
    /// Pass nil (or an empty string) to remove the mock server.
    @objc open func setMockServerURL(_ urlString: String?) {
        mockServer.setURLString(urlString)
    }
    
    /// Enables / disables the redirection to the mock server.
    /// Works independently from the logging switch.
    @objc open func setMockServerEnabled(_ enabled: Bool) {
        mockServer.setEnabled(enabled)
    }
    
    @objc open func isMockServerEnabled() -> Bool {
        return mockServer.configuration.isEnabled
    }
    
    @objc open func getMockServerURLString() -> String? {
        return mockServer.configuration.urlString
    }
    
    /// Per-URL mock mappings. Each key is matched as a substring of the request
    /// URL (fuzzy match); the matching value is the path served by the mock
    /// server, resolved against the mock server URL - e.g. after
    /// `setMockServerURL("http://localhost:3000")` the mapping
    /// ["api.github.com/users": "/users.json"] calls
    /// "http://localhost:3000/users.json". A value may also be an absolute URL
    /// when a mapping has to point somewhere else entirely.
    ///
    /// While at least one mapping is set, only the requests whose URL contains
    /// one of the keys are mocked. Pass an empty dictionary to fall back to
    /// mocking every request with the mock server URL.
    @objc open func setMockServerMappings(_ mappings: [String: String]) {
        mockServer.setMappings(mappings)
    }
    
    @objc open func getMockServerMappings() -> [String: String] {
        return mockServer.configuration.mappings
    }
    
    @objc open func ignoreURLs(_ urls: [String]) {
        ignoredURLs.append(contentsOf: urls)
    }
    
    @objc open func ignoreURLsWithRegex(_ regex: String) {
        ignoredURLsRegex.append(NSRegularExpression(regex))
    }
    
    @objc open func ignoreURLsWithRegexes(_ regexes: [String]) {
        ignoredURLsRegex.append(contentsOf: regexes.map { NSRegularExpression($0) })
    }
    
    internal func getLastVisitDate() -> Date {
        return lastVisitDate
    }
    
    fileprivate func showNFX() {
        if presented {
            return
        }
        
        showNFXFollowingPlatform()
        presented = true
    }
    
    fileprivate func hideNFX() {
        if !presented {
            return
        }
        
        hideNFXFollowingPlatform { () -> Void in
            self.presented = false
            self.lastVisitDate = Date()
        }
    }

    fileprivate func toggleNFX() {
        presented ? hideNFX() : showNFX()
    }
    
    private func fileStorageInit() {
        clearOldData()
        NFXPath.deleteOldNFXLogs()
        NFXPath.createNFXDirIfNotExist()
    }
    
    internal func clearOldData() {
        NFXHTTPModelManager.shared.clear()
        
        NFXPath.deleteNFXDir()
        NFXPath.createNFXDirIfNotExist()
    }
    
    func getIgnoredURLs() -> [String] {
        return ignoredURLs
    }
    
    func getIgnoredURLsRegexes() -> [NSRegularExpression] {
        return ignoredURLsRegex
    }
    
    func getSelectedGesture() -> ENFXGesture {
        return selectedGesture
    }

    /// True while netfox is presented through its own UIKit entry point
    /// (shake gesture / `show()`). Always false when the UI is embedded
    /// with the SwiftUI `netfoxPanel(isPresented:)` modifier.
    var isUIKitPresented: Bool {
        return presented
    }

}

#if os(iOS)

extension NFX {
    fileprivate var presentingViewController: UIViewController? {
        var rootViewController = UIWindow.keyWindow?.rootViewController
		while let controller = rootViewController?.presentedViewController {
			rootViewController = controller
		}
        return rootViewController
    }

    fileprivate func showNFXFollowingPlatform() {
        showNFX(on: presentingViewController)
    }
    
    fileprivate func showNFX(on rootViewController: UIViewController?) {
        let controller = UIHostingController(rootView: NetfoxView())
        controller.presentationController?.delegate = self

        rootViewController?.present(controller, animated: true, completion: nil)
        hostingViewController = controller
    }
    
    fileprivate func hideNFXFollowingPlatform(_ completion: (() -> Void)?) {
        if let presentingViewController = hostingViewController?.presentingViewController {
            presentingViewController.dismiss(animated: true, completion: completion)
        } else {
            hostingViewController?.dismiss(animated: true, completion: completion)
        }
        hostingViewController = nil
    }
}

extension NFX: UIAdaptivePresentationControllerDelegate {

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController)
    {
        guard self.started else { return }
        self.presented = false
    }
}

#elseif os(OSX)
    
extension NFX {
    
    public func windowDidClose() {
        presented = false
    }
    
    private func setupNetfoxMenuItem() {
        nfxMenuItem.target = self
        nfxMenuItem.action = #selector(NFX.motionDetected)
        nfxMenuItem.keyEquivalent = "n"
        nfxMenuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: UInt(Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)))
    }
    
    public func addNetfoxToMainMenu() {
        setupNetfoxMenuItem()
        if let menu = mainMenu {
            menu.insertItem(nfxMenuItem, at: 0)
        }
    }
    
    public func removeNetfoxFromMainmenu() {
        if let menu = mainMenu {
            menu.removeItem(nfxMenuItem)
        }
    }
    
    public func showNFXFollowingPlatform()  {
        if windowController == nil {
            windowController = NFXMacWindowController(rootView: NFXMacHostView())
        }
        windowController?.show()
    }
    
    public func hideNFXFollowingPlatform(completion: (() -> Void)?) {
        windowController?.close()
        if let notNilCompletion = completion {
            notNilCompletion()
        }
    }
}

#endif
