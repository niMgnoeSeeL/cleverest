b = bytes(range(20))
ib = int.from_bytes(b, "big")
print(ib.to_bytes( 0, "big"))