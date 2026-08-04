# frozen_string_literal: true

FactoryBot.define do
  factory :crm_pipeline, class: 'Crm::Pipeline' do
    account
    sequence(:name) { |n| "Pipeline #{n}" }
    position { 0 }
    settings do
      {
        'inbox_ids' => [],
        'janela_dedupe_dias' => 30,
        'exige_proxima_atividade' => false,
        'moeda_padrao' => 'BRL',
        'restrito_por_owner' => false
      }
    end

    trait :default do
      is_default { true }
    end

    trait :restricted_by_owner do
      settings do
        {
          'inbox_ids' => [],
          'janela_dedupe_dias' => 30,
          'exige_proxima_atividade' => false,
          'moeda_padrao' => 'BRL',
          'restrito_por_owner' => true
        }
      end
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
