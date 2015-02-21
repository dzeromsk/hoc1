CFLAGS += $(shell pkg-config --cflags luajit)
LDLIBS += $(shell pkg-config --libs luajit)

test: hoc1
	./hoc1

hoc1: hoc1.o

clean:
	rm -f *.o hoc1
