CFLAGS  = -O2 -I/usr/local/include/luajit-2.0
LDFLAGS = $(MYLDFLAGS) -lz

SOURCES = luazipfilter.c
LIB = zipfilter.so

OBJECTS = $(SOURCES:.c=.o)

all: $(LIB)

$(LIB): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@

$(OBJECTS): $(DEPS)

.c.o:
	$(CC) $(CFLAGS) $< -c -o $@

clean:
	rm -f $(OBJECTS) $(LIB)
