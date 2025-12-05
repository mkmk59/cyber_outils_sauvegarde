FROM debian:bookworm-slim

RUN mkdir -p /var/data

COPY generate.sh /usr/local/bin/generate.sh

RUN chmod +x /usr/local/bin/generate.sh

CMD [ "/usr/local/bin/generate.sh" ]