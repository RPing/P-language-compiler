#!/usr/bin/env python
# -*- coding: UTF-8 -*-
import os

def main():
    current_path = os.getcwd()
    for subdir, dirs, files in os.walk(current_path):
        exclude_list = ['parser','test.py','lextemplate.l','lex.yy.c','Makefile','output','yacctemplate.y','y.tab.h','y.tab.c']
        for file in files:
            if file in exclude_list:
                continue
            name = file.split('.')
            if name[1] == "p":
                os.system('./parser ' + file + ' 2>&1 1>output | tee --append output')
                print '------------------------------------------------------------------------------------'
                print file
                os.system('diff output ' + name[0] + '.output')
                print '------------------------------------------------------------------------------------'
            # print type(file)

if __name__ == '__main__':
    main()
