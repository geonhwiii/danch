//
//  GitStatusModel.swift
//  danch
//
//  Created by 건휘 on 6/22/25.
//

import Foundation
import Combine

@MainActor
class GitStatusModel: ObservableObject {
    @Published var currentBranch: String = ""
    @Published var hasChanges: Bool = false
    @Published var stagedFiles: Int = 0
    @Published var unstagedFiles: Int = 0
    @Published var isGitRepository: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    private var timer: Timer?
    private var fileSystemMonitor: DispatchSourceFileSystemObject?
    private var gitDirectory: URL?
    private let fileManager = FileManager.default
    
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
        executeGitCommand("push", arguments: [])
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