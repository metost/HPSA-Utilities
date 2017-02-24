#!/opt/opsware/agent/bin/python
# HPSA Script based on pytwist library
# 20170207, Ing. Ondrej DURAS (dury)
# ~/prog/HPSA-Utilities/twist-script.py 

#ISSUE:
# WARNING: Could not load agent config file from:\
#  /etc/opt/opsware/agent/agent.args
# [Errno 13] Permission denied: \
# '/etc/opt/opsware/agent/agent.args'
#SOLUTION:
# chmod 644 /etc/opt/opsware/agent/agent.args

## MANUAL ############################################################# {{{ 1

VERSION = 2017.020701
MANUAL  = r"""
NAME: Twist-Script
FILE: twist-script.py

DESCRIPTION:
  This utility should help to find a good one
  HPSA scripty and use it onto server during 
  the migration process.
  Script works in one of three modes:
  -list helps to find a proper script to execute
  -detail helps to know more about the script
  -execute executes the script

USAGE:
  ./twist-script -name myserver   -script-id 123456 -execute
  ./twist-script -oid 12345678    -script-name "snmpLinux" -execute
  ./twist-script -host myserver   -script "snmpLinux" -execute
  ./twist-script -addr 1.2.3.4    -script 123456 -execute
  ./twist-script -server myserver -script "snmpLinux" -execute
  ./twist-script -script-name "snmp%" -list
  ./twist-script -script-name "snmp%" -list -timeout 10
  ./twist-script -script-id 1234 -details

PARAMETERS:
  -name        - HPSA name of the server
  -oid         - HPSA ObjectID of server
  -host        - HostName of the server
  -addr        - IP address of the server
  -server      - any of above
  -script-name - the name of the script
  -script-oid  - Script unique ID
  -script      - the name or ObjectID of the script
  -list        - lists ScriptID = ScriptName
  -detail      - gives a script details
  -execute     - executes a script onto server
  -timeout     - timeout of SOAP session in seconds

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
from pytwist.com.opsware.script import ServerScriptJobArgs
#from pytwist.com.opsware.script import *

SEARCH_NAME = "" # server HPSA canonnical name
SEARCH_HOST = "" # server configured HostName
SEARCH_ADDR = "" # primary server management IP address
SEARCH_OID  = "" # server HPSA ObjectIP
SEARCH_ALL  = "" # Any of above 

SCRIPT_NAME = "" # HPSA script referenced by name
SCRIPT_OID  = "" # HPSA script referenced by OID

MODE_LIST   = 0  # list a Scripts on HPSA  
MODE_DETAIL = 0  # provide details about some script
MODE_EXEC   = 0  # Execute a script onto a customer server

MODE_DEBUG  = "" # troubleshooting /verbose mode 
MODE_DUMP   = 0  # troubleshoot data structures
MODE_REF    = 0  # server is referenced name/IP
MODE_OID    = 0  # server is referenced by OID

hJobStatus = [
  'ABORTED','ACTIVE','CANCELED','DELETED','FAILURE',
  'PENDING','SUCCESS','UNKNOWN','WARNING','TAMPERED','STALE',
  'BLOCKED','RECURRING','EXPIRED','ZOMBIE','TERMINATING',
  'TERMINATED' ]



if len(sys.argv) < 2:
  print MANUAL
  sys.exit()

for idx in range(1,len(sys.argv)):
  argx = sys.argv[idx]
  if re.match("-+na",argx):     idx +=1; SEARCH_NAME = sys.argv[idx]; MODE_REF = 1; continue  # --name <HPSA_NAME>
  if re.match("-+ho",argx):     idx +=1; SEARCH_HOST = sys.argv[idx]; MODE_REF = 1; continue  # --host <HOSTNAME>
  if re.match("-+[ia]",argx):   idx +=1; SEARCH_ADDR = sys.argv[idx]; MODE_REF = 1; continue  # -ip / -addr <IP_ADDRESS>
  if re.match("-+se",argx):     idx +=1; SEARCH_ALL  = sys.argv[idx]; MODE_REF = 1; continue  # --server / --serach <NAME/IP>
  if re.match("-+oi",argx):     idx +=1; SEARCH_OID  = sys.argv[idx]; MODE_OID = 1; continue  # --oid <HPSA_ObjectID>
  if re.match("-+l",argx ):     MODE_LIST   = 1;                                    continue  # --list
  if re.match("-+de",argx):     MODE_DETAIL = 1;                                    continue  # --debug
  if re.match("-+e",argx ):     MODE_EXEC   = 1;                                    continue  # --execute
  if re.match("-+du",argx):     MODE_DUMP   = 1;                                    continue  # --dump
  if re.match("-+script-?name", argx): idx +=1; SCRIPT_NAME = sys.argv[idx];        continue  # --script-name <Script_Name>
  if re.match("-+script-?oid",  argx): idx +=1; SCRIPT_OID  = sys.argv[idx];        continue  # --script-oid  <Script_OID>
  if re.match("-+script$",      argx):                                                        # --script  <Name/OID> 
        idx +=1; SCRIPT_NAME = sys.argv[idx];  
        if re.match("^[0-9]+$",SCRIPT_NAME):
           SCRIPT_OID = SCRIPT_NAME; SCRIP_NAME = ""
        continue  # --script <Name/OID>

# to ensure the line: script <OID = <Script_Name>
if not (MODE_LIST or MODE_DETAIL or MODE_DUMP):
  MODE_LIST = 1

####################################################################### }}} 1
## HPSA Query / Twist based / initial steps ########################### {{{ 1

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
## Query to find Script/s ############################################# {{{ 1


scr_filter = Filter()
if SCRIPT_NAME:
  scr_filter.expression='ServerScriptVO.name like "%s"' % (SCRIPT_NAME)
elif SCRIPT_OID:
  scr_filter.expression='server_script_oid = %s' % (SCRIPT_OID)
else:
  sys.stderr.write("#- None script refference (Name/Oid) given !\n")
  sys.exit(1)

scriptservice = ts.script.ServerScriptService
scripts = scriptservice.findServerScriptRefs(scr_filter)

if len(scripts) < 1:
  sys.stderr.write("#- None Script found !\n")
  sys.exit(1)

for script in scripts:
  if MODE_LIST:
    print "script %d = %s" % (script.id, script.name)

  elif MODE_DETAIL:
    vo = scriptservice.getServerScriptVO(script)
    print "Script name ............ " + str(vo.name)
    print "codeType ............... " + str(vo.codeType)
    print "version ................ " + str(vo.currentVersion.versionLabel)
    print "lifecycle .............. " + str(vo.lifecycle)
    print "serverChanging ......... " + str(vo.currentVersion.serverChanging)
    print "runAsSuperUser ......... " + str(vo.currentVersion.runAsSuperUser)
    print "current ................ " + str(vo.currentVersion.current)
    print "createdDate ............ " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.createdDate))
    print "createdBy .............. " + str(vo.createdBy)
    print "modifiedDate ........... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.modifiedDate))
    print "modifiedBy ............. " + str(vo.modifiedBy)
    print "logChange .............. " + str(vo.logChange)
    print "== DESCRIPTION: ========================"
    print re.sub(r"(.{50,80})\s",r"\1\n",str(vo.description),0)
    print "== USAGE: =============================="
    print re.sub(r"(.{50,80})\s",r"\1\n",str(vo.currentVersion.usage),0)
    print "========================================"
    
  elif MODE_DUMP:
    vo = scriptservice.getServerScriptVO(script)
    pprint.pprint(inspect.getmembers(vo))  

####################################################################### }}} 1
## Query to find Server/s ############################################# {{{ 1

if not MODE_EXEC:  # to search for servers gives a sence in case of
  sys.exit()       # script execution onto customer server only

if len(scripts) > 1:
  sys.stderr.write("#- More than one Script found !\n")
  sys.exit(1)


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

# Displaying response
if len(servers) < 1:
  sys.stderr.write("#- None server found !\n")
  sys.exit(3)

for server in servers:
  #pprint.pprint(inspect.getmembers(vo))
  #pprint.pprint(inspect.getmembers(script))
  if MODE_DETAIL:
    vo = serverservice.getServerVO(server)
    print "Server Name ........... " + vo.name
    print "Management IP ......... " + vo.managementIP
    print "HPSA Object ID ........ " + str(server.id)
    print "OS Version ............ " + vo.osVersion
    print "Customer .............. " + vo.customer.name
    print ""
  elif MODE_DUMP:
    vo = serverservice.getServerVO(server)
    pprint.pprint(inspect.getmembers(vo))
  else:
    print "server %d = %s" % (server.id,server.name)

if len(servers) > 1:
  sys.stderr.write("#- More than one Server found !\n")
  sys.exit(1)

####################################################################### }}} 1
## Executing a Script on a Server ##################################### {{{ 1

# preparing job details
jobservice = ts.job.JobService
JobArg = ServerScriptJobArgs()
JobArg.setTargets(servers)

# the job query
try:
  job = scriptservice.startServerScript(scripts[0],JobArg,"",None,None)
except:
  sys.stderr.write("#- Job has not been created !\n")
  sys.exit(1)

# displaying job details
if MODE_LIST:
  print "job    %d = %s" % (job.id,job.name)
elif MODE_DETAIL:
  print "Job OID ............... " + str(job.id)
  print "Job Long ID ........... " + str(job.idAsLong)
  print "Job Name .............. " + job.name
  print "Job Type .............. " + job.secureResourceTypeName
elif MODE_DUMP:
  pprint.pprint(inspect.getmembers(job))
print "========================================"

# job in progress
count  = 0
status = 1
while status == 1:
  info = jobservice.getJobInfoVO(job)
  status = info.status
  count += 1
  time.sleep(1)
  print "%3d ... %s(%d) Job=%d Server=%d" \
        % (count,hJobStatus[status],status,job.id,server.id)

# basic results when finished (all kinds of processes)
print "== Result =============================="
print "Status ................ %s(%d)" % (hJobStatus[status],status)
print "Job Type .............. %s"     % (info.type)
print "Description ........... %s"     % (info.description)
print "Script Start .......... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(info.startDate))
print "Script End ............ " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(info.endDate))
print "Reason for Blocked .... %s"     % (info.blockedReason)
print "Reason for Canceled ... %s"     % (info.canceledReason)
print "Schedule .............. %s"     % (info.schedule)
print "Notification .......... %s"     % (info.notification)
print "Duration .............. %d seconds " % (int(info.endDate - info.startDate))


####################################################################### }}} 1
## Script Output ###################################################### {{{ 1

# ServerScript specific outputs/errors/exitcode
output = scriptservice.getServerScriptJobOutput(job,server)
print "Exit code ............. %s"     % (output.exitCode)
if output.tailStdout:
  print "== OUTPUT: ============================="
  print output.tailStdout
if output.tailStderr:
  print "== ERROR: =============================="
  print output.tailStderr
print "========================================"

####################################################################### }}} 1
# --- end ---

