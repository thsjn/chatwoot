# frozen_string_literal: true

FactoryBot.define do
  factory :crm_lost_reason, class: 'Crm::LostReason' do
    account
    sequence(:name) { |n| "Lost Reason #{n}" }
    position { 0 }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
