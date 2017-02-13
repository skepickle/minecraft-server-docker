NS = skepickle
VERSION ?= latest

REPO = minecraft-server-docker
NAME = minecraft-server
INSTANCE = default

PORTS = -p 25565:25565/tcp
VOLUMES = -v $(shell pwd)/mc_data:/mc_data
ifeq ("${I_ACCEPT_MINECRAFT_EULA}","yes")
MC_ENV = -e I_ACCEPT_MINECRAFT_EULA=yes
endif
ifeq ("${I_ACCEPT_ORACLE_JAVA_LICENSE}","yes")
OJ_ENV = -e I_ACCEPT_ORACLE_JAVA_LICENSE=yes
endif
ENV = -e LOCAL_USER_ID=$(shell id -u ${USER}) ${MC_ENV} ${OJ_ENV}

.PHONY: build push shell run start attach logs stop rm release default

build:
	docker build -t $(NS)/$(REPO):$(VERSION) .

push:
	docker push $(NS)/$(REPO):$(VERSION)

shell:
	docker run           --name $(NAME)-$(INSTANCE) -i -t $(PORTS) $(VOLUMES) $(ENV) $(NS)/$(REPO):$(VERSION) /bin/bash

run:
	docker run           --name $(NAME)-$(INSTANCE) -i -t $(PORTS) $(VOLUMES) $(ENV) $(NS)/$(REPO):$(VERSION)

start:
	docker run -d        --name $(NAME)-$(INSTANCE) -i -t $(PORTS) $(VOLUMES) $(ENV) $(NS)/$(REPO):$(VERSION)

attach:
	docker attach --sig-proxy=true $(NAME)-$(INSTANCE)

logs:
	docker logs $(NAME)-$(INSTANCE)

stop:
	docker stop $(NAME)-$(INSTANCE)

rm:
	docker rm   $(NAME)-$(INSTANCE)

release: build
	make push -e VERSION=$(VERSION)

default: build

