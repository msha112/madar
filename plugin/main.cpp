// ─────────────────────────────────────────────────────────────
//  madar-csd — Hyprland plugin for Madar
//
//  Hyprland 0.53 ignores three requests that apps send from their own
//  title bars (client-side decorations). This plugin handles them:
//
//    • drag the title bar   → move the window (xdg_toplevel.move)
//    • drag a window edge   → resize it      (xdg_toplevel.resize)
//    • maximize button      → fill the screen next to the rail (scripts/max.sh)
//    • minimize button      → hide the window in special:minimized
//                             (the Madar side rail shows it dimmed;
//                              click it there to bring it back)
//
//  Bonus: dragging a "maximized" window (Madar maximizes by sizing the
//  window to fill the screen, see scripts/max.sh) first gives it back its
//  normal size under the cursor, like Windows does.
//
//  Built against the installed Hyprland headers (hyprland-dev) by install.sh.
//  Must be rebuilt whenever Hyprland is updated.
// ─────────────────────────────────────────────────────────────
#define WLR_USE_UNSTABLE

#include <algorithm>
#include <any>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <format>
#include <fstream>
#include <string>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

// CXDGToplevelResource keeps the protocol object (m_resource) private. Explicit
// template instantiation is allowed to name private members, which gives us a
// member pointer to it without touching the headers.
struct ToplevelResourceTag {
    using type = SP<CXdgToplevel> CXDGToplevelResource::*;
    friend type memberOf(ToplevelResourceTag);
};
template <typename Tag, typename Tag::type M>
struct Expose {
    friend typename Tag::type memberOf(Tag) {
        return M;
    }
};
template struct Expose<ToplevelResourceTag, &CXDGToplevelResource::m_resource>;

static SP<CXdgToplevel> protocolObject(const SP<CXDGToplevelResource>& toplevel) {
    return (*toplevel).*memberOf(ToplevelResourceTag{});
}

inline HANDLE PHANDLE = nullptr;

static bool g_dragging = false;      // a drag we started is in progress
constexpr int RAIL     = 64;         // Madar side rail width (Theme.railWidth)

static std::string addrOf(const PHLWINDOW& w) {
    return std::format("0x{:x}", (uintptr_t)w.get());
}

static void dispatch(const std::string& name, const std::string& arg) {
    const auto it = g_pKeybindManager->m_dispatchers.find(name);
    if (it != g_pKeybindManager->m_dispatchers.end())
        it->second(arg);
}

// A window Madar "maximized" fills the space next to the rail. Before dragging
// it, shrink it back to the size saved by max.sh, keeping the grab point under
// the cursor.
static void restoreBeforeDrag(const PHLWINDOW& w) {
    const auto mon = w->m_monitor.lock();
    if (!mon)
        return;

    const auto pos  = w->m_realPosition->goal();
    const auto size = w->m_realSize->goal();
    const bool full = size.x >= mon->m_size.x - RAIL - 4 && size.y >= mon->m_size.y - 4 &&
                      std::abs(pos.x - (mon->m_position.x + RAIL)) <= 4 && std::abs(pos.y - mon->m_position.y) <= 4;
    if (!full)
        return;

    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    const auto  file    = std::string{runtime ? runtime : "/tmp"} + "/madar-max/" + addrOf(w);

    int nx = 0, ny = 0, nw = 0, nh = 0;
    {
        std::ifstream in(file);
        if (!(in >> nx >> ny >> nw >> nh) || nw <= 0 || nh <= 0) {
            nw = (int)((mon->m_size.x - RAIL) * 0.62);
            nh = (int)(mon->m_size.y * 0.72);
        }
    }
    std::remove(file.c_str());

    const auto  cursor = g_pInputManager->getMouseCoordsInternal();
    const double fx    = size.x > 0 ? (cursor.x - pos.x) / size.x : 0.5;
    const int    x     = (int)(cursor.x - fx * nw);
    const int    y     = (int)(cursor.y - std::min(cursor.y - pos.y, (double)nh / 2));

    const auto target = "address:" + addrOf(w);
    dispatch("resizewindowpixel", std::format("exact {} {},{}", nw, nh, target));
    dispatch("movewindowpixel", std::format("exact {} {},{}", x, y, target));
}

static void beginDrag(PHLWINDOWREF ref, bool resize) {
    const auto w = ref.lock();
    if (!w || g_pInputManager->m_dragMode != MBIND_INVALID)
        return;

    if (!w->m_isFloating)
        dispatch("setfloating", "address:" + addrOf(w));

    if (!resize)
        restoreBeforeDrag(w);

    dispatch("mouse", resize ? "1resizewindow" : "1movewindow");
    g_dragging = g_pInputManager->m_dragMode != MBIND_INVALID;
}

static void hookWindow(const PHLWINDOW& w) {
    if (!w || w->m_isX11)
        return;
    const auto surface = w->m_xdgSurface.lock();
    if (!surface)
        return;
    const auto toplevel = surface->m_toplevel.lock();
    if (!toplevel)
        return;
    const auto resource = protocolObject(toplevel);
    if (!resource)
        return;

    PHLWINDOWREF ref = w;

    resource->setMove([ref](auto&&...) { beginDrag(ref, false); });
    resource->setResize([ref](auto&&...) { beginDrag(ref, true); });
    // maximize button / double-click on the title bar → Madar's floating maximize
    // (scripts/max.sh), so other windows can still come in front of it
    // We never tell the app it's maximized, so its button always sends "maximize";
    // each press toggles. "Unmaximize" requests are ignored: apps send them on
    // their own when their size changes, which undid the maximize right away.
    resource->setSetMaximized([ref](auto&&...) {
        static auto last = std::chrono::steady_clock::time_point{};
        const auto  now  = std::chrono::steady_clock::now();
        if (now - last < std::chrono::milliseconds(500))
            return;                                  // one press can arrive twice
        last = now;
        if (const auto win = ref.lock())
            dispatch("exec", "~/.config/quickshell/scripts/max.sh toggle " + addrOf(win));
    });
    resource->setUnsetMaximized([](auto&&...) {});
    resource->setSetMinimized([ref](auto&&...) {
        if (const auto win = ref.lock())
            dispatch("movetoworkspacesilent", "special:minimized,address:" + addrOf(win));
    });
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[madar-csd] Hyprland was updated — run ./install.sh again to rebuild the plugin",
                                     CHyprColor{1.0, 0.4, 0.3, 1.0}, 8000);
        throw std::runtime_error("[madar-csd] version mismatch");
    }

    // new windows
    static auto P1 = HyprlandAPI::registerCallbackDynamic(PHANDLE, "openWindow", [](void*, SCallbackInfo&, std::any data) {
        hookWindow(std::any_cast<PHLWINDOW>(data));
    });

    // end our drag when the mouse button is released
    static auto P2 = HyprlandAPI::registerCallbackDynamic(PHANDLE, "mouseButton", [](void*, SCallbackInfo&, std::any data) {
        const auto e = std::any_cast<IPointer::SButtonEvent>(data);
        if (g_dragging && e.state == WL_POINTER_BUTTON_STATE_RELEASED) {
            dispatch("mouse", "0movewindow");
            g_dragging = false;
        }
    });

    // windows that were already open when the plugin loaded
    for (const auto& w : g_pCompositor->m_windows)
        if (w->m_isMapped)
            hookWindow(w);

    return {"madar-csd", "Title-bar drag, edge resize and minimize for apps' own title bars", "Madar", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_dragging = false;
}
