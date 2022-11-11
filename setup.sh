#!/bin/bash

norm=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true
yellow=$(tput setaf 3) || true
bold=$(tput bold) || true

# TODO: verify what logs to use
timestamp() {
    date -u "+[%Y-%m-%dT%H:%M:%SZ]"
}

log-info() {
    echo "${bold}$(timestamp) $*${norm}"
}

log-warn() {
    echo "${yellow}$(timestamp) $*${norm}"
}

log-success() {
    echo "${green}$(timestamp) $*${norm}"
}

log-debug() {
    echo "${norm}$(timestamp) $*"
}

fail-now() {
    echo "${red}$(timestamp) $*${norm}"
    exit 1
}

docker-up() {
    if [ $# -eq 0 ]; then
        log-debug "bringing up services..."
    else
        log-debug "bringing up $*..."
    fi
    docker-compose up -d "$@" || fail-now "failed to bring up services."
}

fingerprint() {
	# calculate the SHA1 digest of the DER bytes of the certificate using the
	# "coreutils" output format (`-r`) to provide uniform output from
	# `openssl sha1` on macOS and linux.
	openssl x509 -in "$1" -outform DER | openssl sha1 -r | awk '{print $1}'
}

check-synced-entry() {
  # Check at most 30 times (with one second in between) that the agent has
  # successfully synced down the workload entry.
  MAXCHECKS=30
  CHECKINTERVAL=1
  for ((i=1;i<=MAXCHECKS;i++)); do
      log-info "checking for synced entry ($i of $MAXCHECKS max)..."
      docker-compose logs "$1"
      if docker-compose logs "$1" | grep "$2"; then
          return 0
      fi
      sleep "${CHECKINTERVAL}"
  done

  fail-now "timed out waiting for agent to sync down entry"
}



log-debug "Creating shared folders..."
mkdir -p shared/rootSocket
mkdir -p shared/intermediateSocket

log-debug "Creating x509pop certificates"
go run gencerts.go root/server root/agent
go run gencerts.go intermediate/server intermediate/agent
go run gencerts.go leaf/server leaf/agent

log-debug "Starting root-server..."
docker-up root-server

log-debug "Bootstrapping root-agent..."
docker-compose exec -T root-server \
    /opt/spire/bin/spire-server bundle show > root/agent/bootstrap.crt

log-debug "Starting root-agent..."
docker-up root-agent

log-debug "creating intermediate downstream registration entry..."
docker-compose exec -T root-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://domain.test/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
    -spiffeID "spiffe://domain.test/intermediate" \
    -selector "docker:label:org.integration.name:intermediate" \
    -downstream
check-synced-entry "root-agent" "spiffe://domain.test/intermediate"

# log-debug "creating a root workload..."
# docker-compose exec -T root-server \
    # /opt/spire/bin/spire-server entry create \
    # -parentID "spiffe://domain.test/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
    # -spiffeID "spiffe://domain.test/root/workload" \
    # -selector "unix:uid:0"

log-debug "Starting intermediate-server.."
docker-up intermediate-server

log-debug "bootstrapping intermediate agent..."
docker-compose exec -T intermediate-server \
    /opt/spire/bin/spire-server bundle show > intermediate/agent/bootstrap.crt

log-debug "Starting intermediate-agent..."
docker-up intermediate-agent

log-debug "creating leaf downstream registration entry..."
# Create downstream registation entry on intermediate-server for `leaf-server`
docker-compose exec -T intermediate-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://domain.test/spire/agent/x509pop/$(fingerprint intermediate/agent/agent.crt.pem)" \
    -spiffeID "spiffe://domain.test/leaf" \
    -selector "docker:label:org.integration.name:leaf" \
    -downstream

check-synced-entry "intermediate-agent" "spiffe://domain.test/leaf"

log-debug "creating intermediate workload..."
docker-compose exec -T intermediate-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://domain.test/spire/agent/x509pop/$(fingerprint intermediate/agent/agent.crt.pem)" \
    -spiffeID "spiffe://domain.test/intermediate/workload" \
    -selector "unix:uid:0" 

log-debug "Starting leaf-server.."
docker-up leaf-server

log-debug "bootstrapping leaf agent..."
docker-compose exec -T leaf-server \
    /opt/spire/bin/spire-server bundle show > leaf/agent/bootstrap.crt

log-debug "Starting leaf-agent..."
docker-up leaf-agent

# log-debug "creating leaf workload..."
docker-compose exec -T leaf-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://domain.test/spire/agent/x509pop/$(fingerprint leaf/agent/agent.crt.pem)" \
    -spiffeID "spiffe://domain.test/leaf/workload" \
    -selector "unix:uid:0" 
