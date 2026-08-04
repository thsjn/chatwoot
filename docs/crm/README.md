# CRM Kanban

Um funil de vendas em Kanban dentro do próprio Chatwoot: cada card é uma
oportunidade, ligada ao contato que já existe na conta e às conversas que ela
gerou. O atendimento e a venda passam a viver no mesmo lugar — quem arrasta o
card entre as colunas é a mesma pessoa que responde a conversa, e abrir o card
mostra a conversa de origem sem trocar de ferramenta.

Este módulo vive no fork [`thsjn/chatwoot`](https://github.com/thsjn/chatwoot),
branch `crm`, e é **opt-in por conta**: enquanto o toggle estiver desligado (o
padrão) a instalação se comporta exatamente como um Chatwoot sem ele.

- [Referência da API](./api.md)
- [Arquitetura e decisões de projeto](./arquitetura.md)

## O que o módulo faz

- **Quadro Kanban por funil.** Colunas são os estágios; cards são as
  oportunidades. Arrastar um card entre colunas registra a transição, atualiza o
  status e (quando cai em coluna de perda) pede o motivo.
- **Cards ligados a conversas e contatos.** Toda oportunidade pertence a um
  `Contact` da conta. Conversas podem ser vinculadas ao card, com uma marcada
  como conversa de origem.
- **Ingestão automática de conversa.** Um funil pode declarar quais caixas de
  entrada alimentam o quadro: cada conversa nova dessas caixas vira card — ou é
  anexada ao card que o contato já tem em aberto (deduplicação).
- **Ingestão externa de leads.** Um endpoint público autenticado por token
  recebe leads de landing page, n8n ou qualquer cliente HTTP e cria o card na
  mesma regra de deduplicação.
- **Tempo real.** Criação, edição, movimentação e arquivamento de cards são
  publicados por websocket para todos os quadros abertos, respeitando a mesma
  visibilidade da API.
- **Atividades por oportunidade.** Linha do tempo com notas, ligações,
  reuniões, tarefas e mensagens, com data prevista e conclusão.
- **Relatórios do funil.** Conversão por estágio, tempo médio por estágio, ciclo
  de vendas, previsão ponderada, desempenho por canal, motivos de perda e
  exportação em CSV.
- **Higiene do quadro.** Limite de WIP por coluna, apodrecimento
  (`rotting_days`) sinalizado no card, arquivamento reversível de cards e de
  funis inteiros.

## Conceitos

| Conceito | Tabela | O que é |
|---|---|---|
| **Funil** (pipeline) | `crm_pipelines` | O quadro. Uma conta pode ter vários; um deles é o padrão. Carrega as configurações de ingestão, moeda, janela de deduplicação e visibilidade. |
| **Estágio** (stage) | `crm_stages` | A coluna. Tem posição, cor, probabilidade (usada na previsão), categoria (`open`/`won`/`lost`), limite de WIP e prazo de apodrecimento. |
| **Oportunidade** (deal) | `crm_deals` | O card. Título, valor em centavos, moeda, contato, responsável, time, data prevista de fechamento, campos personalizados e UTM. |
| **Atividade** (activity) | `crm_activities` | Item da linha do tempo do card: `note`, `call`, `meeting`, `task`, `system` ou `whatsapp`, com `due_at` e `completed_at`. |
| **Origem** (source) | `crm_sources` | O canal por onde a oportunidade chegou: `inbox`, `landing`, `import`, `api`, `n8n` ou `manual`. As de tipo credenciado carregam o token da ingestão pública. |
| **Motivo de perda** (lost reason) | `crm_lost_reasons` | Lista curada pela conta. Obrigatório ao mover um card para uma coluna de categoria `lost`. |
| **Transição** | `crm_stage_transitions` | Trilha de auditoria append-only de cada passagem do card por um estágio, com o tempo que ele ficou no estágio anterior. A criação do card também é uma transição (sem estágio de origem). |
| **Vínculo com conversa** | `crm_deal_conversations` | Liga card e conversa; `is_origin` marca a conversa que abriu o card. |

### Papéis

- **Agente**: vê o quadro, cria e edita cards, move cards, registra atividades e
  lê os relatórios.
- **Administrador**: tudo do agente, mais a configuração do funil (funis,
  estágios, origens, motivos de perda), o arquivamento/restauração de cards e a
  geração de tokens de ingestão.

Quando o funil tem `restrito_por_owner` ligado, o agente só enxerga os cards
dos quais é responsável — mais os cards sem responsável, que são leads que
ninguém pegou ainda. Isso vale no quadro, na API, nos relatórios e no
websocket: os agregados usam o mesmo escopo da listagem, então um agente
restrito nunca reconstrói o funil inteiro pelos totais.

## Como ativar

O módulo é ligado por conta pelo toggle `crm_kanban` em `accounts.settings`.
O ritual completo (Super Admin, console, o que exatamente muda com o toggle
desligado e como fazer rollback) está no [`UPGRADE.md`](../../UPGRADE.md) na
raiz do repositório — não duplicamos aqui para não divergir.

Em resumo: Super Admin → Accounts → a conta → Edit → marcar **Crm kanban** →
Update Account. O usuário precisa recarregar a aba para o item de menu passar a
abrir o quadro.

Com o toggle desligado, toda a API do CRM responde **404** (inclusive o
endpoint público de leads, mesmo com token válido), conversa nova não vira card
e nenhum evento `crm_deal.*` é publicado.

## Como semear o funil padrão

`Seeders::CrmSeeder` cria um funil "Vendas" com seis estágios e cinco motivos
de perda. É idempotente (`find_or_create_by!`), então rodar duas vezes não
duplica nada.

```ruby
Seeders::CrmSeeder.new(account: Account.find(<id>)).perform!
```

O que ele cria:

- **Funil** `Vendas`, marcado como padrão, com `settings`:
  `inbox_ids: []` (ingestão automática **desligada**), `janela_dedupe_dias: 30`,
  `exige_proxima_atividade: true`, `moeda_padrao: 'BRL'`,
  `restrito_por_owner: false`.
- **Estágios**: `Novo` (entrada, 10%, apodrece em 3 dias), `Qualificado` (25%,
  7 dias), `Proposta` (50%, 10 dias), `Negociação` (75%, 15 dias), `Ganho`
  (categoria `won`, 100%) e `Perdido` (categoria `lost`, 0%).
- **Motivos de perda**: `Preço`, `Sem resposta`, `Comprou do concorrente`,
  `Fora do perfil`, `Sem interesse no momento`.

Para ligar a ingestão automática depois, edite `settings['inbox_ids']` do funil
(pela tela de administração ou pela API) com os ids das caixas de entrada.

### Trazer conversas antigas para o quadro

`Crm::BackfillJob` aplica as mesmas regras de ingestão às conversas que já
existiam quando as caixas foram configuradas. Ele roda em **modo de simulação
por padrão** — o primeiro retorno é só um relatório de quantos cards *seriam*
criados e quantas conversas *seriam* vinculadas, por caixa.

```ruby
Crm::BackfillJob.perform_now(Account.find(<id>))                                  # prévia
Crm::BackfillJob.perform_now(Account.find(<id>), dry_run: false, window_days: 30) # pra valer
```

A janela padrão é de 90 dias.

## Limitações conhecidas

Nada disto é bug escondido: são recortes conscientes do escopo atual.

- **Soma de valores não converte moeda.** Cada oportunidade guarda a própria
  `currency`, mas todos os totais (cabeçalho de coluna, previsão, relatórios de
  canal e de motivo de perda) somam `value_cents` direto. Numa conta com funis
  em moedas diferentes o total não representa um montante em moeda única — a
  interface avisa isso, e a exportação em CSV traz a moeda linha a linha.
- **Tempo por estágio só conta estadias encerradas.** `duration_seconds` é
  gravado na transição, ou seja, no momento em que o card *sai* do estágio. Um
  card parado há três meses numa coluna não entra na média dela até se mover.
- **Origem e motivo de perda não têm histórico.** O card aponta para a linha
  atual de `crm_sources`/`crm_lost_reasons`. Renomear ou re-etiquetar reescreve
  o passado dos relatórios de canal e de motivo de perda: eles agrupam pela
  chave estrangeira, não por um valor congelado no fechamento. Se quiser trocar
  o significado de uma origem, crie uma nova em vez de renomear a antiga.
- **Reordenar estágios não é atômico.** Não há endpoint de reordenação em lote:
  arrastar colunas dispara um `PATCH` por estágio que mudou de posição. Se um
  deles falhar, a ordem fica parcialmente aplicada até a próxima gravação.
- **Token de origem não expira nem tem janela de rotação.** `regenerate_token`
  invalida o token anterior **na hora**; não existe período de convivência entre
  o token velho e o novo, nem expiração automática. Trocar o token de uma landing
  page ativa derruba as integrações até que elas sejam atualizadas.
- **`exige_proxima_atividade` ainda não faz nada.** A chave existe em
  `Crm::Pipeline::SETTINGS_KEYS`, é editável na tela de configuração do funil e
  é persistida — mas nenhum código do backend ou do quadro a lê para bloquear
  qualquer coisa. Hoje é só uma preferência guardada.
- **Deduplicação conta a partir de agora.** A janela (`janela_dedupe_dias`) é
  medida a partir do instante da ingestão, não da data do evento. Um backfill,
  portanto, colapsa todo o histórico de um contato num único card — que é a
  intenção (um card por negócio, não um por conversa), mas surpreende quem
  espera um card por período.
- **Filtro por período de fechamento exclui cards sem data.** Uma oportunidade
  sem `expected_close_on` cai fora de qualquer intervalo com as duas pontas
  definidas.
- **Relatórios exigem as duas pontas do período.** `since` e `until` só valem
  juntos; com apenas um dos dois o intervalo é ignorado e a métrica considera
  todo o histórico.

## Arquivos do módulo

```
app/models/crm/                       modelos (8 tabelas)
app/models/concerns/crm/              broadcast em tempo real do card
app/controllers/api/v1/accounts/crm/  API autenticada
app/controllers/public/api/v1/accounts/crm/  ingestão pública de leads
app/controllers/concerns/crm/         gate do módulo, filtros do quadro
app/services/crm/                     movimentação, ingestão, agregados
app/services/crm/reports/             as 7 métricas do funil
app/jobs/crm/                         ingestão async, backfill, rebalance
app/policies/crm/                     autorização e escopo de visibilidade
app/views/api/v1/accounts/crm/        jbuilder + CSV
app/javascript/dashboard/routes/dashboard/crm/   quadro, relatórios, config
app/javascript/dashboard/store/crm/   stores Pinia
app/javascript/dashboard/api/crm/     clientes HTTP
lib/seeders/crm_seeder.rb             funil padrão
db/migrate/202608041*                 as 8 tabelas + backfill + índices
```

> `app/services/crm/leadsquared/` e `app/jobs/crm/setup_job.rb` **não** fazem
> parte deste módulo: são a integração com o CRM externo LeadSquared que já vem
> do Chatwoot upstream e que apenas compartilha o namespace `Crm::`.
