.PHONY: all setup format lint credo dialyzer test coverage specs.check

all: format lint credo test coverage dialyzer

setup:
	mix setup

format:
	mix format --check-formatted

lint:
	mix credo --strict

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
