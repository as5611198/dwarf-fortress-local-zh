#include <functional>

extern "C" bool notify_search_textbox(void* widget, void* callback) {
    if (!widget || !callback) return false;
    auto& notify = *static_cast<std::function<void(void*)>*>(callback);
    if (!notify) return false;
    notify(widget);
    return true;
}
