FROM debian:stable-slim

LABEL name="Find duplicates (using fdupes tooling)"
LABEL author="Andreas Ziegler (dev@andreasziegler.net)"
LABEL version="1.0.0"

VOLUME [ "/findup_result", \
	"/findup_config", \
	"/findup_data01", \
	"/findup_data02", \
	"/findup_data03", \
	"/findup_data04", \
	"/findup_data05", \
	"/findup_data06", \
	"/findup_data07", \
	"/findup_data08", \
	"/findup_data09", \
	"/findup_data10" ]

RUN apt-get update && \
	apt-get install --no-install-recommends -y fdupes coreutils findutils sed grep mawk && \
	rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* /usr/share/locale/* /var/cache/apt/*

RUN mkdir /home/findup
WORKDIR /home/findup

COPY ./scripts/findduplicates.sh ./findduplicates.sh

RUN chmod +x ./findduplicates.sh

ENTRYPOINT [ "./findduplicates.sh" ]
