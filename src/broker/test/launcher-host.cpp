#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    HMODULE module = LoadLibraryW(argv[1]);
    if (!module) return 3;
    auto start = reinterpret_cast<int (*)(void*)>(GetProcAddress(module, "start_broker"));
    if (!start) return 4;
    start(nullptr);
    Sleep(4000);
    return 0;
}
