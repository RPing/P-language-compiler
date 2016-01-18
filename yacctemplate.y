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
int label_num = 0;
int if_false_num = 0;
int if_exit_num = 0;
int if_count = 0;
int for_begin_num = 0;
int for_true_num = 0;
int for_false_num = 0;
int for_exit_num = 0;
int while_begin_num = 0;
int while_true_num = 0;
int while_false_num = 0;
int while_exit_num = 0;
table_stack stack;
typeStruct_t tmp_t;
symbol_attribute tmp_a;
typeList_t tmp_l;
symbol_table_entry *tmp_e;
symbol_table_entry *tmp_param_e;

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

void push_for_loop(symbol_table_entry *e){
    tmp_t.v_type = T_INTEGER;
    tmp_t.dim = 0;
    tmp_t.is_const = true;
    push_table(&stack, 1);
    insert_table(&stack.table[stack.top], e->name, K_VARIABLE, &tmp_t, &tmp_a, e->number);
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

bool current_global_scope(){
    if (stack.top == 0)
        return true;
    else
        return false;
}

bool is_global(int level){
    if (level == 0)
        return true;
    else
        return false;
}

void asm_function_head(char *name, typeList_t *param, typeStruct_t *re, bool param_empty, bool is_void){
    fprintf(asm_file, ".method public static %s(", name);
    if (!param_empty) {
        for (i = 0; i <= param->end; i++) {
            switch(param->argument_type[i].v_type){
            case T_INTEGER:
                fprintf(asm_file, "I");
                break;
            case T_BOOLEAN:
                fprintf(asm_file, "Z");
                break;
            case T_REAL:
                fprintf(asm_file, "F");
                break;
            }
        }
    }

    if (is_void) {
        fprintf(asm_file, ")V\n");
    } else {
        switch(re->v_type){
        case T_INTEGER:
            fprintf(asm_file, ")I\n");
            break;
        case T_BOOLEAN:
            fprintf(asm_file, ")Z\n");
            break;
        case T_REAL:
            fprintf(asm_file, ")F\n");
            break;
        }
    }

    fprintf(asm_file, ".limit stack 15\n");
    fprintf(asm_file, ".limit locals 20\n");
}

void asm_id_reference(symbol_table_entry *tmp_e, symbol_table_entry *code){
    char temp[100];
    if (code) {
        if (is_global(tmp_e->level) && !(tmp_e->type.is_const)) { /* global var */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
            case T_BOOLEAN: /* treat boolean type as int in JVM */
                sprintf(temp, "getstatic %s/%s I\n", filename, tmp_e->name);
                break;
            case T_REAL:
                sprintf(temp, "getstatic %s/%s R\n", filename, tmp_e->name);
                break;
            default:
                error("NO STRING VARIABLE AND OTHER TYPE");
            }
        } else if (!is_global(tmp_e->level) && !(tmp_e->type.is_const)) { /* local var */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
            case T_BOOLEAN: /* treat boolean type as int in JVM */
                sprintf(temp, "iload %d\n", tmp_e->number);
                break;
            case T_REAL:
                sprintf(temp, "fload %d\n", tmp_e->number);
                break;
            default:
                error("NO STRING VARIABLE AND OTHER TYPE");
            }
        } else if (tmp_e->type.is_const) { /* id const */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
                sprintf(temp, "sipush %d\n", tmp_e->attr.integer_val);
                break;
            case T_BOOLEAN:
                sprintf(temp, "%s", tmp_e->attr.boolean_val? "iconst_1\n":"iconst_0\n");
                break;
            case T_REAL:
                sprintf(temp, "ldc %f\n", tmp_e->attr.real_val);
                break;
            case T_STRING:
                sprintf(temp, "ldc \"%s\"\n", tmp_e->attr.string_val);
                break;
            default:
                error("[DEBUG 2] SOME BUG...");
            }
        } else {
            error("[DEBUG 2] SOME BUG...");
        }
        strcat(code->asm_buf, temp);
    } else {
        if (is_global(tmp_e->level) && !(tmp_e->type.is_const)) { /* global var */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
            case T_BOOLEAN: /* treat boolean type as int in JVM */
                fprintf(asm_file, "getstatic %s/%s I\n", filename, tmp_e->name);
                break;
            case T_REAL:
                fprintf(asm_file, "getstatic %s/%s R\n", filename, tmp_e->name);
                break;
            default:
                error("NO STRING VARIABLE AND OTHER TYPE");
            }
        } else if (!is_global(tmp_e->level) && !(tmp_e->type.is_const)) { /* local var */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
            case T_BOOLEAN: /* treat boolean type as int in JVM */
                fprintf(asm_file, "iload %d\n", tmp_e->number);
                break;
            case T_REAL:
                fprintf(asm_file, "fload %d\n", tmp_e->number);
                break;
            default:
                error("NO STRING VARIABLE AND OTHER TYPE");
            }
        } else if (tmp_e->type.is_const) { /* id const */
            switch(tmp_e->type.v_type){
            case T_INTEGER:
                fprintf(asm_file, "sipush %d\n", tmp_e->attr.integer_val);
                break;
            case T_BOOLEAN:
                fprintf(asm_file, "%s", tmp_e->attr.boolean_val? "iconst_1\n":"iconst_0\n");
                break;
            case T_REAL:
                fprintf(asm_file, "ldc %f\n", tmp_e->attr.real_val);
                break;
            case T_STRING:
                fprintf(asm_file, "ldc \"%s\"\n", tmp_e->attr.string_val);
                break;
            default:
                error("[DEBUG 2] SOME BUG...");
            }
        } else {
            error("[DEBUG 2] SOME BUG...");
        }
    }
}

void asm_literal_constant(symbol_table_entry *tmp_e, symbol_table_entry *code){
    char temp[100];
    if (code) {
        switch(tmp_e->type.v_type){
        case T_INTEGER:
            sprintf(temp, "sipush %d\n", tmp_e->type.val);
            break;
        case T_BOOLEAN:
            sprintf(temp, "%s", tmp_e->type.bval? "iconst_1\n":"iconst_0\n");
            break;
        case T_REAL:
            sprintf(temp, "ldc %f\n", tmp_e->type.rval);
            break;
        case T_STRING:
            sprintf(temp, "ldc \"%s\"\n", tmp_e->type.sval);
            break;
        default:
            error("[DEBUG 3] SOME BUG...");
        }
        strcat(code->asm_buf, temp);
    } else {
        switch(tmp_e->type.v_type){
        case T_INTEGER:
            fprintf(asm_file, "sipush %d\n", tmp_e->type.val);
            break;
        case T_BOOLEAN:
            fprintf(asm_file, "%s", tmp_e->type.bval? "iconst_1\n":"iconst_0\n");
            break;
        case T_REAL:
            fprintf(asm_file, "ldc %f\n", tmp_e->type.rval);
            break;
        case T_STRING:
            fprintf(asm_file, "ldc \"%s\"\n", tmp_e->type.sval);
            break;
        default:
            error("[DEBUG 3] SOME BUG...");
        }
    }

}

void asm_store(symbol_table_entry *tmp_e){
    if (is_global(tmp_e->level)) {
        switch(tmp_e->type.v_type){
        case T_INTEGER:
            fprintf(asm_file, "putstatic %s/%s I\n", filename, tmp_e->name);
            break;
        case T_BOOLEAN:
            fprintf(asm_file, "putstatic %s/%s Z\n", filename, tmp_e->name);
            break;
        case T_REAL:
            fprintf(asm_file, "putstatic %s/%s F\n", filename, tmp_e->name);
            break;
        default:
            error("NO STRING VARIABLE AND OTHER TYPE");
        }
    } else {
        switch(tmp_e->type.v_type){
        case T_INTEGER:
        case T_BOOLEAN: /* treat boolean type as int in JVM */
            fprintf(asm_file, "istore %d\n", tmp_e->number);
            break;
        case T_REAL:
            fprintf(asm_file, "fstore %d\n", tmp_e->number);
            break;
        default:
            error("NO STRING VARIABLE AND OTHER TYPE");
        }
    }
}

%}

/* in the begining of the development, these lines should be used.
%code requires {
//     #include "symbol.h"
 }*/

%union {
    int value;
    char *text;
    int type;
    float rvalue;
    typeStruct_t typeStruct;
    typeList_t typeList;
    symbol_table_entry entry;
    statement_c countStruct;
    param_l p_list;
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
%type <entry> logical_factor factor
%type <entry> variable_reference array_reference literal_constant
%type <entry> logical_expression integer_expression expression arithmetic_expression relation_expression
%type <entry> boolean_expr logical_term term
%type <entry> function_invoke_statement
%type <typeStruct> type scalar_type multi_array
%type <typeStruct> dimension
%type <typeList> parameter_list identifier_list
%type <value> integer_constant
%type <countStruct> statement
%type <p_list> logical_expression_list

%%

program	: programname{
            if(strcmp($1, filename))
                error("program beginning ID inconsist with file name");
            push_program($1);
            fprintf(asm_file, "; %s.j\n", filename);
            fprintf(asm_file, ".class public %s\n", filename);
            fprintf(asm_file, ".super java/lang/Object\n");
            fprintf(asm_file, ".field public static _sc Ljava/util/Scanner;\n\n");
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
                fprintf(asm_file, ".limit stack 15\n");
                fprintf(asm_file, ".limit locals 20\n");
                fprintf(asm_file, "new java/util/Scanner\n");
                fprintf(asm_file, "dup\n");
                fprintf(asm_file, "getstatic java/lang/System/in Ljava/io/InputStream;\n");
                fprintf(asm_file, "invokespecial java/util/Scanner/<init>(Ljava/io/InputStream;)V\n");
                fprintf(asm_file, "putstatic %s/_sc Ljava/util/Scanner;\n", filename);
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
                        asm_function_head($2, &$4, &$7, false, false);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($2, $15))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN parameter_list R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($2, $4, tmp_t);
                        asm_function_head($2, &$4, &tmp_t, false, true);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($2, $13))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $6.v_type;
                        check_func_def_return(&$6);
                        tmp_l.end = -1;
                        push_function_and_parameter($2, tmp_l, $6);
                        asm_function_head($2, &tmp_l, &$6, true, false);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($2, $14))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | function_declaration IDENT L_PAREN R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_l.end = -1;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($2, tmp_l, tmp_t);
                        asm_function_head($2, &tmp_l, &tmp_t, true, true);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($2, $12))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | IDENT L_PAREN parameter_list R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $6.v_type;
                        check_func_def_return(&$6);
                        push_function_and_parameter($1, $3, $6);
                        asm_function_head($1, &$3, &$6, false, false);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($1, $14))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | IDENT L_PAREN parameter_list R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($1, $3, tmp_t);
                        asm_function_head($1, &$3, &tmp_t, false, true);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($1, $12))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | IDENT L_PAREN R_PAREN COLON type{
                        have_return = false;
                        tmp_retype = $5.v_type;
                        check_func_def_return(&$5);
                        tmp_l.end = -1;
                        push_function_and_parameter($1, tmp_l, $5);
                        asm_function_head($1, &tmp_l, &$5, true, false);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (!have_return)
                            error("return type mismatch");
                        if (strcmp($1, $13))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
                        var_num = 0;
                    }
                    | IDENT L_PAREN R_PAREN{
                        have_return = true;
                        tmp_retype = T_VOID;
                        tmp_l.end = -1;
                        tmp_t.v_type = T_VOID;
                        push_function_and_parameter($1, tmp_l, tmp_t);
                        asm_function_head($1, &tmp_l, &tmp_t, true, true);
                    } SEMICOLON KW_BEGIN varconst_declaration statement END END IDENT{
                        if (strcmp($1, $11))
                            error("the end of the functionName mismatch");
                        pop_table(&stack);

                        if (tmp_retype == T_VOID)
                            fprintf(asm_file, "return\n");
                        fprintf(asm_file, ".end method\n");
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
                                if (current_global_scope()) {
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
                                    insert_table(&stack.table[stack.top], $3.argument_name[i], K_VARIABLE, &$5, &tmp_a, -1);
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
                                switch($5.type.v_type){
                                case T_INTEGER:
                                    tmp_a.integer_val = $5.type.val;
                                    break;
                                case T_REAL:
                                    tmp_a.real_val = $5.type.rval;
                                    break;
                                case T_BOOLEAN:
                                    tmp_a.boolean_val = $5.type.bval;
                                    break;
                                case T_STRING:
                                    tmp_a.string_val = strdup($5.type.sval);
                                    break;
                                default:
                                    error("[DEBUG 1] SOME BUG...");
                                }
                                $5.type.is_const = true;
                                insert_table(&stack.table[stack.top], $3.argument_name[i], K_CONSTANT, &$5.type, &tmp_a, -1);
                            }
                        }
                     }
                     | VAR identifier_list COLON type SEMICOLON{
                        for (i = 0; i <= $2.end ; i++) {
                            if (check_var_redeclare($2.argument_name[i])){
                                $4.is_const = false;
                                if (current_global_scope()) {
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
                                    insert_table(&stack.table[stack.top], $2.argument_name[i], K_VARIABLE, &$4, &tmp_a, -1);
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
                                switch($4.type.v_type){
                                case T_INTEGER:
                                    tmp_a.integer_val = $4.type.val;
                                    break;
                                case T_REAL:
                                    tmp_a.real_val = $4.type.rval;
                                    break;
                                case T_BOOLEAN:
                                    tmp_a.boolean_val = $4.type.bval;
                                    break;
                                case T_STRING:
                                    tmp_a.string_val = strdup($4.type.sval);
                                    break;
                                default:
                                    error("[DEBUG 1] SOME BUG...");
                                }
                                $4.type.is_const = true;
                                insert_table(&stack.table[stack.top], $2.argument_name[i], K_CONSTANT, &$4.type, &tmp_a, -1);
                            }
                        }
                     }
                     |
                     ;

statement : compound_statement{$$.if_count = 0;$$.while_count = 0;$$.for_count = 0;}
          | simple_statement{$$.if_count = 0;$$.while_count = 0;$$.for_count = 0;}
          | conditional_statement{$$.if_count = 1;$$.while_count = 0;$$.for_count = 0;}
          | while_statement{$$.if_count = 0;$$.while_count = 1;$$.for_count = 0;}
          | for_statement{$$.if_count = 0;$$.while_count = 0;$$.for_count = 1;}
          | return_statement{$$.if_count = 0;$$.while_count = 0;$$.for_count = 0;}
          | function_invoke_statement SEMICOLON{$$.if_count = 0;$$.while_count = 0;$$.for_count = 0;}
          | statement compound_statement{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count;
          }
          | statement simple_statement{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count;
          }
          | statement conditional_statement{
            $$.if_count = $1.if_count + 1;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count;
          }
          | statement while_statement{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count + 1;
            $$.for_count = $1.for_count;
          }
          | statement for_statement{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count + 1;
          }
          | statement return_statement{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count;
          }
          | statement function_invoke_statement SEMICOLON{
            $$.if_count = $1.if_count;
            $$.while_count = $1.while_count;
            $$.for_count = $1.for_count;
          }
          |{}
          ;

compound_statement : KW_BEGIN{push_table(&stack, 0);} varconst_declaration statement END{pop_table(&stack);}
                   ;

simple_statement : variable_reference ASSIGN_OP expression SEMICOLON{
                    if ($1.type.is_const) {
                        error("constant cannot be assigned");
                    } else if ($1.type.v_type != $3.type.v_type || $1.type.dim != $3.type.dim) {
                        if ($1.type.v_type == T_REAL && $3.type.v_type == T_INTEGER) {
                            /* coercion */
                            if (!$3.type.is_reference) {
                                if ($3.type.is_const) {
                                    asm_literal_constant(&$3, &$3);
                                } else {
                                    asm_id_reference(&$3, &$3);
                                }
                            }
                            fprintf(asm_file, "%s", $3.asm_buf);
                            fprintf(asm_file, "i2f\n");
                            asm_store(&$1);
                            put_attr(&stack, stack.top, $1.name, &$3, true);
                        } else {
                            error("type mismatch in assignment");
                        }
                    } else {
                        if (!$3.type.is_reference) {
                            if ($3.type.is_const)
                                asm_literal_constant(&$3, &$3);
                            else
                                asm_id_reference(&$3, &$3);
                        }
                        fprintf(asm_file, "%s", $3.asm_buf);
                        asm_store(&$1);
                        put_attr(&stack, stack.top, $1.name, &$3, false);
                    }
                 }
                 | PRINT{
                    fprintf(asm_file, "getstatic java/lang/System/out Ljava/io/PrintStream;\n");
                 } print_post_statement
                 | READ variable_reference SEMICOLON{
                    if ($2.type.is_const){
                        error("the variable(constant) should not change");
                    } else {
                        fprintf(asm_file, "getstatic %s/_sc Ljava/util/Scanner;\n", filename);
                        switch($2.type.v_type){
                        case T_INTEGER:
                            fprintf(asm_file, "invokevirtual java/util/Scanner/nextInt()I\n");
                            break;
                        case T_BOOLEAN:
                            fprintf(asm_file, "invokevirtual java/util/Scanner/nextBoolean()Z\n");
                            break;
                        case T_REAL:
                            fprintf(asm_file, "invokevirtual java/util/Scanner/nextFloat()F\n");
                            break;
                        default:
                            error("STRING OR OTHER TYPE CANNOT BE READ");
                        }
                        asm_store(&$2);
                    }
                 }
                 ;

/* workaround for PRINT */
print_post_statement : expression SEMICOLON{
                        if (!$1.type.is_reference) {
                            if ($1.type.is_const)
                                asm_literal_constant(&$1, &$1);
                            else
                                asm_id_reference(&$1, &$1);
                        }
                        fprintf(asm_file, "%s", $1.asm_buf);

                        switch($1.type.v_type){
                        case T_INTEGER:
                            fprintf(asm_file, "invokevirtual java/io/PrintStream/print(I)V\n");
                            break;
                        case T_BOOLEAN:
                            fprintf(asm_file, "invokevirtual java/io/PrintStream/print(Z)V\n");
                            break;
                        case T_REAL:
                            fprintf(asm_file, "invokevirtual java/io/PrintStream/print(F)V\n");
                            break;
                        case T_STRING:
                            fprintf(asm_file, "invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n");
                            break;
                        default:
                            error("ILLEGAL TYPE");
                        }
                     }
                     ;

conditional_statement : IF boolean_expr{
                            fprintf(asm_file, "%s", $2.asm_buf);
                            if ($2.type.v_type != T_BOOLEAN)
                                error("if statement's operand is not boolean type");
                            else
                                fprintf(asm_file, "ifeq Lfalse_if_%d\n", if_false_num);

                      } then_continue
                      ;

/* some...workaround for error message above */
then_continue : THEN statement{
                    fprintf(asm_file, "goto Lexit_if_%d\n", if_exit_num);
                    fprintf(asm_file, "Lfalse_if_%d:\n", if_false_num - $2.if_count);
                    if_false_num++;
              } ELSE statement END IF{
                    fprintf(asm_file, "Lexit_if_%d:\n", if_exit_num - $5.if_count);
                    if_exit_num++;
              }
              | THEN statement END IF{
                    fprintf(asm_file, "Lfalse_if_%d:\n", if_false_num - $2.if_count);
                    fprintf(asm_file, "Lexit_if_%d:\n", if_exit_num - $2.if_count);
                    if_false_num++; if_exit_num++;
              }
              ;

while_statement : WHILE {
                    fprintf(asm_file, "Lbegin_while_%d:\n", while_begin_num++);
                }boolean_expr{
                    fprintf(asm_file, "%s", $3.asm_buf);
                    if ($3.type.v_type != T_BOOLEAN){
                        error("while statement's operand is not boolean type");
                    } else {
                        fprintf(asm_file, "ifeq Lexit_while_%d\n", while_exit_num++);
                    }
                } DO statement END DO{
                    if ($3.type.v_type == T_BOOLEAN){
                        fprintf(asm_file, "goto Lbegin_while_%d\n", (while_begin_num-1) - $6.while_count);
                        fprintf(asm_file, "Lexit_while_%d:\n", (while_exit_num-1) - $6.while_count);
                    }
                };

for_statement : FOR IDENT ASSIGN_OP integer_constant TO integer_constant DO{
                    if ($4 < 0 || $6 < 0) {
                        error("lower or upper bound of loop parameter < 0");
                    } else if ($4 >= $6) {
                        error("loop parameter's lower bound >= uppper bound");
                    } else if (!check_loop_var_unique($2)) {
                        error("loop variable redeclared in nested loop");
                    } else {
                        tmp_e = check_id_all_scope($2);
                        if (!tmp_e) {
                            sprintf(tmp_buf, "'%s' is not declared", $2);
                            error(tmp_buf);
                        } else if (tmp_e->kind != K_VARIABLE) {
                            error("loop counter should be variable");
                        } else {
                            push_for_loop(tmp_e);
                            fprintf(asm_file, "sipush %d\n", $4);
                            fprintf(asm_file, "istore %d\n", tmp_e->number);
                            fprintf(asm_file, "Lbegin_for_%d:\n", for_begin_num++);
                            fprintf(asm_file, "iload %d\n", tmp_e->number);
                            fprintf(asm_file, "sipush %d\n", $6+1);
                            fprintf(asm_file, "isub\n");
                            fprintf(asm_file, "iflt Ltrue_for_%d\n", for_true_num);
                            fprintf(asm_file, "iconst_0\n");
                            fprintf(asm_file, "goto Lfalse_for_%d\n", for_false_num);
                            fprintf(asm_file, "Ltrue_for_%d:\n", for_true_num++);
                            fprintf(asm_file, "iconst_1\n");
                            fprintf(asm_file, "Lfalse_for_%d:\n", for_false_num++);
                            fprintf(asm_file, "ifeq Lexit_for_%d\n", for_exit_num++);
                        }
                    }
              } statement END DO{
                    tmp_e = check_id_all_scope($2);
                    fprintf(asm_file, "iload %d\n", tmp_e->number);
                    fprintf(asm_file, "sipush 1\n");
                    fprintf(asm_file, "iadd\n");
                    fprintf(asm_file, "istore %d\n", tmp_e->number);
                    fprintf(asm_file, "goto Lbegin_for_%d\n", (for_begin_num-1) - $9.for_count);
                    fprintf(asm_file, "Lexit_for_%d:\n", (for_exit_num-1) - $9.for_count);

                    pop_table(&stack);
              }
              ;

return_statement : RETURN expression SEMICOLON{
                    if (!$2.type.is_reference) {
                        if ($2.type.is_const)
                            asm_literal_constant(&$2, &$2);
                        else
                            asm_id_reference(&$2, &$2);
                    }
                    fprintf(asm_file, "%s", $2.asm_buf);

                    if ($2.type.v_type != tmp_retype){
                        error("return type mismatch");
                    } else {
                        switch($2.type.v_type){
                        case T_INTEGER:
                            fprintf(asm_file, "ireturn\n");
                            break;
                        case T_REAL:
                            fprintf(asm_file, "freturn\n");
                            break;
                        case T_BOOLEAN:
                            fprintf(asm_file, "ireturn\n");
                            break;
                        default:
                            error("CANNOT SUPPORT SUCH A RETURN TYPE");
                        }
                    }
                    have_return = true;
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
                                        for (j = 0; j <= $3.end ; j++) {
                                            if ((tmp_e->attr.param_list.argument_type[j].dim != $3.argument_type[j].dim) ||
                                                (tmp_e->attr.param_list.argument_type[j].v_type != $3.argument_type[j].v_type)) {
                                                if ((tmp_e->attr.param_list.argument_type[j].v_type == T_REAL) &&
                                                    ($3.argument_type[j].v_type == T_INTEGER)) {
                                                    /* coercion */
                                                    if ($3.kind == K_VARIABLE || $3.kind == K_PARAMETER) {
                                                        tmp_param_e = check_id_all_scope($3.argument_name[j]);
                                                    } else {
                                                        tmp_param_e = malloc(sizeof(symbol_table_entry));
                                                        strcpy(tmp_param_e->name, $3.argument_name[j]);
                                                        memcpy(&tmp_param_e->type, &$3.argument_type[j], sizeof(typeStruct_t));
                                                    }

                                                    if (tmp_e->type.v_type == T_VOID) {
                                                        if (!$3.argument_type[j].is_reference) {
                                                            symbol_table_entry *t = NULL;
                                                            if ($3.argument_type[j].is_const) {
                                                                asm_literal_constant(tmp_param_e, t);
                                                            } else {
                                                                asm_id_reference(tmp_param_e, t);
                                                            }
                                                        } else {
                                                            fprintf(asm_file, "%s", $3.asm_buf[j]);
                                                        }
                                                        fprintf(asm_file, "i2f\n");
                                                    } else {
                                                        if (!$3.argument_type[j].is_reference) {
                                                            if ($3.argument_type[j].is_const) {
                                                                asm_literal_constant(tmp_param_e, &$$);
                                                            } else {
                                                                asm_id_reference(tmp_param_e, &$$);
                                                            }
                                                        } else {
                                                            strcat($$.asm_buf, $3.asm_buf[j]);
                                                        }
                                                        strcat($$.asm_buf, "i2f\n");
                                                    }
                                                } else {
                                                    error("parameter type mismatch");
                                                    // break;
                                                }
                                            } else {
                                                /* consistent */
                                                if ($3.kind == K_VARIABLE || $3.kind == K_PARAMETER) {
                                                    tmp_param_e = check_id_all_scope($3.argument_name[j]);
                                                } else {
                                                    tmp_param_e = malloc(sizeof(symbol_table_entry));
                                                    strcpy(tmp_param_e->name, $3.argument_name[j]);
                                                    memcpy(&tmp_param_e->type, &$3.argument_type[j], sizeof(typeStruct_t));
                                                }

                                                if (tmp_e->type.v_type == T_VOID) {
                                                    if (!$3.argument_type[j].is_reference) {
                                                        symbol_table_entry *t = NULL;
                                                        if ($3.argument_type[j].is_const) {
                                                            asm_literal_constant(tmp_param_e, t);
                                                        } else {
                                                            asm_id_reference(tmp_param_e, t);
                                                        }
                                                    } else {
                                                        fprintf(asm_file, "%s", $3.asm_buf[j]);
                                                    }
                                                } else {
                                                    if (!$3.argument_type[j].is_reference) {
                                                        if ($3.argument_type[j].is_const) {
                                                            asm_literal_constant(tmp_param_e, &$$);
                                                        } else {
                                                            asm_id_reference(tmp_param_e, &$$);
                                                        }
                                                    } else {
                                                        strcat($$.asm_buf, $3.asm_buf[j]);
                                                    }
                                                    // printf("---\n%s\n---\n", $$.asm_buf);
                                                }
                                            }
                                        }
                                        if (tmp_e->type.v_type == T_VOID) {
                                            fprintf(asm_file, "invokestatic %s/%s(", filename, $1);
                                            for (j = 0; j <= tmp_e->attr.param_list.end; j++) {
                                                switch(tmp_e->attr.param_list.argument_type[j].v_type){
                                                case T_INTEGER:
                                                    fprintf(asm_file, "I");
                                                    break;
                                                case T_BOOLEAN:
                                                    fprintf(asm_file, "Z");
                                                    break;
                                                case T_REAL:
                                                    fprintf(asm_file, "F");
                                                    break;
                                                }
                                            }
                                            fprintf(asm_file, ")V\n");
                                        } else {
                                            char t[100];
                                            sprintf(t, "invokestatic %s/%s(", filename, $1);
                                            strcat($$.asm_buf, t);
                                            for (j = 0; j <= tmp_e->attr.param_list.end; j++) {
                                                switch(tmp_e->attr.param_list.argument_type[j].v_type){
                                                case T_INTEGER:
                                                    strcat($$.asm_buf, "I");
                                                    break;
                                                case T_BOOLEAN:
                                                    strcat($$.asm_buf, "Z");
                                                    break;
                                                case T_REAL:
                                                    strcat($$.asm_buf, "F");
                                                    break;
                                                }
                                            }
                                            switch(tmp_e->type.v_type){
                                            case T_INTEGER:
                                                strcat($$.asm_buf, ")I\n");
                                                break;
                                            case T_BOOLEAN:
                                                strcat($$.asm_buf, ")Z\n");
                                                break;
                                            case T_REAL:
                                                strcat($$.asm_buf, ")F\n");
                                                break;
                                            }
                                        }
                                        $$.type.v_type = tmp_e->type.v_type;
                                        $$.type.dim = 0;
                                        $$.type.is_reference = true;
                                        $$.kind = $3.kind;
                                    }
                                    sprintf($$.name, "%s", $1);
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
                                        char t[100];
                                        switch(tmp_e->type.v_type){
                                        case T_VOID:
                                            fprintf(asm_file, "invokestatic %s/%s()V\n", filename, $1);
                                            break;
                                        case T_INTEGER:
                                            sprintf(t, "invokestatic %s/%s()I\n", filename, $1);
                                            strcat($$.asm_buf, t);
                                            break;
                                        case T_BOOLEAN:
                                            sprintf(t, "invokestatic %s/%s()Z\n", filename, $1);
                                            strcat($$.asm_buf, t);
                                            break;
                                        case T_REAL:
                                            sprintf(t, "invokestatic %s/%s()F\n", filename, $1);
                                            strcat($$.asm_buf, t);
                                            break;
                                        }
                                        $$.type.v_type = tmp_e->type.v_type;
                                        $$.type.dim = 0;
                                        $$.type.is_reference = true;
                                        $$.kind = K_FUNCTION;
                                    }
                                }
                                sprintf($$.name, "%s", $1);
                          }
                          ;

expression : logical_expression{$$ = $1;}
           ;

boolean_expr : logical_expression{$$ = $1;}
             ;

logical_expression : logical_expression OR logical_term{
                        if ($1.type.v_type != T_BOOLEAN || $3.type.v_type != T_BOOLEAN) {
                            error("operand(s) between 'or' are not boolean");
                        } else {
                            if (!$1.type.is_reference) {
                                if ($1.type.is_const)
                                    asm_literal_constant(&$1, &$$);
                                else
                                    asm_id_reference(&$1, &$$);
                            }
                            if (!$3.type.is_reference) {
                                if ($3.type.is_const)
                                    asm_literal_constant(&$3, &$$);
                                else
                                    asm_id_reference(&$3, &$$);
                            }

                            strcat($$.asm_buf, "ior\n");

                            $$.type.v_type = T_BOOLEAN;
                            $$.type.dim = 0;
                            $$.type.is_const = false;
                            $$.type.is_reference = true;
                        }
                   }
                   | logical_term{$$ = $1;}
                   ;

logical_term : logical_term AND logical_factor{
                if ($1.type.v_type != T_BOOLEAN || $3.type.v_type != T_BOOLEAN) {
                    error("operand(s) between 'and' are not boolean");
                } else {
                    if (!$1.type.is_reference) {
                        if ($1.type.is_const)
                            asm_literal_constant(&$1, &$$);
                        else
                            asm_id_reference(&$1, &$$);
                    }
                    if (!$3.type.is_reference) {
                        if ($3.type.is_const)
                            asm_literal_constant(&$3, &$$);
                        else
                            asm_id_reference(&$3, &$$);
                    }

                    strcat($$.asm_buf, "iand\n");

                    $$.type.v_type = T_BOOLEAN;
                    $$.type.dim = 0;
                    $$.type.is_const = false;
                    $$.type.is_reference = true;
                }
             }
             | logical_factor{$$ = $1;}
             ;

logical_factor : NOT logical_factor{
                    if ($2.type.v_type != T_BOOLEAN) {
                        error("operand of 'not' is not boolean");
                    } else {
                        if (!$2.type.is_reference) {
                            if ($2.type.is_const)
                                asm_literal_constant(&$2, &$$);
                            else
                                asm_id_reference(&$2, &$$);
                        }

                        /* since xor receive two operands, so put a true value. */
                        tmp_e->type.v_type = T_BOOLEAN;
                        tmp_e->type.bval = true;
                        asm_literal_constant(tmp_e, &$$);

                        strcat($$.asm_buf, "ixor\n");

                        $$.type.v_type = T_BOOLEAN;
                        $$.type.dim = 0;
                        $$.type.is_const = false;
                        $$.type.is_reference = true;
                    }
               }
               | relation_expression{$$ = $1;}
               ;

relation_expression : arithmetic_expression relation_operator arithmetic_expression{
                        if (($1.type.v_type != T_INTEGER && $1.type.v_type != T_REAL) ||
                            ($3.type.v_type != T_INTEGER && $3.type.v_type != T_REAL)){
                            sprintf(tmp_buf, "operand(s) between '%s' are not integer/real", $2);
                            error(tmp_buf);
                        } else { /* may coercion */
                            if ($1.type.v_type != $3.type.v_type) {
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if ($1.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }
                                if ($3.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                strcat($$.asm_buf, "fcmpl\n");
                            } else {
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }
                                strcat($$.asm_buf, "isub\n");
                            }
                            if (!strcmp($2, "<")){
                                sprintf(tmp_buf, "iflt L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            } else if (!strcmp($2, "<=")){
                                sprintf(tmp_buf, "ifle L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            }else if (!strcmp($2, "<>")){
                                sprintf(tmp_buf, "ifne L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            }else if (!strcmp($2, ">=")){
                                sprintf(tmp_buf, "ifge L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            }else if (!strcmp($2, ">")){
                                sprintf(tmp_buf, "ifgt L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            }else if (!strcmp($2, "=")){
                                sprintf(tmp_buf, "ifeq L%d\n", label_num);
                                strcat($$.asm_buf, tmp_buf);
                            }

                            strcat($$.asm_buf, "iconst_0\n");
                            sprintf(tmp_buf, "goto L%d\n", label_num+1);
                            strcat($$.asm_buf, tmp_buf);
                            sprintf(tmp_buf, "L%d:\n", label_num++);
                            strcat($$.asm_buf, tmp_buf);
                            strcat($$.asm_buf, "iconst_1\n");
                            sprintf(tmp_buf, "L%d:\n", label_num++);
                            strcat($$.asm_buf, tmp_buf);

                            $$.type.v_type = T_BOOLEAN;
                            $$.type.dim = 0;
                            $$.type.is_const = false;
                            $$.type.is_reference = true;
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
                        if (($1.type.v_type != T_INTEGER && $1.type.v_type != T_REAL) ||
                                ($3.type.v_type != T_INTEGER && $3.type.v_type != T_REAL)) {
                            if ($1.type.v_type == T_STRING && $3.type.v_type == T_STRING) {
                                /* string concatenation */
                                strcat($1.type.sval, $3.type.sval);
                                strcpy($$.type.sval, $1.type.sval);
                                $$.type.v_type = T_STRING;
                                $$.type.dim = 0;
                            } else {
                                error("operand(s) between '+' are not integer/real");
                            }
                        } else {
                            if ($1.type.v_type != $3.type.v_type) {/* coercion */
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if ($1.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }
                                if ($3.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                strcat($$.asm_buf, "fadd\n");

                                $$.type.v_type = T_REAL;
                                $$.type.dim = 0;
                                $$.type.is_const = false;
                                $$.type.is_reference = true;
                            } else {
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }

                                if ($1.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "iadd\n");
                                else
                                    strcat($$.asm_buf, "fadd\n");
                                $$.type.v_type = $1.type.v_type;
                                $$.type.dim = 0;
                                $$.type.is_const = false;
                                $$.type.is_reference = true;
                            }
                        }
                      }
                      | arithmetic_expression SUB_OP term{
                        if (($1.type.v_type != T_INTEGER && $1.type.v_type != T_REAL) ||
                            ($3.type.v_type != T_INTEGER && $3.type.v_type != T_REAL)){
                            error("operand(s) between '-' are not integer/real");
                        } else {
                            if ($1.type.v_type != $3.type.v_type) {/* coercion */
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if ($1.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }
                                if ($3.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "i2f\n");
                                strcat($$.asm_buf, "fsub\n");

                                $$.type.v_type = T_REAL;
                                $$.type.dim = 0;
                                $$.type.is_const = false;
                                $$.type.is_reference = true;
                            } else {
                                if (!$1.type.is_reference) {
                                    if ($1.type.is_const)
                                        asm_literal_constant(&$1, &$$);
                                    else
                                        asm_id_reference(&$1, &$$);
                                }
                                if (!$3.type.is_reference) {
                                    if ($3.type.is_const)
                                        asm_literal_constant(&$3, &$$);
                                    else
                                        asm_id_reference(&$3, &$$);
                                }

                                if ($1.type.v_type == T_INTEGER)
                                    strcat($$.asm_buf, "isub\n");
                                else
                                    strcat($$.asm_buf, "fsub\n");
                                $$.type.v_type = $1.type.v_type;
                                $$.type.dim = 0;
                                $$.type.is_const = false;
                                $$.type.is_reference = true;
                            }
                        }
                      }
                      | relation_expression{$$ = $1;}
                      | term{$$ = $1;}
                      ;

term : term MUL_OP factor{
        if (($1.type.v_type != T_INTEGER && $1.type.v_type != T_REAL) ||
            ($3.type.v_type != T_INTEGER && $3.type.v_type != T_REAL)){
            error("operand(s) between '*' are not integer/real");
        } else {
            if ($1.type.v_type != $3.type.v_type) {/* coercion */
                if (!$1.type.is_reference) {
                    if ($1.type.is_const)
                        asm_literal_constant(&$1, &$$);
                    else
                        asm_id_reference(&$1, &$$);
                }
                if ($1.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "i2f\n");
                if (!$3.type.is_reference) {
                    if ($3.type.is_const)
                        asm_literal_constant(&$3, &$$);
                    else
                        asm_id_reference(&$3, &$$);
                }
                if ($3.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "i2f\n");
                strcat($$.asm_buf, "fmul\n");

                $$.type.v_type = T_REAL;
                $$.type.dim = 0;
                $$.type.is_const = false;
                $$.type.is_reference = true;
            } else {
                if (!$1.type.is_reference) {
                    if ($1.type.is_const)
                        asm_literal_constant(&$1, &$$);
                    else
                        asm_id_reference(&$1, &$$);
                }
                if (!$3.type.is_reference) {
                    if ($3.type.is_const)
                        asm_literal_constant(&$3, &$$);
                    else
                        asm_id_reference(&$3, &$$);
                }

                if ($1.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "imul\n");
                else
                    strcat($$.asm_buf, "fmul\n");
                $$.type.v_type = $1.type.v_type;
                $$.type.dim = 0;
                $$.type.is_const = false;
                $$.type.is_reference = true;
            }
        }
     }
     | term DIV_OP factor{
        if (($1.type.v_type != T_INTEGER && $1.type.v_type != T_REAL) ||
            ($3.type.v_type != T_INTEGER && $3.type.v_type != T_REAL)){
            error("operand(s) between '/' are not integer/real");
        } else {
            if ($1.type.v_type != $3.type.v_type) {/* coercion */
                if (!$1.type.is_reference) {
                    if ($1.type.is_const)
                        asm_literal_constant(&$1, &$$);
                    else
                        asm_id_reference(&$1, &$$);
                }
                if ($1.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "i2f\n");
                if (!$3.type.is_reference) {
                    if ($3.type.is_const)
                        asm_literal_constant(&$3, &$$);
                    else
                        asm_id_reference(&$3, &$$);
                }
                if ($3.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "i2f\n");
                strcat($$.asm_buf, "fdiv\n");

                $$.type.v_type = T_REAL;
                $$.type.dim = 0;
                $$.type.is_const = false;
                $$.type.is_reference = true;
            } else {
                if (!$1.type.is_reference) {
                    if ($1.type.is_const)
                        asm_literal_constant(&$1, &$$);
                    else
                        asm_id_reference(&$1, &$$);
                }
                if (!$3.type.is_reference) {
                    if ($3.type.is_const)
                        asm_literal_constant(&$3, &$$);
                    else
                        asm_id_reference(&$3, &$$);
                }

                if ($1.type.v_type == T_INTEGER)
                    strcat($$.asm_buf, "idiv\n");
                else
                    strcat($$.asm_buf, "fdiv\n");
                $$.type.v_type = $1.type.v_type;
                $$.type.dim = 0;
                $$.type.is_const = false;
                $$.type.is_reference = true;
            }
        }
     }
     | term MOD_OP factor{
        if (!($1.type.v_type == T_INTEGER && $3.type.v_type == T_INTEGER)){
            error("operand(s) between 'mod' are not integer");
        } else {
            if (!$1.type.is_reference) {
                if ($1.type.is_const)
                    asm_literal_constant(&$1, &$$);
                else
                    asm_id_reference(&$1, &$$);
            }
            if (!$3.type.is_reference) {
                if ($3.type.is_const)
                    asm_literal_constant(&$3, &$$);
                else
                    asm_id_reference(&$3, &$$);
            }
            strcat($$.asm_buf, "irem\n");

            $$.type.v_type = T_INTEGER;
            $$.type.dim = 0;
            $$.type.is_const = false;
            $$.type.is_reference = true;
        }
     }
     | factor{$$ = $1;}
     ;

factor : literal_constant{
            $$ = $1;
            $$.type.dim = 0;
            $$.type.is_const = true;
            $$.type.is_reference = false;
        }
       | variable_reference{$$ = $1; $$.type.is_reference = false;}
       | function_invoke_statement{$$ = $1;}
       | L_PAREN logical_expression R_PAREN{$$ = $2;}
       | SUB_OP factor{ /* print -a; will fall here */
            if (!$2.type.is_reference) {
                if ($2.type.is_const)
                    asm_literal_constant(&$2, &$$);
                else
                    asm_id_reference(&$2, &$$);
            }

            switch($2.type.v_type){
            case T_INTEGER:
                $2.type.val *= -1;
                strcat($$.asm_buf, "ineg\n");
                break;
            case T_REAL:
                $2.type.rval *= -1;
                strcat($$.asm_buf, "fneg\n");
                break;
            default:
                error("string and other type cannot be \"negative\".");
            }
            $$ = $2;
            $$.type.is_reference = true;
        }
       ;

logical_expression_list : logical_expression_list COMMA logical_expression{
                            memcpy(&$1.argument_type[++$1.end], &$3.type, sizeof(typeStruct_t));
                            $1.argument_name[$1.end] = strdup($3.name);
                            $1.asm_buf[$1.end] = strdup($3.asm_buf);
                            $1.kind = $3.kind;
                            memcpy(&$$, &$1, sizeof(typeList_t));
                        }
                        | logical_expression{
                            memcpy(&$$.argument_type[0], &$1.type, sizeof(typeStruct_t));
                            $$.end = 0;
                            $$.kind = $1.kind;
                            $$.argument_name[0] = strdup($1.name);
                            $$.asm_buf[0] = strdup($1.asm_buf);
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
                            $$ = *tmp_e;
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
                            $$ = *tmp_e;
                        }
                    }
                };

dimension : dimension ML_BRACE integer_expression MR_BRACE{
            if ($3.type.v_type != T_INTEGER)
                error("array index must be integer type");
            $1.dim++;
            $$ = $1;
          }
          | ML_BRACE integer_expression MR_BRACE{
            if ($2.type.v_type != T_INTEGER)
                error("array index must be integer type");
            $$.dim = 1;
          }
          ;

integer_expression : logical_expression{$$ = $1;}
                   ;

literal_constant : integer_constant{
                    $$.type.val = $1;
                    $$.type.v_type = T_INTEGER;
                 }
                 | SUB_OP integer_constant{ /* ONLY var a: -5; will fall here */
                    $$.type.val = $2 * (-1);
                    $$.type.v_type = T_INTEGER;
                 }
                 | FLOAT_CONST{
                    $$.type.rval = $1;
                    $$.type.v_type = T_REAL;
                 }
                 | SUB_OP FLOAT_CONST{
                    $$.type.rval = $2 * (-1);
                    $$.type.v_type = T_REAL;
                 }
                 | SCIENTIFIC{
                    $$.type.rval = $1;
                    $$.type.v_type = T_REAL;
                 }
                 | SUB_OP SCIENTIFIC{
                    $$.type.rval = $2 * (-1);
                    $$.type.v_type = T_REAL;
                 }
                 | STR_CONST{
                    $$.type.sval = strdup($1);
                    $$.type.v_type = T_STRING;
                 }
                 | TRUE{
                    $$.type.bval = true;
                    $$.type.v_type = T_BOOLEAN;
                 }
                 | FALSE{
                    $$.type.bval = false;
                    $$.type.v_type = T_BOOLEAN;
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
