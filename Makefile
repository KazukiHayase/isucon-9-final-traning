PROJECT_ROOT:=/home/isucon/isucari/webapp
BUILD_DIR:=/home/isucon/isucari/webapp/go
BIN_NAME:=isucari
BRANCH:=main

NGX_LOG:=/tmp/access.log
MYSQL_LOG:=/tmp/slow-query.log

DB_HOST:=127.0.0.1
DB_PORT:=3306
DB_USER:=isucari
DB_PASS:=isucari
DB_NAME:=isucari
MYSQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

ALPSORT=sum
ALPM="[0-9a-zA-Z]+"
OUTFORMAT=count,method,uri,min,max,sum,avg,p99

SLACKCAT:=slackcat --tee --channel notify-logs
SLACKRAW:=slackcat --channel notify-logs

# デプロイ
# make deploy BRANCH=<ブランチ名>でブランチを指定してデプロイ
.PHONY: deploy
deploy: before checkout build restart slow-on

.PHONY: before
before:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	@if [ -f $(NGX_LOG) ]; then \
		sudo mv -f $(NGX_LOG) ~/logs/$(when)/ ; \
	fi
	@if [ -f $(MYSQL_LOG) ]; then \
		sudo mv -f $(MYSQL_LOG) ~/logs/$(when)/ ; \
	fi

.PHONY: checkout
checkout:
	git fetch && \
	git reset --hard origin/$(BRANCH)

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl restart nginx
	sudo systemctl restart mysql
	sudo systemctl restart $(BIN_NAME).golang

# モニタリング
.PHONY: notify
notify: alp slow

## alp
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGX_LOG) --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) | $(SLACKCAT)

## slow-query
.PHONY: slow
slow:
	sudo mysqldumpslow -s t $(MYSQL_LOG) | head -n 20 | $(SLACKCAT)

## pprof
.PHONY: pprof
pprof:
	go tool pprof -http=0.0.0.0:8080 http://localhost:6060/debug/pprof/profile

# DB
.PHONY: slow-on
slow-on:
	echo "set global slow_query_log_file = '$(MYSQL_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;" | sudo mysql -uroot

.PHONY: slow-off
slow-off:
	echo "set global slow_query_log = OFF;" | sudo mysql -uroot

.PHONY: sql
sql:
	sudo $(MYSQL_CMD)

# セットアップ
.PHONY: init
init:
	sudo apt install -y percona-toolkit dstat git unzip snapd gh graphviz
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.10/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install ./alp /usr/local/bin
	rm alp alp_linux_amd64.zip
	TBLS_VERSION=1.56.0 curl -o tbls.deb -L https://github.com/k1LoW/tbls/releases/download/v$TBLS_VERSION/tbls_$TBLS_VERSION-1_amd64.deb
	sudo dpkg -i tbls.deb
	rm tbls.deb
	touch .tbls.yml
	echo "# DSN (Database Source Name) to connect database\ndsn: mysql://$(DB_USER):$(DB_PASS)@$(DB_HOST):$(DB_PORT)/$(DB_NAME)\n# Path to generate document\n# Default is 'dbdoc'\ndocPath: doc/schema" >> .tbls.yml
	sudo cp /etc/nginx/nginx.conf $(PROJECT_ROOT)/etc/nginx/nginx.conf
	curl -Lo slackcat https://github.com/bcicen/slackcat/releases/download/v1.7/slackcat-1.7-$(uname -s)-amd64
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
	slackcat --configure
