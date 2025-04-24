FROM ubuntu:20.04
RUN apt-get update && apt-get install -y build-essential git flex libewf-dev libssl-dev
RUN git clone --recursive https://github.com/simsong/bulk_extractor.git /bulk_extractor
WORKDIR /bulk_extractor
RUN ./configure && make && make install
