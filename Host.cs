using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Threading;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("DriverLoom")]
[assembly: System.Reflection.AssemblyProduct("DriverLoom")]
[assembly: System.Reflection.AssemblyVersion("0.1.8.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.1.8.0")]

namespace DriverLoom
{
    public static class ShellIdentity
    {
        public const string AppId = "SJB.DriverLoom";
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("shell32.dll")] static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr id);
        public static void Set() { Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppId)); }
        public static string CurrentId() { IntPtr p; Marshal.ThrowExceptionForHR(GetCurrentProcessExplicitAppUserModelID(out p)); try { return Marshal.PtrToStringUni(p); } finally { Marshal.FreeCoTaskMem(p); } }
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLink { }
        [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid Format; public uint Id; }
        [StructLayout(LayoutKind.Explicit, Size = 24)] struct Variant
        {
            [FieldOffset(0)] public ushort Type;
            [FieldOffset(8)] public IntPtr Text;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPropertyStore
        {
            void GetCount(out uint count); void GetAt(uint index, out PropertyKey key); void GetValue(ref PropertyKey key, out Variant value);
            void SetValue(ref PropertyKey key, ref Variant value); void Commit();
        }
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref Variant value);
        [DllImport("shell32.dll", PreserveSig = false)] static extern void SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern void SHChangeNotify(uint change, uint flags, string item, IntPtr second);
        static PropertyKey Key(uint id) { return new PropertyKey { Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id = id }; }
        static void Write(IPropertyStore store, uint id, string text)
        {
            PropertyKey key = Key(id); Variant value = new Variant { Type = 31, Text = Marshal.StringToCoTaskMemUni(text) };
            try { store.SetValue(ref key, ref value); } finally { PropVariantClear(ref value); }
        }
        public static void BindWindow(IntPtr window)
        {
            IPropertyStore store; Guid iid = typeof(IPropertyStore).GUID; SHGetPropertyStoreForWindow(window, ref iid, out store);
            try
            {
                string root = AppDomain.CurrentDomain.BaseDirectory;
                Write(store, 2, "\"" + Path.Combine(root, "DriverLoom.exe") + "\"");
                Write(store, 3, Path.Combine(root, "assets", "DriverLoom-loops.ico") + ",0");
                Write(store, 4, "DriverLoom");
                Write(store, 5, AppId);
                store.Commit();
            }
            finally { Marshal.FinalReleaseComObject(store); }
        }
        public static string WindowProperty(IntPtr window, uint id)
        {
            IPropertyStore store; Guid iid = typeof(IPropertyStore).GUID; SHGetPropertyStoreForWindow(window, ref iid, out store);
            PropertyKey key = Key(id); Variant value = new Variant();
            try { store.GetValue(ref key, out value); return value.Type == 31 ? Marshal.PtrToStringUni(value.Text) : ""; }
            finally { PropVariantClear(ref value); Marshal.FinalReleaseComObject(store); }
        }
        public static string ShortcutId(string path, bool write)
        {
            object link = new ShellLink();
            try
            {
                ((IPersistFile)link).Load(path, write ? 2 : 0);
                IPropertyStore store = (IPropertyStore)link;
                PropertyKey key = new PropertyKey { Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id = 5 };
                Variant value = new Variant();
                try
                {
                    if (write) { value.Type = 31; value.Text = Marshal.StringToCoTaskMemUni(AppId); store.SetValue(ref key, ref value); store.Commit(); ((IPersistFile)link).Save(path, true); SHChangeNotify(0x2000, 0x1005, path, IntPtr.Zero); return AppId; }
                    store.GetValue(ref key, out value); return value.Type == 31 ? Marshal.PtrToStringUni(value.Text) : "";
                }
                finally { PropVariantClear(ref value); }
            }
            finally { Marshal.FinalReleaseComObject(link); }
        }
    }
    sealed class AppHost : PSHost
    {
        readonly Guid id = Guid.NewGuid(); readonly QuietUI ui = new QuietUI();
        public int ExitCode;
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "DriverLoom"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override PSHostUserInterface UI { get { return ui; } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.CurrentUICulture; } }
        public override void SetShouldExit(int code) { ExitCode = code; }
        public override void EnterNestedPrompt() { throw new NotSupportedException(); }
        public override void ExitNestedPrompt() { throw new NotSupportedException(); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
    sealed class QuietUI : PSHostUserInterface
    {
        public override PSHostRawUserInterface RawUI { get { return null; } }
        public override string ReadLine() { throw new NotSupportedException(); }
        public override System.Security.SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
        public override void Write(string value) { Console.Error.Write(value); }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) { Write(value); }
        public override void WriteLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteErrorLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteDebugLine(string value) { }
        public override void WriteVerboseLine(string value) { }
        public override void WriteWarningLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { throw new NotSupportedException(); }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException(); }
    }
    static class Program
    {
        [STAThread] static int Main(string[] args)
        {
            try { Console.OutputEncoding = new System.Text.UTF8Encoding(false); } catch { }
            bool smoke = Array.IndexOf(args, "-SmokeTest") >= 0;
            try
            {
                if (!Environment.Is64BitProcess) throw new InvalidOperationException("DriverLoom requires Windows x64.");
                ShellIdentity.Set();
                if (args.Length == 2 && (args[0] == "--shortcut-id" || args[0] == "--read-shortcut-id"))
                { Console.WriteLine(ShellIdentity.ShortcutId(args[1], args[0] == "--shortcut-id")); return 0; }
                AppHost host = new AppHost();
                InitialSessionState initial = InitialSessionState.CreateDefault();
                initial.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                using (Runspace runspace = RunspaceFactory.CreateRunspace(host, initial))
                {
                    runspace.ApartmentState = ApartmentState.STA; runspace.ThreadOptions = PSThreadOptions.UseCurrentThread; runspace.Open();
                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = runspace;
                        if (smoke)
                        {
                            ps.AddScript("$job=Start-Job { $PSVersionTable.PSEdition + '|' + [Environment]::Is64BitProcess }; try { $null=Wait-Job $job -Timeout 10; if($job.State -ne 'Completed'){throw 'Background job failed.'}; Receive-Job $job -ErrorAction Stop } finally { Remove-Job $job -Force }");
                            Collection<PSObject> probe = ps.Invoke();
                            if (ps.HadErrors || probe.Count != 1 || probe[0].ToString() != "Desktop|True") throw new InvalidOperationException("Native host could not run a 64-bit Windows PowerShell background job.");
                            ps.Commands.Clear();
                        }
                        ps.AddCommand(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Launch.ps1")).AddParameter("SmokeTest", smoke);
                        foreach (PSObject result in ps.Invoke()) Console.WriteLine(result == null ? "" : result.ToString());
                        if (ps.HadErrors && host.ExitCode == 0) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    }
                }
                return host.ExitCode;
            }
            catch (Exception error)
            {
                try { string local = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); string folder = Path.Combine(local, "HardwareUpdateLauncher"); Directory.CreateDirectory(folder); File.WriteAllText(Path.Combine(folder, "host-error.log"), error.ToString()); } catch { }
                if (smoke) Console.Error.WriteLine(error.ToString());
                else MessageBox.Show("DriverLoom could not start.\r\n\r\n" + error.Message, "DriverLoom", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
