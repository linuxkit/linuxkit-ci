.PHONY: all docker clean

all:
	jbuilder build --dev src/ci.exe

docker:
	docker build -t linuxkitci/ci .

clean:
	jbuilder clean
