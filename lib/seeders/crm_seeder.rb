## Class to seed the default CRM funnel (pipeline + stages + lost reasons) for an @Account.
############################################################
### Usage #####
#
#   # Seed the default CRM funnel for an account
#   Seeders::CrmSeeder.new(account: Account.find(1)).perform!
#
#
############################################################

class Seeders::CrmSeeder
  DEFAULT_PIPELINE_NAME = 'Vendas'.freeze

  # `color` is a token from `Crm::Stage::COLORS`, mapped to Tailwind classes by the dashboard.
  DEFAULT_STAGES = [
    { name: 'Novo', category: :open, probability: 10, is_entry: true, rotting_days: 3, color: 'slate' },
    { name: 'Qualificado', category: :open, probability: 25, is_entry: false, rotting_days: 7, color: 'blue' },
    { name: 'Proposta', category: :open, probability: 50, is_entry: false, rotting_days: 10, color: 'violet' },
    { name: 'Negociação', category: :open, probability: 75, is_entry: false, rotting_days: 15, color: 'amber' },
    { name: 'Ganho', category: :won, probability: 100, is_entry: false, rotting_days: nil, color: 'emerald' },
    { name: 'Perdido', category: :lost, probability: 0, is_entry: false, rotting_days: nil, color: 'ruby' }
  ].freeze

  DEFAULT_LOST_REASONS = [
    'Preço',
    'Sem resposta',
    'Comprou do concorrente',
    'Fora do perfil',
    'Sem interesse no momento'
  ].freeze

  POSITION_STEP = 1000

  def initialize(account:)
    @account = account
  end

  def perform!
    seed_pipeline
    seed_stages
    seed_lost_reasons
  end

  private

  def seed_pipeline
    @pipeline = Crm::Pipeline.find_or_create_by!(account: @account, name: DEFAULT_PIPELINE_NAME) do |pipeline|
      pipeline.is_default = true
      pipeline.settings = default_pipeline_settings
    end
  end

  def default_pipeline_settings
    {
      'inbox_ids' => [],
      'janela_dedupe_dias' => 30,
      'exige_proxima_atividade' => true,
      'moeda_padrao' => 'BRL',
      'restrito_por_owner' => false
    }
  end

  def seed_stages
    DEFAULT_STAGES.each_with_index do |stage_data, index|
      Crm::Stage.find_or_create_by!(pipeline: @pipeline, name: stage_data[:name]) do |stage|
        stage.account = @account
        stage.category = stage_data[:category]
        stage.probability = stage_data[:probability]
        stage.is_entry = stage_data[:is_entry]
        stage.rotting_days = stage_data[:rotting_days]
        stage.color = stage_data[:color]
        stage.position = (index + 1) * POSITION_STEP
      end
    end
  end

  def seed_lost_reasons
    DEFAULT_LOST_REASONS.each_with_index do |reason_name, index|
      Crm::LostReason.find_or_create_by!(account: @account, name: reason_name) do |reason|
        reason.position = (index + 1) * POSITION_STEP
      end
    end
  end
end
