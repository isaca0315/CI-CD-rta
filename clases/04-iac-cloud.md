# Clase 4 - IaC, cloud y hardening

**Duracion:** 3 h en clase + trabajo autonomo · **Modulos:** M4 + M5 + M6
**Labs:** 12, 14, 15 en clase; 13 y 16 demo; 17, 18 y 19 autonomos
**Nivel:** medio-alto

## Resultado esperado

Al terminar la clase el alumno entiende que `terraform plan` ejecuta codigo,
que el state es una entrada no confiable del pipeline y que un permiso de
escritura en un bucket puede convertirse en RCE en el CI. Sabe ademas extraer
credenciales cloud desde un RCE, leer un token de identidad y proponer el
conjunto de controles que cubre IaC, cloud y aplicacion.

## Como encajar 8 labs en 3 h

La clase 4 concentra tres modulos. No caben los ocho labs con teoria y defensa.
Hay dos rutas validas:

- **Ruta esencial (3 h)**: teoria + labs 12, 14 y 15 + demos 13/16 + cierre
  defensivo con 17, 18 y 19 como trabajo autonomo. Es la recomendada.
- **Ruta completa (2 sesiones)**: sesion 4a con 12, 13, 14 y 15; sesion 4b con
  16, 17, 18 y 19. Usala si el grupo tiene 6 h o si el curso se parte en dos
  jornadas.

La agenda de abajo es la ruta esencial.

## Agenda (180 min)

| Min | Bloque | Contenido | Recurso |
|---|---|---|---|
| 0-10 | Apertura | Repaso de la clase 3 y encuadre de IaC/cloud | este documento |
| 10-50 | Teoria | Terraform, providers, state, IMDS, identidad cloud | este documento |
| 50-55 | Descanso | | |
| 55-80 | Lab | RCE en `terraform plan` | `labs/12-terraform-plan-rce.md` |
| 80-115 | Lab | Backdoor en el state | `labs/14-terraform-state-backdoor.md` |
| 115-145 | Lab | De RCE a credenciales cloud (IMDS + S3) | `labs/15-aws-imds-s3.md` |
| 145-160 | Demo | `apply` y token de Azure/GCP | `labs/13-terraform-apply-rce.md`, `labs/16-cloud-identity-tokens.md` |
| 160-175 | Defensa | Controles por capa y deteccion | Anexo, secciones 3 y 8 |
| 175-180 | Cierre | Ruta autonoma 17-19 y cierre del curso | este documento |

## Objetivos de aprendizaje

1. Describir el ciclo `init -> plan -> apply` y que se ejecuta en cada fase.
2. Reconocer `data.external`, `local-exec` y `remote-exec` como ejecucion.
3. Explicar por que el state es una entrada no confiable y como se envenena.
4. Extraer credenciales temporales de un metadata service y usarlas.
5. Leer claims de un token cloud y decidir a que da acceso.
6. Elegir controles de IaC, cloud y aplicacion con coste razonable.

## Teoria

### 1. Terraform: que ejecuta y cuando

```
terraform init    descarga providers y modulos
terraform plan    lee estado real, evalua data sources, calcula el diff
terraform apply   crea/modifica/destruye recursos
```

- **Provider**: plugin que habla con una API. Se descarga de un registry.
- **Resource**: objeto gestionado.
- **Data source**: lectura; puede ejecutar codigo si es `external`.
- **State**: JSON con lo que Terraform cree que existe.

La trampa: `plan` se percibe como "solo lectura", pero los `data` sources se
evaluan ahi. `data "external"` ejecuta un programa local para obtener su
resultado. Eso es el lab 12.

Ademas, en `apply` existen `local-exec` y `remote-exec`, que ejecutan comandos
en la maquina que aplica o en el recurso. En el lab 13 el `local-exec` roba un
archivo del home y un `data "http"` lo envia.

Casos reales de 2026: CVE-2026-27900 dejo credenciales expuestas en logs de
debug de un provider de Terraform, y CVE-2026-112407 dio escalada de
privilegios por una politica IAM demasiado amplia en una toolchain de CI/CD.
Se comentan en los labs
12 y 15. Ejecutar codigo y filtrar secretos son riesgos distintos aunque
compartan pipeline.

### 2. El state es la fuente de verdad (y una entrada)

El pipeline lee el state al empezar y lo escribe al terminar. Contiene recursos,
atributos y a veces secretos. Si un atacante puede escribirlo:

1. anade un recurso que no esta en el codigo,
2. sube el `serial` para que Terraform lo acepte,
3. el siguiente `plan` intenta destruirlo,
4. para destruirlo carga el provider que lo gestiona,
5. si ese provider es malicioso, ejecuta un comando.

Ese es el lab 14. Lo importante no es el provider concreto, sino el patron:
**state escribible -> provider controlable -> ejecucion en el pipeline**. El
permiso minimo que basta es `s3:PutObject` sobre el objeto del state.

Defensas: bucket con acceso solo del rol del pipeline, versionado, locking,
cifrado, `required_providers` fijado y allowlist de providers, y alerta cuando
el `serial` cambia sin un run de CI.

### 3. Credenciales cloud desde dentro

Un metadata service (IMDS) entrega credenciales al workload que corre en la
instancia o contenedor. El flujo real:

```
GET /latest/meta-data/iam/security-credentials/       -> nombre del rol
GET /latest/meta-data/iam/security-credentials/<rol>   -> AccessKeyId, Secret, Token
```

En AWS moderno se exige IMDSv2: primero `PUT` con un token y luego `GET` con
`X-aws-ec2-metadata-token`. Azure y GCP tienen endpoints equivalentes y
devuelven un token portador (JWT en Azure, `ya29...` en GCP).

Un token de identidad no se "rompe": se usa tal cual contra la API. Los claims
(`aud`, `tid`, `oid`, `exp`) dicen a que API sirve y cuanto dura. El lab 16 los
decodifica.

### 4. La cadena completa del modulo

```
app con command injection (15)
  -> IMDS / token de identidad (15, 16)
  -> credenciales temporales
  -> S3: escritura en el state (15)
  -> terraform plan del pipeline (14)
  -> ejecucion en el CI
```

Es la misma idea de las clases 2 y 3: un permiso pequeno en un eslabon se
convierte en ejecucion en el siguiente.

### 5. Hardening: cinco capas

| Capa | Control | Lab |
|---|---|---|
| Codigo | revision, SAST, sin secretos | 17 |
| Dependencias e imagen | SCA, SBOM, firma, digest | 18 |
| App en ejecucion | DAST, validacion de entrada | 19 |
| IaC | policy as code, providers fijados, state protegido | 12-14 |
| Cloud | IMDSv2, RBAC minimo, OIDC, tokens cortos | 15, 16 |

Ninguna capa sola es suficiente. El curso lo demuestra: Trivy no ve la command
injection y ZAP baseline no la ve; el full scan activo si, pero solo con
permiso y en un entorno aislado.

## Demo del instructor (15 min)

1. `terraform apply` del lab 13 y mostrar las dos peticiones en hookcat.
2. Repetir el apply y ensenar `No changes`: el backdoor se ejecuta una vez.
3. Pedir el token de Azure a traves del RCE y decodificar el JWT en vivo.
4. Cerrar con la pregunta: "que control habria parado cada paso?".

## Laboratorio

| Lab | Modo | Tiempo | Se evalua |
|---|---|---|---|
| 12 - plan RCE | en clase | 25 min | `data.external`, ejecucion sin apply |
| 14 - state backdoor | en clase | 35 min | serial, provider, plan y apply |
| 15 - IMDS y S3 | en clase | 30 min | RCE, credenciales, flag en S3 |
| 13 - apply RCE | demo | 10 min | `local-exec`, `data.http`, idempotencia |
| 16 - tokens Azure/GCP | demo | 10 min | JWT, claims, alcance |
| 17 - gitleaks | autonomo | 20 min | historial, triage, rotacion |
| 18 - Trivy | autonomo | 20 min | misconfigs, CVEs, SBOM |
| 19 - ZAP | autonomo | 25 min | baseline vs full scan, limite del DAST |

## Preguntas para discusion

1. En que fase de Terraform se ejecuta un `data.external` y por que?
2. Que dos campos del state hay que tocar para que Terraform lo acepte?
3. Por que el ataque al state es mas sigiloso que un commit?
4. Que diferencia hay entre credenciales de rol y una access key fija?
5. Que claim de un JWT dice si sirve para management o solo para storage?
6. Por que el baseline de ZAP no ve la inyeccion y el full scan si?

## Defensa (15 min)

Ejercicio final: construir una tabla de tres columnas por capa.

| Capa | Prevencion | Deteccion |
|---|---|---|
| plan | prohibir `external`/`local-exec` por policy | provider o `data` nuevo en el diff |
| state | solo el rol del CI escribe; versionado y locking | `serial` cambia sin run de CI |
| IMDS | IMDSv2, hop limit 1, network policy | llamada a link-local desde la app |
| identidad | RBAC minimo, OIDC, tokens cortos | uso anomalo de token (IP, resource) |
| app | sin `shell=True`, validacion | payloads de inyeccion en logs/WAF |

Cada grupo presenta dos filas y justifica el coste. Se evalua la concrecion, no
la cantidad.

## Evaluacion

| Criterio | Puntos | Entregable de la clase |
|---|---|---|
| Ejecucion | 25 | labs 12, 14 y 15 con flag |
| Explicacion | 25 | por que el plan ejecuta y por que el state es entrada |
| Evidencia | 20 | plan con `destroy`, peticiones en hookcat, credenciales y S3 |
| Impacto | 15 | cadena app -> cloud -> CI explicada de punta a punta |
| Defensa | 15 | tabla de controles y dos reglas de deteccion |

## Materiales

- `tools/tf` y `tools/aws` funcionando (`--network host`).
- Buckets `tfstate` y `prod-artifacts` creados por `make up`; si `moto` se
  recreo, volver a ejecutar `./seed/bootstrap.sh`.
- State limpio (`rce.deploy`) al empezar; si esta sucio, aplicar el lab 14
  hasta el paso de limpieza.
- Imagenes de gitleaks, trivy y zap descargadas para el trabajo autonomo.

## Errores comunes del instructor

| Sintoma | Causa / arreglo |
|---|---|
| `Backend initialization required` | ejecutar `tools/tf init -input=false` |
| `Error loading state: serial` | el state subido tiene serial menor o igual |
| El plan no muestra el recurso inyectado | se subio a otra key/bucket |
| No hay peticion en hookcat | `init` no instalo el provider `rce` |
| `terraform` no encuentra el provider | revisar `.terraform.lock.hcl` y red |
| `aws` no autentica | exportar credenciales de moto o del IMDS |

## Cierre del curso

- Repasar la kill chain completa del anexo (seccion 2) y pedir a cada alumno
  que senale el eslabon que mas le costo.
- Entregar el informe final: un hallazgo completo por alumno, con severidad,
  causa raiz y remediacion.
- Recordar la limpieza: repo, Jenkins, webhooks, state y `make down`.

## Trabajo autonomo

- Labs 17, 18 y 19 completos, con evidencia y una conclusion por lab.
- Informe final de un hallazgo (plantilla del anexo, seccion 6).
- Ejercicio de defensa: una regla de deteccion por cada clase.

## Puente

No hay clase 5. El puente es el informe: lo que el alumno no pueda explicar por
escrito, no lo ha entendido.
