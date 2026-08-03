import Foundation

/// The AppKit/AVFoundation renderer implements this protocol. Keeping the
/// coordinator independent of AVFoundation makes display and playback policy
/// testable on CI without physical monitors or video hardware.
@MainActor
public protocol PlaybackSession: AnyObject {
    var currentURL: URL? { get }
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var hasPlaybackError: Bool { get }

    func load(url: URL, muted: Bool)
    func setMuted(_ muted: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func releaseResources()
}

/// Owns one independent session per display and applies one playback policy to
/// all of them. A single session is elected as the audio owner when unmuted.
@MainActor
public final class PlaybackCoordinator {
    public private(set) var currentURL: URL?
    public private(set) var wantsPlayback = false
    public private(set) var isMuted = true
    public private(set) var audioOwnerID: UInt32?

    private var sessions: [UInt32: any PlaybackSession] = [:]
    private let driftTolerance: Double

    public init(driftTolerance: Double = 0.25) {
        self.driftTolerance = driftTolerance
    }

    public var sessionIDs: [UInt32] {
        sessions.keys.sorted()
    }

    public var sessionCount: Int {
        sessions.count
    }

    public func addSession(
        id: UInt32,
        session: any PlaybackSession
    ) {
        let anchor = sessions[sessionIDs.first ?? id]?.currentTime
        sessions[id]?.releaseResources()
        sessions[id] = session
        if let currentURL {
            session.load(url: currentURL, muted: true)
            session.setMuted(isMuted || id != audioOwnerID)
            if wantsPlayback {
                session.play()
                if let anchor, anchor.isFinite {
                    session.seek(to: anchor)
                }
            } else {
                session.pause()
            }
        }
        applyAudioRouting()
    }

    public func removeSession(id: UInt32) {
        sessions.removeValue(forKey: id)?.releaseResources()
        if audioOwnerID == id {
            audioOwnerID = nil
            applyAudioRouting()
        }
    }

    public func setContent(url: URL?, muted: Bool) {
        isMuted = muted
        if currentURL == url {
            applyAudioRouting()
            return
        }

        currentURL = url
        for session in sessions.values {
            if let url {
                if session.currentURL != nil {
                    session.releaseResources()
                }
                session.load(url: url, muted: true)
            } else if session.currentURL != nil {
                session.releaseResources()
            }
        }
        applyAudioRouting()
        applyPlaybackState()
    }

    public func recoverFailedSessions() {
        guard let currentURL else { return }
        for id in sessionIDs where sessions[id]?.hasPlaybackError == true {
            guard let session = sessions[id] else { continue }
            session.releaseResources()
            session.load(url: currentURL, muted: true)
        }
        applyAudioRouting()
        applyPlaybackState()
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        applyAudioRouting()
    }

    public func play() {
        wantsPlayback = true
        applyPlaybackState()
    }

    public func pause() {
        wantsPlayback = false
        applyPlaybackState()
    }

    /// Correct only sessions that have drifted beyond the tolerance. This is
    /// intentionally cheap and is called periodically while playing rather
    /// than recreating players on every state notification.
    public func synchronizeDrift() {
        guard wantsPlayback, currentURL != nil else { return }
        guard let leaderID = sessionIDs.first,
              let leader = sessions[leaderID],
              leader.currentTime.isFinite else { return }
        for id in sessionIDs.dropFirst() {
            guard let session = sessions[id], session.currentTime.isFinite else {
                continue
            }
            if abs(session.currentTime - leader.currentTime) > driftTolerance {
                session.seek(to: leader.currentTime)
            }
        }
    }

    public func releaseAll() {
        for session in sessions.values {
            session.releaseResources()
        }
        sessions.removeAll()
        currentURL = nil
        wantsPlayback = false
        audioOwnerID = nil
    }

    private func applyPlaybackState() {
        guard currentURL != nil, wantsPlayback else {
            for session in sessions.values {
                session.pause()
            }
            return
        }

        let anchor = sessions[sessionIDs.first ?? 0]?.currentTime
        for session in sessions.values {
            session.play()
        }
        if let anchor, anchor.isFinite {
            for id in sessionIDs.dropFirst() {
                sessions[id]?.seek(to: anchor)
            }
        }
    }

    private func applyAudioRouting() {
        if isMuted || sessions.isEmpty {
            audioOwnerID = nil
        } else if audioOwnerID == nil || sessions[audioOwnerID!] == nil {
            audioOwnerID = sessionIDs.first
        }

        for id in sessionIDs {
            sessions[id]?.setMuted(isMuted || id != audioOwnerID)
        }
    }
}
