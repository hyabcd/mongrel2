SQLITE3_DIR=$(PWD)/deps/sqlite3-3.7.2
ZEROMQ_DIR=$(PWD)/deps/zeromq-2.0.8

CFLAGS=-Wall -I$(PWD)/src -I$(SQLITE3_DIR) -I$(ZEROMQ_DIR)/include
LDFLAGS=-pthread -luuid -ldl
PREFIX?=/usr/local

ASM=$(wildcard src/**/*.S src/*.S)
RAGEL_TARGETS=src/state.c src/http11/http11_parser.c
SOURCES=$(wildcard src/**/*.c src/*.c) $(RAGEL_TARGETS)
OBJECTS=$(patsubst %.c,%.o,${SOURCES}) $(patsubst %.S,%.o,${ASM})
LIB_SRC=$(filter-out src/mongrel2.c,${SOURCES})
LIB_OBJ=$(filter-out src/mongrel2.o,${OBJECTS})
TEST_SRC=$(wildcard tests/*.c)
TESTS=$(patsubst %.c,%,${TEST_SRC})

STATIC_LIBS=$(PWD)/build/libm2.a $(SQLITE3_DIR)/sqlite3.a $(ZEROMQ_DIR)/src/.libs/libzmq.a

release: CFLAGS+=-O2 -DNDEBUG
release: all

dev: CFLAGS+=-g -Wall -Wextra
dev: all

all: bin/mongrel2 tests m2sh

bin/mongrel2: $(STATIC_LIBS) src/mongrel2.o
	$(CXX) $(LDFLAGS) src/mongrel2.o -o $@ $(STATIC_LIBS)

$(PWD)/build/libm2.a: build/libm2.a
build/libm2.a: build ${LIB_OBJ}
	ar rcs $@ ${LIB_OBJ}
	ranlib $@

build:
	@mkdir -p build
	@mkdir -p bin

clean:
	rm -rf build bin lib ${OBJECTS} ${TESTS} tests/config.sqlite
	find . -name "*.gc*" -exec rm {} \;
	cd $(SQLITE3_DIR) && $(MAKE) clean
	cd $(ZEROMQ_DIR) && $(MAKE) clean
	rm -f $(TESTS) tests/*.o
	$(MAKE) -C tools/m2sh clean

distclean:	pristine

pristine: clean
	rm -rf examples/python/build examples/python/dist examples/python/m2py.egg-info
	find . -name "*.pyc" -exec rm {} \;
	$(MAKE) -C docs/manual clean
	$(MAKE) -C docs/ clean
	$(MAKE) -C examples/kegogi clean
	rm -f logs/*
	rm -f run/*
	cd $(ZEROMQ_DIR) && rm -f Makefile
	$(MAKE) -C tools/m2sh pristine

tests: build/libm2.a tests/config.sqlite ${TESTS}
	sh ./tests/runtests.sh

tests/config.sqlite: src/config/config.sql src/config/example.sql src/config/mimetypes.sql
	$(SQLITE3_DIR)/sqlite3 $@ < src/config/config.sql
	$(SQLITE3_DIR)/sqlite3 $@ < src/config/example.sql
	$(SQLITE3_DIR)/sqlite3 $@ < src/config/mimetypes.sql

$(TESTS): %: %.c %.o $(STATIC_LIBS)
	$(CXX) $(LDFLAGS) -o $@ $@.o $(STATIC_LIBS)

src/state.c: src/state.rl src/state_machine.rl
src/http11/http11_parser.c: src/http11/http11_parser.rl
src/http11/httpclient_parser.c: src/http11/httpclient_parser.rl
src/control.c: src/control.rl

check:
	@echo Files with potentially dangerous functions.
	@egrep '[^_.>a-zA-Z0-9](str(n?cpy|n?cat|xfrm|n?dup|str|pbrk|tok|_)|stpn?cpy|a?sn?printf|byte_)' $(filter-out src/bstr/bsafe.c,${SOURCES})

m2sh:
	$(MAKE) -C tools/m2sh all "CFLAGS=$(CFLAGS) -Isrc" "LDFLAGS=$(LDFLAGS)" "STATIC_LIBS=$(STATIC_LIBS)"

install: all install-bin install-m2sh

install-bin:
	install -d $(PREFIX)/bin/
	install bin/mongrel2 $(PREFIX)/bin/

install-m2sh:
	$(MAKE) -C tools/m2sh install

examples/python/mongrel2/sql/config.sql: src/config/config.sql src/config/mimetypes.sql
	cat src/config/config.sql src/config/mimetypes.sql > $@

ragel:
	ragel -G2 src/state.rl
	ragel -G2 src/http11/http11_parser.rl
	ragel -G2 src/handler_parser.rl
	ragel -G2 src/http11/httpclient_parser.rl
	ragel -G2 src/control.rl

valgrind:
	valgrind --leak-check=full --show-reachable=yes --log-file=valgrind.log --suppressions=tests/valgrind.sup ./bin/mongrel2 tests/config.sqlite localhost

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

coverage: CFLAGS += -fprofile-arcs -ftest-coverage
coverage: clean all coverage_report

coverage_report:
	rm -rf tests/m2.zcov tests/coverage
	zcov-scan tests/m2.zcov
	zcov-genhtml tests/m2.zcov tests/coverage
	zcov-summarize tests/m2.zcov

system_tests:
	./tests/system_tests/curl_tests
	./tests/system_tests/chat_tests

$(SQLITE3_DIR)/sqlite3.a:
	cd $(SQLITE3_DIR) && $(MAKE)

$(ZEROMQ_DIR)/src/.libs/libzmq.a:	$(ZEROMQ_DIR)/Makefile
	cd $(ZEROMQ_DIR) && $(MAKE)

$(ZEROMQ_DIR)/Makefile:
	cd $(ZEROMQ_DIR) && ./configure --prefix=$(PREFIX)
