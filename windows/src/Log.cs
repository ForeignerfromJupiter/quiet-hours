using System;
using System.IO;

namespace QuietHours.Windows
{
    /// A screen saver has no console. Problems go to %LOCALAPPDATA%\Quiet Hours\quiethours.log
    /// (trimmed when it passes 256 KB).
    static class Log
    {
        public static string Folder { get; } =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Quiet Hours");

        static string FilePath => Path.Combine(Folder, "quiethours.log");

        public static void Info(string message) => Write("info", message);

        public static void Error(string where, Exception e) => Write("error", where + ": " + e);

        static void Write(string level, string message)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                var info = new FileInfo(FilePath);
                if (info.Exists && info.Length > 256 * 1024) info.Delete();
                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {message}{Environment.NewLine}");
            }
            catch
            {
                // Logging must never take the saver down.
            }
        }
    }
}
