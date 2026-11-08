using System;
using System.IO;
using System.Reflection;

namespace QuietHours.Windows
{
    /// Loads Microsoft.Web.WebView2.Core.dll from the .scr's own resources, so the .scr is a single
    /// file (Windows lists screen savers from C:\Windows\System32, and nothing else belongs there).
    /// This class must not mention any WebView2 type.
    static class EmbeddedAssemblies
    {
        const string CoreName = "Microsoft.Web.WebView2.Core";
        static Assembly core;

        public static void Install() => AppDomain.CurrentDomain.AssemblyResolve += Resolve;

        static Assembly Resolve(object sender, ResolveEventArgs args)
        {
            if (new AssemblyName(args.Name).Name != CoreName) return null;
            if (core != null) return core;
            using (var stream = typeof(EmbeddedAssemblies).Assembly.GetManifestResourceStream("lib/" + CoreName + ".dll"))
            {
                if (stream == null) return null;
                using (var buffer = new MemoryStream())
                {
                    stream.CopyTo(buffer);
                    return core = Assembly.Load(buffer.ToArray());
                }
            }
        }
    }
}
