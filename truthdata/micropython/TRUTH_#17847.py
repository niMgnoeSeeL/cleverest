import micropython
rb = micropython.RingIO(bytearray(0))
rb.write(b'\1')