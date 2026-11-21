# Same tag as the deployed stack (terraform/portainer/stacks/calibre.yml), so CI
# scans what production runs. Bump both together.
FROM linuxserver/calibre:v9.17.0-ls430

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
