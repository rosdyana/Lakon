import AVFoundation
import CStbVorbis
import LakonCore

/// AudioManager stand-in: BGM / BGS / ME channels plus an SE pool on AVAudioEngine.
/// Formats: .ogg (stb_vorbis, honouring MZ's LOOPSTART/LOOPLENGTH comments), .m4a/.wav/.mp3/.caf via AVAudioFile.
final class AudioPlayer {
    static var volumes: [String: Double] = ["bgm": 0.9, "bgs": 0.9, "me": 0.9, "se": 0.9]

    struct Decoded { let buffer: AVAudioPCMBuffer; let loopStart: AVAudioFramePosition?; let loopLength: AVAudioFramePosition? }

    final class Channel {
        let node = AVAudioPlayerNode()
        let speed = AVAudioUnitVarispeed()
        var file: AudioFile?
        var baseVolume = 1.0
        var fadeFrames = 0, fadeTotal = 0
        var fadeIn = false
    }

    let project: Project
    let engine = AVAudioEngine()
    let bgm = Channel(), bgs = Channel(), me = Channel()
    var se: [Channel] = (0..<8).map { _ in Channel() }
    var seIndex = 0
    var cache: [String: Decoded] = [:]
    var started = false
    var bgmPausedForMe: AudioFile?

    /// Every buffer is converted to this format at decode time, so the graph is wired once.
    let format: AVAudioFormat

    init(project: Project) {
        self.project = project
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44100, channels: 2)!
        for c in [bgm, bgs, me] + se {
            engine.attach(c.node); engine.attach(c.speed)
            engine.connect(c.node, to: c.speed, format: format)
            engine.connect(c.speed, to: engine.mainMixerNode, format: format)
        }
        do { try engine.start(); started = true } catch { print("audio unavailable: \(error)") }
    }

    deinit { engine.stop() }

    // MARK: commands from the simulation

    func handle(_ cmds: [AudioCommand]) {
        guard started else { return }
        for c in cmds {
            switch c {
            case .playBgm(let f, _):
                if me.node.isPlaying { bgmPausedForMe = f; continue }
                play(bgm, f, folder: "bgm", loop: true)
            case .stopBgm: stop(bgm); bgmPausedForMe = nil
            case .fadeOutBgm(let s): fade(bgm, seconds: s)
            case .playBgs(let f): play(bgs, f, folder: "bgs", loop: true)
            case .stopBgs: stop(bgs)
            case .fadeOutBgs(let s): fade(bgs, seconds: s)
            case .playMe(let f):
                // ME interrupts the BGM, which resumes afterwards (AudioManager.playMe).
                if let cur = bgm.file, bgm.node.isPlaying { bgmPausedForMe = cur; stop(bgm) }
                play(me, f, folder: "me", loop: false) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, let b = self.bgmPausedForMe else { return }
                        self.bgmPausedForMe = nil
                        self.play(self.bgm, b, folder: "bgm", loop: true)
                        self.bgm.fadeIn = true; self.bgm.fadeTotal = 60; self.bgm.fadeFrames = 60; self.bgm.node.volume = 0
                    }
                }
            case .playSe(let f):
                let ch = se[seIndex]; seIndex = (seIndex + 1) % se.count
                play(ch, f, folder: "se", loop: false)
            case .stopSe: for c in se { stop(c) }
            }
        }
    }

    /// Call once per frame (fades).
    func update() {
        for c in [bgm, bgs] where c.fadeFrames > 0 {
            c.fadeFrames -= 1
            let t = Double(c.fadeFrames) / Double(max(1, c.fadeTotal))
            c.node.volume = Float(c.baseVolume * (c.fadeIn ? 1 - t : t))
            if c.fadeFrames == 0 && !c.fadeIn { stop(c) }
            if c.fadeFrames == 0 { c.fadeIn = false }
        }
    }

    func stopAll() { for c in [bgm, bgs, me] + se { stop(c) } }

    /// Editor preview.
    func preview(_ folder: String, _ name: String) {
        stopAll()
        play(folder == "se" ? se[0] : bgm, AudioFile(name), folder: folder, loop: folder == "bgm" || folder == "bgs")
    }

    // MARK: playback

    private func play(_ c: Channel, _ f: AudioFile, folder: String, loop: Bool, completion: (() -> Void)? = nil) {
        guard let d = decode(folder, f.name) else { return }
        c.node.stop()
        c.file = f
        c.baseVolume = Double(f.volume) / 100 * (Self.volumes[folder] ?? 0.9)
        c.node.volume = Float(c.baseVolume)
        c.node.pan = Float(f.pan) / 100
        c.speed.rate = Float(max(50, min(150, f.pitch))) / 100
        c.fadeFrames = 0; c.fadeIn = false
        if loop {
            if let ls = d.loopStart, let ll = d.loopLength, ls + ll <= AVAudioFramePosition(d.buffer.frameLength), ll > 0,
               let intro = slice(d.buffer, 0, ls + ll), let body = slice(d.buffer, ls, ll) {
                c.node.scheduleBuffer(intro, at: nil, options: [])
                c.node.scheduleBuffer(body, at: nil, options: [.loops])
            } else {
                c.node.scheduleBuffer(d.buffer, at: nil, options: [.loops])
            }
        } else {
            c.node.scheduleBuffer(d.buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in completion?() }
        }
        c.node.play()
    }

    private func stop(_ c: Channel) { c.node.stop(); c.file = nil; c.fadeFrames = 0 }

    private func fade(_ c: Channel, seconds: Int) {
        guard c.node.isPlaying else { return }
        if seconds <= 0 { stop(c); return }
        c.fadeIn = false; c.fadeTotal = seconds * 60; c.fadeFrames = seconds * 60
    }

    private func slice(_ b: AVAudioPCMBuffer, _ start: AVAudioFramePosition, _ length: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: AVAudioFrameCount(length)),
              let src = b.floatChannelData, let dst = out.floatChannelData else { return nil }
        for ch in 0..<Int(b.format.channelCount) { memcpy(dst[ch], src[ch] + Int(start), Int(length) * MemoryLayout<Float>.size) }
        out.frameLength = AVAudioFrameCount(length)
        return out
    }

    // MARK: decoding

    func decode(_ folder: String, _ name: String) -> Decoded? {
        guard !name.isEmpty else { return nil }
        let key = folder + "/" + name
        if let d = cache[key] { return d }
        guard let url = project.audioURL(folder, name) else { return nil }
        guard let raw = url.pathExtension.lowercased() == "ogg" ? Self.decodeOgg(url) : Self.decodeAV(url),
              let conv = convert(raw.buffer) else { return nil }
        let ratio = format.sampleRate / raw.buffer.format.sampleRate
        let d = Decoded(buffer: conv, loopStart: raw.loopStart.map { AVAudioFramePosition(Double($0) * ratio) },
                        loopLength: raw.loopLength.map { AVAudioFramePosition(Double($0) * ratio) })
        cache[key] = d
        return d
    }

    /// Resample / up-mix to the engine format (AVAudioConverter).
    func convert(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if b.format == format { return b }
        guard let conv = AVAudioConverter(from: b.format, to: format) else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * format.sampleRate / b.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return b
        }
        return err == nil ? out : nil
    }

    static func decodeAV(_ url: URL) -> Decoded? {
        guard let f = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return nil }
        do { try f.read(into: buf) } catch { return nil }
        return Decoded(buffer: buf, loopStart: nil, loopLength: nil)
    }

    static func decodeOgg(_ url: URL) -> Decoded? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.withUnsafeBytes { raw -> Decoded? in
            var err: Int32 = 0
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress,
                  let v = stb_vorbis_open_memory(base, Int32(data.count), &err, nil) else { return nil }
            defer { stb_vorbis_close(v) }
            let info = stb_vorbis_get_info(v)
            let channels = Int(info.channels), total = Int(stb_vorbis_stream_length_in_samples(v))
            guard channels > 0, total > 0,
                  let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(info.sample_rate), channels: AVAudioChannelCount(channels)),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(total)),
                  let dst = buf.floatChannelData else { return nil }
            var interleaved = [Float](repeating: 0, count: total * channels)
            let got = interleaved.withUnsafeMutableBufferPointer { p in
                Int(stb_vorbis_get_samples_float_interleaved(v, Int32(channels), p.baseAddress, Int32(total * channels)))
            }
            for i in 0..<got { for ch in 0..<channels { dst[ch][i] = interleaved[i * channels + ch] } }
            buf.frameLength = AVAudioFrameCount(got)
            // RPG Maker loop tags in Vorbis comments.
            var loopStart: AVAudioFramePosition?, loopLength: AVAudioFramePosition?
            let comments = stb_vorbis_get_comment(v)
            for i in 0..<Int(comments.comment_list_length) {
                guard let cstr = comments.comment_list[i] else { continue }
                let s = String(cString: cstr).uppercased()
                if s.hasPrefix("LOOPSTART=") { loopStart = AVAudioFramePosition(s.dropFirst(10)) }
                if s.hasPrefix("LOOPLENGTH=") { loopLength = AVAudioFramePosition(s.dropFirst(11)) }
            }
            return Decoded(buffer: buf, loopStart: loopStart, loopLength: loopLength)
        }
    }
}
