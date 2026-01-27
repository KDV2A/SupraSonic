using System.IO;
using System.Linq;
using Windows.Storage;

namespace SupraSonicWin.Models
{
    public class ModelManager
    {
        public static ModelManager Shared { get; } = new ModelManager();

        public bool HasTargetModel()
        {
            // Logic should match TranscriptionManager.getModelDirectoryURL()
            string appSupport = ApplicationData.Current.LocalFolder.Path;
            string baseDir = Path.Combine(appSupport, "models", "huggingface.co", "mlx-community");
            
            // Check for official name
            string targetName = "parakeet-tdt-0.6b-v3-onnx"; 
            string targetPath = Path.Combine(baseDir, targetName);
            
            return Directory.Exists(targetPath);
        }
    }
}
