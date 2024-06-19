all: clean dist

PACKAGE_VERSION            := `cat version.txt | tr -d '\n'`
BUILD_TAG                  := $(shell git describe --always --dirty)
DOCKER_TEST_IMAGE          := harbor.h2o.ai/h2ogpt/test-image:$(BUILD_TAG)
DOCKER_TEST_IMAGE_VLLM     := harbor.h2o.ai/h2ogpt/test-image-vllm:$(BUILD_TAG)
DOCKER_TEST_IMAGE_INTERNVL := harbor.h2o.ai/h2ogpt/test-image-internvl:$(BUILD_TAG)
PYTHON_BINARY              ?= `which python`
DEFAULT_MARKERS            ?= "not need_tokens and not need_gpu"

.PHONY: venv dist test publish docker_build build_info.txt

clean:
	rm -rf dist build h2ogpt.egg-info

venv:
	$(PYTHON_BINARY) -m virtualenv -p $(PYTHON_BINARY) venv

install:
	$(PYTHON_BINARY) -m pip install dist/h2ogpt-$(PACKAGE_VERSION)-py3-none-any.whl

install-%:
	$(PYTHON_BINARY) -m pip install dist/h2ogpt-$(PACKAGE_VERSION)-py3-none-any.whl[$*]

dist:
	$(PYTHON_BINARY) setup.py bdist_wheel

test:
	$(PYTHON_BINARY) -m pip install requirements-parser
	$(PYTHON_BINARY) -m pytest tests --disable-warnings --junit-xml=test_report.xml -m "$(DEFAULT_MARKERS)"

test_imports:
	$(PYTHON_BINARY) -m pytest tests/test_imports.py --disable-warnings --junit-xml=test_report.xml -m "$(DEFAULT_MARKERS)"

publish:
	echo "Publishing not implemented yet."

build_info.txt:
	@rm -rf build_info.txt
	@echo "commit=\"$(shell git rev-parse HEAD)\"" >> $@
	@echo "branch=\"`git rev-parse HEAD | git branch -a --contains | grep -v detached | sed -e 's~remotes/origin/~~g' -e 's~^ *~~' | sort | uniq | tr '*\n' ' '`\"" >> $@
	@echo "describe=\"`git describe --always --dirty`\"" >> $@
	@echo "build_os=\"`uname -a`\"" >> $@
	@echo "build_machine=\"`hostname`\"" >> $@
	@echo "build_date=\"$(shell date "+%Y%m%d")\"" >> $@
	@echo "build_user=\"`id -u -n`\"" >> $@
	@echo "base_version=\"$(PACKAGE_VERSION)\"" >> $@

git_hash.txt:
	@echo "$(shell git rev-parse HEAD)" >> $@


DOCKER_BASE_OS_IMAGE := gcr.io/vorvan/h2oai/h2ogpt-oss-wolfi-base:4
DOCKER_VLLM_IMAGE    := gcr.io/vorvan/h2oai/h2ogpte-vllm:0.5.0.post1

docker_build: build_info.txt git_hash.txt
	docker pull $(DOCKER_BASE_OS_IMAGE)
ifeq ($(shell curl --connect-timeout 4 --write-out %{http_code} -sS --output /dev/null -X GET http://harbor.h2o.ai/api/v2.0/projects/h2ogpt/repositories/test-image/artifacts/$(BUILD_TAG)/tags),200)
	@echo "Image already pushed to Harbor: $(DOCKER_TEST_IMAGE)"
else
	DOCKER_BUILDKIT=1 docker build -t $(DOCKER_TEST_IMAGE) -t h2ogpt:current -f Dockerfile .
	docker push $(DOCKER_TEST_IMAGE)
endif
ifeq ($(shell curl --connect-timeout 4 --write-out %{http_code} -sS --output /dev/null -X GET http://harbor.h2o.ai/api/v2.0/projects/h2ogpt/repositories/test-image-vllm/artifacts/$(BUILD_TAG)/tags),200)
	@echo "VLLM Image already pushed to Harbor: $(DOCKER_TEST_IMAGE_VLLM)"
else
	docker pull $(DOCKER_VLLM_IMAGE)
	docker tag $(DOCKER_VLLM_IMAGE) $(DOCKER_TEST_IMAGE_VLLM)
	docker push $(DOCKER_TEST_IMAGE_VLLM)
endif
ifeq ($(shell curl --connect-timeout 4 --write-out %{http_code} -sS --output /dev/null -X GET http://harbor.h2o.ai/api/v2.0/projects/h2ogpt/repositories/test-image-internvl/artifacts/$(BUILD_TAG)/tags),200)
	@echo "internvl Image already pushed to Harbor: $(DOCKER_TEST_IMAGE_INTERNVL)"
else
	DOCKER_BUILDKIT=1 docker build -t $(DOCKER_TEST_IMAGE_INTERNVL) -f docs/Dockerfile.internvl .
	docker push $(DOCKER_TEST_IMAGE_INTERNVL)
endif

just_docker_build: build_info.txt git_hash.txt
	docker pull $(DOCKER_BASE_OS_IMAGE)
	DOCKER_BUILDKIT=1 docker build -t $(DOCKER_TEST_IMAGE) -t h2ogpt:current -f Dockerfile .
	DOCKER_BUILDKIT=1 docker build -t $(DOCKER_TEST_IMAGE_INTERNVL) -f docs/Dockerfile.internvl .

docker_build_runner: docker_build
	-docker pull $(DOCKER_TEST_IMAGE)
	-docker pull $(DOCKER_TEST_IMAGE_VLLM)

	docker tag $(DOCKER_TEST_IMAGE) gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(BUILD_TAG)
	docker tag $(DOCKER_TEST_IMAGE_VLLM) gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(BUILD_TAG)
	docker tag $(DOCKER_TEST_IMAGE_INTERNVL) gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(BUILD_TAG)

	docker tag $(DOCKER_TEST_IMAGE) gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(PACKAGE_VERSION)
	docker tag $(DOCKER_TEST_IMAGE_VLLM) gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(PACKAGE_VERSION)
	docker tag $(DOCKER_TEST_IMAGE_INTERNVL) gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(PACKAGE_VERSION)

	docker tag $(DOCKER_TEST_IMAGE) gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:latest
	docker tag $(DOCKER_TEST_IMAGE_VLLM) gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:latest
	docker tag $(DOCKER_TEST_IMAGE_INTERNVL) gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:latest

	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(BUILD_TAG)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(PACKAGE_VERSION)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:latest

	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(BUILD_TAG)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(PACKAGE_VERSION)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:latest

	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(BUILD_TAG)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(PACKAGE_VERSION)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:latest

ifdef BUILD_ID
	docker tag $(DOCKER_TEST_IMAGE) gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(PACKAGE_VERSION)-$(BUILD_ID)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-runtime:$(PACKAGE_VERSION)-$(BUILD_ID)

	docker tag $(DOCKER_TEST_IMAGE_VLLM) gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(PACKAGE_VERSION)-$(BUILD_ID)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-vllm:$(PACKAGE_VERSION)-$(BUILD_ID)

	docker tag $(DOCKER_TEST_IMAGE_INTERNVL) gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(PACKAGE_VERSION)-$(BUILD_ID)
	docker push gcr.io/vorvan/h2oai/h2oai-h2ogpt-internvl:$(PACKAGE_VERSION)-$(BUILD_ID)
endif

print-%:
	@echo $($*)
