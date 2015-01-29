#!/bin/bash
#Script para remover mensagens de MAILER-DAEMON da fila

for i in $(/opt/zimbra/postfix/sbin/mailq |grep MAILER-DAEMON|awk -F" " '{print $1}' |awk -F"*" '{print $1}'); do /opt/zimbra/postfix/sbin/postsuper -d $i; done
