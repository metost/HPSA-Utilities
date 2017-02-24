#!/bin/env python

## Defaults ########################################################### {{{ 1

import os
import sys
import re
import random

VERSION = 2017.020102
MODE_DEBUG = ""
PWA_SESSION_PHRASE = PWA_DEFAULT_PHRASE = "HPe#1Helion2VPC3!"
SECRET = {}

####################################################################### }}} 1
## pwaChar / pwaEncrypt / pwaDecrypt ################################## {{{ 1

def pwaChar(DATA,PHRASE,REFA,REFB):
  global PWA_DEFAULT_PHRASE, MODE_DEBUG
  LEN = len(PHRASE)
  if not LEN:
    PHRASE = PWA_DEFAULT_PHRASE
    LEN = len(PHRASE)
  B = REFB[0] = (int(REFB[0]) + 1) % 256
  A = REFA[0] = (int(REFA[0]) + B) % 256
  IDX  = (A * B) % LEN
  DATX = (DATA ^ A ^ ord(PHRASE[IDX])) % 256
  #print "#: DATA=%d DATX=%d REFA=%d REFB=%d" % (DATA,DATX,REFA[0],REFB[0])
  return DATX


def pwaEncrypt(TEXT,PHRASE):
  global PWA_DEFAULT_PHRASE
  if len(PHRASE) < 2: PHRASE = PWA_DEFAULT_PHRASE
  KEYA = [ord(PHRASE[0])]; KEYB = [ord(PHRASE[1])]
  CODE = ""
  for I in range(len(TEXT)):
    CODE += "%02x" % pwaChar(ord(TEXT[I]),PHRASE,KEYA,KEYB)
  return CODE

def pwaDecrypt(CODE,PHRASE):
  global PWA_DEFAULT_PHRASE
  if len(PHRASE) < 2: PHRASE = PWA_DEFAULT_PHRASE
  KEYA = [ord(PHRASE[0])]; KEYB = [ord(PHRASE[1])]
  TEXT = ""
  LEN=len(CODE);
  if (LEN % 2):
    sys.stderr.write("#- Warning: Wrong cryptogram length !\n");
  for IDX in range(0,LEN,2):
    TEXT += chr(pwaChar(int(str(CODE[IDX]+CODE[IDX+1]),16),PHRASE,KEYA,KEYB))
  return TEXT


####################################################################### }}} 1
## pwaPhrase / pwaGenerate ############################################ {{{ 1


def pwaPhrase(session=0):
  global PWA_SESSION_PHRASE, PWA_DEFAULT_PHRASE
  PHRASE = ""
  TTY    = ""
  
  if "SESSIONNAME" in os.environ:
    TTY=os.environ["SESSIONNAME"]
  elif "SSH_TTY" in os.environ:
    TTY=os.environ["SSH_TTY"]
  else:
    TTY=str(os.system("tty"))
    if not TTY:
      TTY='1234'
  TTY=re.sub(r"[^0-9]","",TTY,0)
  if not re.match("[0-9]",TTY):
    TTY='0'
  PHRASE += TTY

  SOCK = ""
  if "SSH_AUTH_SOCK" in os.environ:
    SOCK = os.environ["SSH_AUTH_SOCK"]
    SOCK = re.sub(r"(ssh|agent|tmp)","",SOCK,0)
    SOCK = re.sub(r"[^A-Za-z0-9]","",SOCK,0)
    PHRASE += SOCK
  PORT = "" 
  if "SSH_CLIENT" in os.environ:
    PORT = os.environ["SSH_CLIENT"]
    PORT = re.sub(r".* ([0-9]+) .*","\\1",PORT,0)
    PHRASE += PORT 

  if len(PHRASE) < 7: 
    PHRASE += PWA_DEFAULT_PHRASE

  if session: return PHRASE
  if "DATA_LOCK" in os.environ:
    PWA_SESSION_PHRASE = pwaDecrypt(os.environ["DATA_LOCK"],PHRASE)
  else:
    PWA_SESSION_PHRASE = PWA_DEFAULT_PHRASE
  return PWA_SESSION_PHRASE


def pwaGenerate():
  PHRASE = ""
  COUNT  = random.randint(10,27)
  for I in range(COUNT):
    PHRASE += chr(random.randint(65,90))
  return PHRASE


####################################################################### }}} 1
## pwaEnv / pwaDump ################################################### {{{ 1

def pwaEnv():
  CONFIG = {}
  PHRASE = pwaPhrase()
  for KEY in os.environ:

    if re.match("CRED_.*",KEY,re.I):
       USER=re.sub("^CRED_","",KEY,1).lower()
       (LOGIN,PASS)=os.environ[KEY].split(r'%',1)
       CONFIG[USER]={}
       CONFIG[USER]["login"]    = LOGIN
       CONFIG[USER]["password"] = pwaEncrypt(PASS,"")
       CONFIG[USER]["method"]   = "password"
       #print "#: CRED_ USER=%s LOGIN=%s PASSWORD=%s" % (USER,LOGIN,PASS)

    if re.match("PWA_.*",KEY,re.I):
       USER=re.sub("^PWA_","",KEY,1).lower()
       (METH,LOGIN,PASS) = re.split(r"%|;|:",
                                    pwaDecrypt(os.environ[KEY],
                                    PHRASE),2)
       if not (USER in CONFIG):
          CONFIG[USER] = {}
       CONFIG[USER]["login"]    = LOGIN
       CONFIG[USER]["password"] = pwaEncrypt(PASS,"")
       CONFIG[USER]["method"]   = METH
    
    if re.match("VAR_.*_.*",KEY,re.I):
       (XXX,USER,UKEY)=os.environ[KEY].split(r'_',2)
       if not (USER in CONFIG):
          CONFIG[USER] = {}
       CONFIG[USER][UKEY]=os.environ[KEY]   

  return CONFIG

def pwaDump(CONFIG=None):
  global SECRET
  if CONFIG == None:
    CONFIG=SECRET
  for USER in CONFIG.keys():
    print "[%s]" % (USER)
    for KEY in CONFIG[USER].keys():
      VAL = CONFIG[USER][KEY]
      print "   %s = '%s'" % (KEY,VAL)

####################################################################### }}} 1
## pwa / pwaLogin / pwaPassword / pwaMethod / pwaCred ################# {{{ 1

def pwa(USER,KEY):
  global SECRET
  VAL=""
  try:
    VAL=SECRET[USER][KEY]
  except:
    VAL=""
  #print "#: USER=%s KEY=%s VAL=%s" % (USER,KEY,VAL)
  return VAL

def pwaLogin(USER):
  return pwa(USER,'login')

def pwaPassword(USER):
  return pwaDecrypt(pwa(USER,'password'),"")

def pwaMethod(USER):
  METHOD=pwa(USER,'method')
  if not METHOD:
    METHOD='password'
  return METHOD

def pwaCred(USER):
  return [ pwaMethod(USER), 
         pwaLogin(USER), 
         pwaPassword(USER) ]


####################################################################### }}} 1
## Main ############################################################### {{{ 1

def main():
  if "MODE_DEBUG" in os.environ:
      MODE_DEBUG = os.environ["MODE_DEBUG"]
      print "#: MODE_DEBUG = %s" % (MODE_DEBUG)
  for idx in (1,len(sys.argv),1):
    argx = sys.argv[idx]
    if re.match("-+test",argx):
      TEXT1 = "Ahoj Svet !"
      CODE1 = pwaEncrypt(TEXT1,"")
      TEXT2 = pwaDecrypt(CODE1,"")
      print TEXT1
      print CODE1
      print TEXT2
      sys.exit(0)

    if re.match("-+dump",argx):   # --dump
      pwaDump(SECRET)
      sys.exit(0)
   
    if re.match("-+e",argx):      # --encrypt (easy)
      idx = idx + 1
      PASS = sys.argv[idx]
      print pwaEncrypt(PASS,"")
      sys.exit(0)
      
    if re.match("-+d",argx):      # --decrypt (easy)
      idx = idx + 1
      PASS = sys.argv[idx]
      print pwaDecrypt(PASS,"")
      sys.exit(0)
      
    if re.match("-+E",argx):      # --Encrypt (session related)
      idx = idx + 1
      PASS = sys.argv[idx]
      print pwaEncrypt(PASS,pwaPhrase())
      sys.exit(0)
      
    if re.match("-+D",argx):      # --Decrypt (session related)
      idx = idx + 1
      PASS = sys.argv[idx]
      print pwaDecrypt(PASS,pwaPhrase())
      sys.exit(0)
      

SECRET = pwaEnv()
if __name__ == "__main__":
  main()

####################################################################### }}} 1


