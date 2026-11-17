# Asignable 1 - Superficie, secretos y cadena de suministro

**Cubre:** labs 00 a 09
**Clases:** 1, 2 y la primera parte de la 3
**Tiempo estimado:** 6 h de laboratorio mas 2 h de informe
**Riesgos OWASP CI/CD:** CICD-SEC-2, CICD-SEC-3, CICD-SEC-4, CICD-SEC-6,
CICD-SEC-8, CICD-SEC-9

## Enunciado

Tu equipo acaba de heredar un laboratorio CI/CD local del que no tiene inventario.
Tienes credenciales de desarrollador, un repo con un token filtrado y un Jenkins
expuesto. Tu tarea es convertir ese desorden en un mapa defendible: que superficie
existe, que credenciales la abren y que se puede alcanzar con ellas.

El trabajo termina cuando puedes explicar, con evidencia, como un token de repo
lleva a un secreto de produccion. No basta con capturar flags: cada flag debe
estar acompanado de su comando, su salida y su impacto.

Este asignable continua en el [Asignable 2](ASIGNABLE-2.md), que empieza con el
token que encuentras aqui.

## Pasos

### Fase A. Arranque y mapa (labs 00-01)

| Lab | Que entregas |
|---|---|
| [00 - Preparar el laboratorio](00-setup.md) | `make up` y `make flags` funcionando; versiones de Docker y Compose |
| [01 - El pipeline](01-pipeline.md) | mapa source -> build -> artifact -> deploy con duenos y permisos |

Anota los cuatro servicios y sus puertos. El mapa del lab 01 es el indice del
resto del trabajo: si no sabes donde corre algo, no puedes atacarlo.

### Fase B. El token y el puesto (labs 02-03)

| Lab | Flag | Que demuestra |
|---|---|---|
| [02 - Enumeracion con PAT](02-gitea-enumeration.md) | `gitea_enum_private_repo` | un token personal ve mas que una busqueda publica |
| [03 - Extension maliciosa](03-ide-extension.md) | `ide_extension_backdoor` | el puesto de trabajo es parte de la cadena |

Mide el alcance del token antes de usarlo: repos, permisos y webhooks visibles.
En el lab 03 trabaja solo en el perfil desechable.

### Fase C. El artefacto y la persistencia (labs 04-06)

| Lab | Flag | Que demuestra |
|---|---|---|
| [04 - Dockerfile backdoor](04-dockerfile-backdoor.md) | `dockerfile_backdoor` | cambiar `ENTRYPOINT` deja la app intacta y el artefacto comprometido |
| [05 - Workflow malicioso](05-gitea-actions.md) | `gitea_actions_secret` | quien edita el workflow lee sus secretos |
| [06 - Webhook](06-webhook.md) | sin flag | reconexion continua y persistencia sin sesion |

Guarda el diff del workflow y la peticion recibida en hookcat. Explica por que
borrar el webhook no invalida el token que lo creo.

### Fase D. Jenkins y sus secretos (labs 07-09)

| Lab | Flag | Que demuestra |
|---|---|---|
| [07 - Consola de scripts](07-jenkins-anon-console.md) | `jenkins_anon_script_console`, `jenkins_cred_decrypt` | `unsecured` equivale a shell como root |
| [08 - Exfiltracion desde el Jenkinsfile](08-jenkinsfile-exfil.md) | `jenkins_cred_decrypt` | el pipeline puede robar sus propias credenciales sin `/script` |
| [09 - Token de API en logs](09-jenkins-api-token.md) | `jenkins_api_token_logs` | una credencial valida se convierte en enumeration |

El token del lab 09 es la entrada del Asignable 2. Guardalo en tu cuaderno sin
pegarlo en el informe: referencia la ruta del archivo, no su valor.

## Entrega

Un archivo `entrega-asignable-1.md` con:

1. **Cuaderno de evidencias.** Una fila por lab con hora UTC, comando, salida
   cruda, flag y defensa propuesta. Usa la plantilla del
   [Anexo](ANEXO-metodo-red-team.md), seccion 5.
2. **Dos hallazgos.** Con la plantilla del anexo, seccion 6. Al menos uno debe
   venir de los labs 05, 07 u 08 y llevar su riesgo `CICD-SEC-*`.
3. **Mapa de ataque.** De 6 a 8 lineas: token del lab 02 -> puesto -> artefacto
   -> workflow -> Jenkins -> secreto. Cada flecha nombra la evidencia que la
   sostiene.
4. **Tabla de controles.** Cinco eslabones (puesto, repo, workflow, imagen,
   Jenkins) con una prevencion y una deteccion cada uno.
5. **Cadena de custodia.** Que rastro dejaste en el entorno (webhook, archivos,
   jobs) y como lo limpiaste.

Las salidas crudas van en `evidencias/asignable-1/` y se referencian por nombre.
Prosa maxima: 3 paginas. El resto es evidencia.

## Rubrica (100 puntos)

| Criterio | Puntos | Que se mira |
|---|---|---|
| Ejecucion | 25 | 10 labs recorridos; 7 flags correctos (el 07 da dos y el 08 reusa uno) |
| Explicacion | 25 | Por que el token ve el repo privado, por que rotar no es borrar y por que `ENTRYPOINT` cambio el artefacto |
| Evidencia | 20 | Salidas con fecha, ruta, comando y peticiones reproducibles; sin secretos en claro |
| Impacto | 15 | Consecuencia en terminos de acceso y credenciales, no solo el comando |
| Defensa | 15 | Controles concretos y una regla de deteccion que el lab dispare |

Se aprueba con 70/100 y al menos un hallazgo con defensa verificada. Un flag sin
explicacion no pasa de 25/100.
