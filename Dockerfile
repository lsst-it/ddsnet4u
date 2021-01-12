FROM alpine:3.12

ARG RUN_SCRIPT='/usr/local/bin/ddsnet4u.sh'

RUN apk add --no-cache --upgrade bash iproute2

COPY ddsnet4u.sh "${RUN_SCRIPT}"
RUN chmod 0755 "${RUN_SCRIPT}"
CMD ["/usr/local/bin/ddsnet4u.sh"]
