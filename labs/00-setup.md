# 00 - Preparar el laboratorio y el cuaderno de evidencias

**Clase 1 · 25 min · Preparacion**
**Fase:** montaje del entorno (no es ataque, es el campo de tiro)

## Escenario

Eres el miembro de red team de una empresa. Te han dado un entorno de practicas
que reproduce su cadena DevOps: Gitea, Jenkins, un registry, un backend S3 y una
app interna. Todo corre en tu maquina, en `localhost`. El objetivo del curso es
recorrer esa cadena como lo haria un atacante real y aprender a defenderla.

Antes de atacar nada necesitas tres cosas: el entorno arriba, un mapa de lo que
hay y un sitio donde ir apuntando lo que encuentras. Sin cuaderno no hay
informe, y sin informe no hay hallazgo.

## Reglas del juego

- Todo es local y deliberadamente vulnerable. **No lo expongas a una red** ni lo
  levantes en un laptop de empresa.
- Las credenciales y flags son de laboratorio. No sirven fuera del laboratorio.
- Cada comando que ejecutes debe quedar en tu cuaderno. Un flag sin evidencia
  no cuenta como hallazgo.
- Trabaja siempre contra `localhost`. Si un lab te pide otro host, lee por que
  antes de ejecutarlo.

## Paso 1 - Arrancar el stack

```bash
cd devops-redteam
make up
```

La primera vez tarda varios minutos: descarga imagenes, compila Jenkins e
instala plugins. Al final imprime las URLs y las credenciales.

**Que debe pasar:** el comando termina sin errores y muestra el bloque
`Lab listo` con las URLs.

## Paso 2 - Comprobar que cada servicio responde

```bash
curl -s http://localhost:3000/api/healthz
curl -s -o /dev/null -w 'jenkins %{http_code}\n' http://localhost:8080/login
curl -s -o /dev/null -w 'registry %{http_code}\n' http://localhost:5000/v2/
curl -s -o /dev/null -w 'hookcat %{http_code}\n' http://localhost:8888/
curl -s -o /dev/null -w 'moto %{http_code}\n' http://localhost:4566/
curl -s http://localhost:8000/health
```

**Que demuestra:** Gitea devuelve `"status": "pass"`, el resto `200` y la app
`{"ok":true}`. Si alguno falla, no sigas: mira `make logs`.

## Paso 3 - Confirmar que los flags existen

```bash
make flags
```

Salida esperada (ocho flags):

```
jenkins anon console : FLAG{jenkins_anon_script_console}
jenkins rce          : FLAG{jenkins_update_job_rce}
webapp               : FLAG{dockerfile_backdoor}
host (docker.sock)   : FLAG{docker_sock_host_root}
host (ide extension) : FLAG{ide_extension_backdoor}
host (tf state)      : FLAG{terraform_state_backdoor}
host (tf apply)      : FLAG{terraform_apply_rce}
host (tf plan)       : FLAG{terraform_plan_rce}
```

**Por que importa:** si falta uno, el lab correspondiente fallara. `make ci`
re-siembra usuarios, repos y secretos; `make reset && make up` reconstruye todo.

## Paso 4 - Mapa del entorno

| Sustituye a | Servicio local | URL | Credenciales |
|---|---|---|---|
| GitHub | Gitea | http://localhost:3000 | `gitea_admin` / `gitea_admin123` |
| GitHub Actions | Gitea Actions + runner | misma UI | runner automatico |
| Jenkins | Jenkins LTS | http://localhost:8080 | `devops` / `devops123` |
| ECR | registry:2 | http://localhost:5000 | sin auth |
| S3 / STS / IAM | moto | http://localhost:4566 | cualquiera (`lab`/`lab`) |
| webhook.site | hookcat | http://localhost:8888 | - |
| app victima + IMDS | webapp | http://localhost:8000 | - |

Usuarios de Gitea:

| Usuario | Password | Rol |
|---|---|---|
| `dev` | `dev12345` | admin de `devops-org/devops-demo`, lector de `internal-docs` |
| `attacker` | `attacker123` | sin permisos: punto de partida del atacante |

## Paso 5 - Crear el cuaderno de evidencias

```bash
mkdir -p ~/do-rta-evidence
cat > ~/do-rta-evidence/README.md <<'EOF'
# Cuaderno de evidencias DO-RTA

| Lab | Hora | Comando | Resultado | Flag | Defensa propuesta |
|-----|------|---------|-----------|------|-------------------|
EOF
```

Durante el curso anota una fila por hallazgo. En el anexo
[`ANEXO-metodo-red-team.md`](ANEXO-metodo-red-team.md) tienes la plantilla de
informe y el mapeo de cada lab a la kill chain.

## Evidencia para el informe

- `make flags` completo (captura o salida).
- `docker compose ps` con los siete servicios `running`.
- Version de las piezas: `docker --version`, `docker compose version`,
  `git --version`.
- Hora de inicio del entorno (`date -Is`).

## Checkpoint

1. Que diferencia hay entre `make down`, `make reset` y `make up`?
2. Por que el laboratorio no debe estar accesible desde la red?
3. Que flag falta si `make flags` imprime `?` en una linea?

## Defensa

Este entorno es un ejemplo de lo que **no** se despliega: Jenkins sin auth,
socket de Docker montado, secretos en repos, IMDS alcanzable desde la app. En
la ultima clase veras como detectar cada una de esas piezas.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| Jenkins no carga a los 2 min | primer arranque instala plugins: `docker logs -f lab-jenkins` |
| Un servicio en `Exit` | `docker compose logs <servicio>`; suele ser un puerto ocupado |
| Runner de Actions en Offline | `make ci`; revisa `docker logs lab-act-runner` |
| `docker: command not found` dentro de Jenkins | reconstruye: `docker compose build jenkins` |
| Gitea no tiene usuarios | `./seed/bootstrap.sh` (o `make ci`) |
| Quiero empezar de cero | `make reset && make up` (borra volumenes y flags) |
