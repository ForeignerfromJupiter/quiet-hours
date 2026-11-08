using System;
using System.Linq;
using System.Reflection;

namespace QuietHours.Windows
{
    /// The style this .scr shows. Fixed at build time (-p:QHStyle=Chorus → [AssemblyMetadata("QHStyle")]),
    /// like QHStyle in each macOS bundle's Info.plist, so renaming the file can't change it.
    sealed class StyleInfo
    {
        public string Id { get; }          // "chorus": the web page's style id
        public string Name { get; }        // "Chorus"
        public string DarkFinish { get; }  // "Night"
        public string LightFinish { get; } // "Paper"

        StyleInfo(string name, string dark, string light)
        {
            Name = name;
            Id = name.ToLowerInvariant();
            DarkFinish = dark;
            LightFinish = light;
        }

        // Same names as StyleID.finishNames in Sources/Shared/Core/Settings.swift.
        static readonly StyleInfo[] All =
        {
            new StyleInfo("Hinge", "Graphite", "Ivory"),
            new StyleInfo("Chorus", "Night", "Paper"),
            new StyleInfo("Breath", "Graphite", "Paper"),
            new StyleInfo("Lumen", "Night", "Paper"),
            new StyleInfo("Prose", "Night", "Paper"),
            new StyleInfo("Slice", "Night", "Paper"),
            new StyleInfo("Poster", "Night", "Paper"),
            new StyleInfo("Module", "Night", "Paper"),
        };

        public static StyleInfo Current { get; } = Resolve();

        static StyleInfo Resolve()
        {
            var meta = typeof(StyleInfo).Assembly
                .GetCustomAttributes<AssemblyMetadataAttribute>()
                .FirstOrDefault(a => a.Key == "QHStyle");
            var name = meta?.Value ?? "Hinge";
            return All.FirstOrDefault(s => string.Equals(s.Name, name, StringComparison.OrdinalIgnoreCase)) ?? All[0];
        }
    }
}
