SHELL := /bin/bash
COMPOSE := docker compose

.PHONY: help up down reset logs ps urls bootstrap ci flags

help:
	@echo "up        levanta todo y siembra el lab"
	@echo "down      para los contenedores"
	@echo "reset     borra contenedores, volumenes y estado (destructivo)"
	@echo "logs      logs de todos los servicios"
	@echo "urls      URLs y credenciales"
	@echo "ci        garantiza el runner de Gitea Actions"
	@echo "flags     muestra los flags del lab"

.env:
	cp .env.example .env

up: .env
	$(COMPOSE) up -d --build
	./seed/bootstrap.sh

down:
	$(COMPOSE) down

reset:
	@read -r -p "Esto BORRA volumenes y flags. Escribe 'si': " ans; [ "$$ans" = "si" ] || exit 1
	$(COMPOSE) --profile ci down -v
	rm -f /tmp/devops-lab-host-flag.txt "$$HOME/.devops-lab-flag" "$$HOME/.devops-lab-tf-flag" "$$HOME/.devops-lab-tf-apply-flag" "$$HOME/.devops-lab-tf-plan-flag"
	rm -rf seed/repo/.git seed/repo/secrets lab/act_runner/.runner
	@echo "reset ok"

logs:
	$(COMPOSE) logs -f --tail=50

ps:
	$(COMPOSE) ps

urls:
	@echo "Gitea     http://localhost:3000"
	@echo "Jenkins   http://localhost:8080"
	@echo "Registry  http://localhost:5000/v2/_catalog"
	@echo "Hookcat   http://localhost:8888"
	@echo "S3/AWS    http://localhost:4566 (moto)"
	@echo "Webapp    http://localhost:8000"

bootstrap:
	./seed/bootstrap.sh

ci:
	./seed/bootstrap.sh

flags:
	@echo "jenkins anon console : $$(docker exec lab-jenkins cat /var/jenkins_home/flag.txt 2>/dev/null || echo '?')"
	@echo "jenkins rce          : $$(docker exec lab-jenkins cat /var/jenkins_home/secrets/flag-rce.txt 2>/dev/null || echo '?')"
	@echo "webapp               : $$(docker exec lab-webapp cat /flag.txt 2>/dev/null || echo '?')"
	@echo "host (docker.sock)   : $$(cat /tmp/devops-lab-host-flag.txt 2>/dev/null || echo '?')"
	@echo "host (ide extension) : $$(cat $$HOME/.devops-lab-flag 2>/dev/null || echo '?')"
	@echo "host (tf state)      : $$(cat $$HOME/.devops-lab-tf-flag 2>/dev/null || echo '?')"
	@echo "host (tf apply)      : $$(cat $$HOME/.devops-lab-tf-apply-flag 2>/dev/null || echo '?')"
	@echo "host (tf plan)       : $$(cat $$HOME/.devops-lab-tf-plan-flag 2>/dev/null || echo '?')"
