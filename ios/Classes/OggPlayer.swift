//
//  PlayerViewModel.swift
//  VLCKit-Example
//
//  Created by Ajith on 19/09/22.
//

import Foundation
import MobileVLCKit
import Combine

enum Status: Int {
  case stopped = 0
  case playing
  case paused
}

enum PlayerState: Comparable {
    case unknown
    case buffering
    case playing
    case paused
    case stopped
    case failed
    case ended

    var controlActionTitle: String {
        switch self {
        case .unknown, .paused, .stopped, .failed, .ended:
            return "Play"
        case .buffering:
            return "Loading..."
        case .playing:
            return "Pause"
        }
    }
}

struct Track {
    let filePath: URL
}

class OggPlayer: ObservableObject {
    @Published var playerState: PlayerState {
        didSet {
            controlButtonTitle = playerState.controlActionTitle
        }
    }

    var onStatusChanged: ((OggPlayer) -> Void)?

    @Synchronized(value: .stopped)
    fileprivate(set) var status: Status {
      didSet {
        self.onStatusChanged?(self)
      }
    }

    var playRate: Float = 1.0
    @Published var durationString: String = ""
    private(set) var controlButtonTitle: String
    var controlIconName: String {
        isPlaying ? "pause" : "play"
    }
    
    var postion : Double = 0

    let track: Track
    let path: String
    lazy var mediaPlayer = VLCMediaPlayer()
    var cancellable = Set<AnyCancellable>()

    // MARK: - Initializer

    init(track: Track, path: String) {
        let initialPlayerState = PlayerState.unknown
        self.controlButtonTitle = initialPlayerState.controlActionTitle
        self.playerState = initialPlayerState

        self.track = track
        self.path = path
        loadTrack(track)

        setupObservers()
    }

    deinit {
        cancelObservers()
    }

    // MARK: - Controls
    
    func newInit(){
        loadTrack(track)
        setupObservers()
    }

    func play() {
        self.mediaPlayer.play()
        status = Status.playing
    }

    func stop() {
        self.mediaPlayer.stop()
        status = Status.stopped
    }

    func pause() {
        self.mediaPlayer.pause()
        status = Status.stopped
    }

    func setPosition(_ position: Double) {
        self.mediaPlayer.position = Float(position)
    }

    // MARK: - Load Track

    private func loadTrack(_ track: Track) {
        let media = VLCMedia(url: track.filePath)
        mediaPlayer.media = media
    }

    // MARK: - Observers

    func setupObservers() {
        observeTimeElapsed()
        observeRemainingTime()
    }

    func cancelObservers() {
        cancellable.forEach { $0.cancel() }
    }

    private func observeRemainingTime() {
        mediaPlayer
            .publisher(for: \.state, options: [.new])
            .sink { state in
                print("remainingTime \(String(describing: state))")
                print("remainingTime \(state)")
                if(state.rawValue == 0){
                    self.status = Status.paused
                    self.newInit()
                }
            }
            .store(in: &cancellable)
    }

    private func observeTimeElapsed() {
        mediaPlayer
            .publisher(for: \.time, options: [.new])
            .sink { time in
                print("Time: \(time)")
                self.postion = time.value?.doubleValue ?? 0
            }
            .store(in: &cancellable)
    }

    // MARK: - Helpers

    var isPlaying: Bool {
        return playerState == .playing
    }

    var duration: Int {
        guard let lengthInMilliseconds = mediaLength?.intValue else {
            return 0
        }

        let msToSeconds = lengthInMilliseconds / 1000
        return Int(msToSeconds)
    }
    

    var formattedDuration: Double {
        return Double(mediaLength?.intValue ?? 0)
    }

    // MARK: - VLCKit Related

    private var mediaLength: VLCTime? {
        guard let nowPlusFive = Calendar.current.date(byAdding: .second,
                                                      value: 5,
                                                      to: Date()),
              let length = self.mediaPlayer.media?.lengthWait(until: nowPlusFive) else {
            return nil
        }
        return length
    }
}
