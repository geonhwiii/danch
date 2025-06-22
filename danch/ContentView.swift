//
//  ContentView.swift
//  danch
//
//  Created by 건휘 on 6/22/25.
//

import SwiftUI

struct NotchContentView: View {
    @EnvironmentObject var viewModel: NotchViewModel
    
    var body: some View {
        ZStack {
            // 노치 배경 - alcove 스타일
            RoundedRectangle(cornerRadius: viewModel.isExpanded ? 32 : 18)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: viewModel.isExpanded ? 32 : 18)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            // 콘텐츠 영역
            VStack(spacing: 0) {
                // 축소 상태에서 보이는 부분 (항상 표시)
                compactContent
                    .frame(height: viewModel.isExpanded ? 32 : 28)
                
                // 확장 상태에서만 보이는 부분
                if viewModel.isExpanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    let verticalTranslation = value.translation.height
                    if verticalTranslation > 30 && !viewModel.isExpanded {
                        viewModel.expand()
                    } else if verticalTranslation < -30 && viewModel.isExpanded {
                        viewModel.collapse()
                    }
                }
        )
    }
    
    // MARK: - Compact Content (항상 보이는 부분)
    private var compactContent: some View {
        HStack(spacing: viewModel.isExpanded ? 12 : 8) {
            // 시간 표시
            Text(formatTime(viewModel.currentTime))
                .font(.system(size: viewModel.isExpanded ? 14 : 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // 간단한 상태 표시
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                
                if viewModel.isExpanded {
                    Text("danch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, viewModel.isExpanded ? 16 : 12)
    }
    
    // MARK: - Expanded Content (확장 시에만 보이는 부분)
    private var expandedContent: some View {
        VStack(spacing: 16) {
            // 구분선
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 16)
            
            // 시간과 날짜 (더 큰 크기)
            VStack(spacing: 6) {
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formatDate(viewModel.currentTime))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // 추가 정보 영역
            HStack(spacing: 20) {
                // WiFi 상태
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                    
                    Text("연결됨")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // 간단한 액션 버튼
                Button(action: {
                    viewModel.collapse()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: date)
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
        .frame(width: 200, height: 32)
        .background(.gray.opacity(0.3))
}
