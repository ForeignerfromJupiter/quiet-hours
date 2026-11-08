using System;
using QuietHours.Windows;
using Xunit;

public class LaunchArgsTests
{
    [Theory]
    [InlineData(new string[0], "Configure", 0)]
    [InlineData(new[] { "/s" }, "FullScreen", 0)]
    [InlineData(new[] { "/S" }, "FullScreen", 0)]
    [InlineData(new[] { "-s" }, "FullScreen", 0)]
    [InlineData(new[] { "/p", "4242" }, "Preview", 4242)]
    [InlineData(new[] { "/P:4242" }, "Preview", 4242)]
    [InlineData(new[] { "/c:1234" }, "Configure", 1234)]
    [InlineData(new[] { "/c" }, "Configure", 0)]
    [InlineData(new[] { "/w" }, "Window", 0)]
    [InlineData(new[] { "/a", "99" }, "Configure", 99)]
    public void Parses(string[] args, string mode, long hwnd)
    {
        var a = LaunchArgs.Parse(args);
        Assert.Equal(mode, a.Mode.ToString());
        Assert.Equal(new IntPtr(hwnd), a.Window);
    }

    [Fact]
    public void IgnoresGarbageWindowHandle()
    {
        var a = LaunchArgs.Parse(new[] { "/p", "nope" });
        Assert.Equal(LaunchMode.Preview, a.Mode);
        Assert.Equal(IntPtr.Zero, a.Window);
    }
}

public class TimeFormatTests
{
    [Theory]
    [InlineData("HH:mm", true)]        // en-GB, de-DE
    [InlineData("H:mm", true)]         // fi-FI
    [InlineData("h:mm tt", false)]     // en-US
    [InlineData("tt h:mm", false)]     // ko-KR
    [InlineData("HH 'h' mm", true)]    // fr-CA style literal
    [InlineData("h 'H' mm tt", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void DetectsTwentyFourHour(string pattern, bool expected) =>
        Assert.Equal(expected, TimeFormat.IsTwentyFourHour(pattern));
}
