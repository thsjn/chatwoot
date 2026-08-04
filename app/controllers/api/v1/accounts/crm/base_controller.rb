# Every authenticated CRM controller hangs off this one, so the account toggle is checked in a
# single place instead of once per controller. Same shape as
# `Api::V1::Accounts::InternalChat::BaseController`.
class Api::V1::Accounts::Crm::BaseController < Api::V1::Accounts::BaseController
  include Crm::ModuleEnabled
end
