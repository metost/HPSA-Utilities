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

VERSION = 2017.022201
MANUAL  = r"""
NAME: HPSA Customer Utility on pytwist basis
FILE: twist-customer.pl

DESCRIPTION:
  Allows to browse the list of Customers.
  Also it allows you to check or set the right customer
  onto the server in Compute area.
  Script works in one of four modes.
  -list helps to find a Customer
  -detail helps to know more about the Customer
  -get provides a list of servers with their customers
  -set a customer for ONE particular server

USAGE:
  ./twist-customer -list   NASA%
  ./twist-customer -detail 123435
  ./twist-customer -detail NASA%
  ./twist-customer -getoid "NASA%"
  ./twist-customer -oid    1234567    -get
  ./twist-customer -name   mysrvida12 -set 12345
  ./twist-customer -server 12345678   -set markem
  ./twist-customer -addr   1.2.3.4    -get
  ./twist-customer -host   server123  -get -timeout 10


PARAMETERS:
  -list    - filtered list of the Customers
  -detail  - gives the details of ONE Customer
  -getoid  - gives a Customer ObjectID
  -get     - gets a customer of the particular ONE server
  -set     - sets a customer for particular ONE server
  -name    - HPSA name of the server
  -oid     - HPSA ObjectID of server
  -host    - HostName of the server
  -addr    - IP address of the server
  -server  - any of above server related
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

SEARCH_NAME = "" # 
SEARCH_HOST = "" #
SEARCH_ADDR = "" #
SEARCH_ALL  = "" #
SEARCH_OID  = "" # 

CUSTOM_NAME = "" #
CUSTOM_OID  = "" #
CUSTOM_MSG  = "" #

MODE_LIST   = 0  #
MODE_DETAIL = 0  #
MODE_GETOID = 0  #
MODE_QUIET  = 0  #
MODE_GET    = 0  #
MODE_SET    = 0  #
MODE_DUMP   = 0  #

if len(sys.argv) < 2:
  print MANUAL
  sys.exit()

for idx in range(1,len(sys.argv)):
  argx = sys.argv[idx]
  if re.match("-+l",argx):    idx +=1; CUSTOM_NAME = sys.argv[idx]; MODE_LIST   = 1; continue # --list   <customerName/Oid>
  if re.match("-+d",argx):    MODE_DETAIL = 1;                                       continue # --detail
  if re.match("-+getoid",argx):idx+=1; CUSTOM_NAME = sys.argv[idx]; MODE_GETOID = 1; continue # --getoid <customerName/Oid>
  if re.match("-+get$",argx): MODE_GET  = 1;                                         continue # --get 
  if re.match("-+set$",argx): idx +=1; CUSTOM_NAME = sys.argv[idx]; MODE_SET    = 1; continue # --set <customerName/Oid>

  if re.match("-+na",argx):   idx +=1; SEARCH_NAME = sys.argv[idx]; MODE_REF    = 1; continue # --name <ServerName>
  if re.match("-+ho",argx):   idx +=1; SEARCH_HOST = sys.argv[idx]; MODE_REF    = 1; continue # --host <HostName>
  if re.match("-+[ia]",argx): idx +=1; SEARCH_ADDR = sys.argv[idx]; MODE_REF    = 1; continue # --ip / --addr <PrimaryMgmtIP>
  if re.match("-+s",argx):    idx +=1; SEARCH_ALL  = sys.argv[idx]; MODE_REF    = 1; continue # --search / --server <IP/Name/Hostname>
  if re.match("-+o",argx):    idx +=1; SEARCH_OID  = sys.argv[idx]; MODE_OID    = 1; continue # --oid <Server_ObjectID>
  if re.match("-+du",argx):   MODE_DUMP = 1;                                         continue # --dump

if re.match("^[0-9]+$",CUSTOM_NAME):
  CUSTOM_OID = CUSTOM_NAME; CUSTOM_NAME = ""

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

####################################################################### }}} 1
## List Customers ##################################################### {{{ 1

customers=[]
if MODE_LIST or MODE_GETOID or MODE_SET:
  customerservice = ts.locality.CustomerService
  cus_filter = Filter()
  customers = []
  
  if CUSTOM_NAME:
    cus_filter.expression = '((CustomerVO.name like "%s") | '       \
                            '(CustomerVO.displayName like "%s") | ' \
                            '(customer_rc_name like "%s"))' %       \
                            (CUSTOM_NAME, CUSTOM_NAME, CUSTOM_NAME)
    customers = customerservice.findCustomerRefs(cus_filter)
  elif CUSTOM_OID:
    cus_filter.expression =  'customer_rc_id = "%s"' % (CUSTOM_OID) # worked in 10.20
    #cus_filter.expression =  'customer_dvc_id == "%s"' % (CUSTOM_OID) # worked in 10.20
    customers = customerservice.findCustomerRefs(cus_filter)
    #customers = [ customerservice.getCustomerVO(CUSTOM_OID) ]
    #customers = [ customerservice.CustomerRef(CUSTOM_OID) ]
    #print "#: DEBUG3"
    #customer = customerservice.CustomerRef(CUSTOM_OID)
    #customers = [ customer ]
    #print "#: DEBUG4 %d %s" % (customer.id, customer.name)
  #print "cus_filter = %s" % str(cus_filter.expression)
  
  
  if len(customers) < 1:
    sys.stderr.write("#- None customer found !\n");
    sys.exit(1)
  
  for customer in customers:
    if MODE_DETAIL:
      vo = customerservice.getCustomerVO(customer)
      print "Customer Name .... " + str(customer.name)
      print "Customer OID ..... " + str(customer.id)
      print "authDomain ....... " + str(vo.authDomain)
      print "Display Name ..... " + str(vo.displayName)
      print "businessAccId .... " + str(vo.businessAcctId)
      print "internal ......... " + str(vo.internal)
      print "status ........... " + str(vo.status)
      print "createdDate ...... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.createdDate))
      print "createdBy ........ " + str(vo.createdBy)
      print "modifiedDate ..... " + time.strftime("%Y-%m-%d %H:%M:%S",time.gmtime(vo.modifiedDate))
      print "modifiedBy ....... " + str(vo.modifiedBy)
      print "Facilities:"
      for facility in vo.facilities:
        print "  %s = %s" % (facility.id,facility.name)
      print "========================================"
    elif MODE_DUMP:
      vo = customerservice.getCustomerVO(customer)
      pprint.pprint(inspect.getmembers(vo))
    else:
      print "customer %s = %s" % (customer.id,customer.name)
 
  if MODE_SET and (len(customers) > 1):
    sys.stderr.write("#- More than one customer found !\n")
    sys.exit(1)

####################################################################### }}} 1
## List Servers ####################################################### {{{ 1

# Query to HPSA
servers=[]
if MODE_GET or MODE_SET:
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
      if MODE_GET:
        vo = serverservice.getServerVO(server)
        print "Found customer %d = %s" % (vo.customer.id,vo.customer.name)

  if MODE_SET and (len(servers) > 1):
    sys.stderr.write("#- More than one server found !\n")
    sys.exit(1)

####################################################################### }}} 1
## Setting Customer to Server ######################################### {{{ 1

if MODE_SET:
  print "Setting the customer ..."
  customer = customers[0]
  server   = servers[0]
  serverservice.setCustomer(server,customer)
  vo = serverservice.getServerVO(server)
  print "Customer set to %d (%s)" % (vo.customer.id,vo.customer.name)

####################################################################### }}} 1
