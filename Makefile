# Makefile for go-coding
.PHONY: all build build-all clean cmd default docker dep depend godep qb run test fmt lint list vet

# Set project variables
PROJECT := go-coding
GITHUB_CORP := dockerian
GITHUB_REPO := $(PROJECT)

# Set docker variables
DOCKER_IMAG := $(PROJECT)
DOCKER_USER := $(GITHUB_CORP)
DOCKER_TAGS := $(DOCKER_USER)/$(DOCKER_IMAG)
DOCKER_FILE ?= Dockerfile
DOCKER_DENV := $(wildcard /.dockerenv)
DOCKER_PATH := $(shell which docker)

# Don't need to start docker in 2 situations:
ifneq ("$(DOCKER_DENV)","")  # assume inside docker container
	DONT_RUN_DOCKER := true
endif
ifeq ("$(DOCKER_PATH)","")  # docker command is NOT installed
	DONT_RUN_DOCKER := true
endif

# returns "" if all undefined; otherwise, there is defined.
ifdef_any_of = $(filter-out undefined,$(foreach v,$(1),$(origin $(v))))
# usage:
#   * checking if any defined
#     - ifneq ($(call ifdef_any_of,VAR1 VAR2),)
#   * checking if none defined
#     - ifeq ($(call ifdef_any_of,VAR1 VAR2),)

# returns "" if all defined; otherwise, there is undefined.
ifany_undef = $(filter undefined,$(foreach v,$(1),$(origin $(v))))
# usage:
#   * checking if any undefined
#     - ifneq ($(call ifany_undef,VAR1 VAR2),)
#   * checking if both defined
#     - ifeq ($(call ifany_undef,VAR1 VAR2),)

# define uniq function - usage: $(info $(call uniq,$(VAR)))
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))

# Set OS platform
# See http://stackoverflow.com/questions/714100/os-detecting-makefile
# TODO: macro commands 'cp', 'mkdir', 'mv', 'rm', etc. for Windows
ifeq ($(shell uname),Darwin) # Mac OS
	OS_PLATFORM := darwin
	OS_PLATFORM_NAME := Mac OS
else ifeq ($(OS),Windows_NT) # Windows
		OS_PLATFORM := windows
		OS_PLATFORM_NAME := Windows
else
	OS_PLATFORM := linux
	OS_PLATFORM_NAME := Linux
endif

# Set build parameters
BINARY ?= $(PROJECT)
BUILDS_DIR := builds
BUILD_OS ?= $(OS_PLATFORM)
BUILD_VERSION ?= $(shell cat release/tag)
BUILD_MASTER_VERSION ?= 0
BUILD_PREFIX := $(BINARY)-$(BUILD_VERSION)
ALL_PACKAGES := $(shell go list ./... 2>/dev/null|grep -v -E '/v[0-9]+/client|/v[0-9]+/server|/vendor/')
PROJECT_PACKAGE := $(subst $(GOPATH)/src/, , $(PWD))
CMD_PACKAGE := $(PROJECT_PACKAGE)/cli/cmd
SOURCE_PATH := $(GOPATH)/src/github.com/$(GITHUB_CORP)/$(PROJECT)
SYSTOOLS := awk egrep find git go grep jq rm sort tee xargs zip
MAKE_RUN := tools/run.sh

DEBUG ?= 1


# Set testing parameters
GOMAXPROCS ?= 4
TEST_COVERFUNC := cover-func.out
TEST_COVER_ALL := cover-all.out
TEST_COVER_OUT := cover.out

ifeq ("$(TEST_COVER_MODE)","")
	TEST_COVER_MODE = set
endif
ifeq ("$(TEST_COVERAGES)","")
	TEST_COVERAGES = 65
endif

TEST_MATCH ?= .
TEST_TAGS ?= all
ifneq ("$(TEST_TAGS)","all")
	TEST_COVERAGES := 10
endif

ifneq ("$(TEST_BENCH)","")
	TEST_BENCH := -bench=$(TEST_MATCH)
endif

ifneq ("$(TEST_DIR)","")
	TEST_PROFILE := -covermode=$(TEST_COVER_MODE) -coverprofile=$(TEST_COVER_ALL) ./$(TEST_DIR)
	TEST_PACKAGE := $(PROJECT_PACKAGE)/$(TEST_DIR)
else
	TEST_PROFILE := -covermode=$(TEST_COVER_MODE)
	TEST_PACKAGE := ""
endif

ifeq ("$(DEBUG)","1")
	TEST_VERBOSE := -v
endif
ifneq ($(TEST_VERBOSE)$(VERBOSE),)
	TEST_VERBOSE := -v
endif

TEST_ARGS := -cpu=$(GOMAXPROCS) $(TEST_BENCH) $(TEST_VERBOSE) -run=$(TEST_MATCH) -tags=$(TEST_TAGS) $(TEST_PROFILE)
TEST_LOGS := tests.log

# Set the -ldflags option for go build, interpolate the variable values
LDFLAGS := -ldflags "-X '$(PROJECT_PACKAGE).buildVersion=$(BUILD_VERSION)'"

# Set linter level, higher is looser (golint default is 0.8)
LINTER_LEVEL=0.0

# Set variables for distribution
BIN_DIR := $(BUILDS_DIR)/bin
DIST_ARCH := amd64
DIST_DIR := dist
DIST_DOWNLOADS := $(DIST_DIR)/downloads
DIST_UPDATES := $(DIST_DIR)/v$(BUILD_MASTER_VERSION)
DIST_VER := $(DIST_UPDATES)/$(BUILD_VERSION)
DIST_PREFIX := $(DIST_DOWNLOADS)/$(BUILD_PREFIX)
GO_SELF_UPDATE_INPUTS := $(PWD)/build/updates
GO_SELF_UPDATE_PUBLIC := $(PWD)/public

# Set codegen variables
# default codegen language
CODEGEN_LANG ?= go
# default api spec version
CODEGEN_SPEC ?= v1
# merging all with unique api spec versions
CODEGEN_VERS := $(call uniq,$(CODEGEN_SPEC) v1 v2)
# path to code generated
CODEGEN_PATH ?= api
# codegen bash script
MAKE_CODEGEN := ./tools/codegen.sh
# swagger.yaml folder
SWAGGER_PATH := api/doc
# docker image for codegen cli
SWAGGER_IMAG := swaggerapi/swagger-codegen-cli
# docker container port for swagger ui
SWAGGER_PORT ?= 8888
SWAGGER_PAGE := http://localhost:$(SWAGGER_PORT)
SWAGGER_EDIT := swaggerapi/swagger-editor
# docker image for swagger ui
SWAGGER_UIMG := swaggerapi/swagger-ui
SWAGGER_WTAG := swagger-web


# Makefile targets
default: cmd
all: build-all run test


# build targets
build: clean-cache check-tools build-only

build-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" BUILD_OS=$(BUILD_OS) \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "......................................................................."
	@echo "Building: '$(BINARY)' ... [BUILD_OS = $(BUILD_OS)]"
	go get -u

	GOARCH=$(DIST_ARCH) GOOS=$(BUILD_OS) go build $(LDFLAGS) -o $(BIN_DIR)/$(BUILD_OS)/$(BINARY) main.go

	@echo ""
	@echo "Copying $(BIN_DIR)/$(BUILD_OS)/$(BINARY) [BUILD_OS = $(BUILD_OS)]"
	cp -f $(BIN_DIR)/$(BUILD_OS)/$(BINARY) $(BUILDS_DIR)/$(BINARY)
endif
	@echo ""
	@echo "- DONE: $@"

build-all: clean-cache check-tools build-all-only

build-all-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" BUILD_OS=$(BUILD_OS) \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "......................................................................."
	@echo "Building $(BINARY) for all platforms..."
	go get -u
	go get -t github.com/sanbornm/go-selfupdate
	go install github.com/sanbornm/go-selfupdate

	mkdir -p $(BIN_DIR)
	mkdir -p $(DIST_DOWNLOADS)
	mkdir -p $(GO_SELF_UPDATE_INPUTS)

	@- $(foreach os,darwin linux windows, \
		echo ""; \
		echo "Building $(BUILD_VERSION) for $(os) platform"; \
		echo "GOARCH=$(DIST_ARCH) GOOS=$(os) go build $(LDFLAGS) -o $(BIN_DIR)/$(os)/$(BINARY) main.go"; \
		GOARCH=$(DIST_ARCH) GOOS=$(os) go build $(LDFLAGS) -o $(BIN_DIR)/$(os)/$(BINARY) main.go; \
		cp -p $(BIN_DIR)/$(os)/$(BINARY) $(GO_SELF_UPDATE_INPUTS)/$(os)-$(DIST_ARCH); \
		if [[ "$(os)" == "windows" ]]; then \
			mv $(BIN_DIR)/$(os)/$(BINARY) $(BIN_DIR)/$(os)/$(BINARY).exe; \
			zip -jr $(DIST_PREFIX)-$(os)-$(DIST_ARCH).zip $(BIN_DIR)/$(os)/$(BINARY).exe; \
		else \
			tar -C $(BIN_DIR)/$(os)/ -cvzf $(DIST_PREFIX)-$(os)-$(DIST_ARCH).tar.gz ./$(BINARY); \
		fi; \
	)
	@echo ""

	# create self-update distribution in public folder
	go-selfupdate "$(GO_SELF_UPDATE_INPUTS)" "$(BUILD_VERSION)"

	mkdir -p "$(DIST_VER)"
	rm -rf "$(DIST_VER)"
	cp -rf "$(GO_SELF_UPDATE_PUBLIC)"/* "$(DIST_UPDATES)/"
	cp -rf "$(GO_SELF_UPDATE_PUBLIC)"/*.json "$(DIST_VER)/"
	rm -rf "$(GO_SELF_UPDATE_PUBLIC)"

	# show distribution
	@tree "$(DIST_DIR)" 2>/dev/null; true
endif
	@echo ""
	@echo "- DONE: $@"


check-tools:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "--- Checking for presence of required tools: $(SYSTOOLS)"
	$(foreach tool,$(SYSTOOLS),\
	$(if $(shell which $(tool)),$(echo "boo"),\
	$(error "ERROR: Cannot find '$(tool)' in system $$PATH")))
endif
	@echo ""
	@echo "- DONE: $@"


clean-cache clean:
	@echo ""
	@echo "-----------------------------------------------------------------------"
	@echo "Cleaning build ..."
	find . -name '.DS_Store' -type f -delete
	find . -name \*.bak -type f -delete
	find . -name \*.log -type f -delete
	find . -name \*.out -type f -delete
	@echo ""
	@echo "Cleaning up codegen spec and $(SWAGGER_WTAG) ..."
	for ver in $(CODEGEN_VERS); do \
	rm -rf $(SWAGGER_PATH)/$$ver/spec; \
	done
	docker container rm -f -v $(SWAGGER_WTAG) || true
	@echo ""
	@echo "Cleaning up cache and coverage data ..."
	rm -rf .cache
	rm -rf .vscode
	find . -name cover\*.out -type f -delete
	rm -rf ./$(BIN_DIR)
	rm -rf ./$(BUILDS_DIR)
	rm -rf ./$(DIST_DIR)
	rm -rf ./$(TEST_COVER_OUT)
	rm -rf ./$(TEST_LOGS)
	@echo ""
	@echo "- DONE: $@"

clean-all: clean-cache
	@echo ""
	@echo "Cleaning up codegen client and server ..."
	for ver in $(CODEGEN_VERS); do \
	rm -rf "$(CODEGEN_PATH)/$$ver/client" "$(CODEGEN_PATH)/$$ver/server"; \
	done
	@echo ""
ifeq ("$(DOCKER_DENV)","")
	# not in a docker container
	@echo "Cleaning up docker container and image ..."
	docker rm -f \
		$(shell docker ps -a|grep $(DOCKER_IMAG)|awk '{print $1}') \
		2>/dev/null || true
	docker rmi -f \
		$(shell docker images -a|grep $(DOCKER_TAGS) 2>&1|awk '{print $1}') \
		2>/dev/null || true
	rm -rf docker_build.tee
	rm -rf projectFilesBackup
endif
	@echo ""
	@echo "- DONE: $@"


# codegen using default $(CODEGEN_SPEC); see $(CODEGEN_VERS) targets
codegen: $(CODEGEN_SPEC)
	@echo "- DONE: $@"

# codegen targets: codegen using api spec in '$(SWAGGER_PATH)/$@/swagger.yaml'
$(CODEGEN_VERS):
	@echo ""
	$(eval SWAGGER_YAML = $(SWAGGER_PATH)/$@/swagger.yaml)
	$(eval SWAGGER_JSON = $(SWAGGER_PATH)/$@/spec/swagger.json)
ifeq ("$(DOCKER_DENV)","")
	@echo "Checking api spec '$(SWAGGER_YAML)' ..."
	@stat "$(SWAGGER_YAML)" 1>/dev/null  # api spec does not exist yet
	$(eval OUT_API_SPEC = $(SWAGGER_PATH)/$@/spec)
	@echo "Cleaning generated $(CODEGEN_LANG) code in $(OUT_GOSERVER)"
	@rm -rf "$(OUT_API_SPEC)"
	@echo ""
	@echo "Execute:"
	CODEGEN_PATH=$(SWAGGER_PATH)/$@ CODEGEN_LANG=swagger CODEGEN_TYPE=spec \
	SWAGGER_YAML=$(SWAGGER_YAML) USE_DOCKER=false $(MAKE_CODEGEN) --keep-jar
	@echo ""
	@echo "Execute:"
	CODEGEN_PATH=$(CODEGEN_PATH)/$@ CODEGEN_LANG=$(CODEGEN_LANG) CODEGEN_TYPE=client \
	SWAGGER_YAML=$(SWAGGER_YAML) USE_DOCKER=false $(MAKE_CODEGEN) --keep-jar
	@echo ""
	@echo "Execute:"
	CODEGEN_PATH=$(CODEGEN_PATH)/$@ CODEGEN_LANG=$(CODEGEN_LANG)-server CODEGEN_TYPE=server \
	SWAGGER_YAML=$(SWAGGER_YAML) USE_DOCKER=false $(MAKE_CODEGEN)
else
	@echo "- make: $@ cannot run codegen inside docker container"
endif
	@echo ""
	@echo "- DONE: codegen [$@]"


# dependencies
dep depend godep:
	@echo ""
	@echo "Installing go lib and package managers ..."
	go get -u -f github.com/golang/lint/golint
	go get -u -f github.com/golang/dep/cmd/dep
	go get -u -f github.com/Masterminds/glide
	go get -u -f github.com/kardianos/govendor
	go get -u -f github.com/tools/godep
	@echo ""
	@echo "Saving go dependency packages info ..."
	dep ensure || true
	godep save -t ./... || true
	govendor add +external || true
	git checkout -- vendor/vendor.json 2>/dev/null || true
	govendor sync +external || true
	@echo ""
ifneq ("$(DOCKER_DENV)","")  # assume in docker container
	@echo "CAUTION: this is restoring to $$GOPATH [$(GOPATH)]"
	godep restore
endif
	tools/check_packages.sh --vendor
	@echo ""
	@echo "- DONE: $@"

dep-status:
	@echo ""
ifeq ("$(DOCKER_DENV)","")  # NOT inside docker container
	@echo "--- Opening dep status ---"
ifeq ($(OS), Windows_NT) # Windows
	choco install graphviz.portable
	dep status -dot | dot -T png -o status.png; start status.png
else ifeq ($(shell uname),Darwin) # Mac OS
	brew install graphviz
	dep status -dot | dot -T png | open -f -a /Applications/Preview.app
else
	sudo apt-get install graphviz
	dep status -dot | dot -T png | display
endif
else
	@echo ""
	@echo "Cannot show dep status in the container."
endif


# docker targets
docker cmd: docker_build.tee
	@echo ""
ifeq ("$(DOCKER_DENV)","")
	# not in a docker container yet
	@echo `date +%Y-%m-%d:%H:%M:%S` "Start bash in container '$(DOCKER_IMAG)'"
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) cmd
else
	@echo "env in the container:"
	@echo "-----------------------------------------------------------------------"
	@env | sort
	@echo "-----------------------------------------------------------------------"
endif
	@echo ""
	@echo "- DONE: $@"

docker_build.tee: $(DOCKER_FILE)
	@echo ""
ifeq ("$(DOCKER_DENV)","")
	# make in a docker host environment
	@echo `date +%Y-%m-%d:%H:%M:%S` "Building '$(DOCKER_TAGS)'"
	@echo "-----------------------------------------------------------------------"
	docker build -f "$(DOCKER_FILE)" -t $(DOCKER_TAGS) . | tee docker_build.tee
	@echo "-----------------------------------------------------------------------"
	@echo ""
	docker images --all | grep -e 'REPOSITORY' -e '$(DOCKER_TAGS)'
	@echo "......................................................................."
	@echo "- DONE: {docker build}"
	@echo ""
endif


# http://golang.org/cmd/go/#hdr-Run_gofmt_on_package_sources
fmt: check-tools fmt-only

fmt-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "Formatting code ..."
	go fmt $(ALL_PACKAGES) || true
endif
	@echo ""
	@echo "- DONE: $@"


lint: check-tools lint-only

lint-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "Check coding style ..."
	# go get -u github.com/golang/lint/golint
	golint -min_confidence $(LINTER_LEVEL) -set_exit_status $(ALL_PACKAGES)
endif
	@echo ""
	@echo "- DONE: $@"

list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | xargs


qb:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" BUILD_OS=$(BUILD_OS) \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "......................................................................."
	@echo "Building $(BIN_DIR)/$(OS_PLATFORM)/$(BINARY) [OS = $(OS_PLATFORM)]"
	GOARCH=$(DIST_ARCH) GOOS=$(BUILD_OS) go build $(LDFLAGS) -o $(BUILDS_DIR)/$(BINARY) main.go
endif
	@echo ""
	@echo "- DONE: $@"

run:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "......................................................................."
	@echo "Running: $(BIN_DIR)/$(OS_PLATFORM)/$(BINARY) ..."
	@$(BIN_DIR)/$(OS_PLATFORM)/$(BINARY)
endif
	@echo ""
	@echo "- DONE: $@"

show-env:
	@echo ""
	@env | sort
	@echo "......................................................................."
	@echo "OS Platform: "$(OS_PLATFORM_NAME)
	@echo "-----------------------------------------------------------------------"
	@echo "   PWD = $(PWD)"
	@echo "GOPATH = $(GOPATH) [$(shell go version)]"
	@echo "GOROOT = $(GOROOT)"
	@echo " SHELL = $(SHELL)"
	@echo ""


# swagger targets
swagger-editor: clean
	@echo ""
ifneq ("$(DOCKER_PATH)","")
	@echo "Starting $@ in docker container ..."
	docker run --name $(SWAGGER_WTAG) -d -p $(SWAGGER_PORT):8080 $(SWAGGER_EDIT)
ifeq ($(OS), Windows_NT) # Windows
	start $(SWAGGER_PAGE)
else ifeq ($(shell uname),Darwin) # Mac OS
	open $(SWAGGER_PAGE)
else
	nohup xdg-open $(SWAGGER_PAGE) >/dev/null 2>&1 &
endif
	@echo "......................................................................."
	@echo "Started $@ at http"
else
	@echo "Cannot start docker run for $@"
endif
	@echo ""
	@echo "- DONE: $@"

swagger-ui: clean codegen
	@echo ""
ifneq ("$(DOCKER_PATH)","")
	@echo "Starting $@ in docker container ..."
	docker run --name $(SWAGGER_WTAG) -d -p $(SWAGGER_PORT):8080 -v $(PWD):/project \
	-e SWAGGER_JSON=/project/$(SWAGGER_JSON) $(SWAGGER_UIMG)
ifeq ($(OS), Windows_NT) # Windows
	start $(SWAGGER_PAGE)
else ifeq ($(shell uname),Darwin) # Mac OS
	open $(SWAGGER_PAGE)
else
	nohup xdg-open $(SWAGGER_PAGE) >/dev/null 2>&1 &
endif
	@echo "......................................................................."
	@echo "Started $@ at http"
else
	@echo "Cannot start docker run for $@"
endif
	@echo ""
	@echo "- DONE: $@"


# show target does not require to re-run test
show-coverage show:
	@echo ""
	@echo "......................................................................."
	@echo "Generating test coverage report from $(TEST_COVER_ALL)"
	go tool cover -html=$(TEST_COVER_ALL)
	@echo ""
	@echo "- DONE: $@"

test-coverage cover: test show-coverage
	@echo ""
	@echo "- DONE: $@"


# test targets
test: check-tools fmt-only lint-only vet-only test-only
	@echo ""
	@echo "- DONE: $@"

test-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" DEBUG=$(DEBUG) \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	TEST_DIR=$(TEST_DIR) TEST_MATCH=$(TEST_MATCH) TEST_BENCH=$(TEST_BENCH) \
	TEST_COVER_MODE=$(TEST_COVER_MODE) TEST_COVERAGES=$(TEST_COVERAGES) \
	ALL_PACKAGES="$(ALL_PACKAGES)" TEST_TAGS=$(TEST_TAGS) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) dep $@
else
	@rm -rf ./$(TEST_LOGS)
	@echo "......................................................................."
	@echo "Running tests ... [tags: $(TEST_TAGS)] $(TEST_COVERAGES) %"
	@echo "go test $(TEST_PACKAGE) $(TEST_ARGS)"
ifdef TEST_DIR
	go test $(TEST_PACKAGE) $(TEST_ARGS) 2>&1 | tee ./$(TEST_LOGS)
	go tool cover -func="$(TEST_COVER_ALL)" | tee "$(TEST_COVERFUNC)"
else
	PROJECT_DIR="$(PWD)" \
	ALL_PACKAGES="$(ALL_PACKAGES)" \
	COVER_MODE="$(TEST_COVER_MODE)" \
	COVER_ALL_OUT="$(TEST_COVER_ALL)" \
	TEST_ARGS="$(TEST_ARGS)" TEST_LOGS="$(TEST_LOGS)" \
	tools/check_coverage.sh $(TEST_COVERAGES) "$(TEST_COVERFUNC)" --test
endif
	@echo ""
	TEST_LOGS="$(TEST_LOGS)" tools/check_tests.sh
	@echo ""
	@echo "Checking test coverage thresholds [$(TEST_COVERAGES) %] ..."
	PROJECT_DIR="$(PWD)" \
	COVER_MODE="$(TEST_COVER_MODE)" \
	COVER_ALL_OUT="$(TEST_COVER_ALL)" \
	tools/check_coverage.sh $(TEST_COVERAGES) "$(TEST_COVERFUNC)" --pass
endif
	@echo ""
	@echo "- DONE: $@"


# http://godoc.org/code.google.com/p/go.tools/cmd/vet
# go get code.google.com/p/go.tools/cmd/vet
vet: check-tools vet-only

vet-only:
	@echo ""
ifndef DONT_RUN_DOCKER
	PROJECT_DIR="$(PWD)" \
	GITHUB_USER=$(GITHUB_CORP) GITHUB_REPO=$(GITHUB_REPO) \
	DOCKER_USER=$(DOCKER_USER) DOCKER_NAME=$(DOCKER_IMAG) DOCKER_FILE="$(DOCKER_FILE)" \
	$(MAKE_RUN) $@
else
	@echo "Check go code correctness ..."
	go vet $(ALL_PACKAGES) || true
endif
	@echo ""
	@echo "- DONE: $@"
