# 01 - El pipeline: de commit a artefacto

**Clase 1 · 45 min · M1 + M2**
**Fase:** reconocimiento de la cadena de suministro
**MITRE ATT&CK:** T1195 (Supply Chain Compromise), T1078 (Valid Accounts)
**Riesgo OWASP CI/CD:** CICD-SEC-1 (control de flujo), CICD-SEC-9 (integridad del artefacto)

## Escenario

Antes de romper nada, un red team dibuja el flujo. En este laboratorio vas a
ejecutar el pipeline real de la empresa y a seguir el rastro de cada credencial:
quien construye, con que permisos y donde queda el artefacto. Ese mapa es el que
se ataca en las clases 2, 3 y 4.

## Objetivo de aprendizaje

- Identificar las cuatro fases: **source -> build -> artifact -> deploy**.
- Ver que el runner de CI acumula privilegios: socket de Docker, token de Git y
  credenciales de despliegue.
- Saber donde mirar cuando un pipeline se compromete.

## Antes de empezar

```bash
cd devops-redteam
export J=http://localhost:8080
source <(sed -n 's/^\(JENKINS_[A-Z]*\)=\(.*\)/export \1="\2"/p' seed/repo/secrets/jenkins_token.txt)
```

El token del repo es de `devops`, el usuario de automatizacion. Lo usaremos
porque es el mismo que usaria un pipeline; en el lab 09 veremos que no deberia
estar ahi.

## Paso 0 - Enumeracion inicial (10 min)

Antes de lanzar nada, convierte servicios en superficie. Enumerar no es
explotar: es descubrir endpoints, repos, jobs y tags visibles sin autenticacion.
Esta es la misma tecnica de enumeracion; aqui la resolvemos contra
`localhost`.

```bash
for p in 3000 8080 5000 8888 4566 8000; do
  printf '%s ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' http://localhost:$p/
done
curl -s http://localhost:8080/api/json \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["mode"],[j["name"] for j in d["jobs"]])'
curl -s 'http://localhost:3000/api/v1/repos/search?q=devops-demo' \
  | python3 -c 'import sys,json;print([r["full_name"] for r in json.load(sys.stdin)["data"]])'
curl -s http://localhost:5000/v2/_catalog; echo
```

**Que esperar:** los seis puertos responden; Jenkins muestra `NORMAL` y sus
jobs (entre ellos `build-and-push`); Gitea devuelve
`devops-org/devops-demo`; el registry devuelve
`{"repositories":["devops-demo"]}`.

**Por que importa:** esta informacion es la que usara un atacante para elegir
objetivo. OWASP lo nombra como CICD-SEC-2 (identidad y acceso) y CICD-SEC-10
(registro y visibilidad). Anotala en el cuaderno antes de ejecutar el build.

## Paso 1 - Lanzar el build

Por la UI: http://localhost:8080 -> job **build-and-push** -> *Build Now*.

Por API, que es lo que hace un atacante con un token:

```bash
C=$(curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" -c /tmp/cj01 \
  $J/crumbIssuer/api/json | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -o /dev/null -w 'trigger %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" -b /tmp/cj01 -H "Jenkins-Crumb: $C" \
  -X POST $J/build-and-push/build
```

**Que esperar:** `201`. Jenkins encola el build y hace checkout de
`http://gitea:3000/devops-org/devops-demo.git`, rama `main`.

## Paso 2 - Seguir el build en la consola

```bash
sleep 20
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
  $J/job/build-and-push/lastBuild/consoleText | tail -20
```

**Que esperar:** las etapas `Test`, `Build image`, `Push image` y `Notify`, y
`Finished: SUCCESS`. La ultima linea del log incluye el numero de build.

**Por que funciona:** el job es un `pipelineJob` con `cpsScm`; cada build lee el
`Jenkinsfile` del repo y ejecuta lo que diga el archivo. Esa caracteristica es
la que se explota en el lab 08.

## Paso 3 - Ver el artefacto

```bash
curl -s http://localhost:5000/v2/_catalog; echo
curl -s http://localhost:5000/v2/devops-demo/tags/list; echo
```

**Que esperar:**

```json
{"repositories":["devops-demo"]}
{"name":"devops-demo","tags":["1"]}
```

El tag es el numero de build. El registry no tiene autenticacion: cualquiera que
llegue al puerto puede leer y empujar imagenes.

## Paso 4 - Ver la notificacion

```bash
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["path"],"|",x["body"]) for x in json.load(sys.stdin) if "jenkins" in x["path"]]'
```

**Que esperar:** `POST /jenkins/build-done` con `build=1`. El pipeline habla con
un webhook interno; en el lab 06 veremos como un atacante crea uno propio.

## Paso 5 - Provocar un cambio y volver a construir

```bash
cd /tmp && rm -rf devops-demo
git clone http://dev:dev12345@localhost:3000/devops-org/devops-demo.git
cd devops-demo
sed -i 's/v1/v2/' app/index.html
git -c user.name=dev -c user.email=dev@lab.local commit -am "ui: v2"
git push
```

Vuelve a lanzar el build (paso 1). Aparece un tag nuevo (`2`).

```bash
curl -s http://localhost:5000/v2/devops-demo/tags/list
```

**Lo que acabas de demostrar:** un push al repo cambia el artefacto que se
despliega. Si controlas el repo, controlas produccion. Ese es el primer eslabon
de la cadena de suministro.

## Paso 6 - Inventariar los privilegios del runner

Sin atacar todavia, solo observa lo que Jenkins tiene a mano:

```bash
docker exec lab-jenkins sh -c 'ls /var/jenkins_home/credentials.xml && test -S /var/run/docker.sock && echo socket-presente'
```

**Que esperar:** el archivo de credenciales y `socket-presente`.

| Recurso | Donde vive | Se explota en |
|---|---|---|
| Credenciales Jenkins | `/var/jenkins_home/credentials.xml` | labs 07, 08 |
| Claves de descifrado | `/var/jenkins_home/secrets/` | labs 07, 08 |
| Socket de Docker | `/var/run/docker.sock` | lab 11 |
| Token de Gitea | repo `secrets/jenkins_token.txt` | lab 09 |
| Token de desarrollador | repo `secrets/dev_token.txt` | labs 02, 06 |

## Evidencia para el informe

- Salida de la enumeracion inicial (puertos, jobs, repos y `_catalog`).
- Numero de build y resultado (`SUCCESS`).
- Salida de `_catalog` y `tags/list` antes y despues del cambio.
- Peticion `/jenkins/build-done` en hookcat.
- Diagrama propio: que credencial usa cada fase.

## Checkpoint

1. Que informacion cambio de "desconocida" a "inventariada" en el paso 0?
2. Que componente decide que codigo se ejecuta en el build?
3. Por que el tag de la imagen no es un identificador inmutable?
4. Si el runner tiene el socket de Docker, que gana un atacante que ya ejecuta
   codigo en el build?

## Defensa

- El runner no debe compartir el daemon Docker del host (lab 11).
- Credenciales por scope minimo, rotacion y separacion build/deploy.
- Desplegar por digest, no por tag mutable (lab 04).
- Auditar quien puede cambiar `Jenkinsfile` y workflows (labs 08, 05).
