# frozen_string_literal: true

FactoryBot.define do
  factory :crm_deal, class: 'Crm::Deal' do
    sequence(:title) { |n| "Deal #{n}" }
    currency { 'BRL' }
    value_cents { 100_000 }
    status { :open }
    position { 0 }

    # The deal carries eight cross-tenant validations, so the factory has to keep account,
    # pipeline, stage and contact consistent no matter which of them the caller passes in.
    after(:build) do |deal|
      deal.account ||= deal.pipeline&.account || deal.stage&.account || deal.contact&.account || create(:account)
      deal.pipeline ||= deal.stage&.pipeline || create(:crm_pipeline, account: deal.account)
      deal.stage ||= create(:crm_stage, account: deal.account, pipeline: deal.pipeline)
      deal.contact ||= create(:contact, account: deal.account)
    end

    trait :archived do
      archived_at { Time.current }
    end

    trait :won do
      status { :won }
      closed_at { Time.current }
    end

    trait :lost do
      status { :lost }
      closed_at { Time.current }
    end
  end
end
