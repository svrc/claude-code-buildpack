BUILDPACK_ID := io.tanzu.buildpacks.claude-code
VERSION := $(shell cat VERSION)
REGISTRY ?= ghcr.io/stuartcharlton
IMAGE := $(REGISTRY)/claude-code-buildpack:$(VERSION)

.PHONY: test package publish clean lint

test:
	@echo "Running unit tests..."
	bash tests/unit/run_tests.sh

lint:
	@echo "Checking script syntax..."
	bash -n bin/detect
	bash -n bin/build
	bash -n exec.d/claude-env
	bash -n scripts/claude-entrypoint.sh
	bash -n scripts/tmux-attach.sh
	node --check scripts/health-check.js
	@echo "All scripts valid."

package: lint
	pack buildpack package $(IMAGE) --config ./package.toml

publish: lint
	pack buildpack package $(IMAGE) --config ./package.toml --publish

clean:
	rm -rf /tmp/cnb-test-*

register:
	@echo "Registering buildpack with Korifi..."
	@echo "1. Add to ClusterStore:"
	@echo "   kubectl patch ClusterStore/cf-default-buildpacks --type json \\"
	@echo "     -p '[{\"op\":\"add\",\"path\":\"/spec/sources/-\",\"value\":{\"image\":\"$(IMAGE)\"}}]'"
	@echo ""
	@echo "2. Add to ClusterBuilder order:"
	@echo "   kubectl patch ClusterBuilder/cf-kpack-cluster-builder --type json \\"
	@echo "     -p '[{\"op\":\"add\",\"path\":\"/spec/order/-\",\"value\":{\"group\":[{\"id\":\"$(BUILDPACK_ID)\"}]}}]'"
