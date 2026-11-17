# 17 - Secret scanning con gitleaks

**Clase 4 · 20 min · Hardening (shift-left)**
**Fase:** defensa / deteccion temprana
**MITRE ATT&CK:** T1552.001 (Credentials In Files)
**Riesgo OWASP CI/CD:** CICD-SEC-6 (higiene de credenciales), CICD-SEC-10 (registro y visibilidad)

## Escenario

Los labs anteriores usaron secretos que estaban en el repo. En un cliente real,
esos secretos suelen llevar meses en el historial de Git y nadie los ha visto.
Tu trabajo como red team incluye demostrar el fallo, pero el entregable que
cambia algo es el control que lo detecta antes de produccion.

`gitleaks` escanea el arbol de trabajo y el historial de Git buscando patrones
de credenciales. Es barato, rapido y se integra en pre-commit y en CI.

## Objetivo de aprendizaje

- Distinguir escaneo del arbol de trabajo (`--no-git`) y del historial (`.git`).
- Interpretar los hallazgos y separar los reales de los de ejemplo.
- Integrar gitleaks en pre-commit y en un workflow.

## Antes de empezar

```bash
cd /home/ponciop/devops-redteam
```

## Paso 1 - `detect -s .` depende de donde estes

```bash
docker run --rm -v "$PWD":/repo zricethezav/gitleaks:latest detect -s /repo -v
```

**Que esperar:** en el repo publicado del curso, `leaks found: 2`. Son los dos
secretos de ejemplo de `seed/repo/config/prod.env` guardados en el historial.
Si tu carpeta no tiene `.git` exterior, el comando dice `no leaks found`.

Sin `--no-git`, gitleaks recorre commits. Aqui hay un commit que incluye
`prod.env`, asi que los ejemplos aparecen aunque el arbol de trabajo este limpio.
En un carpeta sin historial no hay nada que recorrer. Este detalle confunde a
mucha gente en el primer intento.

## Paso 2 - Escanear el arbol de trabajo

```bash
docker run --rm -v "$PWD":/repo zricethezav/gitleaks:latest \
  detect -s /repo --no-git -v
```

**Que esperar:** `leaks found: 5`.

| Archivo | Regla | Que es |
|---|---|---|
| `lab/act_runner/.runner` | `generic-api-key` | token del runner de Gitea Actions |
| `seed/repo/config/prod.env` | `stripe-access-token` | clave de Stripe de ejemplo |
| `seed/repo/config/prod.env` | `github-pat` | token de GitHub de ejemplo |
| `seed/repo/secrets/dev_token.txt` | `generic-api-key` | PAT de Gitea del lab 02 |
| `seed/repo/secrets/jenkins_token.txt` | `generic-api-key` | token de Jenkins del lab 09 |

Los dos ultimos y `.runner` son secretos **reales** del lab: `bootstrap.sh` crea
el PAT y el runner guarda su token al registrarse. Los de `prod.env` son de
ejemplo; gitleaks los marca igual porque el patron es valido. Esa es la primera
leccion de triage: **no todo hallazgo es explotable**.

## Paso 3 - Escanear el historial de un repo

`seed/repo` si tiene `.git` (es el repo que se empuja a Gitea). Escanealo:

```bash
docker run --rm -v "$PWD/seed/repo":/repo zricethezav/gitleaks:latest \
  detect -s /repo -v
```

**Que esperar:** `leaks found: 8`.

Los mismos tres archivos aparecen varias veces porque cada commit que los toca
deja una copia en el historial. Ese es el motivo por el que **rotar** es
obligatorio: borrar el archivo no borra los commits.

## Paso 4 - Salida JSON para el informe

```bash
docker run --rm -v "$PWD":/repo zricethezav/gitleaks:latest \
  detect -s /repo --no-git -f json -r /repo/gitleaks.json
python3 - <<'PY'
import json
d = json.load(open('gitleaks.json'))
print(len(d), 'hallazgos')
for x in d:
    print(f"{x['RuleID']:20} {x['File']}:{x['StartLine']}")
PY
```

**Que esperar:** 5 hallazgos con archivo y linea. Guarda el JSON como evidencia;
incluye la version de gitleaks y la fecha.

## Paso 5 - Integrarlo

`.pre-commit-config.yaml` (commit-time):

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.0
    hooks:
      - id: gitleaks
```

Workflow de Gitea Actions (push/PR):

```yaml
name: gitleaks
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: |
          apk add --no-cache curl tar >/dev/null
          curl -sSL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_x64.tar.gz \
            | tar -xz -C /usr/local/bin gitleaks
          gitleaks detect --source . -v
```

`fetch-depth: 0` es imprescindible: sin historial completo, el escaneo solo ve el
ultimo commit.

## Evidencia para el informe

- Numero de hallazgos y desglose por regla/archivo.
- Que hallazgos son reales y cuales de ejemplo (y por que).
- Captura del historial: el mismo secreto en varios commits.
- Propuesta: pre-commit + CI + rotacion.

## Checkpoint

1. Por que `detect` sin `--no-git` no ve los secretos del arbol de trabajo?
2. Que hace falta para que un secreto desaparezca del historial (y por que no
   basta con `git rm`)?
3. Como reduces falsos positivos sin desactivar reglas?

## Defensa

- Un secreto commiteado hay que **rotarlo**, no solo borrarlo.
- Pre-commit es la primera red; el escaneo en CI es la ultima.
- `.gitleaksignore` con fingerprints concretos, nunca desactivar reglas enteras.
- Escanear tambien imagenes y artefactos (lab 18).
- Rotar tokens de CI con cadencia y guardar solo referencias a un vault.
