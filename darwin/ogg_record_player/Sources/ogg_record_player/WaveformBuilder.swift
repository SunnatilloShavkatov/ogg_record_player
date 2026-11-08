import Foundation

/// Collects one peak per `peakSampleScope` PCM samples while recording and reduces them to the
/// `numberOfIntensities` bytes the Dart side draws as a waveform.
struct WaveformBuilder {
  private let peakSampleScope = 100
  private let numberOfIntensities = 100

  private var peaks = Data()
  private var currentPeak: UInt16 = 0
  private var currentPeakCount = 0

  mutating func append(pcmData: Data) {
    let numberOfSamples = pcmData.count / MemoryLayout<Int16>.size
    guard numberOfSamples > 0 else {
      return
    }
    pcmData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
      let samples = ptr.bindMemory(to: Int16.self)
      for i in 0 ..< numberOfSamples {
        currentPeak = max(currentPeak, Self.magnitude(of: samples[i]))
        currentPeakCount += 1
        if currentPeakCount >= peakSampleScope {
          withUnsafeBytes(of: currentPeak) { peaks.append(contentsOf: $0) }
          currentPeak = 0
          currentPeakCount = 0
        }
      }
    }
  }

  func makeWaveform() -> Data {
    var intensities = [UInt8](repeating: 0, count: numberOfIntensities)
    let numberOfRawSamples = peaks.count / MemoryLayout<UInt16>.size
    guard numberOfRawSamples > 0 else {
      return Data(intensities)
    }
    peaks.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
      let rawSamples = ptr.bindMemory(to: UInt16.self)
      var minRawSample: UInt16 = .max
      var maxRawSample: UInt16 = 0
      for i in 0 ..< numberOfRawSamples {
        minRawSample = min(minRawSample, rawSamples[i])
        maxRawSample = max(maxRawSample, rawSamples[i])
      }
      let rawRange = UInt32(maxRawSample) - UInt32(minRawSample)
      guard rawRange > 0 else {
        if maxRawSample > 0 {
          for i in 0 ..< numberOfRawSamples {
            intensities[i * numberOfIntensities / numberOfRawSamples] = UInt8.max
          }
        }
        return
      }
      let delta = Float(UInt8.max) / Float(rawRange)
      for i in 0 ..< numberOfRawSamples {
        let intensity = min(Float(UInt8.max), Float(rawSamples[i]) * delta)
        intensities[i * numberOfIntensities / numberOfRawSamples] = UInt8(intensity)
      }
    }
    return Data(intensities)
  }

  private static func magnitude(of sample: Int16) -> UInt16 {
    // `abs(Int16.min)` overflows because 32768 is not representable as Int16.
    if sample == .min {
      return UInt16(Int(Int16.max) + 1)
    }
    return UInt16(abs(Int(sample)))
  }
}
