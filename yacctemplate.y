%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "symbol.h"

extern int linenum;             /* declared in lex.l */
extern FILE *yyin;              /* declared by lex */
extern char *yytext;            /* declared by lex */
extern char buf[256];           /* declared in lex.l */
char *filename;
char error_buf[MAX_STRING_SIZE];
bool have_smerror = false;
int i, j, k;

char tmp_buf[256];
int tmp_retype; /* workaround for RETURN statement(v_type) */
bool have_return; /* workaround for RETURN statement(if def has return value, but no return value in body) */
int var_num = 0; /* to store the next local variable number */
table_stack stack;
typeStruct_t tmp_t;
symbol_attribute tmp_a;
typeList_t tmp_l;
symbol_table_entry *tmp_e;

FILE *asm_file;

void error(const char *msg){
    have_smerror = true;
    snprintf(error_buf, MAX_STRING_SIZE, "%s", msg);
    fprintf(stderr, "########## Error at Line#%d: %s ##########\n", linenum, error_buf);
}

void push_program(char *name){
    init_table_stack(&stack);
    tmp_t.v_type = T_VOID;
    tmp_t.dim = 0;
    tmp_t.is_const = true;
    push_table(&stack, 0);
    insert_table(&stack.table[stack.top], name, K_PROGRAM, &tmp_t, &tmp_a, -1);
}

void push_function_and_parameter(char *name, typeList_t list, typeStruct_t type){
    int x, y;
    /* if any array parameter, reverse. this is because the grammar rule of "multi_array" */
    for (i = 0; i <= list.end; i++) {
        if (list.argument_type[i].dim > 0) {
            for (x = 0, y = list.argument_type[i].dim - 1; x < y; x++, y--)
                exchange(list.argument_type[i].dims[x], list.argument_type[i].dims[y]);
        }
    }
    /* function */
    tmp_t.dim = 0;
    tmp_t.v_type = type.v_type;
    tmp_t.is_const = true;
    tmp_a.param_list = list;
    insert_table(&stack.table[stack.top], name, K_FUNCTION, &tmp_t, &tmp_a, -1);
    /* parameter */
    push_table(&stack, 0);
    for (i = 0; i <= list.end; i++) {
        tmp_t.v_type = list.argument_type[i].v_type;
        if (list.argument_type[i].dim == 0) {
            tmp_t.dim = 0;
        } else {
            tmp_t.dim = list.argument_type[i].dim;
            for (j = 0; j < tmp_t.dim; j++)
                tmp_t.dims[j] = list.argument_type[i].dims[j];
        }
        tmp_t.is_const = false;
        insert_table(&stack.table[stack.top], list.argument_name[i], K_PARAMETER, &tmp_t, &tmp_a, var_num);
        var_num++;
    }
}

void push_for_loop(char *name){
    tmp_t.v_type = T_INTEGER;
    tmp_t.dim = 0;
    tmp_t.is_const = true;
    push_table(&stack, 1);
    insert_table(&stack.table[stack.top], name, K_VARIABLE, &tmp_t, &tmp_a, -1);
}

void check_func_def_return(typeStruct_t *p_type){
    if (p_type->dim > 0) {
        error("FATAL ERROR: function return type cannot be array. program will stop.^_^");
        exit(-1);
    }
}

bool check_var_redeclare(char *id){ /* true if id is unique */
    if (!lookup_table(&stack.table[stack.top], id)) {
        return true;
    } else {
        char tmp[128];
        sprintf(tmp, "symbol %s is redeclared", id);
        error(tmp);
        return false;
    }
}

bool check_loop_var_unique(char *id){ /* true if id is unique */
    for (i = stack.top; i >= 0; i--) {
        if (!stack.table[i].scope_type)
            break;
        if (lookup_table(&stack.table[i], id))
            return false;
    }
    return true;
}

symbol_table_entry *check_id_all_scope(char *id){
    symbol_table_entry *tmp_ent;
    for (i = stack.top; i >= 0; i--) {
        if (tmp_ent = lookup_table(&stack.table[i], id))
            break;
    }
    return tmp_ent;
}

bool is_global(){
    if (stack.top == 0)
        return true;
    else
        return false;
}

%}

/* %code requires {
//     #include "symbol.h"
 }*/

%union {
    int value;
    char *text;
    int type;
    float rvalue;
    typeStruct_t typeStruct;
    typeList_t typeList;
}

%token COMMA
%token SEMICOLON
%token COLON
%token L_PAREN
%token R_PAREN
%token ML_BRACE
%token MR_BRACE

%token ADD_OP
%token SUB_OP
%token MUL_OP
%token DIV_OP
%token <text> LT_OP
%token <text> GT_OP
%token <text> EQ_OP
%token MOD_OP
%token ASSIGN_OP
%token <text> LE_OP
%token <text> GE_OP
%token <text> LG_OP

%token AND
%token OR
%token NOT
%token ARRAY
%token KW_BEGIN
%token <type> BOOLEAN
%token DEF
%token DO
%token ELSE
%token END
%token FALSE
%token FOR
%token <type> INTEGER
%token IF
%token OF
%token PRINT
%token READ
%token <type> REAL
%token <type> STRING
%token THEN
%token TO
%token TRUE
%token RETURN
%token VAR
%token WHILE

%token <text> IDENT
%token <value> OCTINT_CONST
%token <value> INT_CONST
%token <rvalue> FLOAT_CONST
%token <rvalue> SCIENTIFIC
%token <text> STR_CONST

%type <text> identifier programname relation_operator
%type <typeStruct> variable_reference type scalar_type multi_array literal_constant
%type <typeStruct> factor term arithmetic_expression relation_expression
%type <typeStruct> logical_factor logical_term logical_expression boolean_expr
%type <typeStruct> expression integer_expression
%type <typeStruct> dimension array_reference
%type <typeStruct> function_invoke_statement
%type <typeList> parameter_list identifier_list logical_expression_list
%type <value> integer_constant

%%

program	: programname{
            if(strcmp($1, filename))
                error("program beginning ID inconsist with file name");
            push_program($1);
            fprintf(asm_file, "; %s.j\n", filename);
            fprintf(asm_file, ".class public %s\n", filename);
            fprintf(asm_file, ".super java/lang/Object\n\n");
        } SEMICOLON programbody END IDENT{
            if(strcmp($1, $6))
                error("program end ID inconsist with the beginning ID");
            if(strcmp($6, filename))
                error("program end ID inconsist with file name");
            pop_table(&stack);
        }
		;

programname	: identifier {$$ = $1;}
		    ;

identifier : IDENT {$$ = $1;}
		   ;

programbody : varconst_declaration function_declaration {
                fprintf(asm_file, ".method public static main([Ljava/lang/String;)V\n");
                // fprintf(asm_file, ".limit stack 15\n");
                var_num = 1;
            }compound_statement{
                fprintf(asm_file, "return\n");
                fprintf(asm_file, ".end method\n");
            };

function_declaration : function_declaration IDENT L_PAREN parameter_list R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $7.v_type;
                        check_func_def_return(&$7);
                        push_function_and_parameter($2, $4, $7);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($2, $15))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN parameter_list R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($2, $4, tmp_t);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($2, $13))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $6.v_type;
                        check_func_def_return(&$6);
                        tmp_l.end = -1;
                        push_function_and_parameter($2, tmp_l, $6);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($2, $14))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_l.end = -1;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($2, tmp_l, tmp_t);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($2, $12))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | IDENT L_PAREN parameter_list R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $6.v_type;
                        check_func_def_return(&$6);
                        push_function_and_parameter($1, $3, $6);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($1, $14))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | IDENT L_PAREN parameter_list R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($1, $3, tmp_t);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($1, $12))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | IDENT L_PAREN R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $5.v_type;
                        check_func_def_return(&$5);
                        tmp_l.end = -1;
                        push_function_and_parameter($1, tmp_l, $5);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($1, $13))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    | IDENT L_PAREN R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_l.end = -1;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($1, tmp_l, tmp_t);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($1, $11))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);
                        var_num = 0;
                    }
                    |
                     ;

parameter_list : parameter_list SEMICOLON identifier_list COLON type{
                    if ($5.dim == 0) {
                        for (i = 0, k = $1.end+1; i <= $3.end; i++, k++) {
                            $1.argument_name[k] = strndup($3.argument_name[i], 32);
                            $1.argument_type[k].v_type = $5.v_type;
                            $1.argument_type[k].dim = 0;
                        }
                    } else {
                        // array parameter
                        for (i = 0, k = $1.end+1; i <= $3.end; i++, k++) {
                            $1.argument_name[k] = strndup($3.argument_name[i], 32);
                            $1.argument_type[k].v_type = $5.v_type;
                            $1.argument_type[k].dim = $5.dim;
                            for (j = 0; j < $5.dim; j++)
                                $1.argument_type[k].dims[j] = $5.dims[j];
                        }
                    }
                    $1.end += $3.end + 1;
                    memcpy(&$$, &$1, sizeof(typeList_t));
                }
               | identifier_list COLON type{
                    if ($3.dim == 0) {
                        for (i = 0; i <= $1.end; i++) {
                            $1.argument_type[i].v_type = $3.v_type;
                            $1.argument_type[i].dim = 0;
                        }
                    } else {
                        // array parameter
                        for (i = 0; i <= $1.end; i++) {
                            $1.argument_type[i].v_type = $3.v_type;
                            $1.argument_type[i].dim = $3.dim;
                            for (j = 0; j < $3.dim; j++)
                                $1.argument_type[i].dims[j] = $3.dims[j];
                        }
                    }
                    memcpy(&$$, &$1, sizeof(typeList_t));
                }
               ;

identifier_list : identifier_list COMMA IDENT{
                    $1.argument_name[++$1.end] = strndup($3, 32);
                    memcpy(&$$, &$1, sizeof(typeList_t));
                }
                | IDENT{
                    $$.end = 0;
                    $$.argument_name[$$.end] = strndup($1, 32);
                }
                ;

varconst_declaration : varconst_declaration VAR identifier_list COLON type SEMICOLON{
                        for (i = 0; i <= $3.end ; i++) {
                            if (check_var_redeclare($3.argument_name[i])){
                                $5.is_const = false;
                                if (is_global()) {
                                    switch($5.v_type){
                                    case T_INTEGER:
                                        fprintf(asm_file, ".field public static %s I\n", $3.argument_name[i]);
                                        break;
                                    case T_REAL:
                                        fprintf(asm_file, ".field public static %s F\n", $3.argument_name[i]);
                                        break;
                                    case T_BOOLEAN:
                                        fprintf(asm_file, ".field public static %s Z\n", $3.argument_name[i]);
                                        break;
                                    default:
                                        error("NO STRING VARIABLE AND OTHER TYPE");
                                    }
                                } else {
                                    insert_table(&stack.table[stack.top], $3.argument_name[i], K_VARIABLE, &$5, &tmp_a, var_num);
                                    var_num++;
                                }
                            }
                        }
                    }
                     | varconst_declaration VAR identifier_list COLON literal_constant SEMICOLON{
                        for (i = 0; i <= $3.end ; i++) {
                            if (check_var_redeclare($3.argument_name[i])){
                                switch($5.v_type){
                                case T_INTEGER:
                                    tmp_a.integer_val = $5.val;
                                    break;
                                case T_REAL:
                                    tmp_a.real_val = $5.rval;
                                    break;
                                case T_BOOLEAN:
                                    tmp_a.boolean_val = $5.bval;
                                    break;
                                case T_STRING:
                                    tmp_a.string_val = strdup($5.sval);
                                    break;
                                default:
                                    error("[DEBUG 1] SOME BUG...");
                                }
                                $5.is_const = true;
                                insert_table(&stack.table[stack.top], $3.argument_name[i], K_CONSTANT, &$5, &tmp_a, -1);
                            }
                        }
                     }
                     | VAR identifier_list COLON type SEMICOLON{
                        for (i = 0; i <= $2.end ; i++) {
                            if (check_var_redeclare($2.argument_name[i])){
                                $4.is_const = false;
                                if (is_global()) {
                                    switch($4.v_type){
                                    case T_INTEGER:
                                        fprintf(asm_file, ".field public static %s I\n", $2.argument_name[i]);
                                        break;
                                    case T_REAL:
                                        fprintf(asm_file, ".field public static %s F\n", $2.argument_name[i]);
                                        break;
                                    case T_BOOLEAN:
                                        fprintf(asm_file, ".field public static %s Z\n", $2.argument_name[i]);
                                        break;
                                    default:
                                        error("NO STRING VARIABLE AND OTHER TYPE");
                                    }
                                } else {
                                    insert_table(&stack.table[stack.top], $2.argument_name[i], K_VARIABLE, &$4, &tmp_a, var_num);
                                    var_num++;
                                }
                            }
                        }
                     }
                     | VAR identifier_list COLON literal_constant SEMICOLON{
                        for (i = 0; i <= $2.end ; i++) {
                            if (check_var_redeclare($2.argument_name[i])){
                                switch($4.v_type){
                                case T_INTEGER:
                                    tmp_a.integer_val = $4.val;
                                    break;
                                case T_REAL:
                                    tmp_a.real_val = $4.rval;
                                    break;
                                case T_BOOLEAN:
                                    tmp_a.boolean_val = $4.bval;
                                    break;
                                case T_STRING:
                                    tmp_a.string_val = strdup($4.sval);
                                    break;
                                default:
                                    error("[DEBUG 1] SOME BUG...");
                                }
                                $4.is_const = true;
                                insert_table(&stack.table[stack.top], $2.argument_name[i], K_CONSTANT, &$4, &tmp_a, -1);
                            }
                        }
                     }
                     |
                     ;

statement : compound_statement
          | simple_statement
          | conditional_statement
          | while_statement
          | for_statement
          | return_statement
          | function_invoke_statement SEMICOLON
          | statement compound_statement
          | statement simple_statement
          | statement conditional_statement
          | statement while_statement
          | statement for_statement
          | statement return_statement
          | statement function_invoke_statement SEMICOLON
          |
          ;

compound_statement : KW_BEGIN{push_table(&stack, 0);} varconst_declaration statement END{pop_table(&stack);}
                   ;

simple_statement : variable_reference ASSIGN_OP expression SEMICOLON{
                    if ($1.is_const) {
                        error("constant cannot be assigned");
                    } else if ($1.v_type != $3.v_type || $1.dim != $3.dim) {
                        if ($1.v_type == T_REAL && $3.v_type == T_INTEGER) {
                            /* coercion */
                        } else {
                            error("type mismatch in assignment");
                        }
                    }
                 }
                 | PRINT variable_reference SEMICOLON
                 | PRINT expression SEMICOLON
                 | PRINT function_invoke_statement SEMICOLON
                 | READ variable_reference SEMICOLON{
                    if ($2.is_const)
                        error("the variable(constant) should not change");
                 }
                 ;

conditional_statement : IF boolean_expr then_continue{
                        if ($2.v_type != T_BOOLEAN)
                            error("if statement's operand is not boolean type");
                      }
                      ;

/* some...workaround for error message above */
then_continue : THEN statement ELSE statement END IF
              | THEN statement END IF
              ;

while_statement : WHILE boolean_expr{
                    if ($2.v_type != T_BOOLEAN)
                        error("while statement's operand is not boolean type");
                } DO statement END DO;

for_statement : FOR IDENT ASSIGN_OP integer_constant TO integer_constant DO{
                    if ($4 < 0 || $6 < 0) {
                        error("lower or upper bound of loop parameter < 0");
                    } else if ($4 >= $6) {
                        error("loop parameter's lower bound >= uppper bound");
                    } else if (!check_loop_var_unique($2)) {
                        error("loop variable redeclared in nested loop");
                    } else {
                        push_for_loop($2);
                    }
              } statement END DO{
                    if (check_loop_var_unique($2))
                    pop_table(&stack);
              }
              ;

return_statement : RETURN expression SEMICOLON{
                    have_return = true;
                    if ($2.v_type != tmp_retype)
                        error("return type mismatch");
                 }
                 ;

function_invoke_statement : IDENT L_PAREN logical_expression_list R_PAREN{
                                tmp_e = check_id_all_scope($1);
                                if (!tmp_e) {
                                    sprintf(tmp_buf, "function '%s' is not declared", $1);
                                    error(tmp_buf);
                                } else {
                                    if (tmp_e->attr.param_list.end > $3.end) {
                                        sprintf(tmp_buf, "too few arguments to function '%s'", $1);
                                        error(tmp_buf);
                                    } else if (tmp_e->attr.param_list.end < $3.end) {
                                        sprintf(tmp_buf, "too many arguments to function '%s'", $1);
                                        error(tmp_buf);
                                    } else {
                                        for (i = 0; i <= $3.end ; i++) {
                                            if ((tmp_e->attr.param_list.argument_type[i].dim != $3.argument_type[i].dim) ||
                                                (tmp_e->attr.param_list.argument_type[i].v_type != $3.argument_type[i].v_type)) {
                                                if ((tmp_e->attr.param_list.argument_type[i].v_type == T_REAL) &&
                                                    ($3.argument_type[i].v_type == T_INTEGER)) {
                                                    /* coercion */
                                                } else {
                                                    break;
                                                }
                                            }
                                        }
                                        if (i <= $3.end) {
                                            error("parameter type mismatch");
                                        } else {
                                            $$.v_type = tmp_e->type.v_type;
                                            $$.dim = 0;
                                        }
                                    }
                                }
                          }
                          | IDENT L_PAREN R_PAREN{
                                tmp_e = check_id_all_scope($1);
                                if (!tmp_e) {
                                    sprintf(tmp_buf, "function '%s' is not declared", $1);
                                    error(tmp_buf);
                                } else {
                                    if (tmp_e->attr.param_list.end != -1) {
                                        sprintf(tmp_buf, "too few arguments to function '%s'", $1);
                                        error(tmp_buf);
                                    } else {
                                        $$.v_type = tmp_e->type.v_type;
                                        $$.dim = 0;
                                    }
                                }
                          }
                          ;

expression : logical_expression{$$ = $1;}
           ;

boolean_expr : logical_expression{$$ = $1;}
             ;

logical_expression : logical_expression OR logical_term{
                        if ($1.v_type != T_BOOLEAN || $3.v_type != T_BOOLEAN) {
                            error("operand(s) between 'or' are not boolean");
                        } else {
                            $$.v_type = T_BOOLEAN;
                            $$.dim = 0;
                        }
                   }
                   | logical_term{$$ = $1;}
                   ;

logical_term : logical_term AND logical_factor{
                if ($1.v_type != T_BOOLEAN || $3.v_type != T_BOOLEAN) {
                    error("operand(s) between 'and' are not boolean");
                } else {
                    $$.v_type = T_BOOLEAN;
                    $$.dim = 0;
                }
             }
             | logical_factor{$$ = $1;}
             ;

logical_factor : NOT logical_factor{
                    if ($2.v_type != T_BOOLEAN) {
                        error("operand of 'not' is not boolean");
                    } else {
                        $$.v_type = T_BOOLEAN;
                        $$.dim = 0;
                    }
               }
               | relation_expression{$$ = $1;}
               ;

relation_expression : arithmetic_expression relation_operator arithmetic_expression{
                        if (($1.v_type != T_INTEGER && $1.v_type != T_REAL) ||
                            ($3.v_type != T_INTEGER && $3.v_type != T_REAL)){
                            sprintf(tmp_buf, "operand(s) between '%s' are not integer/real", $2);
                            error(tmp_buf);
                        } else { /* may coercion */
                            $$.v_type = T_BOOLEAN;
                            $$.dim = 0;
                        }
                    }
                    | arithmetic_expression{$$ = $1;}
                    ;

relation_operator : LT_OP{$$ = $1;}
                  | LE_OP{$$ = $1;}
                  | EQ_OP{$$ = $1;}
                  | GE_OP{$$ = $1;}
                  | GT_OP{$$ = $1;}
                  | LG_OP{$$ = $1;}
                  ;

arithmetic_expression : arithmetic_expression ADD_OP term{
                        if (($1.v_type != T_INTEGER && $1.v_type != T_REAL) ||
                                ($3.v_type != T_INTEGER && $3.v_type != T_REAL)) {
                            if ($1.v_type == T_STRING && $3.v_type == T_STRING) {
                                /* string concatenation */
                                $$.v_type = T_STRING;
                                $$.dim = 0;
                            } else {
                                error("operand(s) between '+' are not integer/real");
                            }
                        } else {
                            if ($1.v_type == T_REAL || $3.v_type == T_REAL) {/* coercion */
                                $$.v_type = T_REAL;
                                $$.dim = 0;
                            } else {
                                $$.v_type = T_INTEGER;
                                $$.dim = 0;
                            }
                        }
                      }
                      | arithmetic_expression SUB_OP term{
                        if (($1.v_type != T_INTEGER && $1.v_type != T_REAL) ||
                            ($3.v_type != T_INTEGER && $3.v_type != T_REAL)){
                            error("operand(s) between '-' are not integer/real");
                        } else {
                            if ($1.v_type == T_REAL || $3.v_type == T_REAL) {/* coercion */
                                $$.v_type = T_REAL;
                                $$.dim = 0;
                            } else {
                                $$.v_type = T_INTEGER;
                                $$.dim = 0;
                            }
                        }
                      }
                      | relation_expression{$$ = $1;}
                      | term{$$ = $1;}
                      ;

term : term MUL_OP factor{
        if (($1.v_type != T_INTEGER && $1.v_type != T_REAL) ||
            ($3.v_type != T_INTEGER && $3.v_type != T_REAL)){
            error("operand(s) between '*' are not integer/real");
        } else {
            if ($1.v_type == T_REAL || $3.v_type == T_REAL) {/* coercion */
                $$.v_type = T_REAL;
                $$.dim = 0;
            } else {
                $$.v_type = T_INTEGER;
                $$.dim = 0;
            }
        }
     }
     | term DIV_OP factor{
        if (($1.v_type != T_INTEGER && $1.v_type != T_REAL) ||
            ($3.v_type != T_INTEGER && $3.v_type != T_REAL)){
            error("operand(s) between '/' are not integer/real");
        } else {
            if ($1.v_type == T_REAL || $3.v_type == T_REAL) {/* coercion */
                $$.v_type = T_REAL;
                $$.dim = 0;
            } else {
                $$.v_type = T_INTEGER;
                $$.dim = 0;
            }
        }
     }
     | term MOD_OP factor{
        if (!($1.v_type == T_INTEGER && $3.v_type == T_INTEGER)){
            error("operand(s) between 'mod' are not integer");
        } else {
            $$.v_type = T_INTEGER;
            $$.dim = 0;
        }
     }
     | factor{$$ = $1;}
     ;

factor : literal_constant{$$ = $1;}
       | variable_reference{$$ = $1;}
       | function_invoke_statement{$$ = $1;}
       | L_PAREN logical_expression R_PAREN{$$=$2;}
       | SUB_OP factor{$$=$2;}
       ;

logical_expression_list : logical_expression_list COMMA logical_expression{
                            $1.argument_type[++$1.end].v_type = $3.v_type;
                            $1.argument_type[$1.end].dim = $3.dim;
                            memcpy(&$$, &$1, sizeof(typeList_t));
                        }
                        | logical_expression{
                            $$.end = 0;
                            $$.argument_type[0].v_type = $1.v_type;
                            $$.argument_type[0].dim = $1.dim;
                        }
                        ;

variable_reference : IDENT{
                        tmp_e = check_id_all_scope($1);
                        if (!tmp_e) {
                            sprintf(tmp_buf, "'%s' is not declared", $1);
                            error(tmp_buf);
                        } else if (tmp_e->type.dim > 0) {
                            error("P language disallow array arithmetic");
                        } else {
                            $$ = tmp_e->type;
                        }
                   }
                   | array_reference{$$ = $1;}
                   ;

array_reference : IDENT dimension{
                    tmp_e = check_id_all_scope($1);
                    if (!tmp_e) {
                        sprintf(tmp_buf, "'%s' is not declared", $1);
                        error(tmp_buf);
                    } else {
                        if (tmp_e->type.dim != $2.dim) {
                            error("P language disallow array arithmetic");
                        } else {/* actually it should be index, passed from 'integer_expression' in 'dimension' */
                            $$ = tmp_e->type;
                        }
                    }
                };

dimension : dimension ML_BRACE integer_expression MR_BRACE{
            if ($3.v_type != T_INTEGER)
                error("array index must be integer type");
            $1.dim++;
            $$ = $1;
          }
          | ML_BRACE integer_expression MR_BRACE{
            if ($2.v_type != T_INTEGER)
                error("array index must be integer type");
            $$.dim = 1;
          }
          ;

integer_expression : logical_expression{$$ = $1;}
                   ;

literal_constant : integer_constant{
                    $$.val = $1;
                    $$.dim = 0;
                    $$.v_type = T_INTEGER;
                 }
                 | SUB_OP integer_constant{
                    $$.val = $2;
                    $$.dim = 0;
                    $$.v_type = T_INTEGER;
                 }
                 | FLOAT_CONST{
                    $$.rval = $1;
                    $$.dim = 0;
                    $$.v_type = T_REAL;
                 }
                 | SUB_OP FLOAT_CONST{
                    $$.rval = $2;
                    $$.dim = 0;
                    $$.v_type = T_REAL;
                 }
                 | SCIENTIFIC{
                    $$.rval = $1;
                    $$.dim = 0;
                    $$.v_type = T_REAL;
                 }
                 | SUB_OP SCIENTIFIC{
                    $$.rval = $2;
                    $$.dim = 0;
                    $$.v_type = T_REAL;
                 }
                 | STR_CONST{
                    $$.sval = strdup($1);
                    $$.dim = 0;
                    $$.v_type = T_STRING;
                 }
                 | TRUE{
                    $$.bval = true;
                    $$.dim = 0;
                    $$.v_type = T_BOOLEAN;
                 }
                 | FALSE{
                    $$.bval = false;
                    $$.dim = 0;
                    $$.v_type = T_BOOLEAN;
                 }
                 ;

integer_constant : INT_CONST{$$ = $1;}
                 | OCTINT_CONST{$$ = $1;}
                 ;

type : scalar_type{$$ = $1; $$.dim = 0;}
     | multi_array{$$ = $1;}
     ;

multi_array : ARRAY integer_constant TO integer_constant OF multi_array{
                if ($2 < 0 || $4 < 0)
                    error("array index must be greater than or equal to zero");
                if ($2 >= $4)
                    error("the upper bound of an array must be greater than its lower bound");
                $6.dims[$6.dim++] = $4 - $2 + 1;
                $$ = $6;
            }
            | scalar_type{
                $1.dim = 0;
                $$ = $1;
            }
            ;

scalar_type : INTEGER{$$.v_type = $1;}
            | REAL{$$.v_type = $1;}
            | STRING{$$.v_type = $1;}
            | BOOLEAN{$$.v_type = $1;}
            ;

%%

int yyerror( char *msg )
{
    fprintf( stderr, "\n|--------------------------------------------------------------------------\n" );
	fprintf( stderr, "| Error found in Line #%d: %s\n", linenum, buf );
	fprintf( stderr, "|\n" );
	fprintf( stderr, "| Unmatched token: %s\n", yytext );
    fprintf( stderr, "|--------------------------------------------------------------------------\n" );
    exit(-1);
}

int  main( int argc, char **argv )
{
	if( argc != 2 ) {
		fprintf(  stdout,  "Usage:  ./parser  [filename]\n"  );
		exit(0);
	}

    filename = strdup(argv[1]);
    char *dot = strchr(filename, '.');
    if(dot) *dot = '\0';

    char asm_name[MAX_STRING_SIZE];
    snprintf(asm_name, MAX_STRING_SIZE, "%s.j", filename);
    asm_file = fopen( asm_name, "w" );

	FILE *fp = fopen( argv[1], "r" );

	if( fp == NULL )  {
		fprintf( stdout, "Open  file  error\n" );
		exit(-1);
	}
	yyin = fp;
	yyparse();

    fprintf( stdout, "\n" );
    if (have_smerror) {
        fprintf( stdout, "|--------------------------------|\n" );
        fprintf( stdout, "|  There is no syntactic error!  |\n" );
        fprintf( stdout, "|--------------------------------|\n" );
    } else {
        fprintf( stdout, "|-------------------------------------------|\n" );
        fprintf( stdout, "| There is no syntactic and semantic error! |\n" );
        fprintf( stdout, "|-------------------------------------------|\n" );
    }

	exit(0);
}
