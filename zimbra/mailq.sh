#!/bin/bash

#Script para contar as mensagens na fila do Zimbra. Esse script é utilizado pelo Zabbix para monitorar a fila do servidor.

/opt/zimbra/postfix/sbin/mailq |tail -n1 | awk -F" " '{print $5}'
