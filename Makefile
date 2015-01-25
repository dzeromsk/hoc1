CFLAGS += $(shell pkg-config --cflags luajit)
LDLIBS += $(shell pkg-config --libs luajit)

test: hocjit
	./hocjit
hocjit: hocjit.o
clean:
	rm -f *.o hocjit
