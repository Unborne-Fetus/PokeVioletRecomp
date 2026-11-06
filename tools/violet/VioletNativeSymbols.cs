// DbgHelp symbol resolution for the exact build/violet-gnu/lasrecomp.exe and its matching PDB.
// Runs locally; no game data, PDB, crash dump, or private paths are uploaded.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class VioletNativeSymbols
{
    [DllImport("dbghelp.dll", EntryPoint = "SymSetOptions", SetLastError = true)]
    private static extern uint SymSetOptions(uint options);

    [DllImport("dbghelp.dll", EntryPoint = "SymInitializeW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SymInitialize(IntPtr process, string path, [MarshalAs(UnmanagedType.Bool)] bool invade);

    [DllImport("dbghelp.dll", EntryPoint = "SymLoadModuleExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ulong SymLoadModuleEx(IntPtr process, IntPtr file, string image, string name,
                                                 ulong baseAddress, uint size, IntPtr data, uint flags);

    [DllImport("dbghelp.dll", EntryPoint = "SymFromAddr", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SymFromAddr(IntPtr process, ulong address, out ulong displacement, IntPtr symbol);

    [StructLayout(LayoutKind.Sequential)]
    private struct ImagehlpLine64 {
        public uint SizeOfStruct;
        public IntPtr Key;
        public uint LineNumber;
        public IntPtr FileName;
        public ulong Address;
    }

    [DllImport("dbghelp.dll", EntryPoint = "SymGetLineFromAddr64", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SymGetLineFromAddr64(IntPtr process, ulong address,
                                                     out uint displacement, ref ImagehlpLine64 line);

    [DllImport("dbghelp.dll", EntryPoint = "SymCleanup", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SymCleanup(IntPtr process);

    public static string[] Resolve(string imagePath, ulong[] rvas)
    {
        if (!File.Exists(imagePath)) throw new FileNotFoundException("Native executable not found", imagePath);
        string folder = Path.GetDirectoryName(Path.GetFullPath(imagePath));
        // This build's lld linker normally places lasrecomp.pdb under build/violet-gnu/link/,
        // not alongside the final lasrecomp.exe. Search both, without moving or modifying PDBs.
        string symbolPath = folder + ";" + Path.Combine(folder, "link");
        IntPtr proc = Process.GetCurrentProcess().Handle;
        SymSetOptions(0x2 | 0x4 | 0x10 | 0x200); // UNDNAME, DEFERRED_LOADS, LOAD_LINES, FAIL_CRITICAL_ERRORS
        if (!SymInitialize(proc, symbolPath, false))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "DbgHelp could not initialize");
        const ulong imageBase = 0x180000000UL;
        var output = new List<string>();
        IntPtr symbol = IntPtr.Zero;
        try
        {
            ulong loaded = SymLoadModuleEx(proc, IntPtr.Zero, Path.GetFullPath(imagePath), null,
                                            imageBase, 0, IntPtr.Zero, 0);
            if (loaded == 0)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "DbgHelp could not load EXE/PDB");
            // SYMBOL_INFO on x64: struct sizeof 88; MaxNameLen offset 80; Name offset 84.
            symbol = Marshal.AllocHGlobal(4096);
            for (int i = 0; i < rvas.Length; ++i)
            {
                ulong rva = rvas[i];
                ulong displacement = 0;
                string name = "(no matching public/private PDB symbol)";
                string source = "";
                for (int k = 0; k < 4096; k++) Marshal.WriteByte(symbol, k, 0);
                Marshal.WriteInt32(symbol, 0, 88);
                Marshal.WriteInt32(symbol, 80, 1000);
                if (SymFromAddr(proc, loaded + rva, out displacement, symbol))
                {
                    int nameLength = Marshal.ReadInt32(symbol, 76);
                    if (nameLength > 0 && nameLength < 1000)
                    {
                        name = Marshal.PtrToStringAnsi(IntPtr.Add(symbol, 84), nameLength);
                        name += String.Format(" +0x{0:x}", displacement);
                    }
                }
                var line = new ImagehlpLine64();
                line.SizeOfStruct = (uint)Marshal.SizeOf(typeof(ImagehlpLine64));
                uint lineOffset;
                if (SymGetLineFromAddr64(proc, loaded + rva, out lineOffset, ref line) && line.FileName != IntPtr.Zero)
                    source = String.Format(" ({0}:{1})", Marshal.PtrToStringAnsi(line.FileName), line.LineNumber);
                output.Add(String.Format("lasrecomp.exe+0x{0:x} -> {1}{2}", rva, name, source));
            }
        }
        finally
        {
            if (symbol != IntPtr.Zero) Marshal.FreeHGlobal(symbol);
            SymCleanup(proc);
        }
        return output.ToArray();
    }
}
