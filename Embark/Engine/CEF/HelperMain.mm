// Entry point for the "Embark Helper" apps (GPU, Renderer, Plugin) that Chromium launches
// as separate processes. Each helper bundle lives in Embark.app/Contents/Frameworks.
#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

int main(int argc, char *argv[]) {
    CefScopedLibraryLoader libraryLoader;
    if (!libraryLoader.LoadInHelper()) return 1;
    CefMainArgs mainArgs(argc, argv);
    return CefExecuteProcess(mainArgs, nullptr, nullptr);
}
