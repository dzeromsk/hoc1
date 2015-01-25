%{
#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdint.h>
#include <float.h>

#define YYSTYPE int

void emitvn(uint32_t op, int n);
void emitvv(uint32_t op);
void printbc();
void eval();

#include "bc.def"

%}

%token NUMBER
%left '+' '-'
%left '*' '/' /* declared later to take precedence */
%left UNARYMINUS

%%

list:	  /* empty */
	| list '\n'
	| list expr '\n'	{ printbc(); eval(); }
	;
expr:	  NUMBER	{ emitvn(KNUM, $1); }
	| expr '+' expr { emitvv(ADDVV); }
	| expr '-' expr { emitvv(SUBVV); }
	| expr '*' expr { emitvv(MULVV); }
	| expr '/' expr { emitvv(DIVVV); }
	;

%%


#define MAGIC 0x014a4c1b

char* progname;
int lineno = 1;

struct {
	double value[256];
	size_t n;
} knum = {{0}, 0};

struct {
	uint32_t ops[256];
	size_t n;
} bc = {{0}, 0};

int slot = 0;

int main(int argc, char** argv) {
	progname = argv[0];
	yyparse();
	return 0;
}

typedef struct {
    uint8_t* b;
    size_t pos;
    size_t size;
} buf_t;

buf_t* new(size_t size) {
    uint8_t* b = calloc(size, sizeof(uint8_t));
    buf_t* buf = malloc(sizeof(buf_t));
    buf->b = b;
    buf->pos = 0;
    buf->size = size;
    return buf;
}

void destroy(buf_t* b) {
    free(b->b);
    free(b);
}

void resize(buf_t* b, size_t newsize) {
    b->b = realloc(b->b, newsize);
    b->size = newsize;
}

void need(buf_t* b, size_t size) {
    if (b->pos + size > b->size)
       resize(b, b->pos + size);
}

void write(buf_t* b, uint8_t* data, size_t size) {
    need(b, size);
    memcpy(b->b + b->pos, data, size);
    b->pos += size;
}

void write_byte(buf_t* b, uint8_t v) {
    write(b, &v, 1);
}

void write_dword(buf_t* b, uint32_t v) {
    write(b, (uint8_t*)&v, 4);
}

void write_uleb128(buf_t* b, uint64_t v) {
    uint8_t x;
    do {
        x = (uint8_t)v;
        v >>= 7;
        if (v)
            x |= 0x80;
        write_byte(b, x);
    } while (v);
}

void write_ktabk(buf_t* b);

void write_ktab(buf_t* b);

void write_kgc(buf_t* b) {
    write_byte(b, 0x0c); //type|string
    write_byte(b, 'h');
    write_byte(b, 'e');
    write_byte(b, 'l');
    write_byte(b, 'l');
    write_byte(b, 'o');
    write_byte(b, 'o');
    write_byte(b, '!');

    write_byte(b, 0x0a); //type|string
    write_byte(b, 'p');
    write_byte(b, 'r');
    write_byte(b, 'i');
    write_byte(b, 'n');
    write_byte(b, 't');
}

void write_knum_int(buf_t* b, int v) {
   write_uleb128(b, (uint64_t)v << 1);
}

void write_knum_double(buf_t* b, double d) {
   union {
       double d;
       struct {
           uint32_t lo;
           uint32_t hi;
	};
   } v;

   v.d = d;

   write_uleb128(b, (uint64_t)v.lo << 1 | 1);
   write_uleb128(b, v.hi);
}

void write_knum(buf_t* b) {
	int i;
	for (i = 0; i < knum.n; i++)
		write_knum_double(b, knum.value[i]);
}

void write_bytecode(buf_t* b) {
	slot--;
	emitvn(RET1, 2);
	int i;
	for (i = 0; i < bc.n; i++)
		write_dword(b, bc.ops[i]);
}

void write_proto(buf_t* b) {
    buf_t* p = new(8);
    // flagsB numparamsB framesizeB numuvB numkgcU numknU numbcU [debuglenU [firstlineU numlineU]]
    write_byte(p, 0x02); // flags
    write_byte(p, 0x00); // numparams
    write_byte(p, 0x02); // framesize
    write_byte(p, 0x00); // numuv
    write_uleb128(p, 0x02); // numkgc
    write_uleb128(p, knum.n); // numkn
    write_uleb128(p, bc.n + 1); // numbc

    // bcinsW* uvdataH* kgc* knum*
    write_bytecode(p);
    write_kgc(p);
    write_knum(p);

    write_uleb128(b, p->size);
    write(b, p->b, p->size);

    destroy(p);
}
void write_header(buf_t* b) {
    write_dword(b, MAGIC);
    write_byte(b, 0x02); // flags
}

void write_footer(buf_t* b) {
    write_byte(b, 0x00); // EOF
}

double exec(buf_t* b) {
    lua_State* L;
    int error;
    double ret = 0;

    L = luaL_newstate();
    //luaL_openlibs(L);

    error = luaL_loadbuffer(L, b->b, b->size, "(main)") ||
            lua_pcall(L, 0, 1, 0);
    if (error) {
      fprintf(stderr, "%s\n", lua_tostring(L, -1));
      lua_pop(L, 1);
    }

    if (lua_isnumber(L, -1))
       ret = lua_tonumber(L, -1);

    lua_close(L);

    return ret;
}

// D | A | OP
void emitvn(uint32_t op, int n) {
	bc.ops[bc.n++] = (n << 16) | (slot++ << 8) | op;
	
}

// B | C | A | OP
void emitvv(uint32_t op) {
	bc.ops[bc.n++] = (--slot << 24) | (--slot << 16) | (slot++ << 8) | op;
}

void printbc() {
	int i;
	for(i = 0; i < bc.n; i++)
		printf("%.3d\t %08x\n", i, bc.ops[i]);
}

void eval() {
	buf_t* b = new(6);

	write_header(b);
	write_proto(b);
	write_footer(b);

	printf("\t%f\n", exec(b));
	
	slot = 0;
	bc.n = 0;
	knum.n = 0;

	destroy(b);
}

int addknum(double v) {
	int i;
	for (i = 0; i < knum.n; i++)
		if (knum.value[i] == v)
			return i;
	knum.value[knum.n] = v;
	return knum.n++;
}

int yylex() {
	int c;
	
	while ((c=getchar()) == ' ' || c == '\t');

	if (c == EOF)
		return 0;
	if (c == '.' || isdigit(c)) {
		double v;
		ungetc(c, stdin);
		scanf("%lf", &v);
		yylval = addknum(v);
		return NUMBER;
	}
	if (c == '\n')
		lineno++;
	return c;
}

void warning(char* s, char* t) {
	fprintf(stderr, "%s: %s", progname, s);
	if (t)
		fprintf(stderr, " %s", t);
	fprintf(stderr, " near line %d\n", lineno);
}

int yyerror(char* s) {
	warning(s, (char*) 0);
}

