CHART_DIR     ?= rift
RELEASE_NAME  ?= cloud-rift
NAMESPACE     ?= cloud-rift
VALUES_FILE   ?= values.yaml
DIST_DIR      ?= dist

.PHONY: deps lint template package install upgrade uninstall clean

## Resolve all chart dependencies (topological order)
deps:
	./scripts/helm-deps.sh dep-up

## Lint all charts (topological order, includes dep resolution)
lint:
	./scripts/helm-deps.sh lint

## Render templates locally (full dep chain + lint first)
template: lint
	helm template $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--values $(CHART_DIR)/$(VALUES_FILE) \
		--values $(CHART_DIR)/dev-values.yaml

## Package all charts (topological order: dep-up + lint + package)
package:
	./scripts/helm-deps.sh package $(DIST_DIR)

## Install the chart into the cluster
install: lint
	helm install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values $(CHART_DIR)/$(VALUES_FILE)

## Upgrade an existing release
upgrade: lint
	helm upgrade $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--values $(CHART_DIR)/$(VALUES_FILE)

## Uninstall the release
uninstall:
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)

## Remove generated artifacts
clean:
	rm -rf $(DIST_DIR)
	find . -path '*/.git' -prune -o -name 'charts' -type d -print | xargs rm -rf
	find . -name 'Chart.lock' -not -path '*/.git/*' -delete
