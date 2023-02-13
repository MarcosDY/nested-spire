#!/bin/bash
container=$1
docker-compose exec -u ${container}User ${container}-agent ./bin/spire-agent api fetch x509 -write /tmp -socketPath /opt/spire/sockets/workload_api.sock

echo "Certificate"
docker-compose exec ${container}-agent cat /tmp/svid.0.pem
echo "Bundle"
docker-compose exec ${container}-agent cat /tmp/bundle.0.pem
