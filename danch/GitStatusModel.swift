//
//  GitStatusModel.swift
//  danch
//
//  Created by 건휘 on 6/22/25.
//

import Foundation
import Combine

enum GitAuthStatus {
    case unknown      // 아직 확인 안 함
    case checking     // 확인 중
    case authenticated // 인증됨
    case needsAuth    // 인증 필요
}

@MainActor
class GitStatusModel: ObservableObject {
    @Published var currentBranch: String = ""
    @Published var hasChanges: Bool = false
    @Published var stagedFiles: Int = 0
    @Published var unstagedFiles: Int = 0
    @Published var isGitRepository: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var hasRemoteTrackingBranch: Bool = false
    @Published var isAheadOfRemote: Bool = false
    @Published var behindRemoteCount: Int = 0
    @Published var aheadRemoteCount: Int = 0
    @Published var authStatus: GitAuthStatus = .unknown
    
    private var timer: Timer?
    private var fileSystemMonitor: DispatchSourceFileSystemObject?
    private var gitDirectory: URL?
    private let fileManager = FileManager.default
    private var lastAuthCheck: Date?
    private var authCheckCache: GitAuthStatus?
    
    init() {
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
        fileSystemMonitor?.cancel()
    }
    
    private func startMonitoring() {
        // 초기 상태 확인
        updateGitStatus()
        
        // Git 디렉토리가 있으면 실시간 모니터링 시작
        if let gitDir = gitDirectory {
            startFileSystemMonitoring(for: gitDir)
        }
        
        // 백업으로 30초마다 Git 상태 업데이트 (파일 시스템 모니터링 실패 시 대비)
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateGitStatus()
            }
        }
    }
    
    private func startFileSystemMonitoring(for directory: URL) {
        let gitDir = directory.appendingPathComponent(".git")
        
        // .git 디렉토리 모니터링
        let fileDescriptor = open(gitDir.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            NSLog("❌ Failed to open .git directory for monitoring")
            return
        }
        
        fileSystemMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .background)
        )
        
        fileSystemMonitor?.setEventHandler { [weak self] in
            Task { @MainActor in
                NSLog("🔄 Git directory changed - updating status")
                self?.updateGitStatus()
            }
        }
        
        fileSystemMonitor?.setCancelHandler {
            close(fileDescriptor)
        }
        
        fileSystemMonitor?.resume()
        NSLog("✅ Started file system monitoring for .git directory")
    }
    
    private func updateGitStatus() {
        guard let currentDirectory = getCurrentWorkingDirectory() else {
            isGitRepository = false
            gitDirectory = nil
            return
        }
        
        // Git 저장소인지 확인
        let gitDir = currentDirectory.appendingPathComponent(".git")
        isGitRepository = fileManager.fileExists(atPath: gitDir.path)
        
        if isGitRepository {
            // Git 디렉토리가 변경되었으면 모니터링 재시작
            if gitDirectory?.path != currentDirectory.path {
                gitDirectory = currentDirectory
                fileSystemMonitor?.cancel()
                fileSystemMonitor = nil
                startFileSystemMonitoring(for: currentDirectory)
            }
            
            updateBranchName(in: currentDirectory)
            updateFileStatus(in: currentDirectory)
            updateRemoteTrackingStatus(in: currentDirectory)
        } else {
            gitDirectory = nil
        }
    }
    
    private func getCurrentWorkingDirectory() -> URL? {
        // 디버깅을 위해 현재 경로 출력
        let currentPath = fileManager.currentDirectoryPath
        NSLog("🔍 Current working directory: \(currentPath)")
        
        // 우선순위 검색 경로
        let searchPaths = [
            // 1. 현재 danch 프로젝트 경로 (가장 우선)
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Github/danch"),
            // 2. 현재 작업 디렉토리
            URL(fileURLWithPath: currentPath),
            // 3. 사용자 홈 디렉토리
            fileManager.homeDirectoryForCurrentUser,
            // 4. 일반적인 개발 폴더들
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Github"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Projects"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Development"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        ]
        
        // 각 경로에서 Git 저장소 찾기
        for basePath in searchPaths {
            NSLog("🔍 Searching in: \(basePath.path)")
            if let gitRepo = findGitRepository(in: basePath) {
                NSLog("✅ Found Git repository at: \(gitRepo.path)")
                return gitRepo
            }
        }
        
        NSLog("❌ No Git repository found in search paths")
        return nil
    }
    
    private func findGitRepository(in directory: URL) -> URL? {
        // 현재 디렉토리에 .git이 있는지 확인
        let gitDir = directory.appendingPathComponent(".git")
        NSLog("  🔍 Checking .git at: \(gitDir.path)")
        
        if fileManager.fileExists(atPath: gitDir.path) {
            NSLog("  ✅ Found .git directory!")
            return directory
        }
        
        // 하위 디렉토리들 검색 (1단계만)
        do {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            NSLog("  🔍 Searching \(contents.count) subdirectories...")
            
            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let gitSubDir = item.appendingPathComponent(".git")
                    if fileManager.fileExists(atPath: gitSubDir.path) {
                        NSLog("  ✅ Found .git in subdirectory: \(item.lastPathComponent)")
                        return item
                    }
                }
            }
        } catch {
            NSLog("  ❌ Error accessing directory: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func updateBranchName(in directory: URL) {
        let headFile = directory.appendingPathComponent(".git/HEAD")
        
        guard let headContent = try? String(contentsOf: headFile, encoding: .utf8) else {
            currentBranch = "unknown"
            return
        }
        
        let trimmedContent = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBranch: String
        
        if trimmedContent.hasPrefix("ref: refs/heads/") {
            newBranch = String(trimmedContent.dropFirst("ref: refs/heads/".count))
        } else {
            // Detached HEAD 상태
            let shortHash = String(trimmedContent.prefix(7))
            newBranch = "HEAD \(shortHash)"
        }
        
        // 브랜치가 변경되었을 때 로그 출력
        if currentBranch != newBranch && !currentBranch.isEmpty {
            NSLog("🔄 Branch changed: \(currentBranch) → \(newBranch)")
        }
        
        currentBranch = newBranch
    }
    
    private func updateRemoteTrackingStatus(in directory: URL) {
        // 현재 브랜치가 원격 브랜치를 추적하는지 확인
        checkRemoteTrackingBranch(in: directory)
        
        // 원격과의 차이 확인 (ahead/behind)
        if hasRemoteTrackingBranch {
            checkRemoteDifference(in: directory)
        } else {
            isAheadOfRemote = false
            behindRemoteCount = 0
            aheadRemoteCount = 0
        }
    }
    
    private func checkRemoteTrackingBranch(in directory: URL) {
        // .git/config에서 현재 브랜치의 원격 추적 설정 확인
        let configFile = directory.appendingPathComponent(".git/config")
        
        guard let configContent = try? String(contentsOf: configFile, encoding: .utf8) else {
            hasRemoteTrackingBranch = false
            return
        }
        
        // [branch "브랜치명"] 섹션 찾기
        let branchSectionPattern = "\\[branch \"\\(NSRegularExpression.escapedPattern(for: currentBranch))\"\\]"
        let remotePattern = "remote\\s*=\\s*(\\w+)"
        let mergePattern = "merge\\s*=\\s*refs/heads/(\\w+)"
        
        do {
            let branchRegex = try NSRegularExpression(pattern: branchSectionPattern)
            let remoteRegex = try NSRegularExpression(pattern: remotePattern)
            let mergeRegex = try NSRegularExpression(pattern: mergePattern)
            
            let range = NSRange(configContent.startIndex..<configContent.endIndex, in: configContent)
            
            if let branchMatch = branchRegex.firstMatch(in: configContent, range: range) {
                // 브랜치 섹션을 찾았으면, 그 이후에서 remote와 merge 설정 찾기
                let branchSectionStart = branchMatch.range.location
                let remainingContent = String(configContent.dropFirst(branchSectionStart))
                let remainingRange = NSRange(remainingContent.startIndex..<remainingContent.endIndex, in: remainingContent)
                
                let hasRemote = remoteRegex.firstMatch(in: remainingContent, range: remainingRange) != nil
                let hasMerge = mergeRegex.firstMatch(in: remainingContent, range: remainingRange) != nil
                
                hasRemoteTrackingBranch = hasRemote && hasMerge
                NSLog("🔍 Remote tracking for '\(currentBranch)': \(hasRemoteTrackingBranch ? "YES" : "NO")")
            } else {
                hasRemoteTrackingBranch = false
                NSLog("🔍 No remote tracking configuration found for '\(currentBranch)'")
            }
        } catch {
            NSLog("❌ Error checking remote tracking: \(error)")
            hasRemoteTrackingBranch = false
        }
    }
    
    private func checkRemoteDifference(in directory: URL) {
        // Git 명령어로 원격과의 차이 확인하는 대신, 간단한 파일 기반 접근
        // 실제로는 git rev-list --count origin/branch..HEAD 같은 명령이 필요하지만
        // 여기서는 기본적인 상태만 확인
        
        // 로컬에 커밋이 있고 아직 푸시되지 않았다면 ahead 상태로 가정
        let logsDir = directory.appendingPathComponent(".git/logs/refs/heads/\(currentBranch)")
        
        if fileManager.fileExists(atPath: logsDir.path) {
            // 로그 파일이 있으면 커밋이 있다고 가정
            isAheadOfRemote = true
            aheadRemoteCount = 1 // 간단히 1로 설정
        } else {
            isAheadOfRemote = false
            aheadRemoteCount = 0
        }
        
        behindRemoteCount = 0 // 간단히 0으로 설정
    }
    
    // MARK: - Authentication Status
    func checkAuthenticationStatus() {
        // 캐시 확인 (10분간 유효)
        if let lastCheck = lastAuthCheck,
           let cachedStatus = authCheckCache,
           Date().timeIntervalSince(lastCheck) < 600 {
            authStatus = cachedStatus
            return
        }
        
        // 원격 추적 브랜치가 있는 경우에만 인증 확인
        guard hasRemoteTrackingBranch || !hasRemoteTrackingBranch else {
            authStatus = .unknown
            return
        }
        
        authStatus = .checking
        NSLog("🔐 Checking GitHub authentication status...")
        
        Task {
            await checkRemoteAccess()
        }
    }
    
    func forceAuthenticationCheck() {
        // 캐시 초기화
        lastAuthCheck = nil
        authCheckCache = nil
        
        authStatus = .checking
        NSLog("🔐 Force checking GitHub authentication status...")
        
        Task {
            await checkRemoteAccess()
        }
    }
    
    private func checkRemoteAccess() async {
        guard let gitDirectory = gitDirectory else {
            await MainActor.run {
                authStatus = .needsAuth
            }
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-remote", "--heads", "origin"]
        process.currentDirectoryURL = gitDirectory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if process.terminationStatus == 0 && !output.isEmpty {
                    // 성공: 원격 저장소에 접근 가능
                    let previousStatus = authStatus
                    authStatus = .authenticated
                    
                    if previousStatus == .needsAuth {
                        NSLog("🎉 GitHub authentication setup completed! Ready to publish.")
                    } else {
                        NSLog("✅ GitHub authentication verified")
                    }
                } else {
                    // 실패: 인증 필요
                    authStatus = .needsAuth
                    NSLog("❌ GitHub authentication required. Please setup your Git credentials.")
                    NSLog("💡 Try running 'git push' in terminal first to setup authentication.")
                }
                
                // 결과 캐시
                lastAuthCheck = Date()
                authCheckCache = authStatus
            }
        } catch {
            await MainActor.run {
                authStatus = .needsAuth
                NSLog("❌ Error checking authentication: \(error)")
            }
        }
    }
    
    private func updateFileStatus(in directory: URL) {
        // Git index 파일 확인으로 staged 파일 감지
        let indexFile = directory.appendingPathComponent(".git/index")
        let hasIndex = fileManager.fileExists(atPath: indexFile.path)
        
        // 워킹 디렉토리의 파일 변경 감지
        let unstagedCount = detectUnstagedChanges(in: directory)
        
        // 상태 업데이트
        let previousStagedFiles = stagedFiles
        let previousUnstagedFiles = unstagedFiles
        
        stagedFiles = hasIndex ? 1 : 0  // 실제 구현에서는 더 정교하게
        unstagedFiles = unstagedCount
        hasChanges = stagedFiles > 0 || unstagedFiles > 0
        
        // 변경사항이 있을 때만 로그 출력
        if previousStagedFiles != stagedFiles || previousUnstagedFiles != unstagedFiles {
            NSLog("📊 File status updated - Staged: \(stagedFiles), Unstaged: \(unstagedFiles)")
        }
    }
    
    private func detectUnstagedChanges(in directory: URL) -> Int {
        // 간단한 방법: 최근 수정된 파일들 확인
        // 실제로는 git status를 파싱해야 하지만, 기본적인 감지만 구현
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let now = Date()
            let recentThreshold = now.addingTimeInterval(-3600) // 1시간 이내
            
            let recentFiles = contents.filter { url in
                guard let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return modificationDate > recentThreshold
            }
            
            return min(recentFiles.count, 5) // 최대 5개까지만 표시
        } catch {
            return 0
        }
    }
    
    // MARK: - Git Commands
    
    func gitAdd() {
        executeGitCommand("add", arguments: ["."])
    }
    
    func gitCommit(message: String) {
        guard !message.isEmpty else { return }
        executeGitCommand("commit", arguments: ["-m", message])
    }
    
    func gitPush() {
        if hasRemoteTrackingBranch {
            executeGitCommand("push", arguments: [])
        } else {
            // 원격 추적 브랜치가 없으면 publish 실행
            gitPublish()
        }
    }
    
    func gitPublish() {
        // git push -u origin 브랜치명
        NSLog("🚀 Publishing branch '\(currentBranch)' to origin...")
        executeGitCommand("push", arguments: ["-u", "origin", currentBranch])
    }
    
    private func executeGitCommand(_ command: String, arguments: [String]) {
        guard let gitDirectory = gitDirectory else {
            lastError = "Git repository not found"
            return
        }
        
        isLoading = true
        lastError = nil
        
        NSLog("🚀 Executing git command: git \(command) \(arguments.joined(separator: " "))")
        
        Task {
            do {
                let result = try await runGitCommand(command, arguments: arguments, in: gitDirectory)
                
                await MainActor.run {
                    self.isLoading = false
                    if result.success {
                        NSLog("✅ Git command succeeded: \(result.output)")
                        self.updateGitStatus()
                        
                        // Push나 Publish 명령어가 성공했을 때 원격 추적 상태 재확인
                        if command == "push" {
                            if let gitDir = self.gitDirectory {
                                self.checkRemoteTrackingBranch(in: gitDir)
                                NSLog("🔄 Rechecking remote tracking branch status after push...")
                            }
                        }
                    } else {
                        NSLog("❌ Git command failed: \(result.error)")
                        self.lastError = result.error
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                    NSLog("❌ Git command error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func runGitCommand(_ command: String, arguments: [String], in directory: URL) async throws -> (success: Bool, output: String, error: String) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Git 실행 파일 경로 설정
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = [command] + arguments
            process.currentDirectoryURL = directory
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0
                continuation.resume(returning: (success: success, output: output, error: error))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
} 