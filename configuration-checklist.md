# Cluster configuration

## Approved Kubernetes configuration

- [ ] The cluster passes the CIS benchmark

- [ ] Disable metadata cloud providers metada API

- [ ] Restrict access to alpha or beta features

## Authentication

- [ ] Use OpenID (OIDC) tokens as a user authentication strategy

## Role-Based Access Control (RBAC)

- [ ] ServiceAccount tokens are for applications and controllers **only**

## Logging setup

- [ ] There's a retention and archival strategy for logs

- [ ] Logs are collected from Nodes, Control Plane, Auditing

- [ ] Prefer a daemon on each node to collect the logs instead of sidecars

- [ ] Provision a log aggregation tool
