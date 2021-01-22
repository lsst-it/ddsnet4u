all: build

build:
	docker build -t lsstit/ddsnet4u .

bundle:
	docker run --rm -v "${PWD}":/usr/src/app -w /usr/src/app ruby:2.7.2-alpine3.13 bundle install

test: build
	docker run --privileged -ti -v "${PWD}/tests":/tests lsstit/ddsnet4u /usr/local/ddsnet4u/ddsnet4u.rb --config /tests/ddsnet4u.yaml --noop

