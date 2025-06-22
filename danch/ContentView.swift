//
//  ContentView.swift
//  danch
//
//  Created by 건휘 on 6/22/25.
//

import SwiftUI

struct NotchContentView: View {
    @EnvironmentObject var viewModel: NotchViewModel
    @StateObject private var gitModel = GitStatusModel()
    @State private var showingCommitInput = false
    @State private var commitMessage = ""
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: viewModel.isExpanded ? 32 : 16)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: viewModel.isExpanded ? 32 : 16)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            // 콘텐츠 영역
            VStack(spacing: 0) {
                // 축소 상태에서 보이는 부분 (항상 표시)
                compactContent
                    .frame(height: viewModel.isExpanded ? 28 : 32)
                
                // 확장 상태에서만 보이는 부분
                if viewModel.isExpanded {
                    expandedContent
                        .frame(maxHeight: 132)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, viewModel.isExpanded ? 16 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { _ in }
        )
    }
    
    // MARK: - Compact Content (축소 상태)
    private var compactContent: some View {
        HStack(spacing: 8) {
            // Git 상태 아이콘
            gitStatusIcon
            
            // 브랜치 이름
            if gitModel.isGitRepository {
                Text(gitModel.currentBranch)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            } else {
                Text("No Git")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 변경사항 표시
            if gitModel.hasChanges {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    // MARK: - Expanded Content (확장 상태)
    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Git 저장소 정보
            gitRepositoryInfo
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // 커밋 메시지 입력 (조건부 표시)
            if showingCommitInput {
                commitMessageInput
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else {
                // Git 명령어 버튼들
                gitActionButtons
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Git Status Icon
    private var gitStatusIcon: some View {
        Group {
            if gitModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if gitModel.isGitRepository {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(gitModel.hasChanges ? .orange : .green)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 16, height: 16)
    }
    
    // MARK: - Git Repository Info
    private var gitRepositoryInfo: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Branch:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text(gitModel.currentBranch)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            if gitModel.hasChanges {
                HStack {
                    Text("Changes:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        if gitModel.stagedFiles > 0 {
                            Label("\(gitModel.stagedFiles)", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                        
                        if gitModel.unstagedFiles > 0 {
                            Label("\(gitModel.unstagedFiles)", systemImage: "circle")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Git Action Buttons
    private var gitActionButtons: some View {
        HStack(spacing: 8) {
            // Add 버튼
            GitActionButton(
                title: "Add",
                icon: "plus.circle",
                color: .blue,
                isEnabled: gitModel.isGitRepository && !gitModel.isLoading
            ) {
                gitModel.gitAdd()
            }
            
            // Commit 버튼
            GitActionButton(
                title: "Commit",
                icon: "checkmark.circle",
                color: .green,
                isEnabled: gitModel.hasChanges && !gitModel.isLoading
            ) {
                showingCommitInput = true
            }
            
            // Push/Publish 버튼 (동적)
            if gitModel.hasRemoteTrackingBranch {
                // 원격 추적 브랜치가 있으면 Push 버튼
                GitActionButton(
                    title: "Push",
                    icon: "arrow.up.circle",
                    color: .blue,
                    isEnabled: !gitModel.isLoading && (gitModel.isAheadOfRemote || gitModel.hasChanges)
                ) {
                    gitModel.gitPush()
                }
            } else {
                // 원격 추적 브랜치가 없으면 Publish 버튼 (인증 상태에 따라 변경)
                publishButton
            }
        }
    }
    
    // MARK: - Publish Button (Dynamic)
    private var publishButton: some View {
        Group {
            switch gitModel.authStatus {
            case .unknown:
                GitActionButton(
                    title: "Publish",
                    icon: "cloud.upload",
                    color: .purple,
                    isEnabled: gitModel.isGitRepository && !gitModel.isLoading
                ) {
                    // 처음 클릭 시 인증 상태 확인
                    gitModel.checkAuthenticationStatus()
                }
                .onAppear {
                    // 버튼이 표시될 때 인증 상태 확인
                    gitModel.checkAuthenticationStatus()
                }
                
            case .checking:
                GitActionButton(
                    title: "Checking...",
                    icon: "clock",
                    color: .gray,
                    isEnabled: false
                ) {
                    // 확인 중에는 비활성화
                }
                
            case .authenticated:
                GitActionButton(
                    title: "Publish",
                    icon: "cloud.upload",
                    color: .green,
                    isEnabled: gitModel.isGitRepository && !gitModel.isLoading
                ) {
                    gitModel.gitPublish()
                }
                
            case .needsAuth:
                GitActionButton(
                    title: "Setup Auth",
                    icon: "key.fill",
                    color: .red,
                    isEnabled: true
                ) {
                    // 인증 설정 안내 또는 재확인
                    gitModel.checkAuthenticationStatus()
                }
            }
        }
    }
    
    // MARK: - Commit Message Input
    private var commitMessageInput: some View {
        VStack(spacing: 10) {
            // 제목과 닫기 버튼
            HStack {
                Text("Commit Message")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // 닫기 버튼 (배경 없는 원형)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCommitInput = false
                        commitMessage = ""
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // TextField와 커밋 버튼을 한 줄에
            HStack(spacing: 8) {
                // TextField
                TextField("Enter commit message...", text: $commitMessage)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(height: 32) // 고정 높이
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .onSubmit {
                        performCommit()
                    }
                
                // 커밋 버튼 (오른쪽에 배치)
                Button {
                    performCommit()
                } label: {
                    Text("Commit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(commitMessage.isEmpty ? Color.gray.opacity(0.3) : Color.green)
                        )
                }
                .disabled(commitMessage.isEmpty)
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity) // 전체 너비 사용
    }
    
    // MARK: - Helper Methods
    private func performCommit() {
        guard !commitMessage.isEmpty else { return }
        
        gitModel.gitCommit(message: commitMessage)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showingCommitInput = false
            commitMessage = ""
        }
    }

}

// MARK: - Git Action Button
struct GitActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isEnabled ? color : .gray)
            .frame(width: 60, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? color.opacity(0.15) : Color.clear)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Legacy ContentView for compatibility
struct ContentView: View {
    var body: some View {
        NotchContentView()
            .environmentObject(NotchViewModel())
    }
}

#Preview {
    NotchContentView()
        .environmentObject(NotchViewModel())
        .frame(width: 180, height: 32)
        .background(.gray.opacity(0.3))
}
