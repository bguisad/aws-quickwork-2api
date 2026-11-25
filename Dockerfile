FROM --platform=$BUILDPLATFORM golang:1.26.3-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/

ARG TARGETOS=linux
ARG TARGETARCH
ARG VERSION=dev
ARG COMMIT=unknown
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
    -o /out/quickproxy ./cmd/quickproxy

FROM alpine:3.23

ARG VERSION=dev
ARG COMMIT=unknown
LABEL org.opencontainers.image.title="QuickWork / Amazon Quick to OpenAI API" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}" \
      org.opencontainers.image.licenses="GPL-3.0-only"

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -g 10001 quickproxy \
    && adduser -D -H -u 10001 -G quickproxy quickproxy \
    && mkdir -p /app/data \
    && chown quickproxy:quickproxy /app/data

WORKDIR /app

COPY --from=build --chown=10001:10001 /out/quickproxy ./quickproxy

USER 10001:10001

EXPOSE 8080
VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["wget", "-q", "-T", "3", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]

ENTRYPOINT ["/app/quickproxy"]
CMD ["server", "-addr", "0.0.0.0:8080", "-config", "/app/data/config.json"]
