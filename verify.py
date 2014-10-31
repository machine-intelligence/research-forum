import sys, passlib.apps
#sys.stderr.write(repr(sys.argv) + "\n")
sys.stdout.write(str(passlib.apps.custom_app_context.verify(sys.argv[1],sys.argv[2])))
