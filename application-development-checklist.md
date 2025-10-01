# Application development

## Health checks

- [ ] Containers have Readiness probes

- [ ] Containers crash when there's a fatal error

- [ ] Configure a passive Liveness probe

- [ ] Liveness probes values aren't the same as the Readiness

## Apps are independent

- [ ] The Readiness probes are independent

- [ ] The app retries connecting to dependent services

## Graceful shutdown

- [ ] The app doesn't shut down on SIGTERM, but it gracefully terminates connections

- [ ] The app still processes incoming requests in the grace period

- [ ] The CMD in the `Dockerfile` forwards the SIGTERM to the process

- [ ] Close all idle keep-alive sockets

## Fault tolerance

- [ ] Run more than one replica for your Deployment

- [ ] Avoid Pods being placed into a single node

- [ ] Set Pod disruption budgets

## Resources utilisation

- [ ] Set memory limits and requests for all containers

- [ ] Set CPU request to 1 CPU or below

- [ ] Disable CPU limits — unless you have a good use case

- [ ] The namespace has a LimitRange

- [ ] Set an appropriate Quality of Service (QoS) for Pods

## Tagging resources

- [ ] Resources have technical labels defined

- [ ] Resources have business labels defined

- [ ] Resources have security labels defined

## Logging

- [ ] The application logs to `stdout` and `stderr`

- [ ] Avoid sidecars for logging (if you can)

## Scaling

- [ ] Containers do not store any state in their local filesystem

- [ ] Use the Horizontal Pod Autoscaler for apps with variable usage patterns

- [ ] Don't use the Vertical Pod Autoscaler while it's still in beta

- [ ] Use the Cluster Autoscaler if you have highly varying workloads

## Configuration and secrets

- [ ] Externalise all configuration

- [ ] Mount Secrets as volumes, not enviroment variables

## Stateful applications

- [ ] The state in managed outside Kubernetes (when possible)

- [ ] There are no StatefulSets, but Operators

- [ ] You are using `local` instead of `hostPath` volumes

- [ ] Use StorageClasses with the WaitForFirstConsumer binding mode

- [ ] Use volumes that are provisioned through the Container Storage Interface (CSI)

- [ ] Define a `default` StorageClass

- [ ] Stateful workloads are scheduled on dedicated Nodes

