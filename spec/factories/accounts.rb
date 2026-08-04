# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    status { 'active' }
    domain { 'test.com' }
    support_email { 'support@test.com' }

    # The CRM module is opt-in in production (`settings['crm_kanban']`, off by default), but every
    # CRM spec — and every spec that asserts the conversation -> card ingestion or the deal
    # broadcast — describes an account that HAS the module on. Defaulting it here keeps that intent
    # explicit in one place instead of repeating `crm_kanban: true` in each of them.
    #
    # The disabled path is covered on purpose by `create(:account, crm_kanban: false)`, in
    # `spec/requests/api/v1/accounts/crm/module_disabled_spec.rb` and in the disabled contexts of
    # the lead ingestion, ingestion service and broadcast specs.
    crm_kanban { true }
  end
end
