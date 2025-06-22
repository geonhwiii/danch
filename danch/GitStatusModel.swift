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
    private let fileManager = FileManager.default
    
    init() {
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        // 초기 상태 확인
        updateGitStatus()
        
        // 5초마다 Git 상태 업데이트
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateGitStatus()
            }
        }
    }
    
    private func updateGitStatus() {
        guard let currentDirectory = getCurrentWorkingDirectory() else {
            isGitRepository = false
            return
        }
        
        // Git 저장소인지 확인
        let gitDir = currentDirectory.appendingPathComponent(".git")
        isGitRepository = fileManager.fileExists(atPath: gitDir.path)
        
        if isGitRepository {
            updateBranchName(in: currentDirectory)
            updateFileStatus(in: currentDirectory)
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
        
        if trimmedContent.hasPrefix("ref: refs/heads/") {
            currentBranch = String(trimmedContent.dropFirst("ref: refs/heads/".count))
        } else {
            // Detached HEAD 상태
            let shortHash = String(trimmedContent.prefix(7))
            currentBranch = "HEAD \(shortHash)"
        }
    }
    
    private func updateFileStatus(in directory: URL) {
        // Git index 파일 확인으로 staged 파일 감지
        let indexFile = directory.appendingPathComponent(".git/index")
        let hasIndex = fileManager.fileExists(atPath: indexFile.path)
        
        // 간단한 파일 변경 감지 (실제로는 git status를 파싱해야 하지만 샌드박스 제한으로 파일 기반 접근)
        stagedFiles = hasIndex ? 1 : 0  // 실제 구현에서는 더 정교하게
        unstagedFiles = 0  // 추후 개선
        hasChanges = stagedFiles > 0 || unstagedFiles > 0
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
        isLoading = true
        lastError = nil
        
        // App Sandbox 환경에서는 Process 실행이 제한되므로
        // 실제 구현에서는 다른 방법을 사용해야 함
        // 여기서는 UI 시뮬레이션만 수행
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isLoading = false
            self?.updateGitStatus()
            
            // 성공 시뮬레이션
            print("Git command executed: git \(command) \(arguments.joined(separator: " "))")
        }
    }
} 