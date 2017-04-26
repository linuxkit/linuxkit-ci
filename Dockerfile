#FROM datakit/ci:latest AS build-env
FROM datakit/ci@sha256:1521fc30ca20eee476c7bb80b3b758e60a38e4ea85a28b17bcb1036bf581af27 AS build-env

ARG CONFIG=dkciCI
ADD . /src
WORKDIR /src
RUN sudo chown opam .
RUN opam config exec make

FROM alpine:3.5
RUN apk update && apk add \
	libev \
	docker \
	py-pip \
	py-setuptools \
	tar \
	tzdata \
	ca-certificates \
	openssl \
	wget \
	bash \
	gmp \
	openssh-client \
	make \
	curl \
	qemu-img \
	qemu-system-x86_64

RUN pip install google-api-python-client
RUN pip install google-cloud-storage

RUN wget https://github.com/docker/notary/releases/download/v0.4.3/notary-Linux-amd64 -O /usr/local/bin/notary
RUN echo '06cd02c4c2e7a3b1ad9899b03b3d4dde5392d964c675247d32f604a24661f839 */usr/local/bin/notary' | sha256sum -w -c -
RUN chmod a+x /usr/local/bin/notary

USER root
ENTRYPOINT ["/usr/local/bin/ci"]
CMD []
ADD run-files/gcloud /gcloud
COPY --from=build-env /src/ci.native /usr/local/bin/ci
