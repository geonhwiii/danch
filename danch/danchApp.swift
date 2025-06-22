//
//  danchApp.swift
//  danch
//
//  Created by 건휘 on 6/22/25.
//

import SwiftUI
import AppKit
import Combine

@main
struct danchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindow: NotchWindow?
    private let notchViewModel = NotchViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 독에서 앱 아이콘 숨기기
        NSApp.setActivationPolicy(.accessory)
        
        createNotchWindow()
    }
    
    private func createNotchWindow() {
        let window = NotchWindow()
        let trackingView = NotchTrackingView(viewModel: notchViewModel)
        let hostingView = NSHostingView(rootView: NotchContentView().environmentObject(notchViewModel))
        
        trackingView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: trackingView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: trackingView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trackingView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: trackingView.bottomAnchor)
        ])
        
        window.contentView = trackingView
        window.makeKeyAndOrderFront(nil)
        
        self.notchWindow = window
        
        // 윈도우 크기 변경 감지
        notchViewModel.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak window] isExpanded in
                guard let window = window else { return }
                
                let newSize = isExpanded ? 
                    NSSize(width: 420, height: 200) : 
                    NSSize(width: 180, height: 32)
                
                let screenFrame = NSScreen.main?.frame ?? .zero
                let notchX = (screenFrame.width - newSize.width) / 2
                
                let fixedNotchTop = screenFrame.height
                let notchY = fixedNotchTop - newSize.height
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(
                        NSRect(x: notchX, y: notchY, width: newSize.width, height: newSize.height),
                        display: true
                    )
                }
            }
            .store(in: &notchViewModel.cancellables)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// MARK: - Custom Window Class
class NotchWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // 노치 위치 계산
        let screenFrame = NSScreen.main?.frame ?? .zero
        let notchWidth: CGFloat = 180
        let notchHeight: CGFloat = 32
        let notchX = (screenFrame.width - notchWidth) / 2
        
        let fixedNotchTop = screenFrame.height
        let notchY = fixedNotchTop - notchHeight
        
        let windowRect = NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
        
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Custom Tracking View
class NotchTrackingView: NSView {
    private let viewModel: NotchViewModel
    private var trackingArea: NSTrackingArea?
    private var collapseTimer: Timer?
    
    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        setupTrackingArea()
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        collapseTimer?.invalidate()
        viewModel.expand()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.viewModel.collapse()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        viewModel.toggle()
    }
}

// MARK: - NotchViewModel
class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    
    var cancellables = Set<AnyCancellable>()
    
    func expand() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isExpanded = true
            }
        }
    }
    
    func collapse() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isExpanded = false
            }
        }
    }
    
    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
    

}
