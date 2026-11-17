# Clase 3 - CI/CD: Jenkins expuesto, credenciales y runners

**Duracion:** 3 h · **Modulo:** M4 · **Labs:** 07, 08 (autonomo), 09, 10, 11
**Nivel:** medio

## Resultado esperado

Al terminar la clase el alumno puede entrar en un Jenkins mal configurado,
explicar donde vive una credencial y como se descifra, pasar de un token de API
a ejecucion remota, y demostrar por que montar el socket de Docker en el runner
equivale a root en el host. Sabe ademas que control rompe cada paso.

## Agenda (180 min)

| Min | Bloque | Contenido | Recurso |
|---|---|---|---|
| 0-10 | Apertura | Repaso de la clase 2 y encuadre del CI | este documento |
| 10-50 | Teoria | Arquitectura Jenkins, authn/authz, credenciales, pipeline, agentes | este documento |
| 50-55 | Descanso | | |
| 55-80 | Lab | Consola de scripts anonima y descifrado | `labs/07-jenkins-anon-console.md` |
| 80-100 | Lab | Token de API expuesto y logs | `labs/09-jenkins-api-token.md` |
| 100-130 | Lab | RCE modificando un job | `labs/10-jenkins-update-job-rce.md` |
| 130-150 | Lab | Escape por `docker.sock` | `labs/11-docker-sock-escape.md` |
| 150-170 | Defensa | Controles, deteccion y diseno de agentes | Anexo, secciones 3 y 8 |
| 170-180 | Cierre | Lab 08 autonomo y puente a la clase 4 | este documento |

El lab 08 (exfiltracion desde el `Jenkinsfile`) se explica en teoria y se asigna
como trabajo autonomo: requiere modificar `main` y lanzar un build, y el grupo
suele ir justo de tiempo. Si sobra tiempo, es la mejor demo de "pipeline como
codigo".

## Objetivos de aprendizaje

1. Distinguir autenticacion de autorizacion y reconocer `unsecured`.
2. Localizar y descifrar credenciales de Jenkins desde el propio servidor.
3. Usar un token de API para enumerar, leer logs y reescribir un job.
4. Adaptar un payload a las restricciones reales (XML, shell, red).
5. Explicar Docker-outside-of-Docker y el impacto del socket.
6. Disenar un runner que pueda construir sin controlar el host.

## Teoria

### 1. Arquitectura de Jenkins

```
navegador / API
      |
  controlador  (JENKINS_HOME: jobs, credentials.xml, secrets/)
      |
  agentes / nodos  (ejecutan los builds)
```

- **Controlador**: sirve la UI y la API, guarda configuracion y credenciales,
  programa builds.
- **Agente**: ejecuta los steps. En el laboratorio el controlador y el agente
  son el mismo contenedor, por eso el build ve `/var/jenkins_home`.
- **JENKINS_HOME**: contiene `jobs/*/config.xml`, `credentials.xml` y
  `secrets/master.key` + `secrets/hudson.util.Secret`.

Ese detalle es la clave del curso: el cifrado de credenciales no protege del
atacante que ya ejecuta codigo en el controlador, porque las llaves estan en el
mismo carpeta.

### 2. Autenticacion y autorizacion

| Modo | Efecto | Riesgo |
|---|---|---|
| `unsecured` | sin login y sin permisos | cualquiera es admin |
| matrix | usuarios y permisos por rol | mal configurado deja `/script` abierto |
| SSO / OIDC | identidad centralizada | depende de grupos y mapeo |

La consola de scripts (`/script`, `/scriptText`) ejecuta Groovy con las clases
de Jenkins. Para un no administrador deberia estar cerrada. En `unsecured` es
una shell como el usuario del proceso (root en el lab).

No hace falta `unsecured` para llegar lejos: CVE-2026-33002 (DNS rebinding
contra el WebSocket de la CLI) y CVE-2026-84645 (RCE por `config.xml` anidada)
fueron corregidos en 2026. Se citan en los labs 07 y 10 como ejemplos de
CICD-SEC-2 y CICD-SEC-7; la defensa sigue siendo la misma: autenticar, autorizar
y reducir lo que el proceso del controlador puede tocar.

**CSRF**: Jenkins exige un crumb y la cookie de la sesion que lo emitio. Por eso
`curl` necesita `-c` y `-b`; sin la cookie, el crumb no sirve y la respuesta es
`403` o `500` (lab 07 y lab 10).

### 3. Credenciales y secretos

`credentials.xml` guarda los valores cifrados con `hudson.util.Secret`, que se
deriva de `master.key` y `hudson.util.Secret`. Con esos tres archivos se
descifra fuera de Jenkins. En el lab 07 se hace en caliente con
`hudson.util.Secret.decrypt`; en el lab 08 se roban los tres y se descifra
despues.

Un token de API es una credencial de usuario. Si aparece en un repo, en un log o
en un historial, hay que tratarlo como password: enumerar su alcance, usarlo y
rotarlo.

### 4. Pipeline como codigo

Un `pipelineJob` con `cpsScm` lee el `Jenkinsfile` del repo en cada build. Eso
significa:

- quien puede escribir en la rama construida puede ejecutar codigo en el
  agente,
- el agente tiene el `JENKINS_HOME` y las credenciales a mano,
- un stage nuevo pasa desapercibido si nadie revisa el diff.

El sandbox de Groovy limita algunas APIs, pero no impide lanzar un `sh` ni leer
archivos a los que el proceso tiene acceso.

### 5. Agentes y Docker

| Patron | Como funciona | Riesgo |
|---|---|---|
| Docker-in-Docker | daemon propio dentro del contenedor | requiere privilegios |
| Docker-outside-of-Docker | monta `/var/run/docker.sock` del host | control total del host |
| Runner efimero en VM | se destruye tras el build | bajo, si no hay socket |

Con el socket montado, `docker run -v /:/host` monta el root del host en un
contenedor nuevo. No hace falta un exploit de kernel ni `--privileged`: se usa
la API del daemon, que corre como root. Ese es el lab 11.

### 6. Cadena de ataque de la clase

```
Jenkins expuesto (07)  ->  credenciales descifradas
token filtrado (09)    ->  logs + permisos de escritura
                       ->  update-job (10)  ->  RCE root en el runner
                       ->  docker.sock (11) ->  root en el host
Jenkinsfile (08)       ->  robo de JENKINS_HOME sin tocar la UI
```

## Demo del instructor (15 min)

1. Abrir `/script` en ventana privada y leer `credentials.xml`.
2. Descifrar `prod-deploy-key` en vivo y explicar de donde salen las llaves.
3. Mostrar `/api/json` con el token y el `consoleText` con el flag.
4. Ensenar el `config.xml` del job y senalar donde se inyectaria un step.

No ejecutes la reverse shell en la demo: deja el lab 10 para el alumno y evita
dejar el job modificado.

## Laboratorio

| Lab | Tiempo | Se evalua |
|---|---|---|
| 07 - Consola anonima | 25 min | acceso sin login, descifrado del secreto |
| 09 - Token de API | 20 min | identidad, jobs, log con secreto, permisos |
| 10 - RCE por update-job | 30 min | XML valido, crumb con cookie, shell root |
| 11 - Escape por socket | 20 min | `docker ps` desde el CI, flag del host |
| 08 - Jenkinsfile | autonomo | stage dentro de `stages`, zip exfiltrado |

Aviso para el lab 10: el step corre con `/bin/sh` (dash), que no entiende
`/dev/tcp`. Hay que envolver el payload en `bash -c '...'` y escapar `&` en el
XML. Son los dos errores que mas tiempo hacen perder.

## Preguntas para discusion

1. Por que `unsecured` es peor que "lectura anonima"?
2. Que dos o tres archivos convierten un robo en persistencia?
3. Que control impide el `update-job` aunque el token se filtre?
4. Por que un agente efimero reduce el impacto del socket?
5. Que diferencia hay entre rotar el token y rotar `master.key`?

## Defensa (20 min)

Disenar el Jenkins que querrias tener:

- SSO + matrix, `/script` solo admin, sin acceso desde internet.
- Credenciales por scope, tokens de solo lectura para automatizacion, rotacion.
- Pipelines desde `main` protegido, revision obligatoria del `Jenkinsfile`.
- Agentes efimeros, sin `JENKINS_HOME` compartido y sin socket.
- Egress filtrado; alertas de acceso anonimo a `/script`, cambios de
  `config.xml` y contenedores creados desde el CI.

Ejercicio: mapear tres hallazgos de la clase a una alerta concreta (que evento,
que campo, que umbral).

## Evaluacion

| Criterio | Puntos | Entregable de la clase |
|---|---|---|
| Ejecucion | 25 | labs 07, 09, 10 y 11 con flag |
| Explicacion | 25 | por que el crumb necesita cookie y por que el socket es root |
| Evidencia | 20 | `/script` sin login, secreto descifrado, `id`, flag del host |
| Impacto | 15 | que hereda un atacante que controla el runner |
| Defensa | 15 | diseno de agente y tres alertas |

## Materiales

- `nc` en el host para los labs 10 y 03.
- `unzip` y `python3` para reconstruir el zip del lab 08.
- Job `prod-deploy` sin modificar al empezar; si esta sucio, restaurar el
  `config.xml` original.
- hookcat vacio.

## Errores comunes del instructor

| Sintoma | Causa / arreglo |
|---|---|
| `500` al usar la API | falta la cookie de sesion o el crumb es de otra sesion |
| `403` al actualizar el job | el token no tiene permiso; revisar el usuario |
| XML invalido | escapar `&` con `xml.sax.saxutils.escape` |
| El shell no conecta | usar `host.docker.internal` y `/bin/bash -c` |
| El build no ve los cambios | el job construye `*/main`; commitear en `main` |
| El socket no esta | revisar el volumen en `docker-compose.yml` |

## Limpieza al terminar

- Restaurar `prod-deploy` con el `config.xml` original.
- Restaurar `main` del repo si se hizo el lab 08.
- Vaciar hookcat y cerrar cualquier listener.

## Trabajo autonomo

- Lab 08 completo y descifrado offline de la credencial.
- Lab 03 (si no se hizo en la clase 2).
- Media pagina: "que cambiaria en mi empresa si el runner tuviera el socket?".

## Puente a la clase 4

La clase 3 comprometio el CI. La clase 4 va un nivel mas abajo: la
infraestructura como codigo y la identidad cloud. El mismo runner que hoy
ejecuta un `Jenkinsfile` manana ejecutara un `terraform plan` con permisos de
produccion.
