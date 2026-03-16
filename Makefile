TARGET = PopcornEPG
# TEST_TARGET = TMDbTests
# INTEGRATION_TEST_TARGET = TMDbIntegrationTests

SWIFT_CONTAINER_IMAGE = swift:6.2.0-jammy

.PHONY: clean
clean:
	swift package clean

.PHONY: format
format:
	@swiftlint --fix .
	@swiftformat .

.PHONY: lint
lint:
	@swiftlint --strict .
	@swiftformat --lint .

.PHONY: build
build:
	set -o pipefail && swift build -Xswiftc -warnings-as-errors 2>&1 | xcsift -f toon --Werror

.PHONY: build-tests
build-tests:
	set -o pipefail && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | xcsift -f toon --Werror

.PHONY: build-linux
build-linux:
	docker run --rm -v "$${PWD}:/workspace" -w /workspace $(SWIFT_CONTAINER_IMAGE) /bin/bash -cl "swift build -Xswiftc -warnings-as-errors"

.PHONY: build-release
build-release:
	set -o pipefail && swift build -c release -Xswiftc -warnings-as-errors 2>&1 | xcsift -f toon --Werror

.PHONY: build-linux-release
build-linux-release:
	docker run --rm -v "$${PWD}:/workspace" -w /workspace $(SWIFT_CONTAINER_IMAGE) /bin/bash -cl "swift build -c release -Xswiftc -warnings-as-errors"

.PHONY: test
test:
	set -o pipefail && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | xcsift -f toon --Werror
	set -o pipefail && swift test --skip-build --filter $(TEST_TARGET) 2>&1 | xcsift -f toon

.PHONY: test-linux
test-linux:
	docker run -i --rm -v "$${PWD}:/workspace" -w /workspace $(SWIFT_CONTAINER_IMAGE) /bin/bash -cl "swift build --build-tests -Xswiftc -warnings-as-errors && swift test --skip-build --filter $(TEST_TARGET)"
