# Resize an mpv window by +-P pixels of width. args: hwnd delta side(R|L|auto)   prints the side used.
import ctypes, sys
from ctypes import wintypes as wt
u = ctypes.windll.user32
u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
class MI(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT), ("rcWork", wt.RECT), ("dwFlags", wt.DWORD)]
u.MonitorFromWindow.restype = wt.HANDLE; u.MonitorFromWindow.argtypes = [wt.HWND, wt.DWORD]
u.GetMonitorInfoW.argtypes = [wt.HANDLE, ctypes.POINTER(MI)]
u.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]
h, delta, side = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
r = wt.RECT(); u.GetWindowRect(h, ctypes.byref(r))
mi = MI(); mi.cbSize = ctypes.sizeof(MI); u.GetMonitorInfoW(u.MonitorFromWindow(h, 2), ctypes.byref(mi))
l, t, rr, b = r.left, r.top, r.right, r.bottom
if delta > 0:
    side = "R" if rr + delta <= mi.rcWork.right else "L"
    if side == "R": rr += delta
    else: l -= delta
else:
    if side == "L": l -= delta
    else: rr += delta
u.SetWindowPos(h, None, l, t, rr - l, b - t, 0x0004 | 0x0010)  # NOZORDER | NOACTIVATE
print(side)
