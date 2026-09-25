using System;
using System.IO;
using System.Runtime.InteropServices;

namespace LotmRussianPatcher
{
    // The modern Explorer folder dialog (IFileOpenDialog + FOS_PICKFOLDERS), the one CPDD opens too.
    public static class FolderPicker
    {
        private const uint FOS_PICKFOLDERS = 0x20;
        private const uint FOS_FORCEFILESYSTEM = 0x40;
        private const uint FOS_PATHMUSTEXIST = 0x800;
        private const uint SIGDN_FILESYSPATH = 0x80058000;
        private const int ERROR_CANCELLED_HR = unchecked((int)0x800704C7);

        [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
        private class FileOpenDialogCom { }

        // IFileDialog vtable up to GetResult (IModalWindow::Show first).
        [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog
        {
            [PreserveSig] int Show(IntPtr parent);
            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(uint fos);
            void GetOptions(out uint pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
        }

        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(uint sigdnName, out IntPtr ppszName);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem ppv);

        // Returns the chosen folder or null when cancelled. Must run on an STA thread.
        public static string Pick(IntPtr owner, string title, string initialDir)
        {
            IFileDialog dialog = (IFileDialog)new FileOpenDialogCom();
            try
            {
                uint options;
                dialog.GetOptions(out options);
                dialog.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
                dialog.SetTitle(title);
                dialog.SetOkButtonLabel("Выбрать папку");

                string start = ExistingParent(initialDir) ?? @"C:\";
                try
                {
                    IShellItem folder;
                    SHCreateItemFromParsingName(start, IntPtr.Zero, typeof(IShellItem).GUID, out folder);
                    dialog.SetFolder(folder);
                }
                catch { }

                int hr = dialog.Show(owner);
                if (hr == ERROR_CANCELLED_HR) return null;
                if (hr != 0) Marshal.ThrowExceptionForHR(hr);

                IShellItem result;
                dialog.GetResult(out result);
                IntPtr namePtr;
                result.GetDisplayName(SIGDN_FILESYSPATH, out namePtr);
                try { return Marshal.PtrToStringUni(namePtr); }
                finally { Marshal.FreeCoTaskMem(namePtr); }
            }
            finally
            {
                Marshal.ReleaseComObject(dialog);
            }
        }

        private static string ExistingParent(string path)
        {
            try
            {
                while (!string.IsNullOrEmpty(path) && !Directory.Exists(path)) path = Path.GetDirectoryName(path);
                return string.IsNullOrEmpty(path) ? null : path;
            }
            catch { return null; }
        }
    }
}
