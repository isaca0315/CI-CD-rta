# Clase 1 - Modelo DevOps y cadena de ataque

**Duracion:** 3 h · **Modulos:** M1 + M2 · **Labs:** 00 (previo), 01
**Nivel:** medio (Linux y Docker ya conocidos)

**Material de la clase:** [PPT](01-modelo-devops.pptx)

## Resultado esperado

Al terminar la clase el alumno puede dibujar de memoria el recorrido de un
commit hasta produccion, nombrar que identidad y que secreto usa cada fase, y
explicar por que el runner de CI es el activo mas valioso de la cadena. Sin esa
comprension, los labs de las clases 2-4 son trucos sueltos.

## Agenda (180 min)

| Min | Bloque | Contenido | Recurso |
|---|---|---|---|
| 0-10 | Apertura | Encuadre del curso, alcance (`localhost`), reglas y cuaderno de evidencias | `labs/00-setup.md` |
| 10-50 | Teoria | Modelo DevOps, pipeline, cadena de suministro, OWASP CI/CD y modelo de amenaza | este documento / PPT |
| 50-55 | Descanso | | |
| 55-75 | Demo guiada | Un build real y el inventario de privilegios del runner | `labs/01-pipeline.md` pasos 1-4 y 6 |
| 75-120 | Laboratorio | El pipeline de punta a punta y el cambio que altera el artefacto | `labs/01-pipeline.md` |
| 120-150 | Defensa | Mapa de confianza, controles por fase, ejercicio de deteccion | Anexo, secciones 2 y 8 |
| 150-170 | Puesta en comun | Checkpoints, evidencia minima, primer borrador de informe | Anexo, secciones 5 y 6 |
| 170-180 | Cierre | Que se lleva a la clase 2 y trabajo autonomo | este documento |

**Antes de la clase:** `make up` y `make flags` hechos por el instructor. El
alumno puede ejecutar `labs/00-setup.md` como tarea previa; si no, los primeros
10 minutos se usan para comprobar el stack.

## Objetivos de aprendizaje

1. Describir las fases de un pipeline y que produce cada una.
2. Identificar, en un pipeline concreto, las credenciales y permisos de cada
   componente.
3. Explicar por que un cambio en el repo termina ejecutandose en produccion.
4. Distinguir vulnerabilidad de configuracion, de codigo y de cadena de
   suministro.
5. Escribir la primera fila del cuaderno de evidencias con metodo.
6. Asociar cada fase del pipeline con un riesgo del OWASP Top 10 CI/CD.

## Teoria

### 1. Que resuelve DevOps (y que introduce)

DevOps es una forma de organizar el trabajo para reducir el tiempo entre un
cambio y su valor en produccion, con automatizacion y feedback. No es una
herramienta. El flujo canonico:

```
plan -> code -> build -> test -> release -> deploy -> operate -> monitor
```

Cada flecha es una frontera de confianza: algo o alguien decide que pasa a la
siguiente fase. Un pipeline automatizado sustituye decisiones humanas por
credenciales. Esa es la ganancia operativa y, a la vez, la superficie de ataque.

### 2. El pipeline, en concreto

| Fase | Que ocurre | Identidad tipica | Secreto |
|---|---|---|---|
| Source | El runner hace checkout del repo | token de SCM o deploy key | PAT, SSH key |
| Build | Se compila y se construye la imagen | runner / agente | credenciales de registry |
| Test | Se ejecutan tests y analisis | runner | a veces nada |
| Artifact | La imagen se publica con un tag | robot de CI | registry creds |
| Deploy | Se aplica a produccion | cuenta de despliegue | cloud key, kubeconfig |
| Runtime | La app corre y habla con otros servicios | rol de instancia / service account | credenciales temporales |

En el laboratorio: Gitea (source), Jenkins (build y deploy), `registry:2`
(artifact), `moto` (S3/STS/IAM) y `webapp` (runtime). Cada sustituto conserva la
forma del original: la API, el flujo y el fallo.

### 3. Cadena de suministro

El artefacto final no es solo tu codigo. Es la union de:

- codigo propio y sus dependencias (npm, pip, go modules),
- imagen base y sus paquetes,
- plugins y acciones de CI,
- providers y modulos de Terraform,
- configuracion y secretos inyectados en el build.

Si controlas cualquiera de esas entradas, controlas el artefacto aunque no
toques la aplicacion. Los labs 03, 04, 05 y 14 son variantes de esta idea.

### 4. Por que el CI es el objetivo

Un runner de CI reune cuatro propiedades que rara vez coinciden:

1. **Privilegios**: tokens de SCM, registry, cloud y a veces el socket de Docker.
2. **Ejecucion de codigo de terceros**: cada dependencia, plugin o workflow.
3. **Posicion de red**: habla con el SCM, el registry, el cloud y produccion.
4. **Confianza**: lo que produce se despliega sin que nadie lo mire.

Comprometer el CI no es "hackear una herramienta": es heredar la identidad de
la empresa en su cadena de entrega.

### 5. Modelo de amenaza del curso

| Actor | Acceso inicial | Objetivo | Labs |
|---|---|---|---|
| Externo | app expuesta o Jenkins sin auth | ejecucion, credenciales | 07, 10, 15 |
| Desarrollador comprometido | push en repo, PAT | alterar artefacto, secretos | 02, 04, 05, 08 |
| Proveedor o dependencia | extension, imagen, provider | persistencia, exfiltracion | 03, 14 |
| Cloud | escritura en bucket o token | RCE en el pipeline | 14, 15, 16 |

El curso recorre los cuatro. La defensa no es "bloquear al atacante" sino
reducir lo que cada uno gana si entra.

### 6. Confianza, no solo permisos

La pregunta que ordena todo el curso:

> Quien puede cambiar algo que luego se ejecuta con mas privilegios de los que
> tiene?

Si un desarrollador puede editar el `Jenkinsfile`, ejecuta codigo en el runner.
Si un workflow lee un secreto, quien edita el workflow lee el secreto. Si un
bucket de state es escribible, quien escribe ahi ejecuta en el siguiente plan.
Los labs lo demuestran uno por uno.

### 7. OWASP Top 10 CI/CD Security Risks

El marco de referencia del curso es el
[OWASP Top 10 CI/CD Security Risks](https://owasp.org/projects/top-10-cicd-security-risks)
(2022). Se usa como vocabulario para el informe, no como lista para memorizar:

| ID | Riesgo | Donde aparece |
|---|---|---|
| CICD-SEC-1 | Insufficient Flow Control Mechanisms | labs 01, 10 |
| CICD-SEC-2 | Inadequate Identity and Access Management | labs 02, 07, 15, 16 |
| CICD-SEC-3 | Dependency Chain Abuse | labs 03, 04, 12 |
| CICD-SEC-4 | Poisoned Pipeline Execution (PPE) | labs 05, 08, 12, 13 |
| CICD-SEC-5 | Insufficient PBAC (Pipeline-Based Access Controls) | labs 06, 11, 14, 15 |
| CICD-SEC-6 | Insufficient Credential Hygiene | labs 02, 09, 17 |
| CICD-SEC-7 | Insecure System Configuration | labs 07, 11, 19 |
| CICD-SEC-8 | Ungoverned Usage of 3rd Party Services | labs 03, 18 |
| CICD-SEC-9 | Improper Artifact Integrity Validation | labs 01, 04, 14, 18 |
| CICD-SEC-10 | Insufficient Logging and Visibility | labs 06, 17, 19 |

La asignacion riesgo/lab es una ayuda docente, no una auditoria formal. En la
clase 1 solo se introducen los IDs; cada riesgo se desarrolla en su laboratorio.

Para que no parezca teoria: en 2026 hubo secuestro de tags de acciones de
terceros usadas en CI (CVE-2026-33634, CICD-SEC-8) y RCE en un controlador
Jenkins (CVE-2026-84645, CICD-SEC-7). Se comentan con fecha y componente en los
labs 18 y 10. No se piden de memoria; se usan como ejemplo de que el riesgo es
real.

## Demo del instructor (20 min)

1. Enumerar sin explotar: puertos, `Jenkins/api/json`, repos de Gitea y
   `_catalog`. Misma tecnica de enumeracion, resuelta aqui en localhost.
2. Lanzar `build-and-push` desde la UI y seguir la consola en vivo.
3. Mostrar el artefacto en el registry con `_catalog` y `tags/list`.
4. Hacer un cambio trivial y reconstruir: el tag cambia, el contenido no es
   inmutable.
5. Dentro del runner: `ls /var/jenkins_home/credentials.xml`, comprobar el
   socket de Docker y leer la tabla de privilegios.
6. Cerrar con la pregunta: "que haria falta para que este build fuera de
   confianza?" (respuesta: proteger el codigo, aislar el runner, firmar y
   desplegar por digest).

## Laboratorio

| Lab | Tiempo | Se evalua |
|---|---|---|
| 01 - El pipeline | 45 min | enumerar, ejecutar, leer la consola, mapear credenciales, explicar el cambio de artefacto |

`labs/01-pipeline.md` incluye el comando de build por API, que es el mismo que
usara un atacante con un token en el lab 09.

## Preguntas para discusion

1. Que fase tiene mas privilegios y por que no se suele revisar?
2. Que diferencia hay entre autenticar y autorizar en un pipeline?
3. Si el tag de la imagen es `1`, `2`, `3`, que garantiza ese identificador?
4. Quien puede cambiar el `Jenkinsfile` en tu empresa? Y el workflow?
5. Que evidencia guardarias para demostrar que un artefacto concreto salio de
   un commit concreto?

## Defensa (30 min)

Ejercicio en grupos sobre el mapa del pipeline:

- Marcar las fronteras de confianza y quien cruza cada una.
- Elegir tres controles y justificar coste/beneficio:
  branch protection + revision, agente efimero, despliegue por digest, firma de
  imagen, rotacion de credenciales, egress filtrado.
- Escribir una regla de deteccion por control (que evento, que campo, que
  umbral).
- Nombrar el ID `CICD-SEC` que cubre cada control elegido.

Cierre: en el anexo, seccion 8, hay ejemplos de deteccion y prevencion por
ataque.

## Evaluacion

| Criterio | Puntos | Entregable de la clase |
|---|---|---|
| Ejecucion | 25 | build `SUCCESS` y artefacto visible |
| Explicacion | 25 | checkpoint de `labs/01-pipeline.md` respondido |
| Evidencia | 20 | log del build, `_catalog`, `tags/list`, peticion a hookcat |
| Impacto | 15 | que permite un push malicioso en produccion |
| Defensa | 15 | tres controles concretos y una regla de deteccion |

## Materiales

- Stack arriba y flags verificados.
- Pizarra o diagrama para el mapa de confianza.
- `labs/01-pipeline.md`, `labs/ANEXO-metodo-red-team.md`.
- Cuaderno de evidencias creado (`~/do-rta-evidence`).

## Errores comunes del instructor

| Sintoma | Causa / arreglo |
|---|---|
| El build falla en el primer intento | Jenkins aun instala plugins; esperar y reintentar |
| El tag no aparece | el build no termino; mirar `consoleText` |
| Alumno bloqueado en el setup | usar `make flags` para saber que falta y `make ci` |
| Se adelanta teoria de Jenkins | evitar: la clase 3 tiene su propio marco |

## Trabajo autonomo

- Repetir el lab 01 desde cero y anotar cada credencial usada.
- Leer el anexo, secciones 2 y 3 (kill chain y ATT&CK).
- Escribir media pagina: "por que el runner es una identidad privilegiada".

## Puente a la clase 2

La clase 1 mostro el flujo. La clase 2 empieza por el eslabon mas blando:
el puesto del desarrollador y el repo. El alumno vera que no hace falta tocar
Jenkins para cambiar lo que se despliega.
