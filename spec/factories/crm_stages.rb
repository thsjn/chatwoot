# frozen_string_literal: true

FactoryBot.define do
  factory :crm_stage, class: 'Crm::Stage' do
    sequence(:name) { |n| "Stage #{n}" }
    category { :open }
    probability { 10 }
    position { 0 }

    # The pipeline drives the account: building a stage with a pipeline from another
    # account would trip `pipeline_must_belong_to_account`.
    after(:build) do |stage|
      stage.account ||= stage.pipeline&.account || create(:account)
      stage.pipeline ||= create(:crm_pipeline, account: stage.account)
    end

    trait :entry do
      is_entry { true }
    end

    trait :won do
      category { :won }
      probability { 100 }
    end

    trait :lost do
      category { :lost }
      probability { 0 }
    end
  end
end
