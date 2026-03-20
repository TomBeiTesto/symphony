.PHONY: all setup format lint credo dialyzer test coverage specs.check clean help

all: format credo test coverage dialyzer

setup:
	mix setup

format:
	mix format --check-formatted

lint: credo

credo:
	mix credo --strict

dialyzer:
	mix dialyzer

test:
	mix test

coverage:
	mix test --cover

specs.check:
	mix specs.check

clean:
	mix clean
	rm -rf _build deps priv/plts

help:
	@echo "Available targets:"
	@echo "  all         Run format, credo, test, coverage, dialyzer"
	@echo "  setup       Install dependencies (mix setup)"
	@echo "  format      Check code formatting"
	@echo "  lint        Alias for credo"
	@echo "  credo       Run Credo static analysis (strict)"
	@echo "  dialyzer    Run Dialyzer type analysis"
	@echo "  test        Run ExUnit test suite"
	@echo "  coverage    Run tests with coverage report"
	@echo "  specs.check Verify @spec coverage"
	@echo "  clean       Remove build artifacts and dependencies"
	@echo "  help        Show this help message"
