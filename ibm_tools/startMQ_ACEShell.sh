#!/bin/bash
MQ_HOME=/opt/mqm/bin
ACE_HOME=/opt/ace-12.0.5.0/server/bin

export PATH=${MQ_HOME}:${ACE_HOME}:$PATH

. mqsiprofile

QM=QM_${USER}
BRK=TESTNODE_${USER}

