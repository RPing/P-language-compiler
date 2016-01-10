#include "symbol.h"

extern int Opt_D;               /* declared in lex.l */

const char* KIND_NAME[] = {"program","function","parameter","variable","constant"};
const char* TYPE_NAME[] = {"integer","real","boolean","string","void"};

void init_table(symbol_table* p_table, int level){
    p_table->entry = p_table->end = NULL;
    p_table->level = level;
}

void insert_table(symbol_table* p_table, char* n, int k, typeStruct_t* t, symbol_attribute* a, int num){
    symbol_table_entry* p_tmp;
    symbol_table_entry* p_entry = malloc(sizeof(symbol_table_entry));
    strncpy(p_entry->name, n, 32);
    p_entry->kind = k;
    p_entry->type = *t;
    p_entry->attr = *a;
    p_entry->number = num;
    p_entry->next = NULL;
    if (p_tmp = p_table->end)
        p_table->end = p_tmp->next = p_entry;
    else
        p_table->entry = p_table->end = p_entry;
}

symbol_table_entry* lookup_table(symbol_table* p_table, char* n){
    symbol_table_entry* p_tmp;
    for (p_tmp = p_table->entry; p_tmp != NULL; p_tmp = p_tmp->next){
        if (!strncmp(p_tmp->name, n, 32))
            break;
    }
    return p_tmp;
}

void generate_constant_attr_string(char* buf, symbol_table_entry* p_entry){
    size_t buf_size = MAX_STRING_SIZE;
    switch(p_entry->type.v_type){
    case T_INTEGER:
        snprintf(buf, buf_size, "%d", p_entry->attr.integer_val);
        break;
    case T_REAL:
        snprintf(buf, buf_size, "%f", p_entry->attr.real_val);
        break;
    case T_BOOLEAN:
        snprintf(buf, buf_size, "%s", p_entry->attr.boolean_val ? "true" : "false");
        break;
    case T_STRING:
        snprintf(buf, buf_size, "%s", p_entry->attr.string_val);
        break;
    }
}

void generate_function_attr_atring(char* buf, symbol_table_entry* p_entry){
    int i, j;
    char indice[MAX_STRING_SIZE];
    bzero(buf, MAX_STRING_SIZE);
    for(i = 0; i <= p_entry->attr.param_list.end; i++){
        if(i != 0)
            strcat(buf,",");
        typeStruct_t* p_type = &p_entry->attr.param_list.argument_type[i];
        strcat(buf, TYPE_NAME[p_type->v_type]);
        bzero(indice, MAX_STRING_SIZE);
        for(j = 0; j < p_type->dim; j++){
            snprintf(indice, MAX_STRING_SIZE, "[%d]", p_type->dims[j]);
            strcat(buf, indice);
        }
    }
}

void generate_type_string(char* buf, typeStruct_t type){
    int i;
    char indice[MAX_STRING_SIZE];
    bzero(buf, MAX_STRING_SIZE);
    strcat(buf, TYPE_NAME[type.v_type]);
    for(i = 0; i < type.dim; i++){
        snprintf(indice, MAX_STRING_SIZE, "[%d]", type.dims[i]);
        strcat(buf, indice);
    }
}

void generate_attr_string(char* buf, symbol_table_entry* p_entry){
    bzero(buf, MAX_STRING_SIZE);
    switch(p_entry->kind){
        case K_CONSTANT:
            generate_constant_attr_string(buf, p_entry);
            break;
        case K_FUNCTION:
            generate_function_attr_atring(buf, p_entry);
            break;
    }
}

void dump_symbol_table(symbol_table* table){
    if(!Opt_D){
        return;
    }
    int i;
    symbol_table_entry* p_entry;
    char type_string[MAX_STRING_SIZE];
    char attr_string[MAX_STRING_SIZE];

    printf("%-32s\t%-11s\t%-11s\t%-17s\t%-11s\t\n","Name","Kind","Level","Type","Attribute");
    for(i=0;i<110;i++)
        printf("=");
    printf("\n");
    {
        for(p_entry = table->entry; p_entry != NULL; p_entry = p_entry->next){
            generate_type_string(type_string, p_entry->type);
            generate_attr_string(attr_string, p_entry);
            printf("%-32s\t", p_entry->name);
            printf("%-11s\t", KIND_NAME[p_entry->kind]);
            printf("%d(%s)\t", table->level, table->level > 0 ? "local" : "global");
            printf("%-17s\t", type_string);
            printf("%-11s\t", attr_string);
            printf("\n");
        }
    }
    for(i=0;i<110;i++)
        printf("=");
    printf("\n");
}

void push_table(table_stack* p_stack, int scope_type){ /* scope_type is to identify a for loop scope */
    int level;
    symbol_table* p_new = &p_stack->table[p_stack->top+1];
    if (p_stack->top == -1) /* stack empty */
        level = 0;
    else
        level = p_stack->table[p_stack->top].level+1;
    init_table(p_new, level);
    p_new->scope_type = scope_type;
    p_stack->top += 1;
}

void pop_table(table_stack* p_stack){
    dump_symbol_table(&p_stack->table[p_stack->top]);
    p_stack->top -= 1;
}

void init_table_stack(table_stack* p_stack){
    p_stack->top = -1;
}
