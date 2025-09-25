#!/bin/bash
MQ_HOME=/opt/mqm/bin
ACE_HOME=/opt/ace-12.0.5.0/server/bin

export PATH=${MQ_HOME}:${ACE_HOME}:$PATH
export ODBCSYSINI=/var/mqsi/odbc
export DB2CLIINIPATH=$ODBCSYSINI
export ODBCINI=$ODBCSYSINI/odbc.ini

. mqsiprofile

QM=QM_${USER}
BRK=TESTNODE_${USER}

