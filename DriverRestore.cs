using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace DriverLoom.Security
{
    // Restore one selected device. Never uninstall a driver, select a null driver or force a restart.
    public static class DriverRestore
    {
        [StructLayout(LayoutKind.Sequential)] struct Device { public uint Size; public Guid Class; public uint DevInst; public IntPtr Reserved; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Driver
        {
            public uint Size, Type; public IntPtr Reserved;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Description, Manufacturer, Provider;
            public System.Runtime.InteropServices.ComTypes.FILETIME Date;
            public ulong Version;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Detail
        {
            public uint Size; public System.Runtime.InteropServices.ComTypes.FILETIME Date;
            public uint Offset, Length; public IntPtr Reserved;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Section;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string Inf;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Description;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=1)] public string HardwareId;
        }
        [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(IntPtr guid,string enumerator,IntPtr parent,uint flags);
        [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiOpenDeviceInfo(IntPtr set,string instance,IntPtr parent,uint flags,ref Device device);
        [DllImport("setupapi.dll",SetLastError=true)] static extern bool SetupDiBuildDriverInfoList(IntPtr set,ref Device device,uint type);
        [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiEnumDriverInfo(IntPtr set,ref Device device,uint type,uint index,ref Driver driver);
        [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiGetDriverInfoDetail(IntPtr set,ref Device device,ref Driver driver,IntPtr detail,uint size,out uint needed);
        [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDriverInfoList(IntPtr set,ref Device device,uint type);
        [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupCopyOEMInf(string inf,string media,uint source,uint flags,StringBuilder destination,uint size,out uint needed,IntPtr component);
        [DllImport("newdev.dll",SetLastError=true)] static extern bool DiInstallDevice(IntPtr parent,IntPtr set,ref Device device,ref Driver driver,uint flags,out bool reboot);

        public static bool Select(string instance,string inf,string version,bool install)
        {
            IntPtr set=SetupDiGetClassDevs(IntPtr.Zero,null,IntPtr.Zero,6);
            if(set==new IntPtr(-1)) throw new Win32Exception();
            Device device=new Device {Size=(uint)Marshal.SizeOf(typeof(Device))}; bool built=false;
            try
            {
                if(!SetupDiOpenDeviceInfo(set,instance,IntPtr.Zero,0,ref device)) throw new Win32Exception();
                if(!SetupDiBuildDriverInfoList(set,ref device,2)) throw new Win32Exception(); built=true;
                Version expected=new Version(version);
                ulong wanted=((ulong)expected.Major<<48)|((ulong)expected.Minor<<32)|((ulong)Math.Max(0,expected.Build)<<16)|(uint)Math.Max(0,expected.Revision);
                for(uint i=0;;i++)
                {
                    Driver driver=new Driver {Size=(uint)Marshal.SizeOf(typeof(Driver))};
                    if(!SetupDiEnumDriverInfo(set,ref device,2,i,ref driver)) {if(Marshal.GetLastWin32Error()==259) break; throw new Win32Exception();}
                    if(driver.Version!=wanted) continue;
                    uint needed; SetupDiGetDriverInfoDetail(set,ref device,ref driver,IntPtr.Zero,0,out needed);
                    if(needed<Marshal.SizeOf(typeof(Detail)) || needed>1048576) continue;
                    IntPtr memory=Marshal.AllocHGlobal((int)needed);
                    try
                    {
                        Marshal.WriteInt32(memory,Marshal.SizeOf(typeof(Detail)));
                        if(!SetupDiGetDriverInfoDetail(set,ref device,ref driver,memory,needed,out needed)) throw new Win32Exception();
                        Detail detail=(Detail)Marshal.PtrToStructure(memory,typeof(Detail));
                        if(!String.Equals(Path.GetFullPath(detail.Inf),Path.GetFullPath(inf),StringComparison.OrdinalIgnoreCase)) continue;
                        if(!install) return false;
                        bool reboot;
                        if(!DiInstallDevice(IntPtr.Zero,set,ref device,ref driver,0,out reboot)) throw new Win32Exception();
                        return reboot;
                    }
                    finally {Marshal.FreeHGlobal(memory);}
                }
                throw new InvalidOperationException("Windows did not offer the selected saved driver as compatible with this device.");
            }
            finally {if(built) SetupDiDestroyDriverInfoList(set,ref device,2); SetupDiDestroyDeviceInfoList(set);}
        }
        public static string Stage(string inf)
        {
            StringBuilder destination=new StringBuilder(260); uint needed;
            if(!SetupCopyOEMInf(inf,Path.GetDirectoryName(inf),1,0,destination,(uint)destination.Capacity,out needed,IntPtr.Zero)) throw new Win32Exception();
            if(!System.Text.RegularExpressions.Regex.IsMatch(destination.ToString(),@"\\oem\d+\.inf$",System.Text.RegularExpressions.RegexOptions.IgnoreCase)) throw new InvalidOperationException("Unexpected staged driver path.");
            return destination.ToString();
        }
    }
}
