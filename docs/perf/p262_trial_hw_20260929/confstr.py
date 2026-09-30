# runs ON the MiSTer: read-only scan of Main's memory for the core's CONF_STR as Main read it over SPI
import re, os
pid = os.popen('pidof MiSTer').read().split()[0]
hits = set()
with open('/proc/%s/maps' % pid) as maps, open('/proc/%s/mem' % pid, 'rb', 0) as mem:
    for l in maps:
        a, perm = l.split()[:2]
        if 'r' not in perm or 'w' not in perm: continue
        s, e = (int(x, 16) for x in a.split('-'))
        if e - s > 256 << 20: continue
        try:
            mem.seek(s); d = mem.read(e - s)
        except Exception: continue
        for m in re.finditer(rb'MacQuadra800;UART[\x20-\x7e]{0,3000}', d):
            hits.add(m.group(0))
for h in hits:
    print(len(h)); print(h.decode().replace(';', ';\n'))
