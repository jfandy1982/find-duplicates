FROM debian:stretch

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
	"/findup_data05" ]

# install all required packages and updates
RUN apt-get update && \
	apt-get install -y apt-utils fdupes && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# Create workspace directory & mark it as working directory
RUN mkdir /home/findup
WORKDIR /home/findup

# Copy scripts into WORKDIR -> changes more often than basic setup
COPY ./scripts/*.sh ./

RUN chmod +x *.sh

ENTRYPOINT [ "./findduplicates.sh" ]
