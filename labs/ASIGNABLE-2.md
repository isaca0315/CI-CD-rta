# Asignable 2 - Del token al host, IaC y defensa

**Cubre:** labs 10 a 19
**Clases:** parte de la 3 y toda la 4
**Tiempo estimado:** 7 h de laboratorio mas 2 h de informe
**Riesgos OWASP CI/CD:** CICD-SEC-1, CICD-SEC-2, CICD-SEC-4, CICD-SEC-5,
CICD-SEC-6, CICD-SEC-7, CICD-SEC-8, CICD-SEC-9, CICD-SEC-10

## Enunciado

Continuas donde termino el [Asignable 1](ASIGNABLE-1.md). Ya tienes un token de
Jenkins con permisos de lectura y escritura. Ahora tienes que demostrar hasta
donde llega: ejecucion en el controlador, escape al host, ejecucion desde
Terraform, credenciales cloud y, al final, las defensas que impiden la cadena.

La entrega no es una lista de comandos. Es la cadena completa con evidencia, el
impacto en terminos de negocio y tres defensas probadas en el propio laboratorio.

## Pasos

### Fase A. Del token al host (labs 10-11)

| Lab | Flag | Que demuestra |
|---|---|---|
| [10 - RCE con `update-job`](10-jenkins-update-job-rce.md) | `jenkins_update_job_rce` | reescribir `config.xml` convierte un token en shell |
| [11 - Escape por `docker.sock`](11-docker-sock-escape.md) | `docker_sock_host_root` | el socket del CI es root del host |

Compara esta via con los CVEs de 2026 citados en el lab 10 (CVE-2026-84645 y
CVE-2026-33001): el resultado es el mismo aunque la entrada sea distinta.

### Fase B. La infraestructura como entrada (labs 12-14)

| Lab | Flag | Que demuestra |
|---|---|---|
| [12 - RCE en `terraform plan`](12-terraform-plan-rce.md) | `terraform_plan_rce` | `data "external"` ejecuta durante el plan |
| [13 - RCE en `terraform apply`](13-terraform-apply-rce.md) | `terraform_apply_rce` | `local-exec` y `data "http"` exfiltran |
| [14 - Backdoor en el state](14-terraform-state-backdoor.md) | `terraform_state_backdoor` | escribir el state es ejecutar en el siguiente pipeline |

El state envenenado del lab 14 es el mismo que alcanzas por S3 en el lab 15.
Guarda el archivo modificado y su `serial` como evidencia.

### Fase C. Credenciales cloud (labs 15-16)

| Lab | Flag | Que demuestra |
|---|---|---|
| [15 - IMDS falso y S3](15-aws-imds-s3.md) | `aws_s3_lateral` | RCE -> rol temporal -> bucket -> state |
| [16 - Tokens de Azure y GCP](16-cloud-identity-tokens.md) | `cloud_identity_token` | la identidad de la carga util es otra credencial |

Todo ocurre en `localhost`. No uses cuentas reales ni subas evidencia a un
servicio externo.

### Fase D. Defensa y deteccion (labs 17-19)

| Lab | Que entregas |
|---|---|
| [17 - gitleaks](17-gitleaks.md) | hallazgos del historial y explicacion de por que rotar va antes de limpiar |
| [18 - Trivy](18-trivy.md) | SBOM, salida del escaneo y el digest de la imagen; por que fijar por SHA tras CVE-2026-33634 |
| [19 - OWASP ZAP](19-zap.md) | baseline y full scan, con los hallazgos que un escaner NO ve (la injection del lab 15) |

Aplica ademas una defensa real y comprueba que rompe la cadena: quitar el socket
de Docker, cerrar `/script`, o bloquear la salida del runner. Documenta el antes
y el despues.

## Entrega

Un archivo `entrega-asignable-2.md` con:

1. **Cuaderno de evidencias.** Una fila por lab con hora UTC, comando, salida
   cruda, flag y defensa. Plantilla del [Anexo](ANEXO-metodo-red-team.md),
   seccion 5.
2. **Cadena completa.** Un mapa de 8 a 10 pasos desde el token del lab 09 hasta
   el state del lab 14, con la evidencia de cada salto. Debe incluir el lab 15
   como ruta alternativa al mismo state.
3. **Tres hallazgos.** Con la plantilla del anexo, seccion 6. Cada uno con su ID
   `CICD-SEC-*` y su CVE de 2026 cuando aplique.
4. **Defensas probadas.** Tres controles aplicados en el laboratorio, con la
   salida antes y despues. No sirve solo escribir la recomendacion.
5. **Limite de los escaneres.** Una tabla con lo que encontraron gitleaks, Trivy
   y ZAP frente a lo que solo se encontro a mano.

Las salidas crudas van en `evidencias/asignable-2/` y se referencian por nombre.
Prosa maxima: 3 paginas. El resto es evidencia.

## Rubrica (100 puntos)

| Criterio | Puntos | Que se mira |
|---|---|---|
| Ejecucion | 25 | 10 labs recorridos; 7 flags correctos |
| Explicacion | 25 | Por que `plan` ejecuta, por que el state es una entrada y por que el socket equivale a root |
| Evidencia | 20 | Salidas con fecha, ruta, comando y peticiones reproducibles; sin secretos en claro |
| Impacto | 15 | Cadena hasta host y cloud en terminos de credenciales y datos, no solo comandos |
| Defensa | 15 | Tres controles aplicados y verificados, mas una regla de deteccion por hallazgo |

Se aprueba con 70/100, los 7 flags y al menos una defensa ejecutada con evidencia
del antes y el despues.
