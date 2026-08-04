# frozen_string_literal: true

FactoryBot.define do
  factory :crm_activity, class: 'Crm::Activity' do
    kind { :note }
    content { 'Called the lead' }

    after(:build) do |activity|
      activity.account ||= activity.deal&.account || create(:account)
      activity.deal ||= create(:crm_deal, account: activity.account)
    end

    trait :task do
      kind { :task }
      due_at { 1.day.from_now }
    end

    trait :completed do
      completed_at { Time.current }
    end
  end
end
