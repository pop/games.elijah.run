GIT := git
DOCKER := podman
USER := $(shell id -u)
GROUP := $(shell id -g)
PWD := $(shell pwd)
OPTS := --userns=keep-id

init:
	$(GIT) submodule init

build: check
	$(DOCKER) run --rm $(OPTS) -v $(PWD):/app:Z --workdir /app ghcr.io/getzola/zola:v0.17.1 build

check:
	$(DOCKER) run --rm $(OPTS) -v $(PWD):/app:Z --workdir /app ghcr.io/getzola/zola:v0.18.0 check

serve:
	$(DOCKER) run --rm $(OPTS) -v $(PWD):/app:Z --workdir /app -p 8080:8080 ghcr.io/getzola/zola:v0.18.0 serve --interface 0.0.0.0 --port 8080 --base-url localhost
