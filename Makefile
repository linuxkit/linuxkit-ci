OCAMLBUILD_FLAGS=-use-ocamlfind

.PHONY: all docker clean

all:
	ocamlbuild ${OCAMLBUILD_FLAGS} ci.native

docker:
	docker build -t linuxkitci/ci .

clean:
	ocamlbuild -clean
