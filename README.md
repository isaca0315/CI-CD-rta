# · Laboratorio local de DevOps Red Team

Curso de 4 clases (3 h cada una) sobre ataque a cadenas CI/CD, IaC y cloud,
montado **entero en local** con Docker. No hace falta AWS, Azure, GCP, GitHub
ni ninguna cuenta externa: cada servicio real esta sustituido por un equivalente
local que se comporta igual para el atacante.

> ⚠️ **Todo el laboratorio es deliberadamente vulnerable** (Jenkins sin auth,
> socket de Docker montado, secretos en repos, provider malicioso). Ejecutalo
> solo en tu maquina, en `localhost`, y nunca lo publiques en una red. No lo
> levantes en un laptop de trabajo.

## Arranque rapido

```bash
cp .env.example .env     # opcional: cambia puertos aqui
make up                  # construye, arranca y siembra usuarios/repos/flags
make flags               # comprueba que los flags existen
```

La primera vez tarda varios minutos (imagenes + plugins de Jenkins). Al final
imprime las URLs y credenciales. Guia detallada: [`labs/00-setup.md`](labs/00-setup.md).

Requisitos: Linux, Docker 24+ con Compose v2, 8 GB de RAM (16 mejor), 15 GB
libres, `git`, `curl`, `python3`, `nc`. Opcional: VS Code para el lab 03.

## Como estudiar el curso

Cada lab se trabaja en tres pasadas:

1. **Ejecutar** los pasos y anotar la salida real (no la esperada).
2. **Explicar** el checkpoint: por que funciona y que pieza de la cadena falla.
3. **Defender**: proponer y probar el control que rompe el ataque.

Los labs son una cadena, no piezas sueltas: el PAT del 02 alimenta el webhook
del 06, el token del 09 alimenta el RCE del 10, y el state que envenenas en el
14 es el mismo que alcanzas por S3 en el 15. El metodo completo (kill chain,
ATT&CK, reglas de enfrentamiento, cuaderno de evidencias, plantilla de informe y
rubrica) esta en [`labs/ANEXO-metodo-red-team.md`](labs/ANEXO-metodo-red-team.md).
El itinerario por clase, con agenda, teoria y evaluacion, esta en
[`clases/`](clases/01-modelo-devops.md).

Cada lab declara en el encabezado su riesgo del OWASP Top 10 CI/CD
(`CICD-SEC-1` a `CICD-SEC-10`): es el vocabulario del informe, no una lista para
memorizar. Los casos reales de CVE de 2026 se comentan dentro del laboratorio
que los ilustra.

Los labs 00-18 estan verificados con salida real en el entorno del curso; el 19
incluye los resultados de ZAP baseline y full scan medidos en ese mismo entorno.

## Servicios

| Sustituye a | Servicio local | URL | Credenciales |
|---|---|---|---|
| GitHub | Gitea | http://localhost:3000 | `gitea_admin` / `gitea_admin123` |
| GitHub Actions | Gitea Actions + act_runner | misma UI | runner automatico |
| Jenkins | Jenkins LTS | http://localhost:8080 | `devops` / `devops123` |
| ECR | registry:2 | http://localhost:5000 | sin auth |
| S3 / STS / IAM | moto | http://localhost:4566 | cualquiera (`lab`/`lab`) |
| webhook.site | hookcat | http://localhost:8888 | - |
| app victima + IMDS | webapp | http://localhost:8000 | - |

Usuarios de Gitea:

- `dev` / `dev12345` — desarrollador, admin de `devops-org/devops-demo`
- `attacker` / `attacker123` — sin permisos; punto de partida del atacante

## Arquitectura

```
                 host (tu maquina)
   ┌──────────────────────────────────────────────────────────┐
   │  navegador / curl / nc / terraform (tools/tf)            │
   └───────┬───────────────┬───────────────┬──────────────────┘
           │               │               │
   ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼───────┐
   │ gitea :3000  │ │ jenkins     │ │ hookcat :8888│
   │ (repos,      │ │ :8080       │ │ (webhooks)   │
   │  actions)    │ │ docker.sock │ └──────────────┘
   └───────┬──────┘ └──────┬──────┘
           │               │
   ┌───────▼──────┐ ┌──────▼───────┐ ┌──────────────┐
   │ act_runner   │ │ registry     │ │ moto :4566   │
   │ (perfil ci)  │ │ :5000        │ │ S3/STS/IAM   │
   └──────────────┘ └──────────────┘ └──────────────┘
                          │
                  ┌───────▼──────────────┐
                  │ webapp :8000         │
                  │ /update -> RCE       │
                  │ IMDS 169.254.169.254 │  (solo dentro del contenedor)
                  └──────────────────────┘
```

Puntos clave del diseno:

- Jenkins corre como `root` y monta `/var/run/docker.sock` **a proposito**:
  es la misconfiguracion que se explota en el lab 11.
- Jenkins no tiene autenticacion (`authorizationStrategy: unsecured`), como el
  Jenkins expuesto del curso.
- `moto` ocupa el puerto 4566 y hace de S3/STS/ECR. Los buckets `tfstate` y
  `prod-artifacts` se crean en el arranque.
- El IMDS falso vive en el network namespace de `webapp`: no es alcanzable
  desde el host ni desde otros contenedores.

## Los 2 asignables

Todo el curso se entrega en dos tareas, sin material adicional:

| Asignable | Cubre | Contenido |
|---|---|---|
| [1 - Superficie, secretos y cadena de suministro](labs/ASIGNABLE-1.md) | labs 00-09 | inventario, PAT, extension, artefacto, workflow, Jenkins y secretos |
| [2 - Del token al host, IaC y defensa](labs/ASIGNABLE-2.md) | labs 10-19 | RCE, socket de Docker, Terraform, cloud y escaneres |

Cada uno trae enunciado, pasos por lab, entrega y rubrica de 100 puntos. Los dos
juntos cubren los 20 labs. La clase 2 deja listo el primero.

Ademas esta el
[proyecto semestral](proyecto-semestral/README.md): 16 semanas para montar un
pipeline de GitHub Actions con OWASP ZAP (web + API) y disenarlo contra los diez
riesgos del OWASP Top 10 CI/CD, con diagramas Mermaid y rubrica propia.

## Las 4 clases

| Clase | Tema | Teoria | Labs |
|---|---|---|---|
| **[1](clases/01-modelo-devops.md)** | Modelo DevOps y cadena de ataque. Del commit al artefacto | M1 + M2 | 00, 01 |
| **[2](clases/02-supply-chain.md)** | Pre-commit y supply chain: repo, IDE, imagenes, workflows | M3 | 02-06 |
| **[3](clases/03-cicd.md)** | CI/CD: Jenkins expuesto, credenciales, runners, socket | M4 | 07-11 |
| **[4](clases/04-iac-cloud.md)** | IaC y cloud: Terraform, IMDS, tokens, hardening | M4 + M5 + M6 | 12-19 |

Cada guia de clase incluye objetivos, agenda minuto a minuto, teoria, demo del
instructor, laboratorio con tiempos, preguntas de discusion, defensa,
evaluacion y errores comunes. La clase 1 enlaza al resto y la 4 explica como
repartir sus ocho labs en una o dos sesiones.

Material de la clase 1: [PPT](clases/01-modelo-devops.pptx) y [guia](clases/01-modelo-devops.md).

Sugerencia de reparto para 3 h por clase: 45-60 min de teoria, 5 min de
descanso, 90-100 min de laboratorio, 20 min de defensa y cierre.

## Laboratorios

| # | Lab | Clase | Tiempo | Flag |
|---|---|---|---|---|
| 00 | [Preparar el laboratorio](labs/00-setup.md) | 1 | 25 | - |
| 01 | [El pipeline: de commit a artefacto](labs/01-pipeline.md) | 1 | 35 | - |
| 02 | [Enumeracion con un PAT filtrado](labs/02-gitea-enumeration.md) | 2 | 30 | `gitea_enum_private_repo` |
| 03 | [Extension maliciosa de VS Code](labs/03-ide-extension.md) | 2 | 30 | `ide_extension_backdoor` |
| 04 | [Dockerfile backdoor](labs/04-dockerfile-backdoor.md) | 2 | 20 | `dockerfile_backdoor` |
| 05 | [Workflow malicioso en Gitea Actions](labs/05-gitea-actions.md) | 2 | 30 | `gitea_actions_secret` |
| 06 | [Webhook como canal de exfiltracion](labs/06-webhook.md) | 2 | 20 | - (evidencia en hookcat) |
| 07 | [Jenkins anonimo: consola de scripts](labs/07-jenkins-anon-console.md) | 3 | 25 | `jenkins_anon_script_console`, `jenkins_cred_decrypt` |
| 08 | [Exfiltracion desde el Jenkinsfile](labs/08-jenkinsfile-exfil.md) | 3 | 30 | `jenkins_cred_decrypt` |
| 09 | [Token de API expuesto](labs/09-jenkins-api-token.md) | 3 | 20 | `jenkins_api_token_logs` |
| 10 | [RCE modificando un job](labs/10-jenkins-update-job-rce.md) | 3 | 30 | `jenkins_update_job_rce` |
| 11 | [Escape por `docker.sock`](labs/11-docker-sock-escape.md) | 3 | 20 | `docker_sock_host_root` |
| 12 | [RCE en `terraform plan`](labs/12-terraform-plan-rce.md) | 4 | 25 | `terraform_plan_rce` |
| 13 | [RCE en `terraform apply`](labs/13-terraform-apply-rce.md) | 4 | 25 | `terraform_apply_rce` |
| 14 | [Backdoor en el state de Terraform](labs/14-terraform-state-backdoor.md) | 4 | 35 | `terraform_state_backdoor` |
| 15 | [De RCE a credenciales cloud](labs/15-aws-imds-s3.md) | 4 | 30 | `aws_s3_lateral` |
| 16 | [Tokens de Azure y GCP](labs/16-cloud-identity-tokens.md) | 4 | 20 | `cloud_identity_token` |
| 17 | [Secret scanning con gitleaks](labs/17-gitleaks.md) | 4 | 20 | - (defensivo) |
| 18 | [Escaneo con Trivy](labs/18-trivy.md) | 4 | 20 | - (defensivo) |
| 19 | [DAST con OWASP ZAP](labs/19-zap.md) | 4 | 25 | - (defensivo) |

Metodo, mapeo a ATT&CK, plantilla de informe y rubrica:
[`labs/ANEXO-metodo-red-team.md`](labs/ANEXO-metodo-red-team.md).

## Flags

```bash
make flags
```

| Flag | Donde |
|---|---|
| `FLAG{jenkins_anon_script_console}` | `/var/jenkins_home/flag.txt` (lab 07) |
| `FLAG{jenkins_cred_decrypt}` | credencial `prod-deploy-key` en Jenkins (labs 07/08) |
| `FLAG{jenkins_api_token_logs}` | log del job `prod-deploy` (lab 09) |
| `FLAG{jenkins_update_job_rce}` | `/var/jenkins_home/secrets/flag-rce.txt` (lab 10) |
| `FLAG{docker_sock_host_root}` | `/tmp/devops-lab-host-flag.txt` del host (lab 11) |
| `FLAG{ide_extension_backdoor}` | `$HOME/.devops-lab-flag` del host (lab 03) |
| `FLAG{dockerfile_backdoor}` | `/flag.txt` de la imagen webapp (lab 04) |
| `FLAG{gitea_enum_private_repo}` | repo privado `internal-docs` (lab 02) |
| `FLAG{gitea_actions_secret}` | secreto `PROD_KEY` de Gitea Actions (lab 05) |
| `FLAG{aws_s3_lateral}` | `s3://prod-artifacts/flag.txt` (lab 15) |
| `FLAG{cloud_identity_token}` | claim del token de Azure (lab 16) |
| `FLAG{terraform_plan_rce}` | `$HOME/.devops-lab-tf-plan-flag` (lab 12) |
| `FLAG{terraform_apply_rce}` | `$HOME/.devops-lab-tf-apply-flag` (lab 13) |
| `FLAG{terraform_state_backdoor}` | `$HOME/.devops-lab-tf-flag` (lab 14) |

Los flags del host se crean en el arranque y se borran con `make reset`.

## Herramientas

| Comando | Que hace |
|---|---|
| `make up` | construye, arranca y ejecuta `seed/bootstrap.sh` |
| `make down` / `make reset` | para / borra todo (reset pide confirmacion) |
| `make ps` / `make logs` | estado / logs |
| `make urls` / `make flags` | endpoints / valores de los flags |
| `make ci` | re-ejecuta el bootstrap (garantiza runner de Actions) |
| `./tools/tf <args>` | Terraform 1.9 en contenedor, con `$PWD` en `/tf` y `$HOME` en `/hosthome` |
| `./tools/aws <args>` | AWS CLI contra moto (`localhost:4566`) |

Terraform no necesita instalarse en el host; el contenedor usa `--network host`
para que `localhost` sea el del host. En Windows/macOS los labs de red y
`docker.sock` no funcionan igual: usa Linux o una VM.

## Estructura

```
.
├── docker-compose.yml        # gitea, jenkins, registry, moto, hookcat, webapp, runner
├── Makefile
├── .env / .env.example
├── clases/                   # guias docentes de las 4 clases
├── labs/                     # 00-19, guias y soluciones
├── lab/
│   ├── jenkins/              # Dockerfile, plugins, JCasC (jobs y credenciales)
│   ├── webapp/               # app con command injection + IMDS falso
│   ├── hookcat/              # webhook catcher local
│   ├── act_runner/           # config del runner de Gitea Actions
│   └── terraform/            # plan-rce, apply-rce, state (backend S3 en moto)
├── seed/
│   ├── bootstrap.sh          # usuarios, repos, tokens, secretos, flags
│   └── repo/                 # repo devops-demo (Jenkinsfile, workflows, secretos)
└── tools/                    # wrappers de terraform y aws
```

## Notas

- El material teorico viene del curso DO-RTA. Este repo solo
  contiene el laboratorio; no redistribuyas los PDFs.
- Los secretos y credenciales son de laboratorio. No sirven fuera del laboratorio.
- Cada lab incluye una seccion de defensa: ese es el entregable real del curso.
- Problemas de arranque: [`labs/00-setup.md`](labs/00-setup.md#si-algo-falla).
