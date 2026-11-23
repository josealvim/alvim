.POSIX:
CC         = gcc -std=c17
DEPI       = $(shell which depi)
DEPI_FLAGS = -I=sources \
	-S=vendor/stb \
	-S=/usr/include -S=/usr/include/linux \
	-G=generated/

CFLAGS    +=  -Isources \
	-Igenerated \
	-Ivendor/stb \
	-Ivendor/raylib/src \
	-D'typeof=__typeof__'

MAP        = --map='%.c=%.o' --map='%.pak=%'
TARGETS    = $(filter-out targets/tests/%,$(shell find targets/ -type f -name "*.c"))
TESTS      = $(shell find targets/tests/ -type f -name "*.c")
TEST_BINS  = $(patsubst %.c, %.out, ${TESTS})
TEST_SOURCES = sources/gamelib/vector.c
SOURCES    = $(shell find sources/ -type f -name "*.c")
DEPFILE    = .depi.mk
LINKTO     = -lc -lm

.PHONY: all clean test
all: $(patsubst %.c, %.out, ${TARGETS}) 
	@echo done

test: ${TEST_BINS}
	@set -e; for t in ${TEST_BINS}; do echo "running $$t"; ./$$t; done

clean: 
	find -type f -name "*.o"   -exec rm {} \;
	find -type f -name "*.out" -exec rm {} \;
	rm -f ${DEPFILE}

%.out: $(patsubst %.c, %.o, ${SOURCES}) %.o  
	$(CC) $(LDFLAGS) -o $@ $^ ${LINKTO}

%.c.o: 
	$(CC) $(CFLAGS) -c $< -o $@

$(DEPFILE): $(SOURCES) $(TARGETS) $(TESTS) $(wildcard tools/*.c) $(DEPI)
	@tmp="$@.$$$$"; \
	trap 'rm -f "$$tmp"' 0; \
	trap 'exit 1' 1 2 15; \
	find targets/ sources/ -type f -name "*.c" | \
	    $(DEPI) --depfile="$@" $(MAP) $(DEPI_FLAGS) - > "$$tmp" && \
	mv "$$tmp" "$@"

include $(DEPFILE)
