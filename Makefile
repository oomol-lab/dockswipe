CC      ?= clang
CFLAGS  ?= -O2 -Wall
LDFLAGS  = -framework CoreGraphics -framework ApplicationServices
PREFIX  ?= /usr/local
BIN      = dockswipe
SRC      = dockswipe.m

# Version baked into the binary at compile time. Local builds default to
# 0.0.0-development; CI passes the real version, e.g. `make build VERSION=1.2.3`.
VERSION ?= 0.0.0-development
CPPFLAGS += -DDOCKSWIPE_VERSION='"$(VERSION)"'

# Optional target architecture (arm64 | x86_64). Empty = host arch. CI builds
# one thin binary per arch (`make build ARCH=x86_64`); clang cross-compiles
# either slice on an Apple-silicon host.
ARCH ?=
ifneq ($(strip $(ARCH)),)
CFLAGS += -arch $(ARCH)
endif

.PHONY: all build clean install uninstall FORCE

all: build

build: $(BIN)

$(BIN): $(SRC) FORCE
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(BIN)

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)

# Empty phony prerequisite that is always considered out-of-date, so any target
# depending on it (here: $(BIN)) is rebuilt unconditionally on every invocation.
FORCE:
