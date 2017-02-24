#!/opt/opsware/agent/bin/python
# HPSA Policy based on pytwist library
# 20170214, Ing. Ondrej DURAS (dury)
# ~/prog/HPSA-Utilities/twist-policy.py 

#ISSUE:
# WARNING: Could not load agent config file from:\
#  /etc/opt/opsware/agent/agent.args
# [Errno 13] Permission denied: \
# '/etc/opt/opsware/agent/agent.args'
#SOLUTION:
# chmod 644 /etc/opt/opsware/agent/agent.args

## MANUAL ############################################################# {{{ 1

VERSION = 2017.022102
MANUAL  = r"""
NAME: HPSA Software Policy Management Utility
FILE: twist-policy.py

DESCRIPTION:
  Allows to manage HPSA software policies onto server.
  Script works in one of a few modes.
  - list all software policies found on HPSA MESH
  - list policies applicable onto server (platform)
  - list applied/attached software policies onto server
  - apply & remediate software policy onto server
  - install package/s onto server
  - uninstall package/s from the server
  - remove policy from the server

USAGE:
  ./twist-policy -list "linux%"
  ./twist-policy -detail "linux patch%"
  ./twist-policy -compliant "linux" -on 1234567
  ./twist-policy -compliant 1234 -on myserver1
  ./twist-policy -compliant "%" -on myserver1
  ./twist-policy -compliant "%" -platform "%linux%"
  ./twist-policy -is "linux" -on 1234567
  ./twist-policy -policies -on myserver1
  ./twist-policy -attach "linux patch%" -on myserver1
  ./twist-policy -attach 1234 -on myserver1 -force
  ./twist-policy -install "linux patch%" -on myserver1
  ./twist-policy -uninstall "linux patch%" -on myserver1
  ./twist-policy -remove 1234 -on 1234567 -timeout 30
  ./twist-policy -remove 1234 -on 1234567 -force

PARAMETERS:
  -list      - complete or filtered list of software policies
  -getoid    - provides ObjectID of ONE Software Policy for scipts
  -detail    - details related to ONE particular software policy
  -compliant - filtered list of software policies compliant to server
  -platform  - particular platform of compliancy (replaces a server)
  -is        - filtered list of software policies applied already on server
  -on        - ONE server defined by Hostname, HPSA Name or Object ID
  -name      - HPSA name of the affected server
  -oid       - HPSA ObjectID of affected server
  -host      - HostName of the affected server
  -addr      - IP address of the server
  -server    - any of above server search related (it's the same than -on)
  -policies  - list of all software policies applied on the server
  -attach    - adds the software policy to a server
  -install   - installs software policy related packages onto server
  -uninstall - uninstall software policy related packes from server
  -remove    - removes ONE whole software policy from the server
  -force     - does not ask in case of intrusive action (install/attach)
  -timeout   - timeout of SOAP session in seconds


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

POLICY_NAME = "" # HPSA script referenced by name
POLICY_OID  = "" # HPSA script referenced by OID

# modes of the script operation
MODE_LIST   = 0  # listing all/filtered policies
MODE_GETOID = 0  # provides one policy ObjectID
MODE_DETAIL = 0  # list particular ONE policy in detail
MODE_CHECK  = 0  # check whether a a policy is compliant to server
MODE_SHOW   = 0  # shows a (filtered) list of attached policies
MODE_ATTACH = 0  # attach and remediate a policy onto server
MODE_INST   = 0  # install software - troubleshooting purposes only
MODE_UNIN   = 0  # uninstall software - troubleshooting purposes only
MODE_REMOVE = 0  # remove policy from from the server (server from policy in practice)
MODE_FORCE  = 0  # causes the intrusive actions will be proceeded without confirmation

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
  if re.match("-+ip",argx):     idx +=1; SEARCH_ADDR = sys.argv[idx]; MODE_REF = 1; continue  # -ip / -addr <IP_ADDRESS>
  if re.match("-+ad",argx):     idx +=1; SEARCH_ADDR = sys.argv[idx]; MODE_REF = 1; continue  # -ip / -addr <IP_ADDRESS>
  if re.match("-+se",argx):     idx +=1; SEARCH_ALL  = sys.argv[idx]; MODE_REF = 1; continue  # --server / --serach / -on <NAME/IP>
  if re.match("-+on",argx):     idx +=1; SEARCH_ALL  = sys.argv[idx]; MODE_REF = 1; continue  # --server / --serach / -on <NAME/IP>
  if re.match("-+oi",argx):     idx +=1; SEARCH_OID  = sys.argv[idx]; MODE_OID = 1; continue  # --oid <HPSA_ObjectID>
  if re.match("-+du",argx):     MODE_DUMP   = 1;                                    continue  # --dump
  if re.match("-+l",argx ):     idx +=1; POLICY_NAME = sys.argv[idx]; MODE_LIST= 1; continue  # --list
  if re.match("-+det",argx):    MODE_DETAIL = 1;                                    continue  # --debug
  if re.match("-+che",argx):    MODE_CHECK  = 1;                                    continue  # --check / whether the policy is compliant to the server
  if re.match("-+sh",argx):     MODE_SHOW   = 1;                                    continue  # --show / shows a list of attached policies
  if re.match("-+showall",argx):MODE_SHOW   = 1; POLICY_NAME = "%";                 continue  # --showall / shows a list of attached policies
  if re.match("-+att",argx):    idx +=1; POLICY_NAME = sys.argv[idx]; MODE_ATTACH=1;continue  # --attach / --policy <Name/OID>
  if re.match("-+policy$",argx):idx +=1; POLICY_NAME = sys.argv[idx]; MODE_ATTACH=1;continue  # --policy / --attach <Name/OID>
                                
  if re.match("-+policy-?name", argx): idx +=1; POLICY_NAME = sys.argv[idx];        continue  # --policy-name <Policy_Name>
  if re.match("-+policy-?oid",  argx): idx +=1; POLICY_OID  = sys.argv[idx];        continue  # --policy-oid  <Policy_OID>
  if re.match("-+ins",argx):    idx +=1; POLICY_NAME = sys.argv[idx]; MODE_INST=1;  continue  # --install <Policy_Name/OID>
  if re.match("-+uni",argx):    idx +=1; POLICY_NAME = sys.argv[idx]; MODE_UNIN=1;  continue  # --uninstall <Policy_Name/OID>
  if re.match("-+rem",argx):    idx +=1; POLICY_NAME = sys.argv[idx]; MODE_REMOVE=1;continue  # --remove <Policy_Name/OID>
  if re.match("-+del",argx):    idx +=1; POLICY_NAME = sys.argv[idx]; MODE_REMOVE=1;continue  # --remove <Policy_Name/OID>


# to ensure the line: script <OID = <Script_Name>
if not (MODE_LIST or MODE_DETAIL):
  MODE_LIST = 1
# solving grammar of policy reference
if re.match("^[0-9]+$",POLICY_NAME):
   POLICY_OID = POLICY_NAME; SCRIP_NAME = ""
if re.match(".*[^0-9].*",POLICY_OID):
   POLICY_NAME = POLICY_OID; POLICY_OID = ""

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

policyservice = ts.swmgmt.SoftwarePolicyService
jobservice    = ts.job.JobService

####################################################################### }}} 1
## handleJob(job) ##################################################### {{{ 1

def handleJob(job):
  global MODE_LIST, MODE_DETAIL, MODE_DUMP
  global jobservice

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
## Query to find Policy/ies ########################################### {{{ 1


pol_filter = Filter()
if POLICY_NAME:
  pol_filter.expression='SoftwarePolicyVO.name like "%s"' % (POLICY_NAME)
elif POLICY_OID:
  pol_filter.expression='software_policy_folder_id = %s' % (POLICY_OID)
else:
  sys.stderr.write("#- None policy refference (Name/Oid) given !\n")
  sys.exit(1)

policies = policyservice.findSoftwarePolicyRefs(pol_filter)

if len(policies) < 1:
  sys.stderr.write("#- None Software Policy found !\n")
  sys.exit(1)

for policy in policies:
  if MODE_LIST and (not MODE_DETAIL):
    print "policy %d = %s" % (policy.id, policy.name)

  if MODE_DETAIL:
    vo = policyservice.getSoftwarePolicyVO(policy)
    print "Policy name ............ " + str(vo.name)
    print "Locked ................. " + str(vo.locked)
    print "Life Cycle ............. " + str(vo.lifecycle)
    print "Template ............... " + str(vo.template)
    print "Manual Uninstall ....... " + str(vo.manualUninstall)
    print "Software Policy Type ... " + str(vo.softwarePolicyType)
    print "createdDate ............ " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.createdDate))
    print "createdBy .............. " + str(vo.createdBy)
    print "modifiedDate ........... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.modifiedDate))
    print "modifiedBy ............. " + str(vo.modifiedBy)
    print "Description ............ " + str(vo.description)
    print "========================================"
    
  if MODE_DUMP:
    vo = policyservice.getSoftwarePolicyVO(policy)
    pprint.pprint(inspect.getmembers(vo))  

if len(policies) > 1:
  sys.stderr.write("#- More than one Policy found !\n")
  sys.exit(1)

####################################################################### }}} 1
## Query to find Server/s ############################################# {{{ 1

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
    print "Platforms"
    for plax in vo.platforms:
      print "  %s = %s" % (plax.id,plax.name)
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
## Attaching / Detaching SwPolicy ##################################### {{{ 1

if MODE_REMOVE:
  # the job query
  print "Detaching policy..."
  job = None
  try:
    policyservice.detachFromPolicies(policies,servers)
    job = policyservice.startRemediateNow(policies,server)
  except:
    sys.stderr.write("#- Job has not been created !\n")
    sys.stderr.write("#- " + str(sys.exc_info()[0]) + "\n")
    #sys.exit(1)
  if job: handleJob(job)
  print "Removing Policy Association ..."
  try:
    policyservice.removePolicyAssociations(policies,servers)
  except:
    sys.stderr.write("#- Policy Association not removed !\n")
    sys.stderr.write("#- " + str(sys.exc_info()[0]) + "\n")
    sys.exit(1)
  print "Policy Association removed." 
  

if MODE_ATTACH:
  # the job query
  print "Attaching policy..."
  try:
    policyservice.attachToPolicies(policies,servers)
    job = policyservice.startRemediateNow(policies,server)
  except:
    sys.stderr.write("#- Job has not been created !\n")
    sys.stderr.write("#- " + str(sys.exc_info()[0]) + "\n")
    sys.exit(1)
  handleJob(job)
 
####################################################################### }}} 1
# --- end ---

