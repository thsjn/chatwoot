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

## Rollback

Tres niveis, do mais barato ao mais caro:

1. **Desligar a feature flag** `crm_kanban` — resolve a maioria dos casos sem deploy.
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
| `app/javascript/dashboard/routes/dashboard/kanban/Index.vue` | **alto** | e a tela de paywall do fazer.ai, que eles editam. Manter aqui apenas um redirect de 3 linhas; a implementacao vive em `dashboard/routes/dashboard/crm/` |
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
