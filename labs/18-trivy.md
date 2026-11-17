# 18 - Escaneo de imagenes y config con Trivy

**Clase 4 · 20 min · Hardening (shift-left)**
**Fase:** defensa / deteccion de artefactos
**MITRE ATT&CK:** T1195.002 (Supply Chain), T1610 (Deploy Container)
**Riesgo OWASP CI/CD:** CICD-SEC-8 (servicios de terceros), CICD-SEC-9 (integridad del artefacto)

## Escenario

El equipo quiere "pasar un escaner" antes de desplegar. Trivy revisa tres capas
distintas: dependencias del lenguaje, sistema operativo de la imagen y
misconfiguracion de IaC/Dockerfile. Es gratis y se integra en cualquier CI.

La leccion de este lab es doble: Trivy encuentra cosas utiles y **no** encuentra
la command injection del lab 15. Un escaner no sustituye al testing manual.

Y el escaner tambien puede ser el vector: en CVE-2026-33634 (marzo de 2026, en
el catalogo KEV de CISA) hubo secuestro de tags de `trivy-action` y
`setup-trivy` y publicacion de imagenes maliciosas de Trivy. Por eso en este lab
se registra el digest y se fijan las acciones por SHA: verificar lo que ejecuta
el pipeline antes de fiarse del resultado que da.

## Objetivo de aprendizaje

- Escanear configuracion y secretos de un Dockerfile.
- Escanear una imagen construida (CVEs del SO y dependencias).
- Generar un SBOM y usar `--exit-code` para romper el pipeline.
- Entender el limite: no detecta logica de negocio vulnerable.

## Antes de empezar

```bash
cd /home/ponciop/devops-redteam
docker images | grep devops-lab-webapp
```

**Que esperar:** la imagen `devops-lab-webapp:latest` (la construye `make up`).

## Paso 1 - Configuracion y secretos del Dockerfile

```bash
docker run --rm -v "$PWD/lab/webapp":/scan aquasec/trivy:latest \
  fs --scanners vuln,secret,misconfig /scan
```

**Que esperar** (resumen):

```
Dockerfile (dockerfile)
Tests: 27 (SUCCESSES: 25, FAILURES: 2)
Failures: 2 (UNKNOWN: 0, LOW: 1, MEDIUM: 0, HIGH: 1, CRITICAL: 0)

DS-0002 (HIGH): Specify at least 1 USER command in Dockerfile with non-root user
DS-0026 (LOW):  Add HEALTHCHECK instruction in your Dockerfile
```

**Como leerlo:** `DS-0002` es real: el contenedor corre como root. `DS-0026` es
higiene, no explotable. Trivy no dice "esto es vulnerable"; dice "esto se aleja
de una buena practica".

## Paso 2 - Vulnerabilidades de la imagen

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity HIGH,CRITICAL devops-lab-webapp
```

**Que esperar:** una tabla con CVEs de la base Debian y sus dependencias. En la
fecha del laboratorio aparecen ~108 HIGH (0 CRITICAL); el numero cambia con la
base de datos.

Lo importante no es el numero: es que hay decenas de paquetes sin parchear
(`util-linux`, `zlib`, ...). En un engagement se prioriza por explotabilidad
real, no por severidad nominal.

## Paso 3 - SBOM y politica de fallo

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD":/out aquasec/trivy:latest image \
  --format spdx-json --output /out/sbom.json devops-lab-webapp
python3 -c 'import json;d=json.load(open("sbom.json"));print(len(d.get("packages",[])),"paquetes")'
```

**Que esperar:** un SBOM SPDX con decenas de paquetes. Guardalo: es la lista de
lo que hay dentro del artefacto.

Romper el pipeline si hay CRITICAL:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --exit-code 1 --severity CRITICAL devops-lab-webapp
echo "exit=$?"
```

**Que esperar:** `exit=0` hoy (no hay CRITICAL). Si anades `--severity HIGH`,
sale `1` y el build falla. Un escaneo sin `--exit-code` es informativo y se
ignora.

## Paso 4 - Comprobar el limite del escaner

Trivy no encuentra la inyeccion de comandos de `/update`:

```bash
grep -n 'shell=True' lab/webapp/app.py
curl -s -G --data-urlencode 'host=127.0.0.1;id' http://localhost:8000/update \
  | grep -o 'uid=[^ <]*'
```

**Que demuestra:** el RCE es una linea de codigo vulnerable, no una CVE ni una
mala configuracion de Dockerfile. Eso lo cubre SAST (Semgrep/CodeQL) o test
manual, no Trivy.

## Paso 5 - Integracion en CI

```yaml
- name: trivy
  run: |
    apk add --no-cache curl >/dev/null
    curl -sSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin
    trivy fs --exit-code 1 --severity HIGH,CRITICAL .
```

Complementos: firma de imagenes con `cosign`, admission controller que solo
acepte digests firmados, y `trivy image --ignore-unfixed` para no bloquear por
vulnerabilidades sin parche.

## Evidencia para el informe

- Resumen de `fs` (2 misconfigs) y de `image` (conteo HIGH/CRITICAL).
- SBOM generado y numero de paquetes.
- Codigo de salida con y sin `--exit-code`.
- Prueba de que el RCE no aparece en el escaneo (la limitacion).

## Checkpoint

1. Que tres capas cubre Trivy y cual no?
2. Por que `--severity HIGH` sin `--exit-code` no protege nada?
3. Que anadirias ademas de Trivy para cubrir la logica de la app?

## Defensa

- Escanear en el PR (`fs`) y en el push de la imagen (`image`).
- Fallar el build por HIGH/CRITICAL explotables; triage con `--ignore-unfixed`.
- Base image minima, non-root, HEALTHCHECK y sin herramientas de debug.
- Registry inmutable y despliegue por digest.
- Complementar con SAST/DAST (labs 17 y 19).
