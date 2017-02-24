#
# MAKEFILE of HPSA-Utilities project
# 20160501, Ing. Ondrej DURAS (dury)
# ~/prog/Mouradies/makefile
# VERSION=2016.112101
#

PROJECT=HPSA-Utilities-new
PLATFORM=$(shell perl -e "print $$^O;")
TIMESTAMPL=$(shell perl -e "use POSIX; print(strftime(\"%Y%m%d-%H%M%S\",gmtime(time)));")
TIMESTAMPW=$(shell perl -e "use POSIX; print(strftime('%%Y%%m%%d-%%H%%M%%S',gmtime(time)));")

help:
	@echo "self      - makes a copy of project into bin/"
	@echo "backup    - makes a backup tarball within one folder above"
	@echo "mybackup  - makes a backup tarball within archive folder"



self:
	-@make self-${PLATFORM}

self-MSWin32:
	@copy /Y migrateserver.pl     \usr\bin\migrateserver.pl


self-linux:
	@cp -v migrateserver.pl        ${HOME}/bin/migrateserver.pl
	@chmod -v 755 *.pl
	@chmod -v 755 ${HOME}/bin/migrateserver.pl



backup:
	-@make backup-${PLATFORM}

backup-MSWin32:
	@echo ${TIMESTAMPW}
	@7z a     ..\${PROJECT}-${TIMESTAMPW}.7z *
	@dir      ..\${PROJECT}-${TIMESTAMPW}.7z

backup-linux:
	@echo ${TIMESTAMPL}
	tar -jcvf ../${PROJECT}-${TIMESTAMPL}.tar.bz2 ./
	ls -l     ../${PROJECT}-${TIMESTAMPL}.tar.bz2 ./

mybackup:
	@make mybackup-${PLATFORM}

mybackup-MSWin32:
	@echo ${TIMESTAMPW}
	@7z a       c:\usr\archive\${PROJECT}-${TIMESTAMPW}.7z *
	@md5sum     c:\usr\archive\${PROJECT}-${TIMESTAMPW}.7z
	@sha1sum    c:\usr\archive\${PROJECT}-${TIMESTAMPW}.7z 
	@dir        c:\usr\archive\${PROJECT}-${TIMESTAMPW}.7z 

mybackup-linux:
	@echo ${TIMESTAMPL}
	@tar -jcvf ${HOME}/archive/${PROJECT}-${TIMESTAMPL}.tar.bz2 ./
	@md5sum    ${HOME}/archive/${PROJECT}-${TIMESTAMPL}.tar.bz2 
	@sha1sum   ${HOME}/archive/${PROJECT}-${TIMESTAMPL}.tar.bz2 
	@ls -l     ${HOME}/archive/${PROJECT}-${TIMESTAMPL}.tar.bz2 


# --- end ---

