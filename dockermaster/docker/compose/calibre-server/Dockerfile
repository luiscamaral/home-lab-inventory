FROM linuxserver/calibre:latest AS build

# Install packages needed for compilation of plugins
RUN apt update && \
  apt upgrade -y && \
  apt install git golang-go -y

WORKDIR /opt

# Install go 1.23 (needed for rmapi compilation)
#RUN go install golang.org/dl/go1.23.8@latest && \
#  go1.23.8 download

# Download and compile rmapi (ddvk)
#RUN git clone https://github.com/ddvk/rmapi && \
#  cd rmapi && \
#  go install


FROM linuxserver/calibre:latest

LABEL maintainer="local"

WORKDIR /config

#COPY --from=build /config/go/bin/rmapi /usr/local/sbin/
