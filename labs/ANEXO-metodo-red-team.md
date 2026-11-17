# Anexo - Metodo de red team del curso

Este anexo explica **como se trabaja** cada laboratorio. Los labs ensenan la
tecnica; este documento ensena a convertirla en un hallazgo defendible: alcance,
evidencia, impacto, severidad y remediacion. Sin esto, el curso seria una lista
de trucos.

## 1. Como estudiar cada lab (tres pasadas)

1. **Ejecutar.** Sigue los pasos sin saltarte ninguno. Anota la salida real, no
   la que esperabas.
2. **Explicar.** Responde el *checkpoint* en voz alta o por escrito. Si no
   puedes explicar por que funciona, no lo has aprendido.
3. **Defender.** Escribe el control concreto que rompe la cadena y prueba a
   aplicarlo en el lab (por ejemplo, desactivar `/script` o quitar el socket).

Cada lab tiene la misma estructura: escenario, objetivo, pasos con salida
esperada, evidencia, checkpoint, defensa y errores comunes.

## 2. La cadena de ataque del curso

```
Reconocimiento        Acceso inicial           Ejecucion              Impacto
-----------------     -------------------      -----------------      -----------------
01 pipeline           02 PAT filtrado          04 Dockerfile          11 root del host
02 enumeracion        03 extension IDE          05 workflow CI         14 state backdoor
09 token Jenkins      07 Jenkins anonimo        08 Jenkinsfile         15 S3 / IMDS
                      06 webhook (persist.)     10 update-job RCE      16 tokens cloud
                                                12 plan RCE
                                                13 apply RCE
```

La historia completa, en orden:

1. Encuentras el pipeline y sus piezas (01).
2. Un PAT en un repo publico te da un repo privado (02).
3. Con ese acceso creas persistencia (06) o cambias el CI (05).
4. Si el Jenkins esta expuesto, entras sin credenciales (07) o con un token
   filtrado (09) y ejecutas codigo (10).
5. El runner tiene el socket de Docker: root en el host (11).
6. En IaC, `plan`/`apply` ya ejecutan codigo (12, 13); el state es la via mas
   sigilosa (14).
7. De un RCE en la app pasas a identidad cloud (15, 16) y vuelves al state.
8. Cierras con los controles que habrian detectado cada paso (17-19).

## 3. Mapeo a MITRE ATT&CK

| Tactic | Tecnica | Labs |
|---|---|---|
| Reconnaissance | T1592 Gather Host Information | 01, 02 |
| Initial Access | T1190 Exploit Public-Facing Application | 07, 15 |
| Initial Access | T1195.002 Compromise Software Supply Chain | 03, 04, 05, 08 |
| Execution | T1059 Command and Scripting Interpreter | 04, 10, 12, 13 |
| Persistence | T1546 Event Triggered Execution | 03, 14 |
| Persistence | T1078 Valid Accounts | 06, 09 |
| Privilege Escalation | T1611 Escape to Host | 11 |
| Credential Access | T1552.001 Credentials In Files | 02, 05, 07, 08, 09 |
| Credential Access | T1552.005 Cloud Instance Metadata API | 15, 16 |
| Discovery | T1213 Data from Information Repositories | 02, 06 |
| Lateral Movement | T1078 Valid Accounts | 09, 10 |
| Collection/Exfiltration | T1041 Exfiltration Over C2 Channel | 03, 05, 08, 12, 13 |
| Impact | T1496 Resource Hijacking / T1485 Data Destruction | 11, 14 |

No memorices la tabla: usala para justificar por que un hallazgo importa.

### 3.1 Vocabulario OWASP CI/CD

El marco del curso es el
[OWASP Top 10 CI/CD Security Risks](https://owasp.org/projects/top-10-cicd-security-risks)
(2022). Sirve para **nombrar** el riesgo en el informe, no para memorizar diez
nombres. Cada laboratorio declara su ID principal en el encabezado:

| ID | Riesgo | Laboratorio principal |
|---|---|---|
| CICD-SEC-1 | Insufficient Flow Control Mechanisms | 01, 10 |
| CICD-SEC-2 | Inadequate Identity and Access Management | 02, 07, 15, 16 |
| CICD-SEC-3 | Dependency Chain Abuse | 03, 04, 12 |
| CICD-SEC-4 | Poisoned Pipeline Execution (PPE) | 05, 08, 12, 13 |
| CICD-SEC-5 | Insufficient PBAC (Pipeline-Based Access Controls) | 06, 11, 14, 15 |
| CICD-SEC-6 | Insufficient Credential Hygiene | 02, 09, 17 |
| CICD-SEC-7 | Insecure System Configuration | 07, 11, 19 |
| CICD-SEC-8 | Ungoverned Usage of 3rd Party Services | 03, 18 |
| CICD-SEC-9 | Improper Artifact Integrity Validation | 01, 04, 14, 18 |
| CICD-SEC-10 | Insufficient Logging and Visibility | 06, 17, 19 |

Los casos reales de 2026 se comentan dentro del laboratorio que los ilustra
(CVE-2026-33634 en los labs 05 y 18, CVE-2026-84645 y CVE-2026-33001 en el 10,
CVE-2026-33002 y CVE-2026-117620 en el 07, CVE-2026-40313 en el 09,
CVE-2026-27900 en el 12 y CVE-2026-112407 en el 15). Se citan con fecha y
componente para demostrar que el riesgo ocurre fuera del laboratorio; no son un
indice que haya que recitar. La asignacion ID/lab es docente, no una auditoria
formal.

## 4. Reglas de enfrentamiento (ROE)

Antes de tocar un sistema ajeno:

- **Alcance firmado.** Hosts, URLs, cuentas y ventana de pruebas por escrito.
- **Permiso explicito** para pruebas de denegacion de servicio, exfiltracion y
  acceso a datos. Sin permiso, no se hace.
- **Datos minimos.** Prueba el acceso con un archivo de marca, no con datos de
  clientes. Si encuentras datos reales, paras y lo comunicas.
- **No persistencia no autorizada.** Webhooks, usuarios y backdoors se limpian
  al terminar o se documentan para que el cliente los retire.
- **Canal seguro** para evidencia y secretos; nada de pegarlos en el chat del
  equipo.

En este curso el alcance es `localhost`, pero el habito se entrena aqui.

## 5. Cuaderno de evidencias

Una fila por hallazgo. Ejemplo:

| Campo | Ejemplo |
|---|---|
| Lab | 10 |
| Hora (UTC) | 2026-11-17T03:12:00Z |
| Activo | `lab-jenkins` / `http://localhost:8080` |
| Accion | `POST /job/prod-deploy/config.xml` con step de shell |
| Resultado | RCE como root en el runner |
| Evidencia | `evidencias/lab10-build.log`, captura de `id` |
| Flag | `FLAG{jenkins_update_job_rce}` |
| Impacto | control del nodo de CI y de sus credenciales |
| Defensa | token de solo lectura + egress + job DSL |

Consejos:

- Guarda la **salida cruda** en un archivo y referencia ese archivo; no
  transcribas a mano.
- Anota la **hora** y la **version** de la herramienta (`trivy --version`).
- Redacta secretos: `TOKEN=abc...` no aporta y quema la credencial.
- Para peticiones HTTP guarda metodo, ruta, codigo y cabeceras relevantes.
- Un flag demuestra acceso; la evidencia demuestra **como** y **desde donde**.

## 6. Plantilla de informe

```markdown
# [Titulo: impacto en una frase]

## Resumen ejecutivo
Que se ha conseguido, en que activo y que riesgo tiene para el negocio.
Sin comandos ni jerga. 3-5 lineas.

## Alcance y fecha
Activos probados, ventana, limitaciones.

## Hallazgo
- Severidad: Critica / Alta / Media / Baja
- CVSS (si aplica): vector y puntuacion
- Riesgo OWASP CI/CD: ID y nombre, con la prueba que lo sostiene
- Activo afectado:
- Estado: confirmado / requiere validacion

## Reproduccion
1. Prerrequisitos (acceso, red, credenciales).
2. Pasos exactos con comandos.
3. Resultado observado (salida o captura).
4. Frecuencia (siempre / a veces).

## Impacto
Que puede hacer un atacante con esto: datos, disponibilidad, movimiento
lateral, persistencia. En terminos del negocio, no del comando.

## Causa raiz
Configuracion, permiso o codigo concreto. Un parrafo.

## Remediacion
- Inmediata (contener).
- Definitiva (arreglar la causa).
- Deteccion (que alerta lo habria visto).

## Anexo de evidencia
Archivos, hashes, capturas, peticiones.
```

### Severidad con contexto

Una misma tecnica cambia de severidad segun el activo:

| Situacion | Severidad tipica |
|---|---|
| RCE como root en CI con acceso a produccion | Critica |
| Lectura de un repo privado con datos internos | Alta |
| Token de solo lectura sin datos sensibles | Media/Baja |
| Falta de cabecera de seguridad | Baja/Informativa |

No infles la severidad para "que se arregle". Un informe creible vale mas.

## 7. Rubrica de evaluacion (100 puntos)

| Criterio | Puntos | Que se mira |
|---|---|---|
| Ejecucion | 25 | El lab funciona y el flag es correcto |
| Explicacion | 25 | Entiende por que funciona y que pieza falla |
| Evidencia | 20 | Salidas, fechas, rutas y peticiones reproducibles |
| Impacto | 15 | Describe consecuencias reales, no solo el comando |
| Defensa | 15 | Propone controles concretos y verificables |

Un flag sin explicacion no pasa de 25/100: el objetivo es el criterio, no el
trofeo.

## 8. Ejercicio de defensa (blue team)

Al terminar cada clase, en grupos:

1. Elegir dos hallazgos.
2. Escribir la regla de deteccion (que evento, que campo, que umbral).
3. Comprobar si el lab la dispara.
4. Proponer el cambio de configuracion que hace el ataque imposible, no solo
   detectable.

Ejemplos:

| Ataque | Deteccion | Prevencion |
|---|---|---|
| `/script` anonimo | acceso 200 sin usuario a `/script*` | matrix auth + VPN |
| Workflow modificado | diff en `.gitea/workflows` por usuario no CI | CODEOWNERS + aprobacion |
| `terraform plan` con `external` | provider/`data` nuevo en el diff | OPA/conftest |
| `docker run -v /` desde CI | creacion de contenedor con montaje `/` | no montar el socket |
| Uso de credenciales IMDS | llamada a 169.254.169.254 desde la app | IMDSv2 + network policy |

## 9. Checklist de cierre

- [ ] Todos los flags capturados y asociados a evidencia.
- [ ] Cada hallazgo tiene causa raiz e impacto.
- [ ] Cada hallazgo tiene remediacion inmediata y definitiva.
- [ ] Secretos redactados en el informe.
- [ ] Repo y Jenkins restaurados al estado inicial.
- [ ] Webhooks, usuarios y backdoors de prueba eliminados.
- [ ] `make reset` documentado si el entorno se va a reutilizar.

## 10. Limpieza del laboratorio

```bash
# restaurar repo (si un lab lo modifico)
cd seed/repo && git push -f http://dev:dev12345@localhost:3000/devops-org/devops-demo.git main

# borrar webhooks de prueba
PAT=$(grep GITEA_TOKEN seed/repo/secrets/dev_token.txt | cut -d= -f2)
curl -s -H "Authorization: token $PAT" \
  http://localhost:3000/api/v1/repos/devops-org/devops-demo/hooks

# vaciar hookcat
curl -s http://localhost:8888/__clear

# parar todo
make down
```

`make reset` borra volumenes, flags y el repo sembrado. Usalo solo si vas a
reconstruir el entorno (`make up`).
