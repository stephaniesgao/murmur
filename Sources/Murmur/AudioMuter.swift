import CoreAudio
import AudioToolbox

/// Mutes the current output device while dictating (optional, “Mute audio while
/// dictating”) and puts it back exactly as it was afterwards.
final class AudioMuter {
    private var device: AudioDeviceID?
    private var mutedByUs = false
    private var savedVolume: Float32?

    func mute() {
        guard device == nil, let output = Self.defaultOutput() else { return }
        device = output
        var muteAddress = Self.address(kAudioDevicePropertyMute)
        var current: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(output, &muteAddress, &settable) == noErr, settable.boolValue,
           AudioObjectGetPropertyData(output, &muteAddress, 0, nil, &size, &current) == noErr {
            guard current == 0 else { return } // Already muted: leave it alone.
            var on: UInt32 = 1
            if AudioObjectSetPropertyData(output, &muteAddress, 0, nil, size, &on) == noErr { mutedByUs = true; return }
        }
        // Some devices have no mute control; fall back to volume 0 and restore the level later.
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume: Float32 = 0; var volumeSize = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(output, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr, volume > 0 else { return }
        var zero: Float32 = 0
        if AudioObjectSetPropertyData(output, &volumeAddress, 0, nil, volumeSize, &zero) == noErr { savedVolume = volume }
    }

    func restore() {
        guard let output = device else { return }
        if mutedByUs {
            var muteAddress = Self.address(kAudioDevicePropertyMute); var off: UInt32 = 0
            AudioObjectSetPropertyData(output, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
        }
        if var volume = savedVolume {
            var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(output, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        }
        device = nil; mutedByUs = false; savedVolume = nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private static func defaultOutput() -> AudioDeviceID? {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }
}
