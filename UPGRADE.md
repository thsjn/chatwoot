# Ritual de upgrade e rollback

Fork `thsjn/chatwoot`, branch `crm`, sobre `fazer-ai/chatwoot`.

> Os identificadores de infraestrutura (host, dominio, id do servico no Coolify,
> caminhos de backup) ficam **fora deste repositorio**. Substitua os
> placeholders abaixo pelos valores do seu ambiente.
>
> `<HOST>` `<DOMINIO>` `<SERVICO>` `<DIR_BACKUP>`

## Convencoes

- Branch `crm` e sempre **rebaseada** sobre `upstream`, nunca merge.
- Tag no padrao `v<versao-upstream>-crm.<n>` — ex: `v4.16.2-fazer-ai.91-crm.0`.
- O push da tag dispara o workflow `Build imagem CRM`, que publica
  `ghcr.io/thsjn/chatwoot:<tag>`. **Nunca publicamos `:latest`.**
- Build sempre no CI. Nunca no servidor: `vite build` e pesado e a maquina tem
  pouca memoria para isso.

## Upgrade

```bash
git fetch upstream --tags
git rebase v<nova-versao-upstream>          # resolver conflitos (ver secao abaixo)
# suite verde
git tag -a v<nova-versao>-crm.<n> -m "..."
git push origin crm --tags                   # dispara o build (~26 min)
```

Depois que a imagem publicar, no servidor:

1. **Backup obrigatorio** do banco (`pg_dump -Fc`) para `<DIR_BACKUP>`.
2. Trocar a tag da imagem no `docker-compose.yml` do servico `<SERVICO>`.
3. `docker compose -p <SERVICO> up -d rails sidekiq`.

O entrypoint `docker/entrypoints/rails.sh` roda `rake db:chatwoot_prepare`
sozinho no boot. **Nao rode migration a mao.**

## Ligar o modulo CRM numa conta

O CRM e **opt-in por conta**, pelo toggle `crm_kanban` em `accounts.settings`.
Com ele desligado (o padrao) a conta se comporta como se o modulo nunca tivesse
sido publicado:

- toda a API do CRM (`/api/v1/accounts/:id/crm/*`) responde **404**;
- o endpoint publico de leads (`/public/api/v1/accounts/:id/crm/leads`) responde
  **404**, mesmo com token valido;
- conversa nova **nao** vira card (a ingestao automatica para no
  `Crm::IngestConversationService`);
- nenhum evento `crm_deal.*` e publicado no websocket;
- as rotas do board, dos relatorios e da administracao nao abrem, e o item
  "Kanban" da sidebar continua mostrando a tela de paywall do fazer.ai.

### Pelo Super Admin (caminho normal)

1. `https://<DOMINIO>/super_admin` → **Accounts** → a conta.
2. **Edit** → marcar o campo **Crm kanban** → **Update Account**.
3. O usuario precisa recarregar a aba (`accounts/get` so roda no boot do app)
   para o item "Kanban" passar a abrir o board.

Desmarcar o campo desliga tudo de novo, na hora, sem deploy.

### Por console (em massa ou emergencia)

```bash
docker compose -p <SERVICO> exec rails bundle exec rails console
```

```ruby
Account.find(<id>).update!(crm_kanban: true)   # ligar
Account.find(<id>).update!(crm_kanban: false)  # desligar
Account.where(id: [1, 2, 3]).find_each { |a| a.update!(crm_kanban: true) }

# quem esta ligado hoje
Account.where("settings->>'crm_kanban' = 'true'").pluck(:id, :name)
```

## Rollback

Tres niveis, do mais barato ao mais caro:

1. **Desligar o toggle** `crm_kanban` da conta (Super Admin ou console, ver a
   secao acima) — resolve a maioria dos casos sem deploy: a API volta a 404, a
   ingestao para e a sidebar volta ao paywall.
2. **Voltar a tag** — a mesma troca de imagem, invertida. **Medido em 40,3s** no
   ensaio de 04/08/2026 (recriacao dos containers 13s + boot ate a API responder).
3. **Restaurar o dump** — so se uma migration corrompeu dado.

### Regra das duas releases

Nunca remover ou renomear coluna na mesma release que para de usa-la:
primeiro uma release que para de escrever, depois outra que remove. Isso garante
que a imagem anterior sempre funciona com o schema novo, que e o que torna o
rollback por tag viavel.

## Verificacao pos-deploy

```bash
curl -s https://<DOMINIO>/api
```

Esperado: `version` igual a tag publicada, `queue_services: ok`,
`data_services: ok`.

**`data_services: failing` nos primeiros ~30s e normal** — o boot ainda esta
rodando `bundle check` e `db:chatwoot_prepare`. So investigue se persistir
depois de 1 minuto.

## Pontos de toque no upstream (conflitos esperados no rebase)

| Arquivo | Risco | Observacao |
|---|---|---|
| `app/javascript/dashboard/routes/dashboard/kanban/Index.vue` | **alto** | e a tela de paywall do fazer.ai, que eles editam. Aqui ela so foi envelopada no toggle: com `crm_kanban` ligado redireciona para `crm_board`, desligado mantem o paywall. A implementacao vive em `dashboard/routes/dashboard/crm/` |
| `app/javascript/dashboard/routes/dashboard/kanban/kanban.routes.js` | medio | idem |
| `config/features.yml` | medio | upstream tambem anexa flags no fim do arquivo |
| `config/routes.rb` | baixo | bloco proprio do CRM |
| `config/initializers/` (CrmListener) | baixo | |
| `app/models/conversation.rb` | baixo | 1 associacao |
| `app/models/contact.rb` | baixo | 1 associacao |

## Workflows

Ativo no fork: apenas `Build imagem CRM`.

Os workflows herdados do upstream (`Publish Chatwoot EE docker images`,
`Publish Chatwoot CE docker images`, `Frontend Lint & Test`,
`Run Chatwoot CE spec`) foram **desativados em 04/08/2026**: disparavam junto
com as nossas tags, gastando minutos de Actions. Os dois `Publish` falhavam em
30s por falta dos secrets do Docker Hub do upstream.

A partir da F2, quando existir suite propria, reavaliar reativar os de teste.

## Historico

| Data | Tag | Nota |
|---|---|---|
| 04/08/2026 | `v4.16.2-fazer-ai.91-crm.0` | F0 — baseline sem alteracao de codigo. Build 25m40s. Rollback ensaiado: 40,3s |
