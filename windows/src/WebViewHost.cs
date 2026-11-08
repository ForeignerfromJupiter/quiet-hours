using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;

namespace QuietHours.Windows
{
    /// WebView2 plumbing shared by every window: the native loader, one environment per process,
    /// and the page served from embedded resources.
    static class WebViewHost
    {
        /// The page's origin. Never resolved over the network: every request is answered from
        /// memory (`.example` is reserved, so it can't collide with a real host).
        public const string Origin = "https://quiethours.example/";

        static Task<CoreWebView2Environment> environment;
        static Dictionary<string, byte[]> files;

        /// Extract WebView2Loader.dll for this process's architecture to
        /// %LOCALAPPDATA%\Quiet Hours\bin\<version>\<arch>\ and point WebView2 at it.
        public static void PrepareLoader()
        {
            try
            {
                string arch = ProcessArchitecture();
                var asm = typeof(WebViewHost).Assembly;
                using (var src = asm.GetManifestResourceStream($"native/{arch}/WebView2Loader.dll"))
                {
                    if (src == null) throw new InvalidOperationException("No embedded WebView2Loader.dll for " + arch);
                    string version = asm.GetName().Version + "-" + src.Length;
                    string dir = Path.Combine(Log.Folder, "bin", version, arch);
                    string dll = Path.Combine(dir, "WebView2Loader.dll");
                    if (!File.Exists(dll) || new FileInfo(dll).Length != src.Length)
                    {
                        Directory.CreateDirectory(dir);
                        string tmp = dll + "." + Guid.NewGuid().ToString("N") + ".tmp";
                        using (var dst = File.Create(tmp)) src.CopyTo(dst);
                        try { File.Copy(tmp, dll, true); }
                        catch (IOException) { /* another saver process wrote it first */ }
                        finally { File.Delete(tmp); }
                    }
                    CoreWebView2Environment.SetLoaderDllFolderPath(dir);
                }
            }
            catch (Exception e)
            {
                Log.Error("PrepareLoader", e);
            }
        }

        static string ProcessArchitecture()
        {
            // WOW64 and ARM64 emulation both report the process's own architecture here.
            switch ((System.Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") ?? "").ToUpperInvariant())
            {
                case "ARM64": return "arm64";
                case "X86": return "x86";
                case "AMD64": return "x64";
                default: return System.Environment.Is64BitProcess ? "x64" : "x86";
            }
        }

        /// Installed Evergreen runtime version, or null when WebView2 is missing.
        public static string RuntimeVersion()
        {
            try { return CoreWebView2Environment.GetAvailableBrowserVersionString(); }
            catch (Exception) { return null; }
        }

        public static Task<CoreWebView2Environment> Environment() =>
            environment ??= CoreWebView2Environment.CreateAsync(null, Path.Combine(Log.Folder, "WebView2"), null);

        /// Serve the page from embedded resources and refuse everything else: the saver never
        /// touches the network.
        public static void ServePage(CoreWebView2 core, CoreWebView2Environment env)
        {
            files ??= LoadFiles();
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (sender, e) =>
            {
                var uri = new Uri(e.Request.Uri);
                string path = Uri.UnescapeDataString(uri.AbsolutePath).TrimStart('/');
                if (path.Length == 0) path = "index.html";
                if (uri.Host == new Uri(Origin).Host && files.TryGetValue(path, out byte[] body))
                {
                    e.Response = env.CreateWebResourceResponse(
                        new MemoryStream(body, false), 200, "OK",
                        "Content-Type: " + ContentType(path) + "\r\nCache-Control: no-store");
                }
                else
                {
                    e.Response = env.CreateWebResourceResponse(null, 404, "Not Found", "");
                }
            };
        }

        static Dictionary<string, byte[]> LoadFiles()
        {
            var map = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
            var asm = Assembly.GetExecutingAssembly();
            foreach (string name in asm.GetManifestResourceNames())
            {
                string n = name.Replace('\\', '/');
                if (!n.StartsWith("web/", StringComparison.Ordinal)) continue;
                using (var s = asm.GetManifestResourceStream(name))
                using (var m = new MemoryStream())
                {
                    s.CopyTo(m);
                    map[n.Substring(4)] = m.ToArray();
                }
            }
            return map;
        }

        static string ContentType(string path)
        {
            switch (Path.GetExtension(path).ToLowerInvariant())
            {
                case ".html": return "text/html; charset=utf-8";
                case ".js": return "text/javascript; charset=utf-8";
                case ".css": return "text/css; charset=utf-8";
                case ".ttf": return "font/ttf";
                default: return "application/octet-stream";
            }
        }
    }
}
