# runs ON the MiSTer: read-only dump of the ascal DDR header (Main's scaler.cpp layout)
import mmap, os, sys
fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x20000000)
b = m[:16]
w = lambda i: b[i] << 8 | b[i+1]
print('hdr', b.hex(), 'type', b[0], b[1], 'in %dx%d line %d out %dx%d' % (w(6), w(8), w(10), w(12), w(14)))
