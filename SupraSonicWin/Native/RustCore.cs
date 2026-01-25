using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

namespace SupraSonicWin.Native
{
    public class RustCore
    {
        // Delegates for callbacks
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void AudioDataCallback(IntPtr data, uint len);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void AudioLevelCallback(float level);

        // Keep delegates alive to prevent GC
        private AudioDataCallback m_audioCallback;
        private AudioLevelCallback m_levelCallback;

        public event Action<float[]> OnAudioData;
        public event Action<float> OnLevelChanged;

        public void Initialize()
        {
            RustBindings.suprasonic_init();

            m_audioCallback = HandleAudioData;
            m_levelCallback = HandleLevelChanged;

            RustBindings.suprasonic_set_audio_callback(Marshal.GetFunctionPointerForDelegate(m_audioCallback));
            RustBindings.suprasonic_set_level_callback(Marshal.GetFunctionPointerForDelegate(m_levelCallback));
        }

        public void StartRecording()
        {
            int result = RustBindings.suprasonic_start_recording();
            if (result != 0) throw new Exception($"Failed to start recording: {result}");
        }

        public void StopRecording()
        {
            int result = RustBindings.suprasonic_stop_recording();
            if (result != 0) throw new Exception($"Failed to stop recording: {result}");
        }

        private void HandleAudioData(IntPtr data, uint len)
        {
            float[] audioData = new float[len];
            Marshal.Copy(data, audioData, 0, (int)len);
            OnAudioData?.Invoke(audioData);
        }

        private void HandleLevelChanged(float level)
        {
            OnLevelChanged?.Invoke(level);
        }
    }
}
