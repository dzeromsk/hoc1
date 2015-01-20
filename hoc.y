%{
#include <stdio.h>
#define YYSTYPE double
%}

%token NUMBER
%left '+' '-'
%left '*' '/' /* declared later to takes precedence */
%left UNARYMINUS

%%

list:	  /* empty */
	| list '\n'
	| list expr '\n'	{ printf("\t%.8g\n", $2); }
	;
expr:	  NUMBER	{ $$ = $1; }
	| '-' expr %prec UNARYMINUS { $$ = -$2; }
	| expr '+' expr { $$ = $1 + $3; }
	| expr '-' expr { $$ = $1 - $3; }
	| expr '*' expr { $$ = $1 * $3; } 
	| expr '/' expr { $$ = $1 / $3; }
	| '(' expr ')'	{ $$ = $2; }
	;

%%

#include <stdio.h>
#include <ctype.h>

char* progname;
int lineno = 1;

int main(int argc, char** argv) {
	progname = argv[0];
	yyparse();
	return 0;
}

int yylex() {
	int c;
	
	while ((c=getchar()) == ' ' || c == '\t');

	if (c == EOF)
		return 0;
	if (c == '.' || isdigit(c)) {
		ungetc(c, stdin);
		scanf("%1lf", &yylval);
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

