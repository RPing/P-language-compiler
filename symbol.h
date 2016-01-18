#ifndef SYMBOL_H
#define SYMBOL_H
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/*
 * 1. Any definition about symbol table and stack.
 * 2. Any constant.
 */

#define MAX_TABLE_ENTRY 100
#define MAX_TABLE 20
#define MAX_PARAM 20
#define MAX_DIM 10
#define MAX_STRING_SIZE 1024

/* v_type in typeStruct_t */
#define T_INTEGER 0
#define T_REAL 1
#define T_BOOLEAN 2
#define T_STRING 3
#define T_VOID 4    /* note that the function is procedure. no real "void" type */
#define T_ARRAY 5
#define K_PROGRAM 0
#define K_FUNCTION 1
#define K_PARAMETER 2
#define K_VARIABLE 3
#define K_CONSTANT 4

#define exchange(x,y) {(x)^=(y); (y)^=(x); (x)^=(y);}

typedef struct {
    int if_count;
    int while_count;
    int for_count;
} statement_c;

typedef struct {
    int v_type;
    int dim; /* dim is 0 means non-array; dim > 0 means array. */
    int dims[MAX_DIM];

    bool is_const;
    bool is_reference;
    int val;
    bool bval;
    float rval;
    char* sval;
} typeStruct_t;

typedef struct {
    int end;
    typeStruct_t argument_type[MAX_PARAM];
    char* argument_name[MAX_PARAM];
} typeList_t;

typedef struct {
    int end;
    int kind;
    typeStruct_t argument_type[MAX_PARAM];
    char* argument_name[MAX_PARAM];
    char* asm_buf[MAX_PARAM];
} param_l;

typedef union {
    int integer_val;
    float real_val;
    bool boolean_val;
    char* string_val;
    typeList_t param_list;
} symbol_attribute;

typedef struct e{
    char name[33];
    int kind;
    typeStruct_t type;
    symbol_attribute attr;
    int number;
    int level; /* the same as level in symbol_table */
    struct e* next;
    char asm_buf[MAX_STRING_SIZE];
} symbol_table_entry;

typedef struct {
    symbol_table_entry* entry;
    symbol_table_entry* end;
    int level;  /* 0: global 1~: local */
    int scope_type;  /* 1 if for scope else 0. workaround for nested for loop(need id unique) */
} symbol_table;

typedef struct{
    symbol_table table[MAX_TABLE];
    int top;
} table_stack;

void init_table(symbol_table* p_table, int level);
void insert_table(symbol_table* p_table, char* n, int k, typeStruct_t* t, symbol_attribute* a, int num);
symbol_table_entry* lookup_table(symbol_table* p_table, char* n);
void put_attr(table_stack* stack, int top, char* name, symbol_table_entry* right_val_entry, bool coercion);
void generate_constant_attr_string(char* buf, symbol_table_entry* p_entry);
void generate_function_attr_atring(char* buf, symbol_table_entry* p_entry);
void generate_type_string(char* buf, typeStruct_t type);
void generate_attr_string(char* buf, symbol_table_entry* p_entry);
void dump_symbol_table(symbol_table* table);
void push_table(table_stack* p_stack, int scope_type);
void pop_table(table_stack* p_stack);
void init_table_stack(table_stack* p_stack);


#endif
