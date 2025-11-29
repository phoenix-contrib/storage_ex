# --------------------
# PhoenixContribStorageEx Monorepo
# --------------------
PACKAGES := storage_ex storage_ex_s3 storage_ex_ecto
PACKAGES_PATH := packages

# Default target
.PHONY: all
all: compile ## Compile all packages

## --------------------
## Core tasks (all packages)
## --------------------

.PHONY: deps
deps: ## Fetch deps for all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Fetching deps for $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix deps.get); \
	done

.PHONY: compile
compile: ## Compile all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Compiling $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix compile); \
	done

.PHONY: clean
clean: ## Clean all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Cleaning $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix clean); \
	done

.PHONY: install
install: ## Run Igniter install for phoenix_contrib_storage_ex
	@echo "==> Running Igniter install for phoenix_contrib_storage_ex"
	@(cd $(PACKAGES_PATH)/storage_ex && mix igniter.install phoenix_contrib_storage_ex)

## --------------------
## QA tasks (all packages)
## --------------------

.PHONY: test
test: ## Run tests in all packages (requires ffmpeg, poppler, mupdf, libvips)
	@exit_code=0; \
	for pkg in $(PACKAGES); do \
		echo "==> Testing $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && MIX_ENV=test mix test) || exit_code=$$?; \
	done; \
	exit $$exit_code

.PHONY: test.unavailable_tools
test.unavailable_tools: ## Run tests for graceful degradation when tools are unavailable
	@echo "==> Testing storage_ex (unavailable_tools only)"
	@(cd $(PACKAGES_PATH)/storage_ex && MIX_ENV=test mix test --only unavailable_tools)

.PHONY: test.watch
test.watch: ## Run test watch in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Testing $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && MIX_ENV=test mix test.watch); \
	done

.PHONY: dialyzer
dialyzer: ## Run dialyzer in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Dialyzer $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix dialyzer); \
	done

.PHONY: lint
lint: ## Run Credo in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Credo $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix credo); \
	done

.PHONY: lint-strict
lint-strict: ## Run Credo (strict) in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Credo (strict) $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix credo --strict); \
	done

.PHONY: format
format: ## Run mix format in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Formatting $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix format); \
	done

.PHONY: format-check
format-check: ## Check formatting in all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Checking format for $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix format --check-formatted); \
	done

.PHONY: docs
docs: ## Generate documentation for all packages
	@for pkg in $(PACKAGES); do \
		echo "==> Generating docs for $$pkg"; \
		(cd $(PACKAGES_PATH)/$$pkg && mix docs); \
	done

.PHONY: check
check: format lint-strict dialyzer test ## Run full CI check (format, lint, dialyzer, test)
	@echo "✅ All checks passed"

## --------------------
## Utility
## --------------------

.PHONY: shell
shell: ## Open IEx shell for storage_ex
	@(cd $(PACKAGES_PATH)/storage_ex && iex -S mix)

.PHONY: reset
reset: clean deps compile ## Clean, fetch deps, and compile all packages
	@echo "==> Repo reset complete"

## --------------------
## Per-package shortcuts
## --------------------

define make_package_task
.PHONY: $(1).deps
$(1).deps:
	@(cd $(PACKAGES_PATH)/$(1) && mix deps.get)

.PHONY: $(1).compile
$(1).compile:
	@(cd $(PACKAGES_PATH)/$(1) && mix compile)

.PHONY: $(1).clean
$(1).clean:
	@(cd $(PACKAGES_PATH)/$(1) && mix clean)

.PHONY: $(1).test
$(1).test:
	@(cd $(PACKAGES_PATH)/$(1) && MIX_ENV=test mix test)

.PHONY: $(1).test.watch
$(1).test.watch:
	@(cd $(PACKAGES_PATH)/$(1) && MIX_ENV=test mix test.watch)

.PHONY: $(1).dialyzer
$(1).dialyzer:
	@(cd $(PACKAGES_PATH)/$(1) && mix dialyzer)

.PHONY: $(1).lint
$(1).lint:
	@(cd $(PACKAGES_PATH)/$(1) && mix credo)

.PHONY: $(1).lint-strict
$(1).lint-strict:
	@(cd $(PACKAGES_PATH)/$(1) && mix credo --strict)

.PHONY: $(1).format
$(1).format:
	@(cd $(PACKAGES_PATH)/$(1) && mix format)

.PHONY: $(1).docs
$(1).docs:
	@(cd $(PACKAGES_PATH)/$(1) && mix docs)

.PHONY: $(1).check
$(1).check:
	@(cd $(PACKAGES_PATH)/$(1) && mix format && mix credo --strict && mix dialyzer && mix test)
endef

$(foreach pkg,$(PACKAGES),$(eval $(call make_package_task,$(pkg))))

## --------------------
## Help
## --------------------

.PHONY: help
help: ## Show this help
	@echo "📦 StorageEx commands:"
	@echo ""
	@echo "Available global targets:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "💡 Per-package commands are also available:"
	@for pkg in $(PACKAGES); do \
		echo "   make $$pkg.test       # run tests for $$pkg"; \
		echo "   make $$pkg.compile    # compile $$pkg"; \
		echo "   make $$pkg.check      # run full check for $$pkg"; \
	done

