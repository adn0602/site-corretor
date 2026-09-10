# Integração Notion → Supabase

## Fluxo

O site não acessa o Notion diretamente. O endpoint `api/sync-notion-lancamentos.js` roda no servidor da Vercel, consulta o data source do Notion e grava os lançamentos na tabela `public.lancamentos` do Supabase.

O formulário público usa apenas a URL e a chave publicável do Supabase. A chave privada do Supabase e o token do Notion ficam somente nas variáveis de ambiente da Vercel.

## Variáveis de ambiente da Vercel

Configure estas variáveis no projeto `site-corretor`:

```text
NOTION_TOKEN=token_privado_da_integracao
NOTION_DATA_SOURCE_ID=id_do_data_source_de_lancamentos
NOTION_WEBHOOK_VERIFICATION_TOKEN=token_recebido_na_verificacao_do_webhook
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_SERVICE_ROLE_KEY=chave_service_role_do_supabase
SYNC_SECRET=uma_chave_longa_para_teste_manual
```

`SUPABASE_SERVICE_ROLE_KEY` nunca pode ser colocada no HTML, em variáveis com prefixo público ou no GitHub.

## Permissões do Notion

Compartilhe o banco de lançamentos com a integração do Notion e conceda permissão para leitura do conteúdo e das propriedades. O endpoint consulta o data source inteiro, respeitando a paginação de até 100 páginas por requisição.

Para publicar um imóvel, utilize no Notion:

```text
Status = Ativo
Visibilidade no site = Publicado
```

Qualquer outra combinação é sincronizada como `Rascunho` e não aparece para visitantes, devido à política RLS do Supabase.

## Configuração do webhook

1. Publique o projeto na Vercel.
2. Use como endpoint público:

```text
https://site-corretor-seven.vercel.app/api/sync-notion-lancamentos
```

3. Nas configurações da conexão do Notion, crie uma inscrição de webhook para o banco de lançamentos.
4. Quando o Notion enviar o `verification_token`, o endpoint o devolverá para a confirmação.
5. Salve o token recebido na variável `NOTION_WEBHOOK_VERIFICATION_TOKEN` e faça um novo deploy.
6. Ative eventos de alteração de página ou banco de dados.

O endpoint valida o cabeçalho `X-Notion-Signature` usando HMAC-SHA256. Para testes manuais, também aceita:

```http
X-Sync-Secret: valor_da_variavel_SYNC_SECRET
```

## Teste manual após o deploy

```bash
curl -X POST \
  -H "X-Sync-Secret: sua_chave_de_teste" \
  https://site-corretor-seven.vercel.app/api/sync-notion-lancamentos
```

Resposta esperada:

```json
{"ok":true,"synchronized":23}
```

## Formulário do site

O formulário em `index.html` envia para `public.leads_do_site` somente depois que o cliente Supabase é carregado. O WhatsApp só abre após a confirmação de sucesso do insert.

O payload inclui:

```json
{
  "nome": "Nome do cliente",
  "whatsapp": "21999999999",
  "email": "cliente@email.com",
  "interesse": "Conhecer lançamentos exclusivos",
  "regiao": "Barra da Tijuca",
  "orcamento": "Acima de R$ 1M",
  "empreendimento": "Jaguaripe 289",
  "empreendimento_slug": "jaguaripe-289",
  "url_da_pagina": "https://site-corretor-seven.vercel.app/empreendimentos/jaguaripe-289.html",
  "fonte": "site"
}
```

A identificação do empreendimento é feita pela query string, quando presente, ou pelo caminho `/empreendimentos/<slug>.html`. O campo `user_agent` foi removido porque não existe na tabela SQL criada.

## Observação sobre dados antigos

O endpoint faz upsert por `notion_page_id`, mas não apaga automaticamente registros que foram excluídos do Notion. Essa decisão evita perda acidental. Para retirar um imóvel do site, marque-o como `Pausado`, `Encerrado` ou altere a visibilidade para `Rascunho`.
