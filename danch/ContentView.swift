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
            
            // Git 명령어 버튼들
            gitActionButtons
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
                gitModel.gitCommit(message: "Quick commit from danch")
            }
            
            // Push 버튼
            GitActionButton(
                title: "Push",
                icon: "arrow.up.circle",
                color: .purple,
                isEnabled: gitModel.isGitRepository && !gitModel.isLoading
            ) {
                gitModel.gitPush()
            }
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
