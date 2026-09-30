# runs ON the MiSTer: set or clear RTS on /dev/ttyS1 through a second descriptor (termios untouched)
import fcntl, os, struct, sys, termios
fd = os.open('/dev/ttyS1', os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
req = termios.TIOCMBIS if sys.argv[1] == 'on' else termios.TIOCMBIC
fcntl.ioctl(fd, req, struct.pack('I', termios.TIOCM_RTS))
st = struct.unpack('I', fcntl.ioctl(fd, termios.TIOCMGET, struct.pack('I', 0)))[0]
print('RTS', bool(st & termios.TIOCM_RTS), 'CTS', bool(st & termios.TIOCM_CTS))
if len(sys.argv) > 2:
    import time; time.sleep(float(sys.argv[2]))
os.close(fd)
