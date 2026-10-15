import Foundation
import SwiftUI

/// Shared transcript layout; each screen owns its scroll container.
struct ChatTranscriptView: View {
    let segments: [MeetingSegment]
    let selectable: Bool

    var body: some View {
        let groups = TranscriptGrouping.groups(from: segments)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                TranscriptGroupBubble(group: group, selectable: selectable)
            }
        }
    }
}

struct TranscriptGroupBubble: View {
    let group: TranscriptGroup
    let selectable: Bool

    private var speakerColor: Color {
        group.isPendingSpeaker ? .gray : speakerPaletteColor(group.speaker)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for segment in group.segments where !segment.text.isEmpty {
            if !result.characters.isEmpty { result.append(AttributedString(" ")) }
            var text = AttributedString(segment.text)
            text[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] =
                segment.isPending ? Color.secondary : Color.white.opacity(0.9)
            result.append(text)
        }
        return result
    }

    var body: some View {
        HStack {
            if group.isMe { Spacer(minLength: 48) }
            VStack(alignment: group.isMe ? .trailing : .leading, spacing: 4) {
                Text(group.isPendingSpeaker ? "…" : group.speaker.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(speakerColor)
                VStack(alignment: .leading, spacing: 6) {
                    let text = attributedText
                    if !text.characters.isEmpty {
                        if selectable {
                            Text(text).textSelection(.enabled)
                        } else {
                            Text(text)
                        }
                    }
                    if group.hasTypingTail { TypingIndicator() }
                }
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(speakerColor.opacity(group.isMe ? 0.25 : 0.18))
                }
                .overlay {
                    if group.isPendingSpeaker {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                Text(String(format: "%02d:%02d", Int(group.startTime) / 60, Int(group.startTime) % 60))
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            if !group.isMe { Spacer(minLength: 48) }
        }
    }
}

struct TypingIndicator: View {
    @State private var activeIndex = 0

    private let dotCount = 3
    private let animationInterval: TimeInterval = 0.4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(activeIndex == index ? 0.9 : 0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(activeIndex == index ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: animationInterval * 0.8), value: activeIndex)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(animationInterval))
                await MainActor.run {
                    activeIndex = (activeIndex + 1) % dotCount
                }
            }
        }
    }
}

