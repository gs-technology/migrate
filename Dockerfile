FROM golang:1.19-alpine3.16 AS builder
ARG VERSION
RUN apk add --no-cache git gcc musl-dev make
WORKDIR /go/src/github.com/golang-migrate/migrate
ENV GO111MODULE=on
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN make build-docker

FROM alpine:3.16
RUN apk add --no-cache bash curl jq ca-certificates
COPY --from=builder /go/src/github.com/golang-migrate/migrate/build/migrate.linux-386 /usr/local/bin/migrate
ADD migration.sh /migration.sh
RUN wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.9/grpcurl_1.8.9_linux_x86_64.tar.gz
RUN tar zxvf grpcurl_1.8.9_linux_x86_64.tar.gz && rm -rf grpcurl_1.8.9_linux_x86_64.tar.gz
RUN mv grpcurl /usr/bin/ && chmod a+x /usr/bin/grpcurl
ENV confsrvDomain="confsrv:9090"
RUN chmod a+x /migration.sh
ENTRYPOINT ["/migration.sh"]
