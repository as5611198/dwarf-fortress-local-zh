#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>

static HMODULE module_handle;
static HANDLE broker_job;

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        module_handle = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

// Lua's state is intentionally unused: this module only starts the local helper.
extern "C" __declspec(dllexport) int start_broker(void*) {
    if (!broker_job) {
        HANDLE job = CreateJobObjectW(nullptr, nullptr);
        if (!job) return 0;
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation,
            &limits, sizeof(limits))) {
            CloseHandle(job);
            return 0;
        }
        // The game owns this handle until process exit, including abnormal exit.
        broker_job = job;
    }
    wchar_t module_path[32768]{};
    wchar_t game_path[32768]{};
    if (!GetModuleFileNameW(module_handle, module_path, 32768) ||
        !GetCurrentDirectoryW(32768, game_path)) return 0;
    const std::wstring path(module_path);
    const std::wstring directory = path.substr(0, path.find_last_of(L"\\/"));
    const std::wstring executable = directory + L"\\df-local-zh-broker.exe";
    const std::wstring config = directory + L"\\config.json";
    const std::wstring state = std::wstring(game_path) + L"\\dfhack-config\\mods\\df-local-zh-complete";
    std::wstring command = L"\"" + executable + L"\" \"" + config + L"\" \"" + state + L"\" --game-root \"" + game_path + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, game_path, &startup, &process)) {
        if (!AssignProcessToJobObject(broker_job, process.hProcess) ||
            ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
            TerminateProcess(process.hProcess, 1);
            WaitForSingleObject(process.hProcess, INFINITE);
        }
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    }
    return 0;
}
