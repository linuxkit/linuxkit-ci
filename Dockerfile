#FROM datakit/ci:latest AS build-env
FROM datakit/ci@sha256:daecb5fa1e017c39323d39bebfc0e6f94762452f46c29aafe115e7270166d692 AS build-env

ARG CONFIG=dkciCI
ADD . /src
WORKDIR /src
RUN sudo chown -R opam /src
RUN opam config exec make

FROM alpine:3.5
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

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
	expect \
	qemu-img \
	qemu-system-x86_64

RUN pip install google-api-python-client
RUN pip install google-cloud-storage
RUN pip install oauth2client

RUN wget https://github.com/docker/notary/releases/download/v0.4.3/notary-Linux-amd64 -O /usr/local/bin/notary
RUN echo '06cd02c4c2e7a3b1ad9899b03b3d4dde5392d964c675247d32f604a24661f839 */usr/local/bin/notary' | sha256sum -w -c -
RUN chmod a+x /usr/local/bin/notary

USER root
ENTRYPOINT ["/usr/local/bin/ci"]
CMD []
ADD run-files/gcloud /gcloud
COPY --from=build-env /src/_build/default/src/ci.exe /usr/local/bin/ci
