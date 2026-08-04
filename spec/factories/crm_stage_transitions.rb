# frozen_string_literal: true

FactoryBot.define do
  factory :crm_stage_transition, class: 'Crm::StageTransition' do
    automated { false }

    # `to_stage` defaults to the stage the deal already sits in, which is guaranteed to be
    # in the deal's account and pipeline.
    after(:build) do |transition|
      transition.deal ||= create(:crm_deal)
      transition.to_stage ||= transition.deal.stage
    end

    trait :by_automation do
      automated { true }
    end
  end
end
