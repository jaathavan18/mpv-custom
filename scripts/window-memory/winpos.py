# Window position helper. get hwnd -> "l t w h"      set hwnd l t w h -> moves the window, or prints "bad" (exit 1) if it would not be on a screen
import ctypes, sys
from ctypes import wintypes as wt
u = ctypes.windll.user32
u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
u.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]
class MI(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT), ("rcWork", wt.RECT), ("dwFlags", wt.DWORD)]
def work_areas():
    out = []
    cb = ctypes.WINFUNCTYPE(ctypes.c_int, wt.HANDLE, wt.HDC, ctypes.POINTER(wt.RECT), wt.LPARAM)
    def f(m, dc, rc, lp):
        mi = MI(); mi.cbSize = ctypes.sizeof(MI); u.GetMonitorInfoW(m, ctypes.byref(mi))
        out.append((mi.rcWork.left, mi.rcWork.top, mi.rcWork.right, mi.rcWork.bottom)); return 1
    u.EnumDisplayMonitors(None, None, cb(f), 0)
    return out
cmd, h = sys.argv[1], int(sys.argv[2])
if cmd == "get":
    r = wt.RECT(); u.GetWindowRect(h, ctypes.byref(r))
    print(r.left, r.top, r.right - r.left, r.bottom - r.top)
else:
    l, t, w, hh = map(int, sys.argv[3:7])
    ok = w >= 300 and hh >= 200
    if ok:   # the title bar must be mostly on one screen and at least a third of the window must be visible there
        ok = False
        for a, b, c, d in work_areas():
            vis = max(0, min(l + w, c) - max(l, a)) * max(0, min(t + hh, d) - max(t, b))
            if vis * 3 >= w * hh and a <= l + w // 2 < c and b <= t < d: ok = True
    if not ok: print("bad"); sys.exit(1)
    u.SetWindowPos(h, None, l, t, w, hh, 0x0004 | 0x0010)
    print("ok")
