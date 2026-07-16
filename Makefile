# Dhruva local gate — run before every HANDOFF. CI runs the same steps.
APP := app

.PHONY: verify analyze format test coverage build-apk

verify: analyze format test

analyze:
	cd $(APP) && flutter analyze --fatal-infos

format:
	cd $(APP) && dart format --set-exit-if-changed lib test

test:
	cd $(APP) && flutter test

coverage:
	cd $(APP) && flutter test --coverage

build-apk:
	cd $(APP) && flutter build apk --debug
