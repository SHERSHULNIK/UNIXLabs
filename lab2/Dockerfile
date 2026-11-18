FROM alpine:3.22
RUN apk add --no-cache flock
COPY --chmod=755 main.sh /usr/local/bin/main.sh
RUN mkdir -p /shared
ENTRYPOINT ["/usr/local/bin/main.sh"]
