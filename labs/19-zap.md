# 19 - DAST con OWASP ZAP en el pipeline

**Clase 4 · 25 min · Hardening (shift-left)**
**Fase:** defensa / deteccion en la app desplegada
**MITRE ATT&CK:** T1190 (Exploit Public-Facing Application), T1595 (Active Scanning)
**Riesgo OWASP CI/CD:** CICD-SEC-7 (configuracion insegura), CICD-SEC-10 (registro y visibilidad)

## Escenario

El equipo ya tiene SAST y escaneo de imagenes (labs 17 y 18). Falta la ultima
capa: probar la app **en ejecucion**, como lo haria un atacante desde fuera.
ZAP es el DAST de referencia y se integra en cualquier CI.

La leccion del lab sale de comparar dos modos: el baseline (pasivo) no ve la
command injection del lab 15; el full scan (activo) **si la encuentra** y la
demuestra con `cat /etc/passwd` y con un `sleep`. Es decir: lo que separa
"pasar el escaner" de "estar seguro" es el tipo de escaneo, y lo que separa un
escaneo util de un ataque es el permiso.

## Objetivo de aprendizaje

- Ejecutar ZAP baseline (pasivo) y full scan (activo) contra la app victima.
- Leer el resumen `FAIL/WARN/PASS` y priorizar los avisos.
- Ver que el escaneo pasivo se queda corto y el activo confirma el RCE.
- Integrar el baseline en CI sin convertir el CI en un atacante.

> La imagen `zaproxy/zap-stable` pesa ~1 GB y el full scan tarda varios minutos.
> El stack debe estar arriba y solo se escanea `localhost`.

## Antes de empezar

```bash
cd /home/ponciop/devops-redteam
curl -s http://localhost:8000/health
```

**Que esperar:** `{"ok":true}`.

## Paso 1 - Baseline (pasivo)

ZAP baseline no ataca: navega, revisa cabeceras, cookies y respuestas.

```bash
docker run --rm --network host -v "$PWD":/zap/wrk:rw -t \
  zaproxy/zap-stable zap-baseline.py \
  -t http://localhost:8000 -r zap-baseline.html -I
```

**Que esperar** al final:

```
FAIL-NEW: 0   FAIL-INPROG: 0   WARN-NEW: 7   WARN-INPROG: 0   INFO: 0   IGNORE: 0   PASS: 61
```

`-I` hace que el script no devuelva error cuando solo hay warnings. Sin `-I`,
el comando sale con codigo distinto de cero y romperia un CI que no distingue
severidad.

## Paso 2 - Leer los hallazgos del baseline

Los siete avisos, en este entorno:

| Alerta | Que significa | Prioridad |
|---|---|---|
| `Content Security Policy (CSP) Header Not Set` | sin CSP, un XSS tiene menos frenos | media |
| `Missing Anti-clickjacking Header` | falta `X-Frame-Options`/`frame-ancestors` | media |
| `X-Content-Type-Options Header Missing` | el navegador puede adivinar el tipo MIME | baja |
| `Permissions Policy Header Not Set` | no se restringen APIs del navegador | baja |
| `Cross-Origin-*-Policy Header Missing or Invalid` | aislamiento cross-origin incompleto (COEP/CORP) | baja |
| `Server Leaks Version Information` | `Server: Werkzeug/...` revela version | baja |
| `Storable and Cacheable Content` | respuestas con datos podrian cachearse | baja |

**Como leerlo:** ninguno es un RCE. Son cabeceras y configuracion. El informe
HTML (`zap-baseline.html`) trae la peticion y la respuesta de cada alerta, que
es lo que se adjunta como evidencia.

Comprueba que aqui **no** aparece la inyeccion:

```bash
grep -ci 'command injection\|remote os command' zap-baseline.html
```

**Que esperar:** `0`. El baseline no fuzzea parametros, asi que no puede
confirmar el RCE.

## Paso 3 - Full scan (activo)

El full scan hace spider, fuzzing de formularios y pruebas de inyeccion.

```bash
docker run --rm --network host -v "$PWD":/zap/wrk:rw -t \
  zaproxy/zap-stable zap-full-scan.py \
  -t http://localhost:8000 -r zap-full.html -I
```

**Que esperar** al final:

```
FAIL-NEW: 0   FAIL-INPROG: 0   WARN-NEW: 9   WARN-INPROG: 0   INFO: 0   IGNORE: 0   PASS: 134
```

Aparecen tres avisos nuevos respecto al baseline. Los dos primeros son los
importantes:

```
WARN-NEW: Remote OS Command Injection [90020] x 1
    http://localhost:8000/update?host=127.0.0.1%26cat+%2Fetc%2Fpasswd%26
WARN-NEW: Remote OS Command Injection (Time Based) [90037] x 1
    http://localhost:8000/update?host=127.0.0.1%26sleep+1.0%26
```

Decodificado, ZAP envio:

```
/update?host=127.0.0.1&cat /etc/passwd&
/update?host=127.0.0.1&sleep 1.0&
```

**Que demuestra:** el escaner pasivo no vio nada; el activo encontro el mismo
fallo del lab 15 sin ayuda. La diferencia es que ahora el escaneo **ejecuta
comandos en el target** (`cat`, `sleep`). Ese es exactamente el trafico que no
puedes lanzar contra produccion sin permiso.

Tambien aparece `Source Code Disclosure - File Inclusion [43]` sobre `/update`:
es un efecto secundario del propio `cat /etc/passwd` en la respuesta. No es una
vulnerabilidad distinta, es la misma inyeccion vista desde otra regla.

## Paso 4 - Confirmar a mano

El informe ya lo prueba, pero conviene verlo con tus ojos:

```bash
curl -s -G --data-urlencode 'host=127.0.0.1;id' http://localhost:8000/update \
  | grep -o 'uid=[^ <]*'
```

**Que esperar:** `uid=0(root)`.

**Por que importa:** el DAST te da la pista y el payload; la confirmacion manual
te da el impacto y la evidencia limpia para el informe.

## Paso 5 - Integracion en CI

Baseline en cada PR (rapido y seguro):

```yaml
- name: zap baseline
  run: |
    apk add --no-cache docker-cli >/dev/null
    docker run --rm --network host -v "$PWD":/zap/wrk:rw \
      zaproxy/zap-stable zap-baseline.py \
      -t "$TARGET_URL" -r zap.html -I
```

Full scan solo contra un entorno efimero o de staging, nunca produccion:

```yaml
- name: zap full scan
  run: |
    docker run --rm --network host -v "$PWD":/zap/wrk:rw \
      zaproxy/zap-stable zap-full-scan.py \
      -t "$STAGING_URL" -r zap-full.html -I
```

Con autenticacion, exporta un context file de ZAP (`-n context.context`) con el
login y las URLs en alcance. Sin eso, el escaneo solo ve la pagina publica.

## Evidencia para el informe

- Resumen `FAIL/WARN/PASS` del baseline (7 warnings) y del full scan (9).
- Las dos alertas de `Remote OS Command Injection` con su URL codificada.
- Captura del informe HTML y de la confirmacion manual (`uid=0(root)`).
- Version de ZAP y fecha del escaneo.

## Checkpoint

1. Que diferencia hay entre baseline y full scan, y cuando usarias cada uno?
2. Por que el baseline no encontro la inyeccion y el full scan si?
3. Por que `-I` cambia el codigo de salida y que implica en un pipeline?
4. Que hace falta para lanzar el full scan fuera de `localhost`?

## Defensa

- Cabeceras de seguridad y errores genericos en la app.
- Validar toda entrada y no usar `shell=True` con datos del usuario.
- ZAP baseline en cada PR contra el entorno efimero; full scan semanal en
  staging.
- Correlacionar con SAST (Semgrep/CodeQL) para cubrir lo que el DAST no vea.
- Nunca escanear produccion sin alcance firmado: el full scan es trafico de
  ataque real y deja rastro en logs y WAF.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| `docker: permission denied` | tu usuario no esta en el grupo `docker` |
| ZAP no llega a la app | usa `--network host` y `localhost`, no `host.docker.internal` |
| El scan no termina | es normal en full scan; dale 10-20 min y mira el log |
| `FAIL-NEW` mayor que 0 | hay un fallo que ZAP considera grave; abre el HTML y revisa la alerta |
| El informe no se escribe | el volumen debe ser `-v "$PWD":/zap/wrk:rw` |
| No aparece la inyeccion | el spider no encontro el formulario; confirma que `/` responde 200 |
