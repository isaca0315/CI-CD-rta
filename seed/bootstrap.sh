#!/usr/bin/env bash
# Arranca el estado inicial del lab: usuarios, repos, tokens, secretos y flags.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f .env ] || cp .env.example .env
set -a; . ./.env; set +a

G="http://localhost:${GITEA_PORT:-3000}"
J="http://localhost:${JENKINS_PORT:-8080}"
PORT_G="${GITEA_PORT:-3000}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[!] %s\033[0m\n' "$*" >&2; exit 1; }

jsonval() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(eval("d"+sys.argv[1]))' "$1"; }

wait_url() {
  local url="$1" i
  for i in $(seq 1 90); do
    curl -sf -o /dev/null "$url" && return 0
    sleep 2
  done
  return 1
}

api() { # api METHOD PATH [extra curl args...]
  local method="$1" path="$2"; shift 2
  curl -sf -X "$method" -H "Authorization: token ${ADMIN_TOKEN}" \
       -H 'Content-Type: application/json' "$G/api/v1${path}" "$@"
}

say "Esperando a Gitea"
wait_url "$G/api/healthz" || die "Gitea no responde en $G"

say "Creando usuarios de Gitea"
for spec in \
  "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}:${GITEA_ADMIN_EMAIL}:--admin" \
  "${DEV_USER}:${DEV_PASS}:dev@lab.local:" \
  "${ATTACKER_USER}:${ATTACKER_PASS}:attacker@lab.local:"; do
  IFS=: read -r u p e admin <<<"$spec"
  docker compose exec -T -u git gitea gitea admin user create \
    --username "$u" --password "$p" --email "$e" \
    ${admin} --must-change-password=false >/dev/null 2>&1 \
    && echo "  + $u" || echo "  = $u (ya existe)"
done

say "Token de administracion de Gitea"
ADMIN_TOKEN=$(curl -sf -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"seed-$(date +%s)\",\"scopes\":[\"all\"]}" \
  "$G/api/v1/users/${GITEA_ADMIN_USER}/tokens" | jsonval '["sha1"]') \
  || die "no se pudo crear el token de admin"
[ -n "$ADMIN_TOKEN" ] || die "token de admin vacio"

say "Organizacion y repositorios"
api POST "/admin/users/${GITEA_ADMIN_USER}/orgs" \
  -d '{"username":"devops-org","visibility":"public"}' >/dev/null 2>&1 || true

api POST "/orgs/devops-org/repos" \
  -d '{"name":"devops-demo","private":false,"auto_init":false,"default_branch":"main"}' >/dev/null 2>&1 || true

api POST "/orgs/devops-org/repos" \
  -d '{"name":"internal-docs","private":true,"auto_init":true,"default_branch":"main"}' >/dev/null 2>&1 || true

# Dev es admin del repo principal (puede crear webhooks) y lector del privado
api PUT "/repos/devops-org/devops-demo/collaborators/${DEV_USER}" \
  -d '{"permission":"admin"}' >/dev/null 2>&1 || true
api PUT "/repos/devops-org/internal-docs/collaborators/${DEV_USER}" \
  -d '{"permission":"read"}' >/dev/null 2>&1 || true

say "Buckets S3 locales (moto)"
docker compose exec -T moto python - <<'PY'
from botocore.config import Config
import boto3
s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:5000",
    region_name="us-east-1",
    aws_access_key_id="lab",
    aws_secret_access_key="lab",
    config=Config(s3={"addressing_style": "path"}),
)
for bucket in ("tfstate", "prod-artifacts"):
    try:
        s3.create_bucket(Bucket=bucket)
    except Exception:
        pass
s3.put_object(Bucket="prod-artifacts", Key="flag.txt", Body=b"FLAG{aws_s3_lateral}\n")
print("  + buckets tfstate, prod-artifacts")
PY

say "Flag del repo privado"
FLAG_B64=$(printf 'FLAG{gitea_enum_private_repo}\n' | base64 -w0)
if ! api GET "/repos/devops-org/internal-docs/contents/flag.txt" >/dev/null 2>&1; then
  api POST "/repos/devops-org/internal-docs/contents/flag.txt" \
    -d "{\"content\":\"${FLAG_B64}\",\"message\":\"add flag\",\"branch\":\"main\"}" >/dev/null
  echo "  + internal-docs/flag.txt"
fi

say "Subiendo el repo devops-demo"
if [ ! -d seed/repo/.git ]; then
  git -C seed/repo init -q -b main
fi
git -C seed/repo add -A
git -C seed/repo -c user.name=lab -c user.email=lab@lab.local \
  commit -qm "seed inicial" || true
git -C seed/repo push -q --force \
  "http://${GITEA_ADMIN_USER}:${ADMIN_TOKEN}@localhost:${PORT_G}/devops-org/devops-demo.git" \
  main:main
echo "  + push ok"

say "PAT filtrado del desarrollador (para el lab de enumeracion)"
DEV_TOKEN=$(curl -sf -u "${DEV_USER}:${DEV_PASS}" -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"dev-laptop-$(date +%s)\",\"scopes\":[\"all\"]}" \
  "$G/api/v1/users/${DEV_USER}/tokens" | jsonval '["sha1"]') \
  || die "no se pudo crear el PAT de dev"

mkdir -p seed/repo/secrets
printf '# no deberia estar aqui\nGITEA_TOKEN=%s\n' "$DEV_TOKEN" > seed/repo/secrets/dev_token.txt
echo "  + seed/repo/secrets/dev_token.txt"

say "Esperando a Jenkins (puede tardar 1-2 min la primera vez)"
wait_url "$J/login" || die "Jenkins no responde en $J"

say "Token de API de Jenkins (filtrado en el repo)"
CRUMB=$(curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" \
  -c /tmp/hlab-cookies "$J/crumbIssuer/api/json" | jsonval '["crumb"]') \
  || die "no se pudo obtener el crumb de Jenkins"

JENKINS_TOKEN=$(curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" \
  -b /tmp/hlab-cookies -H "Jenkins-Crumb: ${CRUMB}" -X POST \
  "$J/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken?name=lab-$(date +%s)" \
  | jsonval '["data"]["tokenValue"]') || die "no se pudo generar el token de Jenkins"

printf '# no deberia estar aqui\nJENKINS_USER=%s\nJENKINS_TOKEN=%s\n' \
  "$JENKINS_ADMIN_USER" "$JENKINS_TOKEN" > seed/repo/secrets/jenkins_token.txt
git -C seed/repo add -A
git -C seed/repo -c user.name=lab -c user.email=lab@lab.local commit -qm "add tokens" || true
git -C seed/repo push -q --force \
  "http://${GITEA_ADMIN_USER}:${ADMIN_TOKEN}@localhost:${PORT_G}/devops-org/devops-demo.git" \
  main:main
echo "  + seed/repo/secrets/jenkins_token.txt"

say "Secreto de Gitea Actions"
if api PUT "/repos/devops-org/devops-demo/actions/secrets/PROD_KEY" \
  -d '{"data":"FLAG{gitea_actions_secret}"}' >/dev/null 2>&1; then
  echo "  + PROD_KEY"
else
  warn "no se pudo crear el secreto PROD_KEY (revisa que Actions este habilitado)"
fi

say "Runner de Gitea Actions"
REG_TOKEN=$(api GET "/admin/runners/registration-token" | jsonval '["token"]') || REG_TOKEN=""
if docker compose ps act_runner 2>/dev/null | grep -q " running"; then
  echo "  = runner ya en marcha"
elif [ -n "$REG_TOKEN" ]; then
  RUNNER_TOKEN="$REG_TOKEN" docker compose --profile ci up -d act_runner >/dev/null
  echo "  + runner arrancado"
else
  warn "sin registration token; ejecuta 'make ci' mas tarde"
fi

say "Flags en el host"
echo 'FLAG{docker_sock_host_root}' > /tmp/devops-lab-host-flag.txt
echo 'FLAG{ide_extension_backdoor}' > "$HOME/.devops-lab-flag"
echo 'FLAG{terraform_state_backdoor}' > "$HOME/.devops-lab-tf-flag"
echo 'FLAG{terraform_apply_rce}' > "$HOME/.devops-lab-tf-apply-flag"
echo 'FLAG{terraform_plan_rce}' > "$HOME/.devops-lab-tf-plan-flag"
echo "  + /tmp/devops-lab-host-flag.txt"
echo "  + \$HOME/.devops-lab-flag"
echo "  + \$HOME/.devops-lab-tf-flag"
echo "  + \$HOME/.devops-lab-tf-apply-flag"
echo "  + \$HOME/.devops-lab-tf-plan-flag"

cat <<EOF

────────────────────────────────────────────────────────────
 Lab listo.  Guia: labs/00-setup.md
────────────────────────────────────────────────────────────
 Gitea      ${G}            ${GITEA_ADMIN_USER} / ${GITEA_ADMIN_PASS}
 Jenkins    ${J}            ${JENKINS_ADMIN_USER} / ${JENKINS_ADMIN_PASS}
 Registry   http://localhost:${REGISTRY_PORT:-5000}/v2/_catalog
 Hookcat    http://localhost:${HOOKCAT_PORT:-8888}
 S3 (moto)  http://localhost:${MOTO_PORT:-4566}
 Webapp     http://localhost:${APP_PORT:-8000}
 Dev        ${DEV_USER} / ${DEV_PASS}   (miembro de devops-org)
 Attacker   ${ATTACKER_USER} / ${ATTACKER_PASS}
────────────────────────────────────────────────────────────
EOF
