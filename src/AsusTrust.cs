using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;

namespace DriverLoom.Security
{
    public sealed class InfFacts
    {
        public string Version, Catalog, DeviceClass;
        public string[] Ids;
    }
    public static class AsusTrust
    {
        [StructLayout(LayoutKind.Sequential)] struct InfContext { public IntPtr Inf, CurrentInf; public uint Section, Line; }
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SetupOpenInfFile(string file, string infClass, uint style, IntPtr errorLine);
        [DllImport("setupapi.dll")] static extern void SetupCloseInfFile(IntPtr inf);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode)] static extern bool SetupFindFirstLine(IntPtr inf, string section, string key, out InfContext context);
        [DllImport("setupapi.dll")] static extern bool SetupFindNextLine(ref InfContext context, out InfContext next);
        [DllImport("setupapi.dll")] static extern uint SetupGetFieldCount(ref InfContext context);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode)] static extern bool SetupGetStringField(ref InfContext context, uint index, StringBuilder value, uint size, out uint needed);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode)] static extern bool SetupDiGetActualModelsSection(ref InfContext context, IntPtr platform, StringBuilder section, uint size, out uint needed, IntPtr reserved);
        static string Field(ref InfContext context, uint index)
        {
            uint needed; StringBuilder value = new StringBuilder(4096);
            return SetupGetStringField(ref context, index, value, (uint)value.Capacity, out needed) ? value.ToString() : "";
        }
        static bool Next(ref InfContext context)
        {
            InfContext next; if (!SetupFindNextLine(ref context, out next)) return false;
            context=next; return true;
        }
        static string Value(IntPtr inf, string key, uint field)
        {
            InfContext context;
            return SetupFindFirstLine(inf, "Version", key, out context) ? Field(ref context, field) : "";
        }
        public static InfFacts ReadInf(string path)
        {
            IntPtr inf = SetupOpenInfFile(path, null, 2, IntPtr.Zero);
            if (inf == new IntPtr(-1)) throw new InvalidDataException("Windows could not read the driver INF.");
            try
            {
                string catalog = Value(inf, "CatalogFile.NTamd64", 1);
                if (catalog.Length == 0) catalog = Value(inf, "CatalogFile.NT", 1);
                if (catalog.Length == 0) catalog = Value(inf, "CatalogFile", 1);
                HashSet<string> ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                InfContext manufacturer;
                if (SetupFindFirstLine(inf, "Manufacturer", null, out manufacturer))
                {
                    do
                    {
                        uint needed; StringBuilder section = new StringBuilder(4096);
                        if (!SetupDiGetActualModelsSection(ref manufacturer, IntPtr.Zero, section, (uint)section.Capacity, out needed, IntPtr.Zero) || section.ToString().IndexOf(".NTamd64", StringComparison.OrdinalIgnoreCase) < 0) continue;
                        InfContext model;
                        if (!SetupFindFirstLine(inf, section.ToString(), null, out model)) continue;
                        do { uint count = SetupGetFieldCount(ref model); for (uint i = 2; i <= count; i++) { string id = Field(ref model, i); if (id.Length > 0) ids.Add(id); } }
                        while (Next(ref model));
                    } while (Next(ref manufacturer));
                }
                string[] values = new string[ids.Count]; ids.CopyTo(values);
                return new InfFacts { Version=Value(inf,"DriverVer",2), Catalog=catalog, DeviceClass=Value(inf,"Class",1), Ids=values };
            }
            finally { SetupCloseInfFile(inf); }
        }

        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct CatalogInfo
        {
            public uint Size, Version;
            [MarshalAs(UnmanagedType.LPWStr)] public string Catalog, MemberTag, MemberFile;
            public IntPtr File, Hash;
            public uint HashSize;
            public IntPtr Context, Admin;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TrustData
        {
            public uint Size; public IntPtr Policy, Sip; public uint UI, Revocation, Choice;
            public IntPtr Subject; public uint StateAction; public IntPtr State, URL;
            public uint Flags, UIContext; public IntPtr Signature;
        }
        [DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CryptCATAdminAcquireContext2(out IntPtr admin, IntPtr subsystem, string algorithm, IntPtr policy, uint flags);
        [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr admin, IntPtr file, ref uint size, byte[] hash, uint flags);
        [DllImport("wintrust.dll")] static extern bool CryptCATAdminReleaseContext(IntPtr admin, uint flags);
        [DllImport("wintrust.dll")] static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr admin, byte[] hash, uint size, uint flags, IntPtr previous);
        [DllImport("wintrust.dll")] static extern bool CryptCATAdminReleaseCatalogContext(IntPtr admin, IntPtr catalog, uint flags);
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct InstalledCatalog { public uint Size; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string Path; }
        [DllImport("wintrust.dll", CharSet=CharSet.Unicode)] static extern bool CryptCATCatalogInfoFromContext(IntPtr catalog, ref InstalledCatalog info, uint flags);
        [DllImport("wintrust.dll", ExactSpelling=true)] static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);
        static bool VerifyMember(string file, string catalog, string algorithm)
        {
            IntPtr admin = IntPtr.Zero, hashMemory = IntPtr.Zero, catalogMemory = IntPtr.Zero;
            TrustData data = new TrustData(); Guid action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
            try
            {
                if (!CryptCATAdminAcquireContext2(out admin, IntPtr.Zero, algorithm, IntPtr.Zero, 0)) return false;
                using (FileStream stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    uint size = 0; IntPtr handle = stream.SafeFileHandle.DangerousGetHandle();
                    if (!CryptCATAdminCalcHashFromFileHandle2(admin, handle, ref size, null, 0) || size == 0 || size > 64) return false;
                    byte[] hash = new byte[size];
                    if (!CryptCATAdminCalcHashFromFileHandle2(admin, handle, ref size, hash, 0)) return false;
                    hashMemory = Marshal.AllocHGlobal((int)size); Marshal.Copy(hash, 0, hashMemory, (int)size);
                    CatalogInfo info = new CatalogInfo { Size=(uint)Marshal.SizeOf(typeof(CatalogInfo)), Catalog=catalog, MemberTag=BitConverter.ToString(hash).Replace("-",""), MemberFile=file, File=handle, Hash=hashMemory, HashSize=size, Admin=admin };
                    catalogMemory = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(CatalogInfo))); Marshal.StructureToPtr(info, catalogMemory, false);
                    data.Size=(uint)Marshal.SizeOf(typeof(TrustData)); data.UI=2; data.Choice=2; data.Subject=catalogMemory; data.StateAction=1;
                    // Windows validates the catalog trust and file membership. No catalog is installed.
                    return WinVerifyTrust(new IntPtr(-1), ref action, ref data) == 0;
                }
            }
            finally
            {
                if (data.State != IntPtr.Zero) { data.StateAction=2; WinVerifyTrust(new IntPtr(-1), ref action, ref data); }
                if (catalogMemory != IntPtr.Zero) { Marshal.DestroyStructure(catalogMemory, typeof(CatalogInfo)); Marshal.FreeHGlobal(catalogMemory); }
                if (hashMemory != IntPtr.Zero) Marshal.FreeHGlobal(hashMemory);
                if (admin != IntPtr.Zero) CryptCATAdminReleaseContext(admin, 0);
            }
        }
        public static bool VerifyCatalogMember(string file, string catalog)
        {
            return VerifyMember(file, catalog, "SHA256") || VerifyMember(file, catalog, "SHA1");
        }
        public static string FindInstalledCatalog(string file)
        {
            foreach(string algorithm in new string[]{"SHA256","SHA1"})
            {
                IntPtr admin=IntPtr.Zero, catalog=IntPtr.Zero;
                try
                {
                    if(!CryptCATAdminAcquireContext2(out admin,IntPtr.Zero,algorithm,IntPtr.Zero,0)) continue;
                    using(FileStream stream=File.OpenRead(file))
                    {
                        uint size=0; IntPtr handle=stream.SafeFileHandle.DangerousGetHandle();
                        if(!CryptCATAdminCalcHashFromFileHandle2(admin,handle,ref size,null,0) || size==0 || size>64) continue;
                        byte[] hash=new byte[size]; if(!CryptCATAdminCalcHashFromFileHandle2(admin,handle,ref size,hash,0)) continue;
                        catalog=CryptCATAdminEnumCatalogFromHash(admin,hash,size,0,IntPtr.Zero);
                        if(catalog==IntPtr.Zero) continue;
                        InstalledCatalog info=new InstalledCatalog {Size=(uint)Marshal.SizeOf(typeof(InstalledCatalog))};
                        if(CryptCATCatalogInfoFromContext(catalog,ref info,0)) return info.Path;
                    }
                }
                finally {if(catalog!=IntPtr.Zero) CryptCATAdminReleaseCatalogContext(admin,catalog,0); if(admin!=IntPtr.Zero) CryptCATAdminReleaseContext(admin,0);}
            }
            return "";
        }
        public static string[] Files(string root)
        {
            root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
            Queue<string> pending=new Queue<string>(); List<string> files=new List<string>(); pending.Enqueue(root); int directories=0;
            while (pending.Count > 0)
            {
                string dir=pending.Dequeue();
                if (++directories > 10000 || (File.GetAttributes(dir) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Unsafe package directory.");
                foreach (string child in Directory.GetDirectories(dir)) pending.Enqueue(child);
                foreach (string file in Directory.GetFiles(dir))
                {
                    if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0 || files.Count >= 10000) throw new InvalidDataException("Unsafe package file.");
                    files.Add(file.Substring(root.Length));
                }
            }
            files.Sort(StringComparer.OrdinalIgnoreCase); return files.ToArray();
        }
        public static string[] HashFiles(string root, string[] files)
        {
            root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
            string[] hashes=new string[files.Length]; long total=0;
            using (SHA256 sha=SHA256.Create()) for(int i=0;i<files.Length;i++)
            {
                string path=Path.GetFullPath(Path.Combine(root,files[i]));
                if (!path.StartsWith(root,StringComparison.OrdinalIgnoreCase) || (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new InvalidDataException("Unsafe package path.");
                total+=new FileInfo(path).Length; if(total>2147483648L) throw new InvalidDataException("Package is too large.");
                using(FileStream stream=File.OpenRead(path)) hashes[i]=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
            }
            return hashes;
        }
    }
}
