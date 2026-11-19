using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class DriverLoomSetupBridge
{
    [StructLayout(LayoutKind.Sequential)] struct UniqueProcess
    {
        public uint ProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME StartTime;
    }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint session, int flags, StringBuilder key);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint session, uint files, string[] names, uint applications, UniqueProcess[] processes, uint services, string[] serviceNames);
    [DllImport("rstrtmgr.dll")] static extern int RmShutdown(uint session, uint flags, IntPtr callback);
    [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint session);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    public static string InstallerPath(string root)
    {
        if (String.IsNullOrWhiteSpace(root) || !Path.IsPathRooted(root)) throw new ArgumentException("An absolute installation directory is required.");
        string full = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        if (full.Length <= Path.GetPathRoot(full).TrimEnd(Path.DirectorySeparatorChar).Length) throw new ArgumentException("The installation directory cannot be a drive root.");
        return Path.Combine(full, "DriverLoom.exe");
    }
    public static bool IsDriverInstallCommand(string command)
    {
        if (String.IsNullOrWhiteSpace(command)) return true; // An inaccessible elevated PowerShell must be closed manually before a legacy upgrade.
        Match encoded = Regex.Match(command, @"(?:^|\s)-(?:EncodedCommand|enc)\s+([A-Za-z0-9+/=]+)", RegexOptions.IgnoreCase);
        if (encoded.Success)
        {
            try { command = Encoding.Unicode.GetString(Convert.FromBase64String(encoded.Groups[1].Value)); }
            catch { return true; }
        }
        return command.IndexOf("Install-DriverOffers", StringComparison.OrdinalIgnoreCase) >= 0;
    }
    static bool MutexExists(string name)
    {
        Mutex mutex;
        if (!Mutex.TryOpenExisting(name, out mutex)) return false;
        mutex.Dispose(); return true;
    }
    static bool IsCurrentUser(Process process)
    {
        IntPtr token;
        if (!OpenProcessToken(process.Handle, 8, out token)) return false;
        try { using (WindowsIdentity identity = new WindowsIdentity(token)) using (WindowsIdentity current = WindowsIdentity.GetCurrent()) return identity.User == current.User; }
        finally { CloseHandle(token); }
    }
    static bool LegacyDriverInstallationIsActive(int session)
    {
        using (ManagementObjectSearcher search = new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE SessionId=" + session + " AND (Name='powershell.exe' OR Name='pwsh.exe')"))
        using (ManagementObjectCollection results = search.Get())
            foreach (ManagementObject process in results)
                using (process) if (IsDriverInstallCommand(Convert.ToString(process["CommandLine"]))) return true;
        return false;
    }
    static bool AllExited(List<Process> processes, int timeout)
    {
        Stopwatch watch = Stopwatch.StartNew();
        foreach (Process process in processes)
        {
            int remaining = Math.Max(0, timeout - (int)watch.ElapsedMilliseconds);
            if (!process.WaitForExit(remaining)) return false;
        }
        return true;
    }
    static int CloseApps(string root, bool close)
    {
        string target = InstallerPath(root);
        int session = Process.GetCurrentProcess().SessionId;
        List<Process> matches = new List<Process>();
        try
        {
            if (MutexExists(@"Local\DriverLoom.DriverInstall")) return 2;
            foreach (Process process in Process.GetProcessesByName("DriverLoom"))
            {
                bool keep = false;
                try
                {
                    if (!String.Equals(process.MainModule.FileName, target, StringComparison.OrdinalIgnoreCase)) continue;
                    if (process.SessionId != session || !IsCurrentUser(process)) return 3;
                    matches.Add(process); keep = true;
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception) { if (process.SessionId == session) return 3; }
                finally { if (!keep) process.Dispose(); }
            }
            if (matches.Count == 0) return MutexExists(@"Local\HardwareUpdateLauncher") ? 3 : 0;
            if (!close) return 1;
            EventWaitHandle exit;
            try
            {
                exit = EventWaitHandle.OpenExisting(@"Local\DriverLoom.ExitForSetup");
                using (exit) exit.Set();
                // The app can refuse while installing drivers or while settings need attention. Never force it.
                return AllExited(matches, 12000) ? 0 : 2;
            }
            catch (WaitHandleCannotBeOpenedException) { }
            // Older versions have no setup-exit event. Restart Manager also closes tray-mode windows.
            if (LegacyDriverInstallationIsActive(session)) return 2;
            UniqueProcess[] registrations = new UniqueProcess[matches.Count];
            for (int i = 0; i < matches.Count; i++)
            {
                long start = matches[i].StartTime.ToFileTimeUtc();
                registrations[i].ProcessId = (uint)matches[i].Id;
                registrations[i].StartTime.dwLowDateTime = (int)(start & 0xffffffff);
                registrations[i].StartTime.dwHighDateTime = (int)(start >> 32);
            }
            uint manager;
            if (RmStartSession(out manager, 0, new StringBuilder(33)) != 0) return 3;
            try
            {
                if (RmRegisterResources(manager, 0, null, (uint)registrations.Length, registrations, 0, null) != 0) return 3;
                if (RmShutdown(manager, 0, IntPtr.Zero) != 0) return 3;
                return AllExited(matches, 10000) ? 0 : 3;
            }
            finally { RmEndSession(manager); }
        }
        finally { foreach (Process process in matches) process.Dispose(); }
    }
    [STAThread] public static int Main(string[] args)
    {
        try
        {
            if (args.Length != 2 || (args[0] != "--close" && args[0] != "--probe")) return 3;
            return CloseApps(args[1], args[0] == "--close");
        }
        catch { return 3; }
    }
}
