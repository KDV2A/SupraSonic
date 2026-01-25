import AVFoundation
import CoreAudio

class AudioDeviceManager {
    static let shared = AudioDeviceManager()
    
    struct AudioDevice: Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let isInput: Bool
    }
    
    func getInputDevices() -> [AudioDevice] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs)
        
        var inputDevices: [AudioDevice] = []
        
        for deviceID in deviceIDs {
            if isInputDevice(deviceID), let device = getDeviceInfo(deviceID) {
                // Filter out internal system handles and aggregate devices
                let nameLower = device.name.lowercased()
                let uidLower = device.uid.lowercased()
                
                let isFiltered = nameLower.contains("aggregate") || 
                                 nameLower.contains("default") || 
                                 nameLower.contains("system") ||
                                 uidLower.contains("aggregate") ||
                                 uidLower.contains("caddefault")
                
                if !isFiltered {
                    inputDevices.append(device)
                }
            }
        }
        
        return inputDevices
    }
    
    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        return status == noErr && propertySize > 0
    }
    
    private func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDevice? {
        // Get device name
        var propertySize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        let nameStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name)
        
        guard nameStatus == noErr else { return nil }
        
        // Get device UID
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        propertySize = UInt32(MemoryLayout<CFString>.size)
        
        var uid: CFString = "" as CFString
        let uidStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &uid)
        
        guard uidStatus == noErr else { return nil }
        
        return AudioDevice(
            id: deviceID,
            uid: uid as String,
            name: name as String,
            isInput: true
        )
    }
    
    func getDefaultInputDevice() -> AudioDevice? {
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        
        guard status == noErr else { return nil }
        
        return getDeviceInfo(deviceID)
    }
    
    func setInputDevice(_ device: AudioDevice) {
        // Store the selected device UID in UserDefaults
        UserDefaults.standard.set(device.uid, forKey: "selectedMicrophoneUID")
        NotificationCenter.default.post(name: .microphoneChanged, object: device)
    }
    
    func getSelectedDevice() -> AudioDevice? {
        guard let uid = UserDefaults.standard.string(forKey: "selectedMicrophoneUID") else {
            return getDefaultInputDevice()
        }
        
        return getInputDevices().first { $0.uid == uid } ?? getDefaultInputDevice()
    }
}

extension Notification.Name {
    static let microphoneChanged = Notification.Name("microphoneChanged")
}
