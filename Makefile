TARGET = parser
OBJECT = lex.yy.c y.*
CC = gcc
CCFLAG = -O2
LEX = lex
YACC = yacc -d
LIBS = -ll -ly

all: lex.yy.c y.tab.c
	$(CC) $(CCFLAG) lex.yy.c y.tab.c symbol.c -o $(TARGET) $(LIBS)

lex.yy.c: lextemplate.l
	$(LEX) lextemplate.l

y.tab.c: yacctemplate.y
	$(YACC) yacctemplate.y

clean:
	rm -f $(TARGET) $(OBJECT) *.j *.class
