import Foundation

/// A speaker turn whose identity follows its first segment.
struct TranscriptGroup: Identifiable {
    let id: UUID
    var speaker: Speaker
    var segments: [MeetingSegment]

    var startTime: TimeInterval { segments.first?.startTime ?? 0 }
    var endTime: TimeInterval { segments.last?.endTime ?? 0 }
    var isMe: Bool { speaker == .me }
    var isPendingSpeaker: Bool { speaker == .pending }
    var hasTypingTail: Bool {
        guard let last = segments.last else { return false }
        return last.isPending && last.text.isEmpty
    }
}

enum TranscriptGrouping {
    /// Input is already ordered by start time. Pending remote phrases extend a remote turn.
    static func groups(from segments: [MeetingSegment], maxGap: TimeInterval = 30) -> [TranscriptGroup] {
        var groups: [TranscriptGroup] = []
        for segment in segments {
            let key = segment.displaySpeaker
            if let last = groups.last,
               segment.startTime - last.endTime <= maxGap,
               (key == .pending && !last.isMe || key == last.speaker || last.isPendingSpeaker && key != .me) {
                let index = groups.count - 1
                if last.isPendingSpeaker && key != .pending {
                    groups[index].speaker = key
                }
                groups[index].segments.append(segment)
            } else {
                groups.append(TranscriptGroup(id: segment.id, speaker: key, segments: [segment]))
            }
        }
        return groups
    }
}
