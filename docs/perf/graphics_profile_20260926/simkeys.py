#!/usr/bin/env python3
"""simkeys.py STREAM ITEM... -- append guest input to a simulator control stream.

ITEMs: text:Some Name (typed with shift where needed), cmd:o (Command+key, Command = PS/2 Left Alt 0x11),
ret, esc, tab, shot, wait:N (simulated rising edges), profile:start|stop.
Keys are PS/2 set-2 scancodes, as the simulator's SimInput expects.
"""
import subprocess, sys
SC = {**dict(zip("abcdefghijklmnopqrstuvwxyz",
                 [0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A])),
      **dict(zip("1234567890", [0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46,0x45])),
      " ": 0x29, "-": 0x4E, ".": 0x49}
HOLD, GAP = 330000, 3300000
def key(code, shift=False):
    out = []
    if shift: out += ["down 12", f"wait {HOLD}"]
    out += [f"down {code:02x}", f"wait {HOLD}", f"up {code:02x}", f"wait {HOLD}"]
    if shift: out += ["up 12"]
    return out + [f"wait {GAP}"]
cmds = []
for item in sys.argv[2:]:
    if item.startswith("text:"):
        for ch in item[5:]:
            cmds += key(SC[ch.lower()], ch.isupper())
    elif item.startswith("cmd:"):
        c = SC[item[4:].lower()]
        cmds += ["down 11", f"wait {HOLD}", f"down {c:02x}", f"wait {HOLD}", f"up {c:02x}", f"wait {HOLD}", "up 11", f"wait {GAP}"]
    elif item == "ret": cmds += key(0x5A)
    elif item == "esc": cmds += key(0x76)
    elif item == "tab": cmds += key(0x0D)
    elif item == "shot": cmds += ["shot"]
    elif item.startswith("wait:"): cmds += [f"wait {int(item[5:])}"]
    elif item.startswith("profile:"): cmds += [f"profile {item[8:]}"]
    else: sys.exit(f"unknown item {item}")
subprocess.run([sys.executable, "/home/alans/mister/MacQuadra800_MiSTer/scripts/guest/sim_control_send.py", sys.argv[1], *cmds], check=True)
print(f"queued {len(cmds)} commands")
