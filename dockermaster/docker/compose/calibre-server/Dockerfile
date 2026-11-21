# Tracks upstream :latest. Production does not use this image: the deployed stack
# pins linuxserver/calibre:v9.17.0-ls430 (terraform/portainer/stacks/calibre.yml).
# The ls430 tag scored worse in CI (7 fixable high findings vs 2 on :latest, after
# apt-get upgrade): older bundled pebble, dnspython and docker CLI plugins.
FROM linuxserver/calibre:latest

LABEL maintainer="local"

# Pull in the Ubuntu security fixes published since the base image was built.
# The previous "apt upgrade" ran in a build stage that was never copied into the
# final image, so it patched nothing.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /config

# rmapi (ddvk) was built in a separate stage and copied in. The stage was never
# enabled; see git history if it is needed again.
