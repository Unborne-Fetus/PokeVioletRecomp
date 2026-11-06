// Convenience launcher for Violet Recomp. No game files or private data.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#include <stdio.h>

static void show_error(const wchar_t *message, DWORD code) {
    wchar_t details[1024];
    if (code) {
        swprintf(details, 1024, L"%ls\n\nWindows error: %lu\n\nExtract the entire release ZIP before running.", message, (unsigned long)code);
    } else {
        swprintf(details, 1024, L"%ls\n\nExtract the entire release ZIP before running.", message);
    }
    MessageBoxW(NULL, details, L"Pokémon Violet Recomp", MB_OK | MB_ICONERROR);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE prev, PWSTR args, int show) {
    (void)instance; (void)prev; (void)args; (void)show;
    wchar_t folder[32768];
    DWORD length = GetModuleFileNameW(NULL, folder, (DWORD)(sizeof(folder) / sizeof(folder[0])));
    if (!length || length >= sizeof(folder) / sizeof(folder[0])) {
        show_error(L"Could not find the application's folder.", GetLastError());
        return 1;
    }
    wchar_t *last = wcsrchr(folder, L'\\');
    if (!last) { show_error(L"Could not resolve the application folder.", 0); return 1; }
    *last = L'\0';
    wchar_t exe[32768];
    int n = swprintf(exe, sizeof(exe) / sizeof(exe[0]), L"%ls\\lasrecomp.exe", folder);
    if (n < 0 || n >= (int)(sizeof(exe) / sizeof(exe[0]))) {
        show_error(L"Path to the native runtime is too long.", 0);
        return 1;
    }
    if (GetFileAttributesW(exe) == INVALID_FILE_ATTRIBUTES) {
        show_error(L"The native executable (lasrecomp.exe) is missing.", GetLastError());
        return 1;
    }
    wchar_t command[32768];
    n = swprintf(command, sizeof(command) / sizeof(command[0]), L"\"%ls\"", exe);
    if (n < 0 || n >= (int)(sizeof(command) / sizeof(command[0]))) {
        show_error(L"Path to the native runtime is too long.", 0);
        return 1;
    }
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    if (!CreateProcessW(exe, command, NULL, NULL, FALSE, 0, NULL, folder, &startup, &process)) {
        show_error(L"Could not start Violet Recomp.", GetLastError());
        return 1;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
}
