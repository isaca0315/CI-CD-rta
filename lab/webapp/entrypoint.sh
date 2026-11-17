#!/bin/sh
# 169.254.169.254 solo existe dentro de este contenedor: el IMDS falso no
# es alcanzable desde el host ni desde otros contenedores.
ip addr add 169.254.169.254/32 dev lo 2>/dev/null || true
python -u imds_mock.py &
exec python -u app.py
