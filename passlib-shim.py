#!/usr/bin/env python
import sys, passlib.apps

if sys.argv[1] == 'verify':
	sys.stdout.write(str(passlib.apps.custom_app_context.verify(sys.argv[2],sys.argv[3])))
elif sys.argv[1] == 'encrypt':
	sys.stdout.write(passlib.apps.custom_app_context.encrypt(sys.argv[2]))
