APP := sre-tools

EXENAME=sre-tools

build:
	go test -c . -o $(EXENAME)

builda:
	$(SELF) go:build


run: build
	./$(EXENAME)

clean:
	rm -rf ./$(EXENAME)
