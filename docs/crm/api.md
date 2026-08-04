# API do CRM Kanban

Todos os endpoints autenticados vivem sob:

```
/api/v1/accounts/:account_id/crm/
```

e usam a autenticação padrão do Chatwoot (header `api_access_token` de um
usuário, ou a sessão do dashboard). O endpoint de ingestão de leads é a única
exceção: é público e autenticado por token de origem
([ver abaixo](#ingestão-pública-de-leads)).

Nos exemplos, substitua `<HOST>`, `<ACCOUNT_ID>` e `<TOKEN>` pelos valores do
seu ambiente.

## Regras gerais

**Módulo desligado.** Se a conta não tiver `crm_kanban` ligado, **todos** os
endpoints abaixo respondem `404`:

```json
{ "error": "Resource could not be found" }
```

É de propósito: um `403` confirmaria que os endpoints existem. Ver
[`UPGRADE.md`](../../UPGRADE.md).

**Formato de erro.** O módulo usa os handlers padrão do Chatwoot:

| Situação | Status | Corpo |
|---|---|---|
| Recurso inexistente / módulo desligado | `404` | `{ "error": "..." }` |
| Sem permissão | `401` | `{ "error": "You are not authorized to do this action" }` |
| Validação do modelo | `422` | `{ "message": "...", "attributes": ["..."] }` |
| Regra de negócio do `move` | `422` | `{ "error_code": "..." }` |
| Parâmetro obrigatório ausente / destruição bloqueada | `422` | `{ "error": "..." }` |
| Conflito de versão otimista | `409` | o card atual, no mesmo formato do `show` |

**Timestamps.** Datas/horas saem como **epoch em segundos** (inteiro).
`expected_close_on` é a exceção: é uma data (`"2026-08-31"`).

**Dinheiro.** `value_cents` é inteiro em centavos; `value` é o mesmo valor em
unidade principal (float). A moeda fica em `currency`.

**Paginação.** Onde existe, é de 25 itens por página, via `?page=N`, e a
resposta traz `meta.count` (total) e `meta.current_page`.

**Permissões.** Resumo — o detalhe está em cada seção:

| Recurso | Agente | Administrador |
|---|---|---|
| Funis, estágios, origens, motivos de perda | ler | ler e escrever |
| Oportunidades | ler, criar, editar, mover | tudo, mais arquivar/restaurar |
| Atividades | ler, criar, editar | tudo, mais excluir |
| Relatórios e CSV | ler | ler |
| Gerar token de origem | — | sim |

**`restrito_por_owner`.** Quando o funil tem essa chave ligada em `settings`, um
agente só recebe as oportunidades cujo `owner_id` é ele mesmo ou é nulo. Isso é
aplicado em SQL (`Crm::DealPolicy::Scope`) e vale para: a listagem de
oportunidades, os agregados no cabeçalho dos estágios, **todos** os relatórios,
o CSV e os eventos de websocket. Administradores nunca são filtrados.

---

## Funis (pipelines)

### `GET /crm/pipelines`

Lista os funis ativos, ordenados por `position, id`.

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `include_archived` | boolean | Inclui também os funis arquivados. |

```bash
curl -H "api_access_token: <TOKEN>" \
  "https://<HOST>/api/v1/accounts/<ACCOUNT_ID>/crm/pipelines"
```

```json
{
  "payload": [
    {
      "id": 1,
      "name": "Vendas",
      "description": null,
      "position": 0,
      "is_default": true,
      "settings": {
        "inbox_ids": [3],
        "janela_dedupe_dias": 30,
        "exige_proxima_atividade": true,
        "moeda_padrao": "BRL",
        "restrito_por_owner": false
      },
      "archived_at": null,
      "created_at": 1785000000
    }
  ]
}
```

### `GET /crm/pipelines/:id`

Um funil. Resposta: o mesmo objeto acima, sem o envelope `payload`.

### `POST /crm/pipelines` · administrador

```json
{
  "pipeline": {
    "name": "Vendas",
    "description": "Funil comercial",
    "position": 0,
    "is_default": true,
    "settings": {
      "inbox_ids": [3, 7],
      "janela_dedupe_dias": 30,
      "exige_proxima_atividade": false,
      "moeda_padrao": "BRL",
      "restrito_por_owner": false
    }
  }
}
```

Chaves aceitas em `settings`: `inbox_ids`, `janela_dedupe_dias`,
`exige_proxima_atividade`, `moeda_padrao`, `restrito_por_owner`.

Atenção: `settings` é gravado **por inteiro** — mandar só uma chave apaga as
outras quatro. Envie sempre o hash completo.

`is_default: true` é uma **troca**, não um conflito: o funil que era padrão
perde a marca automaticamente, no mesmo `save`.

### `PATCH /crm/pipelines/:id` · administrador

Mesmo corpo do `create`.

### `DELETE /crm/pipelines/:id` · administrador

`200` com corpo vazio. Se o funil ainda tiver oportunidades, responde `422`:

```json
{ "error": "Deals Cannot delete record because dependent deals exist" }
```

Nesse caso use `archive`.

### `POST /crm/pipelines/:id/archive` · administrador
### `POST /crm/pipelines/:id/unarchive` · administrador

Arquivar tira o funil do seletor do quadro e da ingestão automática, mas
**mantém as oportunidades**. Restaurar traz o quadro de volta intacto.

---

## Estágios (stages)

Sempre aninhados no funil:
`/api/v1/accounts/:account_id/crm/pipelines/:pipeline_id/stages`.

### `GET .../stages`

Lista todos os estágios do funil, ordenados por `position, id`, já com os
totais de cada coluna.

Aceita os mesmos filtros do quadro (ver [oportunidades](#oportunidades-deals)):
`stage_id`, `owner_id`, `source_id`, `status`, `q`, `expected_close_since`,
`expected_close_until`.

```json
{
  "payload": [
    {
      "id": 10,
      "pipeline_id": 1,
      "name": "Novo",
      "position": 1000,
      "color": "slate",
      "category": "open",
      "probability": 10,
      "rotting_days": 3,
      "wip_limit": null,
      "is_entry": true,
      "deals_count": 12,
      "deals_value_cents": 4500000,
      "filtered_deals_count": 3,
      "filtered_deals_value_cents": 900000
    }
  ]
}
```

- `deals_count` / `deals_value_cents`: totais do **estágio inteiro**
  (oportunidades abertas e não arquivadas). É contra esse número que o
  `wip_limit` é medido — um filtro na tela nunca faz uma coluna cheia parecer
  vazia.
- `filtered_deals_count` / `filtered_deals_value_cents`: os mesmos totais com os
  filtros aplicados. **Só aparecem quando a requisição carrega filtros** — a
  presença desses campos é o contrato que diz ao quadro que há um filtro ligado.

### `GET .../stages/:id`

### `POST .../stages` · administrador

```json
{
  "stage": {
    "name": "Qualificado",
    "category": "open",
    "position": 2000,
    "color": "blue",
    "probability": 25,
    "rotting_days": 7,
    "wip_limit": 20,
    "is_entry": false
  }
}
```

- `category`: `open`, `won` ou `lost`.
- `color`: um token de `slate`, `blue`, `emerald`, `amber`, `ruby`, `violet`
  (nunca um hex — o quadro mapeia o token para classes do Tailwind).
- `probability`: 0 a 100, usado como peso na previsão.
- `wip_limit` e `rotting_days`: inteiros positivos ou `null`.

### `PATCH .../stages/:id` · administrador
### `DELETE .../stages/:id` · administrador

`422` se o estágio ainda tiver oportunidades.

**Reordenação:** não existe endpoint em lote. Arrastar colunas na interface
manda um `PATCH` de `position` por estágio que mudou — ver
[limitações](./README.md#limitações-conhecidas).

---

## Oportunidades (deals)

### `GET /crm/deals`

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `pipeline_id` | int | Restringe ao funil. |
| `stage_id` | int | Restringe ao estágio. |
| `owner_id` | int | Responsável. |
| `source_id` | int | Origem. |
| `status` | string | `open`, `won` ou `lost`. Valor inválido é ignorado. |
| `q` | string | Busca `ILIKE` no título. |
| `expected_close_since` | date | `YYYY-MM-DD`. Data inválida é ignorada. |
| `expected_close_until` | date | `YYYY-MM-DD`. |
| `archived` | boolean | `true` lista as arquivadas em vez das ativas. |
| `page` | int | Paginação de 25. |

Sem `archived`, lista só as ativas. Sem `status`, lista todos os status.

```bash
curl -H "api_access_token: <TOKEN>" \
  "https://<HOST>/api/v1/accounts/<ACCOUNT_ID>/crm/deals?pipeline_id=1&stage_id=10&page=1"
```

```json
{
  "meta": { "count": 12, "current_page": 1 },
  "payload": [
    {
      "id": 501,
      "pipeline_id": 1,
      "stage_id": 10,
      "title": "Maria Silva",
      "value_cents": 350000,
      "currency": "BRL",
      "value": 3500.0,
      "status": "open",
      "expected_close_on": "2026-09-15",
      "closed_at": null,
      "position": "1000.0",
      "stage_entered_at": 1785000000,
      "last_activity_at": 1785003600,
      "next_activity_at": 1785090000,
      "lock_version": 3,
      "archived_at": null,
      "created_at": 1784900000,
      "updated_at": 1785003600,
      "custom_attributes": {},
      "utm": { "utm_source": "google", "utm_campaign": "black-friday" },
      "contact": {
        "id": 88, "name": "Maria Silva", "email": "maria@example.com",
        "phone_number": "+5511999999999", "thumbnail": "https://<HOST>/..."
      },
      "owner": { "id": 4, "name": "João", "available_name": "João", "thumbnail": null },
      "team": { "id": 2, "name": "Comercial" },
      "source": { "id": 7, "name": "Landing Page", "kind": "landing" },
      "conversations": [
        {
          "id": 9001, "display_id": 42, "is_origin": true, "status": "open",
          "inbox": { "id": 3, "name": "WhatsApp", "channel_type": "Channel::Whatsapp" }
        }
      ],
      "lost_reason": null
    }
  ]
}
```

Notas:

- `position` é um `numeric` do Postgres e chega como **string** no JSON
  (`"1000.0"`). Converta antes de fazer conta.
- `owner`, `team`, `source` e `lost_reason` só aparecem quando existem.
- `conversations` é filtrado por visibilidade: só entram as conversas de caixas
  de entrada às quais o usuário pertence, ou do time dele. Administradores veem
  todas.
- `next_activity_at` é a menor `due_at` futura entre as atividades não
  concluídas do card.

### `GET /crm/deals/:id`

Um card, no mesmo formato, sem envelope.

### `POST /crm/deals`

```json
{
  "deal": {
    "title": "Proposta ACME",
    "contact_id": 88,
    "pipeline_id": 1,
    "stage_id": 10,
    "owner_id": 4,
    "team_id": 2,
    "source_id": 7,
    "source_inbox_id": 3,
    "value_cents": 350000,
    "currency": "BRL",
    "expected_close_on": "2026-09-15",
    "position": 1000,
    "lost_reason_id": null,
    "custom_attributes": { "segmento": "varejo" },
    "utm": { "utm_source": "google" }
  }
}
```

`contact_id` é obrigatório. `stage_id` é opcional: sem ele, o card cai no
estágio de entrada do funil (`is_entry`, ou o primeiro por posição).
`pipeline_id`, `stage_id`, `position` e `lost_reason_id` **só são aceitos na
criação**.

`custom_attributes` aceita apenas chaves registradas em
`custom_attribute_definitions` da conta com escopo `deal_attribute`; chaves do
tipo `list` só aceitam valores da lista. Fora disso, `422`.

Criar um card grava automaticamente uma transição de entrada no funil
(`from_stage_id` nulo), creditada ao usuário da requisição.

### `PATCH /crm/deals/:id`

Aceita os mesmos campos do `create` **menos** `pipeline_id`, `stage_id`,
`position` e `lost_reason_id`. Mover um card é o `move`.

`lock_version` é **opcional** aqui e viaja **fora** do envelope `deal`:

```json
{
  "deal": { "title": "Proposta ACME v2" },
  "lock_version": 3
}
```

Com ele, uma edição concorrente responde `409` com o card atual (para o cliente
reconciliar). Sem ele, o comportamento é o de sempre: a última escrita vence.

### `DELETE /crm/deals/:id` · administrador

**Arquiva** o card (não apaga). `200`, corpo vazio.

### `PATCH /crm/deals/:id/unarchive` · administrador

Restaura o card. Responde com o card.

### `PATCH /crm/deals/:id/move`

O endpoint mais importante do módulo. Move o card de coluna **ou** reordena
dentro da própria coluna, e é o único caminho que grava transição.

Os parâmetros vão na **raiz** do corpo, não dentro de `deal`:

| Parâmetro | Obrigatório | Descrição |
|---|---|---|
| `stage_id` | sim | Estágio de destino. Precisa pertencer ao funil do card. |
| `lock_version` | **sim** | Versão do card que o cliente tinha na tela. |
| `position` | não | Posição fracionária calculada a partir dos vizinhos do ponto onde o card foi solto. Sem ela, o card vai para o fim da coluna. |
| `lost_reason_id` | condicional | Obrigatório quando o destino tem categoria `lost`. |

```bash
curl -X PATCH \
  -H "api_access_token: <TOKEN>" -H "Content-Type: application/json" \
  -d '{"stage_id": 14, "position": 1500, "lock_version": 3, "lost_reason_id": 22}' \
  "https://<HOST>/api/v1/accounts/<ACCOUNT_ID>/crm/deals/501/move"
```

Sucesso: `200` com o card no formato do `show`.

O que o `move` faz além de gravar a posição:

- grava uma `crm_stage_transitions` quando o estágio muda, com o tempo que o
  card passou no estágio anterior (`duration_seconds`);
- deriva o `status` da categoria do estágio de destino — `won` e `lost`
  preenchem `closed_at`, voltar para uma coluna `open` limpa `closed_at` e o
  motivo de perda;
- reinicia `stage_entered_at`;
- agenda o rebalanceamento das posições da coluna em background quando os cards
  ficam próximos demais.

Reordenar dentro da mesma coluna pula as validações de motivo de perda e de WIP
— elas guardam a **entrada** num estágio.

#### Contrato de erro do `move`

`409 Conflict` — outra pessoa moveu o card enquanto este cliente o segurava.
O corpo é o **card atual**, no mesmo formato do `show`, para o cliente
reconciliar sem uma segunda requisição.

`422 Unprocessable Entity` — regra de negócio, sempre no formato
`{ "error_code": "..." }`:

| `error_code` | Quando acontece | O que o cliente deve fazer |
|---|---|---|
| `lock_version_required` | `lock_version` ausente ou vazio. | Corrigir o cliente: o campo é obrigatório. |
| `lost_reason_required` | Destino é coluna `lost` e nenhum motivo foi informado (nem no parâmetro, nem já gravado no card). | Abrir o seletor de motivo e repetir o `move`. |
| `lost_reason_invalid` | O motivo informado não existe nessa conta. | Recarregar a lista de motivos. |
| `lost_reason_inactive` | O motivo existe mas foi desativado. | Pedir outro motivo. |
| `wip_limit_exceeded` | A coluna de destino já atingiu o `wip_limit` (contando as oportunidades abertas e não arquivadas). | Avisar o usuário; o card não se moveu. |

Um `stage_id` que não pertence ao funil do card responde `404`.

---

## Atividades (activities)

Aninhadas na oportunidade:
`/api/v1/accounts/:account_id/crm/deals/:deal_id/activities`.

A visibilidade segue a do card: o controlador autoriza `show?` da oportunidade
antes de qualquer coisa, então `restrito_por_owner` se aplica aqui também.

### `GET .../activities`

Paginado (25 por página), em ordem cronológica.

```json
{
  "meta": { "count": 7, "current_page": 1 },
  "payload": [
    {
      "id": 300,
      "deal_id": 501,
      "kind": "call",
      "content": "Ligação de qualificação",
      "due_at": 1785090000,
      "completed_at": null,
      "created_at": 1785000000,
      "user": { "id": 4, "name": "João" }
    }
  ]
}
```

### `GET .../activities/:id`

### `POST .../activities`

```json
{ "activity": { "kind": "task", "content": "Enviar proposta", "due_at": "2026-08-20T14:00:00Z" } }
```

`kind`: `note` (padrão), `call`, `meeting`, `task`, `system`, `whatsapp`.
O autor é sempre o usuário autenticado.

### `PATCH .../activities/:id`

Mesmos campos, mais `completed_at` (marcar como concluída).

### `DELETE .../activities/:id` · administrador

---

## Origens (sources)

### `GET /crm/sources`

Lista as origens ativas, ordenadas por nome.

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `include_inactive` | boolean | Inclui as desativadas (tela de administração). |

```json
{
  "payload": [
    { "id": 7, "name": "Landing Page", "kind": "landing", "inbox_id": 3,
      "identifier": "lp-principal", "active": true, "has_token": true }
  ]
}
```

O token **nunca** é devolvido aqui — nem o digest. `has_token` só diz se a
origem já foi credenciada.

### `GET /crm/sources/:id`

### `POST /crm/sources` · administrador

```json
{ "source": { "name": "n8n - Formulário", "kind": "n8n", "identifier": "n8n-form", "inbox_id": 3, "active": true } }
```

`kind`: `inbox`, `landing`, `import`, `api`, `n8n`, `manual`.

`inbox_id` é opcional no cadastro, mas **obrigatório para a ingestão pública
funcionar**: o contato é criado pelo builder padrão do Chatwoot, que precisa de
uma caixa de entrada.

### `PATCH /crm/sources/:id` · administrador
### `DELETE /crm/sources/:id` · administrador

As oportunidades que apontavam para a origem ficam com `source_id` nulo.

### `POST /crm/sources/:id/regenerate_token` · administrador

Gera (ou troca) o token de ingestão. **Esta é a única resposta em toda a API que
carrega o token em claro** — o banco guarda apenas um SHA-256. Se perder, só
gerando outro.

```json
{
  "id": 7, "name": "Landing Page", "kind": "landing", "inbox_id": 3,
  "identifier": "lp-principal", "active": true, "has_token": true,
  "token": "3xAmPl3T0k3nBase58...",
  "ingestion_url": "https://<HOST>/public/api/v1/accounts/<ACCOUNT_ID>/crm/leads"
}
```

Chamar de novo invalida o token anterior **imediatamente** — não há janela de
convivência.

---

## Motivos de perda (lost reasons)

### `GET /crm/lost_reasons`

Ativos, ordenados por `position, id`.

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `include_inactive` | boolean | Inclui os desativados. |

```json
{ "payload": [ { "id": 22, "name": "Preço", "position": 1000, "active": true } ] }
```

### `GET /crm/lost_reasons/:id`
### `POST /crm/lost_reasons` · administrador

```json
{ "lost_reason": { "name": "Preço", "position": 1000, "active": true } }
```

### `PATCH /crm/lost_reasons/:id` · administrador
### `DELETE /crm/lost_reasons/:id` · administrador

As oportunidades que usavam o motivo ficam com `lost_reason_id` nulo — e
aparecem no relatório de motivos de perda no balde "sem motivo".

Desativar (`active: false`) é o caminho preferível: o motivo some dos seletores
e o `move` passa a recusá-lo (`lost_reason_inactive`), mas o histórico das
oportunidades permanece.

---

## Relatórios

São sete endpoints `GET` sob `/crm/reports/`, todos com os **mesmos**
parâmetros de escopo:

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `pipeline_id` | int | Restringe a um funil. Ausente = todos os funis da conta. |
| `since` | int | Início do período, **epoch em segundos**. |
| `until` | int | Fim do período, epoch em segundos. |

`since` e `until` só valem **juntos**: com apenas um deles o período é ignorado
e a métrica considera todo o histórico. O intervalo é aberto no fim
(`since...until`).

Cada métrica filtra pelo timestamp que faz sentido para ela, e isso é parte do
contrato:

| Endpoint | Coluna do período |
|---|---|
| `funnel`, `stage_durations`, `deals_export` | `created_at` |
| `sales_cycle`, `sources`, `loss_reasons` | `closed_at` |
| `forecast` | `expected_close_on` |

Oportunidades arquivadas ficam fora de todas as métricas. Todas passam por
`policy_scope`, então um agente com `restrito_por_owner` recebe exatamente os
mesmos números que o quadro dele mostra.

Permissão: agente **ou** administrador (`Crm::ReportPolicy`).

### `GET /crm/reports/funnel`

Conversão por estágio. A fonte é `crm_stage_transitions`, nunca o `stage_id`
atual: um card que já passou por "Qualificado" e hoje está em "Proposta" conta
nos dois. Todos os estágios do funil aparecem, mesmo os que nunca receberam
nada.

```json
{
  "payload": [
    { "stage_id": 10, "pipeline_id": 1, "name": "Novo", "category": "open",
      "position": 1000, "entered_count": 120, "advanced_count": 84,
      "conversion_rate": 70.0 }
  ]
}
```

`advanced_count` = quantos daqueles cards chegaram, em algum momento, a um
estágio de posição maior.

### `GET /crm/reports/stage_durations`

Tempo médio em cada estágio, em segundos.

```json
{
  "payload": [
    { "stage_id": 10, "pipeline_id": 1, "name": "Novo", "category": "open",
      "position": 1000, "avg_duration_seconds": 172800, "transitions_count": 84 }
  ]
}
```

`avg_duration_seconds` é `null` quando ninguém saiu do estágio ainda.
`transitions_count` é o tamanho da amostra — só estadias **encerradas** entram.

### `GET /crm/reports/sales_cycle`

Tempo médio entre criação e fechamento, separado por desfecho.

```json
{
  "payload": {
    "won":  { "avg_cycle_seconds": 1209600, "deals_count": 31 },
    "lost": { "avg_cycle_seconds": 604800,  "deals_count": 44 }
  }
}
```

### `GET /crm/reports/forecast`

Previsão das oportunidades **abertas**, agrupada pelo mês de
`expected_close_on` e ponderada pela `probability` do estágio.

```json
{
  "payload": [
    { "period": "2026-09-01", "deals_count": 12,
      "value_cents": 4500000, "weighted_value_cents": 1575000 },
    { "period": null, "deals_count": 3,
      "value_cents": 900000, "weighted_value_cents": 225000 }
  ]
}
```

`period` é o primeiro dia do mês; `null` agrupa as oportunidades sem data
prevista — que são dinheiro real sem data, não lixo a descartar.

### `GET /crm/reports/sources`

Ganhos e perdas por canal de origem, entre o que fechou no período.

```json
{
  "payload": [
    { "source": { "id": 7, "name": "Landing Page", "kind": "landing" },
      "won_count": 12, "won_value_cents": 3600000,
      "lost_count": 8, "lost_value_cents": 1900000, "win_rate": 60.0 },
    { "source": null, "won_count": 2, "won_value_cents": 400000,
      "lost_count": 1, "lost_value_cents": 100000, "win_rate": 66.67 }
  ]
}
```

Ordenado por `won_value_cents` decrescente. `source: null` são as oportunidades
fechadas sem canal marcado.

### `GET /crm/reports/loss_reasons`

```json
{
  "payload": [
    { "lost_reason": { "id": 22, "name": "Preço" }, "deals_count": 18, "value_cents": 5400000 },
    { "lost_reason": null, "deals_count": 5, "value_cents": 1200000 }
  ]
}
```

Ordenado por quantidade decrescente. `lost_reason: null` são as perdas fechadas
sem motivo registrado.

### `GET /crm/reports/deals_export`

Devolve **`text/csv`**, não JSON, com
`Content-Disposition: attachment; filename=crm_deals.csv`.

Além dos parâmetros de escopo, aceita filtros de linha: `stage_id`, `owner_id`,
`source_id`, `status`.

Colunas, nesta ordem:

```
title, value, currency, stage, status, contact, owner, source, lost_reason, created_at, closed_at
```

`value` sai formatado com duas casas; `created_at`/`closed_at` em ISO 8601. O
arquivo é gerado com `CSVSafe`, que neutraliza injeção de fórmula nas colunas de
texto.

```bash
curl -H "api_access_token: <TOKEN>" \
  "https://<HOST>/api/v1/accounts/<ACCOUNT_ID>/crm/reports/deals_export?pipeline_id=1&status=won" \
  -o crm_deals.csv
```

---

## Ingestão pública de leads

```
POST /public/api/v1/accounts/:account_id/crm/leads
```

Ponto de entrada externo do funil: uma landing page, um fluxo do n8n ou
qualquer cliente HTTP posta um lead e ele vira card. **Não há sessão de
usuário** — quem se autentica é a `Crm::Source` dona do token.

### Autenticação

O token vai em um destes headers:

```
X-CRM-Source-Token: <token>
```

ou, para clientes que só oferecem o padrão OAuth:

```
Authorization: Bearer <token>
```

O token é gerado por `POST /crm/sources/:id/regenerate_token`
(ver [Origens](#origens-sources)).

A origem é procurada **dentro da conta da URL**: um token perfeitamente válido
em outra conta é rejeitado exatamente como um inventado. Origens desativadas
também não autenticam.

### Payload

```json
{
  "name": "Maria Silva",
  "email": "maria@example.com",
  "phone_number": "+5511999999999",
  "title": "Orçamento site institucional",
  "value": 3500.00,
  "pipeline_id": 1,
  "utm": {
    "utm_source": "google",
    "utm_medium": "cpc",
    "utm_campaign": "black-friday",
    "utm_term": "agencia",
    "utm_content": "anuncio-a"
  }
}
```

| Campo | Obrigatório | Notas |
|---|---|---|
| `email` **ou** `phone_number` | sim | Pelo menos um dos dois: sem identificação, todos os leads da conta colapsariam num único card. |
| `name` | não | Vira o título quando `title` não é informado. |
| `title` | não | Título do card. Cai para nome → e-mail → telefone → `Contact #<id>`. |
| `value` | não | Na unidade principal da moeda (`3500.00`), convertido para centavos. |
| `pipeline_id` | não | Sem ele, usa o funil padrão da conta; sem padrão, o primeiro por posição. Só funis **ativos**. |
| `utm` | não | Apenas `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`. O resto é descartado. |

Qualquer outro campo é ignorado: um endpoint público não pode definir
responsável, estágio ou status de um card.

```bash
curl -X POST \
  -H "X-CRM-Source-Token: <TOKEN>" -H "Content-Type: application/json" \
  -d '{"name":"Maria Silva","email":"maria@example.com","value":3500.0,"utm":{"utm_source":"google"}}' \
  "https://<HOST>/public/api/v1/accounts/<ACCOUNT_ID>/crm/leads"
```

### Respostas

`201 Created` — card novo:

```json
{ "deal_id": 501, "contact_id": 88, "pipeline_id": 1, "status": "created" }
```

`200 OK` — o contato já tinha um card aberto dentro da janela de deduplicação
do funil (`janela_dedupe_dias`, padrão 30). O card existente é "tocado"
(`last_activity_at`), **sem** sobrescrever os UTMs do primeiro toque:

```json
{ "deal_id": 501, "contact_id": 88, "pipeline_id": 1, "status": "deduplicated" }
```

`401 Unauthorized`:

```json
{ "error": "Invalid or inactive source token" }
```

`404 Not Found` — conta inexistente **ou** módulo desligado (o mesmo corpo nos
dois casos, de propósito):

```json
{ "error": "Resource could not be found" }
```

`422 Unprocessable Entity` — payload correto, configuração incompleta. Sempre
com um `code` estável:

| `code` | Significado |
|---|---|
| `contact_required` | Nem e-mail nem telefone foram informados. |
| `pipeline_not_found` | Nenhum funil ativo disponível (ou o `pipeline_id` informado não existe/está arquivado). |
| `pipeline_without_stages` | O funil não tem estágios para receber o lead. |
| `source_without_inbox` | A origem não tem caixa de entrada vinculada, então o contato não pode ser criado. |

```json
{ "error": "This source has no inbox linked, so the contact cannot be created",
  "code": "source_without_inbox" }
```

### Rate limit

`60` requisições por minuto, configurável pela variável de ambiente
`RATE_LIMIT_CRM_LEAD_INGESTION`.

A cota é por **conta + token**: cada credencial tem o próprio orçamento, então
uma landing page barulhenta não derruba o fluxo do n8n ao lado. Requisições sem
token compartilham um balde por conta, o que limita a força bruta contra a
própria credencial. O token em claro nunca chega ao cache do Rack::Attack — a
chave usa o SHA-256 dele.

Estourando o limite, a resposta é `429 Too Many Requests`.

### Log

O lead carrega PII e nada disso vai para o log da aplicação. O que se registra é
apenas a rastreabilidade operacional:

```
[CRM][LEAD] account=1 source=7 pipeline=1 deal=501 created=true
```

---

## Eventos de websocket

O quadro é uma superfície compartilhada. Toda escrita num card publica um evento
no canal do Chatwoot:

| Evento | Quando |
|---|---|
| `crm_deal.created` | Card criado (por qualquer caminho: API, ingestão, console). |
| `crm_deal.updated` | Edição comum, incluindo restauração de arquivado. |
| `crm_deal.moved` | Mudou `stage_id` ou `position`. |
| `crm_deal.archived` | Card arquivado. |
| `crm_stage.positions_rebalanced` | A coluna teve as posições renumeradas em background. Payload: `{ stage_id, pipeline_id }` — o cliente deve refazer o fetch da coluna. |

O payload dos quatro primeiros é o **card** (não a gaveta): não traz as
conversas vinculadas, porque o cliente deve **mesclar** esse payload sobre o
card que já tem, e não substituí-lo.

A entrega respeita a mesma visibilidade da API: num funil com
`restrito_por_owner`, um card com responsável só é publicado para
administradores e para o próprio responsável. Cards sem responsável vão para
todos os agentes.

Com o módulo desligado na conta, nenhum evento `crm_*` é publicado.
