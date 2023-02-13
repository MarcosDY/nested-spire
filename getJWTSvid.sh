#!/bin/bash
container=$1
docker-compose exec -u ${container}User ${container}-agent ./bin/spire-agent api fetch jwt -audience $1 -socketPath /opt/spire/sockets/workload_api.sock
