#!/opt/opsware/agent/bin/python
# TWIST-Ping - Utility co check connectivity to HPSA Mesh on pytwist basis
# 20170207, Ing. Ondrej DURAS (dury)
# ~/prog/pyTWIST/twist-ping.py

#ISSUE:
# WARNING: Could not load agent config file from:\
#  /etc/opt/opsware/agent/agent.args
# [Errno 13] Permission denied: \
# '/etc/opt/opsware/agent/agent.args'
#SOLUTION:
# chmod 644 /etc/opt/opsware/agent/agent.args

## MANUAL ############################################################# {{{ 1

VERSION = 2017.022201
MANUAL  = r"""
NAME: HPSA Ping Utility
FILE: twist-ping.pl

DESCRIPTION:
  Checks the connection to HPSA mesh usin pytwist API.

USAGE:
  ./twist-ping -test
  ./twist-ping -test -quiet

PARAMETERS:
  -test    - proceed the test of configured mesh
  -quiet   - suppress the PROXY URL message

"""
MANUAL += "VERSION: %s\n" % (VERSION)

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

import sys
import os
import time
import inspect
import pprint

sys.path.append("/opt/opsware/agent/pylibs")
sys.path.append("/opt/opsware/pylibs")

from pwa      import *
from pytwist  import *
from datetime import datetime

MODE_TEST  = 0
MODE_QUIET = 0
MODE_DUMP  = 0

if len(sys.argv) < 2:
  print MANUAL
  sys.exit()

for idx in range(1,len(sys.argv)):
  argx = sys.argv[idx]
  if re.match("-+t",argx):   MODE_TEST  = 1; continue
  if re.match("-+q",argx):   MODE_QUIET = 1; continue

####################################################################### }}} 1
## HPSA Query / Twist based ########################################### {{{ 1

# Credentials
try:
  USER=pwaLogin('hpsa')
  PASS=pwaPassword('hpsa')
  if not (USER and PASS):
    sys.stderr.write("#- ENV[CRED_HPSA] not found #1 !\n")
    sys.exit(1)
  #(USER,PASS)=os.environ['CRED_HPSA'].split('%',1)
  #print("#: USER='%s' PASS='%s'" % (USER,PASS))
except:
  sys.stderr.write("#- ENV[CRED_HPSA] not found #2 !\n")
  sys.exit(1)

# Twist session
ts=twistserver.TwistServer()
ts.authenticate(USER,PASS)
searchservice = ts.search.SearchService

####################################################################### }}} 1
## MAIN ############################################################### {{{ 1

START  = datetime.now().microsecond
result = None
result = searchservice.getSearchableTypes()
STOP   = datetime.now().microsecond

if MODE_DUMP:
  pprint.pprint(inspect.getmembers(result))

if result:
   DURATION = (STOP - START) / 1000000.0
   print "Good %Ls ." % (DURATION)


####################################################################### }}} 1
