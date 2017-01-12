#!/bin/bash

# Script para atualização do Blog

DIR=/Users/rodrigo.lima/git
REPO=blog

# Remove diretório se existir

if [ -d $DIR/$REPO ] 
   then
	rm -rf $DIR/$REPO && echo "Diretorio $DIR/$REPO removido"
fi


# Cria o diretório vazio e inicia o projeto

echo "Criando diretorio"
mkdir $DIR/$REPO && cd $DIR/$REPO && git init

# Adiciona o repo remoto e faz o pull do branch source

echo "Adicionando o repo remoto"
git remote add origin git@github.com:rodrigodlima/rodrigodlima.github.io.git
echo "Realizando o pull do branch source"
git pull origin source

# Cria o branch local source e remove o master

echo "Criando o branch local source"
git checkout -b source
echo "Removendo o branch local master"
git branch -D master

# Cria o diretório _deploy e sincroniza com o branch remoto master

mkdir _deploy && cd _deploy
git init
git remote add origin git@github.com:rodrigodlima/rodrigodlima.github.io.git
git pull origin master



