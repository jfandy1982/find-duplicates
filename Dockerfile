FROM debian:latest

LABEL name="Find duplicates (using fdupes tooling)"
LABEL author="Andreas Ziegler (dev@andreasziegler.net)"
LABEL version="1.0.0"

# Expose volumes to connect data directories
VOLUME [ "/findup_result", \
	"/findup_config", \
	"/findup_data01", \
	"/findup_data02", \
	"/findup_data03", \
	"/findup_data04", \
	"/findup_data05", \
	"/findup_data06" ]

# install all required packages and updates
RUN apt-get update && \
	apt-get install --no-install-recommends -y apt-utils fdupes && \
	rm -rf /var/lib/apt/lists/*

# Create workspace directory & mark it as working directory
RUN mkdir /home/findup
WORKDIR /home/findup

# Copy scripts into WORKDIR -> changes more often than basic setup
COPY ./scripts/findduplicates.sh ./findduplicates.sh

RUN chmod +x ./findduplicates.sh

ENTRYPOINT [ "./findduplicates.sh" ]
