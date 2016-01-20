%{
#include "symbol.h"
#include <string.h>
#include "y.tab.h"

#define LIST               strcat(buf, yytext)
#define token(t)           {LIST; if (Opt_T) printf("<%s>\n", #t);}
#define tokenChar(t)       {LIST; if (Opt_T) printf("<%c>\n", (t));}
#define tokenInteger(t, i) {LIST; if (Opt_T) printf("<%s: %d>\n", #t, (i));}
#define tokenString(t, s)  {LIST; if (Opt_T) printf("<%s: %s>\n", #t, (s));}
#define MAX_LINE_LENG      256

extern FILE *asm_file;

int Opt_S = 1;
int Opt_T = 1;
int Opt_D = 1;
int linenum = 1;
char buf[MAX_LINE_LENG];
char str[MAX_LINE_LENG];
int legal_string = 1;
%}
digit [0-9]
letter [a-zA-Z]

/* exclusive start conditions */
%x M_COMMENT
%x S_COMMENT
%x STR
%%

"//&"[STD][+-]  {
                    LIST;
                    switch (yytext[3]) {
                    case 'S':
                        if (yytext[4] == '+')   Opt_S = 1;
                        if (yytext[4] == '-')   Opt_S = 0;
                        break;
                    case 'T':
                        if (yytext[4] == '+')   Opt_T = 1;
                        if (yytext[4] == '-')   Opt_T = 0;
                        break;
                    case 'D':
                        if (yytext[4] == '+')   Opt_D = 1;
                        if (yytext[4] == '-')   Opt_D = 0;
                        break;
                    default:
                        printf("[ERROR] %c <= No such an option currently.\n", yytext[3]);
                        exit(-1);
                    }
                }
"//" { LIST; BEGIN S_COMMENT;}
"/*" { LIST; BEGIN M_COMMENT;}

","     { tokenChar(yytext[0]); return COMMA; }
";"     { tokenChar(yytext[0]); return SEMICOLON; }
":"     { tokenChar(yytext[0]); return COLON; }
"("     { tokenChar(yytext[0]); return L_PAREN; }
")"     { tokenChar(yytext[0]); return R_PAREN; }
"["     { tokenChar(yytext[0]); return ML_BRACE; }
"]"     { tokenChar(yytext[0]); return MR_BRACE; }
"+"     { tokenChar(yytext[0]); return ADD_OP; }
"-"     { tokenChar(yytext[0]); return SUB_OP; }
"*"     { tokenChar(yytext[0]); return MUL_OP; }
"/"     { tokenChar(yytext[0]); return DIV_OP; }
"<"     { tokenChar(yytext[0]); yylval.text = strdup(yytext); return LT_OP; }
">"     { tokenChar(yytext[0]); yylval.text = strdup(yytext); return GT_OP; }
"="     { tokenChar(yytext[0]); yylval.text = strdup(yytext); return EQ_OP; }
mod     { token(mod); return MOD_OP; }
":="    { token(:=); return ASSIGN_OP; }
"<="    { token(<=); yylval.text = strdup(yytext); return LE_OP; }
">="    { token(>=); yylval.text = strdup(yytext); return GE_OP; }
"<>"    { token(<>); yylval.text = strdup(yytext); return LG_OP; }
and     { token(and); return AND; }
or      { token(or); return OR; }
not     { token(not); return NOT; }
array   { token(KWarray); return ARRAY; }
begin   { token(KWbegin); return KW_BEGIN; }
boolean { token(KWboolean); yylval.type = T_BOOLEAN; return BOOLEAN; }
def     { token(KWdef); return DEF; }
do      { token(KWdo); return DO; }
else    { token(KWelse); return ELSE; }
end     { token(KWend); return END; }
false   { token(KWfalse); return FALSE; }
for     { token(KWfor); return FOR; }
integer { token(KWinteger); yylval.type = T_INTEGER; return INTEGER; }
if      { token(KWif); return IF; }
of      { token(KWof); return OF; }
print   { token(KWprint); return PRINT; }
read    { token(KWread); return READ; }
real    { token(KWreal); yylval.type = T_REAL; return REAL; }
string  { token(KWstring); yylval.type = T_STRING; return STRING; }
then    { token(KWthen); return THEN; }
to      { token(KWto); return TO; }
true    { token(KWtrue); return TRUE; }
return  { token(KWreturn); return RETURN; }
var     { token(KWvar); return VAR; }
while   { token(KWwhile); return WHILE; }
{letter}({letter}|{digit})*                     { tokenString(id, yytext); yylval.text = strdup(yytext); return IDENT; }
0[0-7]+                                         { tokenString(oct_integer, yytext);
                                                  sscanf(yytext, "%o", &yylval.value);
                                                  return OCTINT_CONST;
                                                }
0|[1-9][0-9]*                                   { tokenString(integer, yytext); yylval.value = atoi(yytext); return INT_CONST;}
(0|[1-9][0-9]*)\.[0-9]*                         { tokenString(float, yytext); yylval.rvalue = atof(yytext); return FLOAT_CONST; }
0[0-7]+[Ee][+-]?(0|[1-9][0-9]*)                 |
(0|[1-9][0-9]*)[Ee][+-]?(0|[1-9][0-9]*)         |
(0|[1-9][0-9]*)\.[0-9]*[Ee][+-]?(0|[1-9][0-9]*) |

0[0-7]+[Ee][+-]?0[0-7]+                         |
(0|[1-9][0-9]*)[Ee][+-]?0[0-7]+                 |
(0|[1-9][0-9]*)\.[0-9]*[Ee][+-]?0[0-7]+         { tokenString(scientific, yytext);
                                                  sscanf(yytext, "%e", &yylval.rvalue);
                                                  return SCIENTIFIC;
                                                }
\"  { LIST; BEGIN STR; }
[ \t]   { LIST; }
\n      {
            LIST;
            if (Opt_S)
                printf("%d: %s", linenum, buf);
            fprintf(asm_file, "; Line #%d: %s", linenum, buf);
            linenum++;
            buf[0] = '\0';
        }
.   { LIST; printf("[ERROR] %s <= WTF with this?\n", yytext); exit(-1);}


<STR>\"      {
                    //LIST;
                    if (legal_string) {
                        yylval.text = strdup(str);
                        str[0] = '\0';
                        tokenString(string, str);
                        BEGIN INITIAL;
                        return STR_CONST;
                    } else {
                        LIST;
                        str[0] = '\0';
                        legal_string = 1;
                        BEGIN INITIAL;
                    }
                    // str[0] = '\0';
                    // legal_string = 1;
                    // BEGIN INITIAL;
                }
<STR>\"\"    { LIST; strcat(str, "\""); }
<STR>.       { LIST; strcat(str, yytext); }
<STR>\n      {
                    LIST;
                    if (Opt_S)
                        printf("%d: %s", linenum, buf);
                    linenum++;
                    buf[0] = '\0';
                    legal_string = 0;
                    printf("[ERROR] You can't embed new line in a string!\n");
                    exit(-1);
                }

<M_COMMENT>.       { LIST; }
<M_COMMENT>\n      {
                        LIST;
                        if (Opt_S)
                            printf("%d: %s", linenum, buf);
                        linenum++;
                        buf[0] = '\0';
                    }
<M_COMMENT>"*/"    { LIST; BEGIN INITIAL; }

<S_COMMENT>.   { LIST; }
<S_COMMENT>\n  {
                    LIST;
                    if (Opt_S)
                        printf("%d: %s", linenum, buf);
                    linenum++;
                    buf[0] = '\0';
                    BEGIN INITIAL;
                }
