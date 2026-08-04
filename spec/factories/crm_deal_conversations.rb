# frozen_string_literal: true

FactoryBot.define do
  factory :crm_deal_conversation, class: 'Crm::DealConversation' do
    is_origin { false }

    after(:build) do |deal_conversation|
      account = deal_conversation.deal&.account || deal_conversation.conversation&.account || create(:account)
      deal_conversation.deal ||= create(:crm_deal, account: account)
      deal_conversation.conversation ||= create(:conversation, account: account)
    end

    trait :origin do
      is_origin { true }
    end
  end
end
