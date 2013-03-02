# Jivelite makefile

all: srcs libs

srcs:
	cd src; make

libs: lib

lib:
	cd lib-src; make

clean:
	cd src; make clean
	cd lib-src; make clean
	rm -Rf lib
