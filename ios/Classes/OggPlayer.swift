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
  case initial = 0
  case playing = 1
  case paused = 2
  case stopped = 3
}

struct Track {
    let filePath: URL
}

class OggPlayer: ObservableObject {
    
    var onStatusChanged: ((OggPlayer) -> Void)?

    @Synchronized(value: .stopped)
    fileprivate(set) var status: Status {
      didSet {
        self.onStatusChanged?(self)
      }
    }

    var playRate: Float = 1.0 {
        didSet {
          mediaPlayer.rate = playRate
        }
    }
    
    var postion : Int = 0

    let track: Track
    let path: String
    lazy var mediaPlayer = VLCMediaPlayer()
    var cancellable = Set<AnyCancellable>()

    // MARK: - Initializer

    init(track: Track, path: String) {
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
    }

    func stop() {
        self.mediaPlayer.stop()
    }

    func pause() {
        self.mediaPlayer.pause()
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
        observeRemainingState()
    }

    func cancelObservers() {
        cancellable.forEach { $0.cancel() }
    }

    private func observeRemainingState() {
        mediaPlayer
            .publisher(for: \.state, options: [.new])
            .sink { state in
//                print("Player State \(String(describing: state))")
//                print("state \(state)")
                if (state.rawValue == 0) {
                    self.status = Status.paused
                    self.newInit()
                } else if( state.rawValue == 6) {
                    self.status = Status.paused
                } else if(state.rawValue == 5) {
                    self.status = Status.playing
                }
            }
            .store(in: &cancellable)
    }

    private func observeTimeElapsed() {
        mediaPlayer
            .publisher(for: \.time, options: [.new])
            .sink { time in
//                print("Time: \(time)")
//                print("postion: \(time.value?.doubleValue ?? 0)")
                self.postion = Int((time.value?.intValue ?? 0) / 1000)
                if (time.stringValue == "--:--") {
                    self.status = Status.initial
                }
            }
            .store(in: &cancellable)
    }

    // MARK: - Helpers

    var isPlaying: Bool {
        return status == .playing
    }

    var duration: Int {
        guard let lengthInMilliseconds = mediaLength?.intValue else {
            return 0
        }
        let msToSeconds: Int = Int(lengthInMilliseconds / 1000)
        return msToSeconds
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
