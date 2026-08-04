# Arquitetura do CRM Kanban

Documento para quem for manter o módulo: o desenho das tabelas, as decisões que
não são óbvias pelo código e as armadilhas que já custaram um incidente cada.

Para o que o módulo faz, veja o [README](./README.md); para os contratos HTTP, a
[referência da API](./api.md).

## As oito tabelas

```
                            accounts
                                │  (todas as tabelas abaixo têm FK
                                │   ON DELETE CASCADE para accounts)
                                ▼
        ┌──────────────────  crm_pipelines  ──────────────────┐
        │                  (funil / quadro)                   │
        │  settings jsonb: inbox_ids, janela_dedupe_dias,     │
        │  exige_proxima_atividade, moeda_padrao,             │
        │  restrito_por_owner                                 │
        │  is_default: UNIQUE parcial por conta               │
        │                                                      │
        │ 1:N (destroy_async)                 1:N (restrict_with_error)
        ▼                                                      ▼
   crm_stages ───────────────────────────────────────────► crm_deals
   (coluna)          1:N (restrict_with_error)            (oportunidade)
   position int                                            position numeric
   category open/won/lost                                  lock_version int
   probability, wip_limit, rotting_days                    status open/won/lost
   is_entry                                                value_cents bigint
        ▲                                                        │
        │ from_stage_id (nullify) / to_stage_id                  │
        │                                                        │
   crm_stage_transitions ◄──────── 1:N (delete_all) ─────────────┤
   (auditoria append-only:                                       │
    só created_at, sem updated_at)                               │
    duration_seconds, automated, user_id                         │
                                                                 │
   crm_activities ◄───────────── 1:N (destroy) ──────────────────┤
   (linha do tempo)                                              │
    kind, content, due_at, completed_at, user_id                 │
    account_id desnormalizado                                    │
                                                                 │
   crm_deal_conversations ◄────── 1:N (destroy) ─────────────────┤
   (join deal ↔ conversation)                                    │
    is_origin bool                                               │
    UNIQUE (deal_id, conversation_id)                            │
    → conversations                                              │
                                                                 │
   crm_sources ─────────────── 1:N (nullify) ────────────────────┤
   (origem/canal)                                                │
    kind: inbox/landing/import/api/n8n/manual                    │
    token_digest (SHA-256), inbox_id                             │
                                                                 │
   crm_lost_reasons ────────── 1:N (nullify) ────────────────────┘
   (motivo de perda)
    active, position
```

Fora do namespace, `crm_deals` referencia ainda `contacts` (cascade), `users`
como `owner_id` (nullify), `teams` (nullify) e `inboxes` como `source_inbox_id`
(nullify).

### O que cada `dependent:` protege

- **`crm_pipelines has_many :deals, dependent: :restrict_with_error`** —
  apagar um funil com oportunidades é recusado; o caminho para retirá-lo do
  quadro é `archive`. A ordem de declaração importa: `deals` vem **antes** de
  `stages` porque o Rails executa os callbacks `dependent:` na ordem em que as
  associações foram declaradas. Declarada depois, a destruição do funil
  enfileiraria o `destroy_async` dos estágios *antes* de ser recusada. **Não
  reordene.**
- **`crm_stages has_many :deals, dependent: :restrict_with_error`** — mesma
  ideia por coluna.
- **`crm_stage_transitions dependent: :delete_all`** — auditoria não tem
  callback nenhum, então vale a deleção em massa.
- **`crm_sources` e `crm_lost_reasons` com `:nullify`** — retirar uma origem ou
  um motivo nunca bloqueia; a oportunidade simplesmente fica sem a etiqueta
  (e vira o balde "sem canal"/"sem motivo" nos relatórios).

## Decisões não óbvias, e o porquê

### Prefixo `crm_` nas tabelas e no namespace

Este fork convive com o módulo Kanban do fork Pro do fazer.ai, que usa
`kanban_tasks` e amigos. Um módulo chamado `kanban` aqui colidiria de frente com
ele no merge — tabelas, rotas, classes e a entrada da sidebar. O prefixo `crm_`
(e o namespace `Crm::`) mantém os dois módulos capazes de existir na mesma base
sem que um upgrade precise escolher entre eles.

O toggle segue a mesma lógica: `crm_kanban` é uma chave em `accounts.settings`
(jsonb), e **não** um flag em `config/features.yml`. Os flags de feature são
posicionais dentro de uma coluna bigint, e as posições divergem entre `main` e
`chatwoot-pro-main` — uma chave nomeada em jsonb é imune a essa deriva. Ver a
seção "Account-level toggles" do `AGENTS.md`.

### `position` como `numeric`, com fractional indexing

Cada coluna do quadro é ordenada por `position`. Soltar um card entre dois
vizinhos grava a **média** das posições deles (entre 1000 e 2000 → 1500), então
reordenar toca **uma linha**, não a coluna inteira. Nas pontas, anda um
`POSITION_GAP` (1000) para baixo ou para cima.

O preço: cada inserção no mesmo intervalo corta o espaço restante pela metade
(1000 → 500 → 250…). Depois de umas cinquenta inserções sucessivas os vizinhos
ficam a menos de uma unidade e o ponto médio deixa de ser um valor distinto —
dois cards colidem e a ordem da coluna vira arbitrária.

Por isso o `Crm::MoveDealService` mede, a cada movimento, a menor distância
entre vizinhos da coluna de destino (uma única passada de window function sobre
`index_crm_deals_active_on_stage_position`). Caindo abaixo de
`POSITION_REBALANCE_THRESHOLD` (1), ele enfileira
`Crm::RebalanceStagePositionsJob`, que renumera a coluna para múltiplos de 1000
numa única `UPDATE ... FROM (VALUES ...)`, com `FOR UPDATE` nas linhas.

O rebalance **não** incrementa `lock_version` nem `updated_at`, de propósito:
a ordem na tela continua byte a byte a mesma, só os números por trás mudaram.
Incrementar deixaria todos os cards da coluna obsoletos de uma vez, e o próximo
arraste em qualquer quadro aberto voltaria `409` por causa de uma faxina que o
usuário não causou. Em vez disso o job publica
`crm_stage.positions_rebalanced` e o cliente refaz o fetch daquela coluna.

### `lock_version` para concorrência

`crm_deals.lock_version` ativa o optimistic locking nativo do Rails (o nome da
coluna precisa ser exatamente esse). Dois agentes arrastando o mesmo card
transformam a segunda gravação num `ActiveRecord::StaleObjectError` em vez de um
sobrescrito silencioso.

No `move` o `lock_version` é **obrigatório** — mover é justamente a operação
concorrente. No `update` é **opcional**: a gaveta manda a versão que renderizou,
mas chamadas internas e scripts contra a API continuam com o velho
last-write-wins, que é o comportamento do resto do Chatwoot.

Em ambos os casos o `409` devolve o **card atual**, não uma mensagem de erro:
o cliente reconcilia sem uma segunda ida ao servidor.

### A criação do card é uma transição

`Crm::Deal#record_creation_transition` (um `after_create`) grava uma
`crm_stage_transitions` com `from_stage_id` NULL e `duration_seconds` NULL.

Sem isso o topo do funil ficaria subdimensionado: o `Crm::Reports::FunnelService`
conta "entrou no estágio X" pela existência de uma transição apontando **para**
X, e um card criado direto em "Novo" que nunca se moveu não teria nenhuma —
sumiria da primeira coluna do relatório. A migração
`20260804130000_backfill_crm_deal_creation_transitions` retrofita esse registro
para as oportunidades que já existiam.

Está no modelo, e não nos chamadores, para que **todo** caminho de criação (API,
ingestão de conversa, ingestão de lead, seed, console) produza o mesmo histórico.
Os `attr_accessor :creation_user` e `:creation_automated` carregam o contexto que
a linha sozinha não sabe: quem criou e se foi ação humana ou automação.

### Advisory lock no dedupe da ingestão

A deduplicação lê antes de escrever: procura um card aberto do contato dentro da
janela e, não achando, cria. Dois eventos do mesmo contato chegando juntos —
rotina no WhatsApp, onde roda um job por conversa, e em landing page com duplo
submit — os dois não achariam nada e os dois criariam um card.

`Crm::DealDedupe#lock_dedupe_key!` serializa esse par leitura-escrita com
`pg_advisory_xact_lock(CRC32("crm_ingest_deal_<account>_<pipeline>_<contact>"))`.
É um lock de **transação**: solta no COMMIT/ROLLBACK, sem unlock para vazar, e
bloqueia apenas outra ingestão exatamente do mesmo par. O `account_id` entra na
chave para que duas contas nunca compartilhem o mesmo slot.

O índice UNIQUE de `crm_deal_conversations` protege só o **vínculo**, não o card
— por isso o lock é necessário e não redundante.

### Agregados passam por `policy_scope`

`Crm::StageAggregatesService` e os sete serviços de relatório recebem um
`deals_scope`, e os controladores sempre passam `policy_scope(Crm::Deal)`.

O motivo é que total, média e previsão são suficientes para reconstruir o que
`restrito_por_owner` deveria esconder: quanto os outros agentes carregam, o que
estão fechando, por quais canais. Se o relatório abrisse para o funil inteiro, a
restrição do quadro seria decorativa.

Reusar o `Crm::DealPolicy::Scope` sem tocá-lo dá duas garantias de graça: um
agente restrito vê nos relatórios exatamente os mesmos números do quadro dele, e
não existe uma segunda cópia da regra de visibilidade para manter em sincronia.

`Crm::Reports::BaseService#base_deals` ainda reaplica `where(account_id:)` por
cima do escopo recebido — redundante hoje, mas garante por construção que uma
métrica não cruze contas se algum chamador futuro passar um escopo esquecido.

### Broadcast respeita a policy

`ActionCableListener#crm_deal_tokens` esconde no websocket exatamente o que
`Crm::DealPolicy::Scope` esconde na API: num funil restrito, um card **com**
responsável só é publicado para os administradores e para o próprio
responsável. Card **sem** responsável continua indo para todos os agentes — é
a mesma exceção que a policy faz (lead que ninguém pegou).

Sem esse cuidado, o push contaria por fora o que a listagem se recusa a contar.

Duas sutilezas na montagem da lista de tokens: os responsáveis são buscados
através de `account.agents` (para não duplicar um responsável que também é
administrador, e para não empurrar nada a um responsável que saiu da conta), e
o resultado passa por `.uniq`.

O evento `crm_stage.positions_rebalanced` publica **apenas** `stage_id` e
`pipeline_id`. Mandar as novas posições junto significaria publicar id e ordem
de cards que um agente restrito não pode ver; o id do estágio já é público para
quem consegue abrir o funil.

E o dispatch inteiro é gateado por `account.crm_kanban?`: com o módulo
desligado não há quadro escutando.

### Broadcast no modelo, não no controlador

`Crm::DealBroadcastable` é incluído no modelo e dispara em
`after_create_commit`/`after_update_commit`. Assim todo caminho que toca um card
— a API, o `Crm::IngestConversationService`, um conserto pelo console — chega
aos quadros abertos. Um `after_action` no controlador cobriria só o primeiro.

O nome do evento é derivado do que **mudou**: `archived_at` presente e card
arquivado → `crm_deal.archived`; mudou `stage_id` ou `position` →
`crm_deal.moved`; o resto → `crm_deal.updated`. Desarquivar reporta como
`updated`, porque o payload carrega `archived_at: nil`, que é o que devolve o
card ao quadro.

### `settings` do funil gravado por inteiro

`PipelinesController#update` permite `settings` como hash e a atribuição
**substitui** o jsonb inteiro. É uma escolha de simplicidade, mas obriga todo
cliente a mandar as cinco chaves — o store do front tem
`buildPipelineSettings()` justamente para preencher as que faltarem. Se um dia
alguém adicionar uma sexta chave, tem que adicioná-la ao default do front no
mesmo commit, ou ela será apagada na primeira edição pela tela.

### `is_default` é uma troca, não um conflito

Marcar um funil como padrão tira a marca de quem a tinha, num `before_save` do
modelo (não do controlador — `is_default` é escrito por seeds, imports e
console também). A ordem é o que torna seguro: o índice
`index_crm_pipelines_on_account_id_default` é UNIQUE parcial e não perdoa duas
linhas `true` nem por um instante, então o padrão anterior é limpo **antes** da
gravação, dentro da mesma transação. O índice fica como guarda de corrida.

### Validações de tenancy em cima das FKs

As chaves estrangeiras garantem que a linha referenciada existe, não que ela
pertence a esta conta. Por isso cada modelo do módulo valida explicitamente que
funil, estágio, contato, responsável, time, origem, caixa e motivo de perda são
da mesma conta — e que o estágio pertence ao funil do card. Sem isso, um payload
forjado apontaria um card para o funil de outra conta.

As tabelas sem `account_id` próprio (`crm_deal_conversations`,
`crm_stage_transitions`) comparam contra a conta **do deal**.

## Armadilhas já pagas

Cada uma destas custou um incidente. Não repita.

### 1. `numeric` do Postgres não é número em lugar nenhum

Foram **três** incidentes distintos, com a mesma origem e sintomas
completamente diferentes:

1. **No JSON, chega como string.** `crm_deals.position` é `numeric`; o Rails
   mapeia para `BigDecimal` e o jbuilder serializa como `"1000.0"`. O quadro faz
   aritmética com isso a cada movimento otimista, e a comparação de strings
   ordenava a coluna errado. Correção: `normalizeDeal` no store converte no
   ingresso (`app/javascript/dashboard/store/crm/board.js`).
2. **`SUM` sobre `bigint` também vira numeric.** Os totais de coluna
   (`Crm::StageAggregatesService`) voltavam como `"4500000.0"` e o quadro somava
   strings. Correção: `.to_i` explícito no serviço, antes do jbuilder.
3. **`BigDecimal` não é tipo nativo do JSON, e o Sidekiq recusa o job.**
   O payload do broadcast viaja como **argumento** de
   `ActionCableBroadcastJob`, e `Sidekiq::JobUtil#verify_json` rejeita
   argumentos que não sejam tipos JSON nativos. Como o dispatch roda em
   `after_*_commit`, a linha **já estava gravada** quando o enfileiramento
   falhava: o usuário levava `500` numa operação que tinha dado certo, o card só
   aparecia depois de recarregar, e o `lock_version` divergia (a próxima edição
   voltava `409`). Correção: `json_safe` em `Crm::DealBroadcastable` converte o
   payload inteiro recursivamente — não campo a campo, para que uma coluna nova
   ou um valor aninhado em `custom_attributes`/`utm` não reintroduza o bug.

Regra prática: **toda** coluna `numeric` do módulo precisa de conversão
explícita em toda fronteira (JSON, argumento de job, aritmética no front).

### 2. `@token` colide com o `devise_token_auth`

`DeviseTokenAuth::Concerns::SetUserByToken` é dono da ivar `@token` (guarda um
`TokenFactory`) e lê `@token.client` no `after_action :update_auth_header` —
que é registrado **antes** do `handle_with_exception` e portanto roda **fora**
dele. Sobrescrever `@token` com uma String num controlador transforma um `200`
já renderizado em um `500` não capturado.

Por isso `SourcesController#regenerate_token` guarda o token em `@plain_token`.
Vale para qualquer controlador novo do fork: **nunca** use `@token`.

### 3. Spec fora dos `paths` do workflow não roda, e o CI fica verde

O `.github/workflows/test-crm.yml` dispara por `paths`. Já aconteceu **duas
vezes** de um arquivo real do módulo ficar fora da lista: o push não acionava
nada, o check aparecia como sucesso e a regressão passava.

Duas consequências práticas:

- A lista começa com o glob largo `**/crm/**` de propósito. **Prefira alargar o
  glob a enumerar mais um diretório**; enumerar é o que falhou das duas vezes.
- Ao criar um spec num caminho que não case com nenhum padrão (por exemplo um
  spec de um arquivo compartilhado como `app/listeners/action_cable_listener.rb`
  ou `lib/events/types.rb`), **adicione o caminho ao workflow no mesmo commit**.
- Um check verde não é prova de que a suíte rodou. Confira que o job realmente
  executou antes de confiar nele.

## Onde encaixar código novo

| Se você vai... | Mexa em |
|---|---|
| Adicionar uma regra que bloqueia um movimento | `Crm::MoveDealService#validate_move!`, com um `error_code` novo documentado na [API](./api.md#contrato-de-erro-do-move) |
| Adicionar uma métrica | Um serviço em `app/services/crm/reports/` herdando de `BaseService`, uma ação em `ReportsController`, uma rota e um jbuilder |
| Adicionar um caminho de ingestão | Um serviço que inclua `Crm::DealDedupe` (para herdar lock, janela e posição de entrada) |
| Adicionar um campo ao card em tempo real | `CARD_EVENT_ATTRIBUTES` ou `TIMESTAMP_EVENT_ATTRIBUTES` em `Crm::DealBroadcastable`, **e** o jbuilder — os dois formatos têm que bater, porque o store faz merge |
| Adicionar uma configuração de funil | `Crm::Pipeline::SETTINGS_KEYS`, os `permitted_params` do controlador **e** `DEFAULT_PIPELINE_SETTINGS` no store do front |
| Adicionar uma consulta ao quadro | Confira se ela cabe num dos índices parciais de `20260804140000_add_crm_performance_indexes` antes de criar outro |
