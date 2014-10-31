import sys, passlib.apps
#sys.stderr.write(repr(sys.argv) + "\n")
sys.stdout.write(passlib.apps.custom_app_context.encrypt(sys.argv[1]))
