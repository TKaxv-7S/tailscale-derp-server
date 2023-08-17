FROM golang:latest AS builder

WORKDIR /app

ADD tailscale /app/tailscale

RUN cd /app/tailscale/cmd/derper && \
    CGO_ENABLED=0 /usr/local/go/bin/go build -buildvcs=false -ldflags "-s -w" -o /app/derper && \
    cd /app && \
    rm -rf /app/tailscale

#FROM bitnami/minideb:bookworm
#FROM debian:bookworm-slim
FROM alpine:3.16
WORKDIR /app

# ========= CONFIG =========
# - derper args
ENV DERP_ADDR :443
ENV DERP_HTTP_PORT 80
ENV DERP_STUN_PORT 3478
ENV DERP_HOST=127.0.0.1
ENV DERP_CERTS=/app/certs/
ENV DERP_STUN true
ENV DERP_VERIFY_CLIENTS false
# ==========================

#RUN apt-get update && apt-get install -y openssl curl
RUN apk add --no-cache ca-certificates iptables iproute2 ip6tables openssl curl

RUN { \
    echo '#!/bin/bash'; \
    echo; \
    echo 'CERT_HOST=$1'; \
    echo 'CERT_DIR=$2'; \
    echo 'CONF_FILE=$3'; \
    echo; \
    echo 'if [ -f "$CERT_DIR/$CERT_HOST.key" ] && [ -f "$CERT_DIR/$CERT_HOST.crt" ]; then'; \
    echo '  exit 0;'; \
    echo 'fi'; \
    echo 'echo "[req]'; \
    echo 'default_bits  = 2048'; \
    echo 'distinguished_name = req_distinguished_name'; \
    echo 'req_extensions = req_ext'; \
    echo 'x509_extensions = v3_req'; \
    echo 'prompt = no'; \
    echo; \
    echo '[req_distinguished_name]'; \
    echo 'countryName = XX'; \
    echo 'stateOrProvinceName = N/A'; \
    echo 'localityName = N/A'; \
    echo 'organizationName = Self-signed certificate'; \
    echo 'commonName = $CERT_HOST: Self-signed certificate'; \
    echo; \
    echo '[req_ext]'; \
    echo 'subjectAltName = @alt_names'; \
    echo; \
    echo '[v3_req]'; \
    echo 'subjectAltName = @alt_names'; \
    echo; \
    echo '[alt_names]'; \
    echo 'IP.1 = $CERT_HOST'; \
    echo '" > "$CONF_FILE"'; \
    echo; \
    echo 'mkdir -p "$CERT_DIR"'; \
    echo 'openssl req -x509 -nodes -days 730 -newkey rsa:2048 -keyout "$CERT_DIR/$CERT_HOST.key" -out "$CERT_DIR/$CERT_HOST.crt" -config "$CONF_FILE"'; \
    } | tee /app/build_cert.sh; \
    chmod +x /app/build_cert.sh;

COPY --from=builder /app/derper /app/derper

CMD sh /app/build_cert.sh $DERP_HOST $DERP_CERTS /app/san.conf && \
    /app/derper --hostname=$DERP_HOST \
    --certmode=manual \
    --certdir=$DERP_CERTS \
    --stun=$DERP_STUN \
    --a=$DERP_ADDR \
    --http-port=$DERP_HTTP_PORT \
    --stun-port=$DERP_STUN_PORT \
    --verify-clients=$DERP_VERIFY_CLIENTS