# Governance

## Namespace limits

- [ ] Namespaces have LimitRange

- [ ] Namespaces have ResourceQuotas

## Pod security policies

- [ ] Enable Pod Security Policies

- [ ] Disable privileged containers

- [ ] Use a read-only filesystem in containers

- [ ] Prevent containers from running as root

- [ ] Limit capabilities

- [ ] Prevent privilege escalation

## Network policies

- [ ] Enable network policies

- [ ] There's a conservative NetworkPolicy in every namespace

## Role-Based Access Control (RBAC) policies

- [ ] Disable auto-mounting of the default ServiceAccount

- [ ] RBAC policies are set to the least amount of privileges necessary

- [ ] RBAC policies are granular and not shared

## Custom policies

- [ ] Allow deploying containers only from known registries

- [ ] Enforce uniqueness in Ingress hostnames

- [ ] Only use approved domain names in the Ingress hostnames
