# P-language-compiler
## Introduction to Compiler Design Fall 2015

A pascal-like language compiler which generates Java bytecode.

The compiler is generated by the tool lex and yacc.

## Environment Requirement
- lex/flex
- yacc/bison
- jasmin assembler http://jasmin.sourceforge.net/
    * pull jasmin.jar into directory
- JRE(Java Runtime Environment)

## Usage
To generate a compiler:

    make

To parse a P source file and generate Java bytecode:

    ./parser [file_name].p

* note that the assembly file based on jasmin format called [filename].j

To run the P program:

    java [file_name]

## TODO
- negation has wrong result
- stop generating assembly code while facing any lexical, syntactic and sematic error
- support assembly code of array and string
