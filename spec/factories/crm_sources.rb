# frozen_string_literal: true

FactoryBot.define do
  factory :crm_source, class: 'Crm::Source' do
    account
    sequence(:name) { |n| "Source #{n}" }
    kind { :manual }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
