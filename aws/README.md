# Scripts de Gerenciamento de Buckets S3

Scripts para listar, esvaziar e deletar buckets S3 na AWS.

## ⚠️ ATENÇÃO - SCRIPTS DESTRUTIVOS

Estes scripts **DELETAM PERMANENTEMENTE** buckets S3 e todo seu conteúdo. Use com extremo cuidado!

## Pré-requisitos

1. **AWS CLI instalado**:
   ```bash
   pip install awscli
   ```

2. **Credenciais AWS configuradas**:
   ```bash
   aws configure
   ```

3. **Permissões necessárias**:
   - `s3:ListAllMyBuckets`
   - `s3:DeleteBucket`
   - `s3:DeleteObject`
   - `s3:DeleteObjectVersion`
   - `s3:GetBucketLocation`
   - `s3:GetBucketVersioning`
   - `s3:ListBucket`
   - `s3:ListBucketVersions`

4. **Dependências opcionais**:
   - `jq` (para o script completo): `sudo apt install jq`

## Scripts Disponíveis

### 1. delete_all_s3_buckets.sh (COMPLETO)

Script robusto com todos os recursos de segurança e logging.

**Características**:
- ✅ Confirmação obrigatória do usuário
- ✅ Mostra informações da conta AWS
- ✅ Lista todos os buckets antes de deletar
- ✅ Remove objetos versionados e delete markers
- ✅ Detecta região do bucket automaticamente
- ✅ Logging colorido e detalhado
- ✅ Resumo da operação
- ✅ Tratamento de erros

**Uso**:
```bash
./delete_all_s3_buckets.sh
```

**Processo**:
1. Verifica AWS CLI e credenciais
2. Mostra conta AWS atual
3. Lista todos os buckets
4. Solicita confirmação (digite `DELETE-ALL`)
5. Remove todos os objetos e versões
6. Deleta os buckets
7. Exibe resumo

---

### 2. delete_s3_simple.sh (SIMPLES)

Versão minimalista e rápida.

**Características**:
- ⚡ Execução rápida
- 🔄 Remove objetos versionados
- ✅ Confirmação básica
- 📝 Output simplificado

**Uso**:
```bash
./delete_s3_simple.sh
```

**Processo**:
1. Solicita confirmação (digite `SIM`)
2. Processa todos os buckets em sequência
3. Remove objetos, versões e buckets

---

### 3. delete_s3_interactive.sh (INTERATIVO)

Versão com seleção interativa de buckets.

**Características**:
- 🎯 Seleção específica de buckets
- 📋 Lista numerada
- ✅ Múltiplas opções de seleção
- 🔒 Confirmação dupla

**Uso**:
```bash
./delete_s3_interactive.sh
```

**Processo**:
1. Lista todos os buckets com índices
2. Permite seleção por número
3. Mostra buckets selecionados
4. Solicita confirmação (digite `DELETE`)
5. Deleta apenas os buckets selecionados

**Opções de seleção**:
- Números específicos: `1 3 5`
- Todos os buckets: `all`
- Cancelar: `q`

## Exemplos de Uso

### Deletar todos os buckets (script completo)
```bash
./delete_all_s3_buckets.sh
# Digite: DELETE-ALL
```

### Deletar todos rapidamente
```bash
./delete_s3_simple.sh
# Digite: SIM
```

### Deletar buckets específicos
```bash
./delete_s3_interactive.sh
# Escolha: 1 3 5
# Confirme: DELETE
```

## Fluxo de Deleção

Para cada bucket, os scripts executam:

1. **Detecção de região**: Identifica a região do bucket
2. **Verificação de versionamento**: Checa se está habilitado
3. **Remoção de versões**: Deleta todas as versões de objetos
4. **Remoção de delete markers**: Remove marcadores de deleção
5. **Remoção de objetos**: Deleta objetos normais
6. **Deleção do bucket**: Remove o bucket vazio

## Logs e Output

### Script Completo
```
[INFO] Conta AWS atual:
{
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/rodrigo"
}

[INFO] Buckets encontrados:
     1  my-bucket-1
     2  my-bucket-2
     3  my-bucket-3

[INFO] Processando bucket: my-bucket-1
[INFO]   Região: us-east-1
[INFO]   Removendo objetos...
[INFO]   ✓ Bucket my-bucket-1 deletado com sucesso!
```

## Tratamento de Erros

Os scripts tratam:
- Buckets com versionamento habilitado
- Buckets em diferentes regiões
- Falhas de permissão
- Buckets com políticas de retenção
- Objetos com legal hold

## Recuperação de Desastre

⚠️ **NÃO HÁ DESFAZER!**

Se você deletou buckets por engano:
- Dados são **permanentemente perdidos**
- Verifique backups ou snapshots
- Use AWS Backup se configurado
- Contate o suporte AWS (pode não ajudar)

## Boas Práticas

### Antes de Executar

1. **Verifique a conta**:
   ```bash
   aws sts get-caller-identity
   ```

2. **Liste os buckets**:
   ```bash
   aws s3 ls
   ```

3. **Faça backup crítico**:
   ```bash
   aws s3 sync s3://bucket-importante ./backup/
   ```

4. **Use o modo interativo** primeiro se não tem certeza

### Alternativas Mais Seguras

Em vez de deletar tudo, considere:

```bash
# Listar buckets por tag
aws s3api list-buckets --query "Buckets[?Tags[?Key=='Environment' && Value=='dev']].Name"

# Deletar apenas buckets vazios
for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
  count=$(aws s3 ls s3://$bucket --recursive | wc -l)
  [ $count -eq 0 ] && aws s3 rb s3://$bucket
done

# Adicionar lifecycle policy para auto-deleção
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-bucket \
  --lifecycle-configuration file://lifecycle.json
```

## Troubleshooting

### Erro: "AWS CLI não encontrado"
```bash
pip install awscli
# ou
brew install awscli
```

### Erro: "Credenciais inválidas"
```bash
aws configure
```

### Erro: "Access Denied"
Verifique permissões IAM:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Erro: "Bucket não pode ser deletado"
Possíveis causas:
- Políticas de retenção ativas
- Object Lock habilitado
- Replicação cross-region ativa
- Bucket não está vazio (versões ocultas)

Solução:
```bash
# Desabilitar versionamento
aws s3api put-bucket-versioning \
  --bucket my-bucket \
  --versioning-configuration Status=Suspended

# Remover políticas de retenção (se possível)
# Remover todas as versões manualmente
```

## Segurança

### Variáveis de Ambiente
Nunca hardcode credenciais! Use:
```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"
```

### MFA
Para operações críticas, use MFA:
```bash
aws sts get-session-token --serial-number arn:aws:iam::123456:mfa/user --token-code 123456
```

## Licença

Scripts para uso interno/educacional. Use por sua conta e risco.

## Contribuindo

Melhorias são bem-vindas! Mantenha o foco em:
- Segurança
- Confirmações claras
- Tratamento de erros
- Logging detalhado

## Contato

Criado para uso na BoundingAI - DevOps Team
