#!/opt/opsware/agent/bin/python
# TWIST-ComTest - HPSA Communication Test on pyTwist basis
# 20170207, Ing. Ondrej DURAS (dury)
# ~/prog/pyTWIST/twist-comtest.py

#ISSUE:
# WARNING: Could not load agent config file from:\
#  /etc/opt/opsware/agent/agent.args
# [Errno 13] Permission denied: \
# '/etc/opt/opsware/agent/agent.args'
#SOLUTION:
# chmod 644 /etc/opt/opsware/agent/agent.args

## MANUAL ############################################################# {{{ 1

VERSION = 2017.020703
MANUAL  = r"""
NAME: HPSA Communication Test Utility
FILE: twist-comtest.py

DESCRIPTION:
  Performs Communication Test
  between server and HPSA MESH.

USAGE:
  ./twist-comtest -name myserver
  ./twist-comtest -oid 12345678
  ./twist-comtest -host myserver.domain.com
  ./twist-comtest -add 1.2.3.4
  ./twist-comtest -server myserver
  ./twist-comtest -server myserver -timeout 10

PARAMETERS:
  -name    - HPSA name of the server
  -oid     - HPSA ObjectID of server
  -host    - HostName of the server
  -addr    - IP address of the server
  -server  - any of above
  -timeout - timeout of SOAP session in seconds

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

from pwa import *
from pytwist import *
from pytwist.com.opsware.search import Filter
from pytwist.com.opsware.server import ServerRef
#from pytwist.com.opsware.script import *

hJobStatus = [
  'ABORTED','ACTIVE','CANCELED','DELETED','FAILURE',
  'PENDING','SUCCESS','UNKNOWN','WARNING','TAMPERED','STALE',
  'BLOCKED','RECURRING','EXPIRED','ZOMBIE','TERMINATING',
  'TERMINATED' ]

SEARCH_NAME = "" # 
SEARCH_HOST = "" #
SEARCH_ADDR = "" #
SEARCH_ALL  = "" #
SEARCH_OID  = "" # 

MODE_DEBUG  = "" # 
MODE_DETAIL = 0
MODE_DUMP   = 0
MODE_REF    = 0
MODE_OID    = 0

if len(sys.argv) < 2:
  print MANUAL
  sys.exit()

for idx in range(1,len(sys.argv)):
  argx = sys.argv[idx]
  if re.match("-+na",argx):   idx=idx+1; SEARCH_NAME = sys.argv[idx]; MODE_REF = 1; continue
  if re.match("-+ho",argx):   idx=idx+1; SEARCH_HOST = sys.argv[idx]; MODE_REF = 1; continue
  if re.match("-+[ia]",argx): idx=idx+1; SEARCH_ADDR = sys.argv[idx]; MODE_REF = 1; continue
  if re.match("-+se",argx):   idx=idx+1; SEARCH_ALL  = sys.argv[idx]; MODE_REF = 1; continue
  if re.match("-+oi",argx):   idx=idx+1; SEARCH_OID  = sys.argv[idx]; MODE_OID = 1; continue
  if re.match("-+de",argx):   MODE_DETAIL = 1;                                      continue
  if re.match("-+du",argx):   MODE_DUMP   = 1;                                      continue

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
serverservice = ts.server.ServerService
jobservice    = ts.job.JobService

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
  
  
  servers = serverservice.findServerRefs(filter)
elif MODE_OID:
  server=ServerRef(SEARCH_OID)
  servers=[server]


####################################################################### }}} 1
## List responsed/translated list of Server/s ######################### {{{ 1

# Displaying response
if len(servers) < 1:
  sys.stderr.write("#- None server found !\n")
  sys.exit(3)

for server in servers:
  if MODE_DETAIL:
    vo = serverservice.getServerVO(server)
    print "HPSA ObjectID ......... " + str(server.id)
    print "Management IP ......... " + vo.managementIP
    print "Name .................. " + vo.name
    print "OS Version ............ " + vo.osVersion
    print "Customer .............. " + vo.customer.name
  elif MODE_DUMP:
    vo = serverservice.getServerVO(server)
    pprint.pprint(inspect.getmembers(vo))
  else:
    print "server %d = %s" % (server.id,server.name)

if len(servers) > 1:
  sys.stderr.write("#- More than one server found !\n")
  sys.exit(3)

# preparing an only server for com-test
server = servers[0]

####################################################################### }}} 1
## Communication Test Job ############################################# {{{ 1

#try:
job = serverservice.runAgentCommTest(servers)
#except:
#  sys.stderr.write("#- Communication test failed !\n")
#  sys.exit(4)
  
print "Job OID ............... " + str(job.id)
print "Job Long ID ........... " + str(job.idAsLong)
print "Job Name .............. " + job.name
print "Job Type .............. " + job.secureResourceTypeName
print "========================================"

count  = 0
status = 1
while status == 1:
  info = jobservice.getJobInfoVO(job)
  status = info.status
  count += 1
  time.sleep(1)
  print "%3d ... %s(%d) Job=%d Server=%d" \
        % (count,hJobStatus[status],status,job.id,server.id)

print "========================================"
print "Status ................ %s(%d)" % (hJobStatus[status],status)
print "Job Type .............. %s"     % (info.type)
print "Description ........... %s"     % (info.description)
print "Comm-Test Start ....... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(info.startDate))
print "Comm-Test End ......... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(info.endDate))
print "Reason for Blocked .... %s"     % (info.blockedReason)
print "Reason for Canceled ... %s"     % (info.canceledReason)
print "Schedule .............. %s"     % (info.schedule)
print "Notification .......... %s"     % (info.notification)


####################################################################### }}} 1
