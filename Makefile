VENV := .venv
PYTHON := $(VENV)/bin/python
PYTHONPATH := src

bootstrap:
	./scripts/bootstrap.sh

doctor:
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) -m wispr doctor

run:
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) -m wispr run

native-build:
	./scripts/build_native_app.sh

native-install:
	./scripts/install_native_app.sh

native-open:
	if [ -d "$$HOME/Applications/Flow.app" ]; then open -n "$$HOME/Applications/Flow.app"; else open -n "$$HOME/Library/Caches/Flow/Flow.app"; fi

native-signing-setup:
	./scripts/setup_codesign_identity.sh

native-login-install:
	./scripts/install_launch_agent.sh

native-login-uninstall:
	./scripts/uninstall_launch_agent.sh
