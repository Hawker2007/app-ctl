# app-ctl

Usage: app-ctl.sh start|status appName|all

Prepare test env: app-ctl.sh prepare-env

# Asumptions
1. Database contains valid/sample data and dont have circular dependencies (for ex: a->b , b->a )
2. required utills are present in PATH
