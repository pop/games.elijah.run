GIT := git
DOCKER := podman

DOCKER_INSTALLED := $(podman --version)
ifdef DOCKER_INSTALLED
	ZOLA := $(DOCKER) run --rm -v $(shell pwd):/app:Z --workdir /app -p 8080:8080 ghcr.io/getzola/zola:v0.18.0
else
	ZOLA := zola
endif

init:
	$(GIT) submodule update --init

build: check
	$(ZOLA) build

check:
	$(ZOLA) check

serve:
	$(ZOLA) serve --interface 127.0.0.1 --port 8080 --base-url localhost
