#!/opt/opsware/agent/bin/python
# HPSA-Server pytwist based
# 20170201, Ing. Ondrej DURAS (dury)
# ~/prog/HPSA-Utilities/twist-server.py

#ISSUE:
# WARNING: Could not load agent config file from:\
#  /etc/opt/opsware/agent/agent.args
# [Errno 13] Permission denied: \
# '/etc/opt/opsware/agent/agent.args'
#SOLUTION:
# chmod 644 /etc/opt/opsware/agent/agent.args

## MANUAL ############################################################# {{{ 1

VERSION = 2017.020702
MANUAL  = r"""
NAME: Twist-Server
FILE: twist-server.py

DESCRIPTION:
  This utility should help to translate
  the server name into HPSA ObjectID at
  any time of the migration process.

USAGE:
  ./twist-server -server myserver
  ./twist-server -name myserver  -detail
  ./twist-server -host myserver.domain
  ./twist-server -addr 1.2.3.4 -dump
  ./twist-server -oid 12345678

PARAMETERS:
  -name    - Name of the server
  -host    - HostName of the server
  -addr    - IP address of the server
  -oid     - HPSA ObjectID
  -server  - Name/HostName/IP/OID of the server
  -detail  - Provides the most used Server Object Values
  -dump    - provides completed Server Object details

RE-ACTIVATION:

  REM Registers Windows HW&SW onto HPSA
  "%ProgramFiles%\Opsware\agent\pylibs\cog\bs_hardware.bat"
  "%ProgramFiles%\Opsware\agent\pylibs\cog\bs_software.bat"

  # Registers Linux HW&SW onto HPSA
  /opt/opsware/agent/pylibs/cog/bs_hardware 
  /opt/opsware/agent/pylibs/cog/bs_software

"""
MANUAL += "VERSION: %s\n" % (VERSION)

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

import sys
import os
import inspect
import pprint

sys.path.append("/opt/opsware/agent/pylibs")
sys.path.append("/opt/opsware/pylibs")

from pwa import *
from pytwist import *
from pytwist.com.opsware.search import Filter
from pytwist.com.opsware.server import ServerRef
#from pytwist.com.opsware.script import *

SEARCH_NAME = "" # 
SEARCH_HOST = "" #
SEARCH_ADDR = "" #
SEARCH_ALL  = "" #
SEARCH_OID  = "" # 
SEARCH_BACK = "" # backup of command-line attribute

MODE_DEBUG  = "" # 
MODE_SILENT = 2  # 1=export 0-isatty 2-TBD
MODE_DETAIL = 0
MODE_DUMP   = 0
MODE_REF    = 0
MODE_OID    = 0
MODE_ONE    = 0  # only one server allowed

MODE_GETATTR= "" # get one custom attribute  --get "ATTRIB_NAME"
MODE_SETATTR= "" # (attribut name)  set one custom attribute  --set "ATTRIB_NAME" "ATTRIB_VALUE"
MODE_VALATTR= "" # (attribut value) set one custom attribute  --set "ATTRIB_NAME" "ATTRIB_VALUE"
MODE_DELATTR= "" # delete a custom attribute  --del "ATTRIB_NAME"
MODE_BKPATTR= "" # make a backup of all custom attributes  --backup
MODE_LOCATTR= 1  # --local changes it into 1  --no-local changes it to 0 (-local gives more, so default)
MODE_BKPWHAT= "" # -add IP / host HN / -name NM ...

MODE_SEDEACT= 0  # --deactivate
MODE_SEREMOV= 0  # --remove
MODE_SEWINST= 0  # --win
MODE_SELNXIN= 0  # --lnx

if len(sys.argv) < 2:
  print MANUAL
  sys.exit()

for idx in range(1,len(sys.argv)):
  argx = sys.argv[idx]

  if re.match("-+lo",argx):   MODE_LOCATTR= 1;                                   continue   # --local (custom attributes)
  if re.match("-+no-?lo",argx): MODE_LOCATTR= 0;                                 continue   # --no-local (custom attributes)
  if re.match("-+back",argx): MODE_BKPATTR= 1;                                   continue   # --backup
  if re.match("-+get",argx):  idx+=1; MODE_GETATTR= sys.argv[idx];               continue   # --get <key>
  if re.match("-+del",argx):  idx+=1; MODE_DELATTR= sys.argv[idx];               continue   # --del <key>
  if re.match("-+set",argx):  MODE_SETATTR=sys.argv[idx+1];MODE_VALATTR=sys.argv[idx+2];idx+=2; continue # --set <key> <value>

  if re.match("-+na",argx):   idx+=1; SEARCH_NAME = sys.argv[idx]; MODE_REF = 1; continue   # --name
  if re.match("-+ho",argx):   idx+=1; SEARCH_HOST = sys.argv[idx]; MODE_REF = 1; continue   # --host
  if re.match("-+[ia]",argx): idx+=1; SEARCH_ADDR = sys.argv[idx]; MODE_REF = 1; continue   # --ip / --addr
  if re.match("-+se",argx):   idx+=1; SEARCH_ALL  = sys.argv[idx]; MODE_REF = 1; continue   # --server <> / --search <>
  if re.match("-+oi",argx):   idx+=1; SEARCH_OID  = sys.argv[idx]; MODE_OID = 1; continue   # --oid
  if re.match("-+det",argx):  MODE_DETAIL = 1;                                   continue   # --detail

  if re.match("-+du",argx):   MODE_DUMP   = 1;                                   continue   # --dump
  if re.match("-+q",argx):    MODE_SILENT = 1;                                   continue   # --quiet
  if re.match("-+v",argx):    MODE_SILENT = 0;                                   continue   # --verbose

  if re.match("-+deact",argx):MODE_SEDEACT= 1;                                   continue   # --deactivate
  if re.match("-+remov",argx):MODE_SEREMOV= 1;                                   continue   # --remove
  if re.match("-+win",argx):  MODE_SEWINST= 1;                                   continue   # --win
  if re.match("-+lnx",argx):  MODE_SELNXIN= 1;                                   continue   # --lnx

if bool(MODE_GETATTR): MODE_ONE = 1
if bool(MODE_SETATTR): MODE_ONE = 1
if bool(MODE_DELATTR): MODE_ONE = 1
if bool(MODE_BKPATTR): MODE_ONE = 1

if bool(MODE_SEDEACT): MODE_ONE = 1
if bool(MODE_SEREMOV): MODE_ONE = 1
if bool(MODE_SEWINST): MODE_ONE = 1
if bool(MODE_SELNXIN): MODE_ONE = 1

# are we going to list the replied servers ?? 1=no 0=yes.
if MODE_ONE:
  if MODE_SILENT == 2:
    if sys.stdout.isatty():
      MODE_SILENT = 0
    else:
      MODE_SILENT = 1
else:
  MODE_SILENT = 0


# command-line attribute for output of --backup
if SEARCH_NAME:
  SEARCH_BACK = "--name "   + SEARCH_NAME
elif SEARCH_HOST:
  SEARCH_BACK = "-host "    + SEARCH_HOST
elif SEARCH_ADDR:
  SEARCH_BACK = "--addr "   + SEARCH_ADDR
elif SEARCH_ALL:
  SEARCH_BACK = "--server " + SEARCH_ALL
elif SEARCH_OID:
  SEARCH_BACK = "--oid "    + SEARCH_OID

####################################################################### }}} 1
## Initiation & Credetials ############################################ {{{ 1

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

####################################################################### }}} 1
## Query Servers ###################################################### {{{ 1

# Query to HPSA
servers=[]
if MODE_REF:
  filter=Filter()
  if SEARCH_NAME:
    filter.expression='ServerVO.name like "%s"' % (SEARCH_NAME)
  if SEARCH_HOST:
    filter.expression='ServerVO.hostName like "%s"' % (SEARCH_HOSTNAME)
  if SEARCH_ADDR:
    filter.expression='((device_interface_ip = "%s") | ' \
                      '(device_management_ip = "%s"))' % (SEARCH_ADDR,SEARCH_ADDR)
  if SEARCH_ALL:
    filter.expression='((ServerVO.name    like "%s") | ' \
                      '(ServerVO.hostName like "%s") | ' \
                      '(device_interface_ip =  "%s") | ' \
                      '(device_management_ip = "%s"))'   \
                      % (SEARCH_ALL,SEARCH_ALL,SEARCH_ALL,SEARCH_ALL)
  
  
  serverservice = ts.server.ServerService
  servers = serverservice.findServerRefs(filter)
elif MODE_OID:
  serverservice = ts.server.ServerService
  server=ServerRef(SEARCH_OID)
  servers=[server]

####################################################################### }}} 1
## Replied Servers #################################################### {{{ 1

# Displaying response
server_ct = len(servers)
if server_ct < 1:
   sys.stderr.write("#- None server found !\n")
   sys.exit(3)

if MODE_SILENT == 0:
  for server in servers:
    #pprint.pprint(inspect.getmembers(vo))
    #pprint.pprint(inspect.getmembers(script))
    if MODE_DETAIL:
      vo = serverservice.getServerVO(server)
      print "HPSA ObjectID .... " + str(server.id)
      print "Management IP .... " + vo.managementIP
      print "Name ............. " + vo.name
      print "OS Version ....... " + vo.osVersion
      print "Customer ......... " + vo.customer.name
      print ""
    elif MODE_DUMP:
      vo = serverservice.getServerVO(server)
      pprint.pprint(inspect.getmembers(vo))
    else:
      print "server %d = %s" % (server.id,server.name)

if not MODE_ONE: # The Basic Listing servers ends here.
  sys.exit()

if server_ct > 1: # Other functions require one server only !
  sys.stderr.write("#- More than one server found !\n")
  sys.exit(1)

server = servers[0] # found only one server is set to be used more simple

####################################################################### }}} 1
## Custom Attributes ################################################## {{{ 1

if MODE_BKPATTR:  # --backup all custom attributes
  attribs = serverservice.getCustAttrs(server,None,MODE_LOCATTR)
  script  = os.path.basename(__file__)
  for key,val in attribs.iteritems():
    print '%s %s -set "%s" "%s"' % (script,SEARCH_BACK,key,val)

    
if MODE_GETATTR:  # --getting one custom attribute
  try:
    attrib = serverservice.getCustAttr(server,MODE_GETATTR,MODE_LOCATTR)
  except:
    attrib = ""
    sys.stderr.write("#- Error: getCustAttr failed")

  if not MODE_SILENT:
    print "custom '%s' = '%s'" % (MODE_GETATTR,attrib)
  elif sys.stdout.isatty():
    print attrib
  else:
    sys.stdout.write(attrib)


if MODE_SETATTR: # --set one custom attribute
  print "Setting  '%s' = '%s'" % (MODE_SETATTR, MODE_VALATTR)
  serverservice.setCustAttr(server,MODE_SETATTR,MODE_VALATTR)
  check = serverservice.getCustAttr(server,MODE_SETATTR, MODE_LOCATTR)
  print "Checking '%s' = '%s'" % (MODE_SETATTR, check)
  if MODE_VALATTR == check:
    print "#+ Pass."
  else:
    print "#- Fail."

if MODE_DELATTR: # --delete one custom attribute 
  print "Deleting '%s'" % (MODE_DELATTR)
  serverservice.removeCustAttr(server,MODE_DELATTR)

####################################################################### }}} 1
## --deactivate / --remove ############################################ {{{ 1

if MODE_SEDEACT:
  print "Deactivating the server in HPSA."
  serverservice.decommission(server)

if MODE_SEREMOV:
  print "Removing the server from HPSA."
  serverservice.remove(server)

####################################################################### }}} 1
