try:
    dict()[:]
except Exception as e:
    exc = e
print(exc.value)