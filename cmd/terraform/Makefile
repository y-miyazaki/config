.PHONY: build test lint vet help

# The helper binary is committed next to module_updater.sh (linux/arm64 dev container).
BINARY  := ../../scripts/terraform/module_updater
CMD     := ./module_updater
VERSION ?= dev

build: ## Build the committed helper binary
	go build -trimpath -ldflags="-s -w -X main.version=$(VERSION)" -o $(BINARY) $(CMD)

test: ## Run tests with race detector and coverage
	mkdir -p coverage
	CGO_ENABLED=1 go test ./... -race -count=1 -covermode=atomic -coverprofile=coverage/coverage.out
	go tool cover -func=coverage/coverage.out

lint: ## Run golangci-lint
	golangci-lint run --config=../../.golangci.yaml ./...

vet: ## Run go vet
	go vet ./...

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
