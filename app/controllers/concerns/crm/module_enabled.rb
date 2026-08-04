# The whole CRM is opt-in per account through `settings['crm_kanban']` (Super Admin → Accounts, or
# `account.update!(crm_kanban: true)`). While the toggle is off the module has to behave as if it
# had never been deployed: not "you are not allowed", but "there is nothing here".
#
# That is why the answer is a 404 built with `render_not_found_error` — the same helper
# `RequestExceptionHandler` uses for a record that does not exist, and the same shape
# (`{ error: ... }` + `:not_found`) the rest of the API returns for an unreachable resource. A 403
# would confirm the endpoints exist, and a 402 would promise an upgrade that this module does not
# sell.
#
# Included once by `Api::V1::Accounts::Crm::BaseController` (which every authenticated CRM
# controller inherits from) and once by the public lead ingestion endpoint, which has no session and
# therefore resolves the account from the URL instead of `Current.account`.
module Crm::ModuleEnabled
  extend ActiveSupport::Concern

  included do
    before_action :ensure_crm_module_enabled
  end

  private

  def ensure_crm_module_enabled
    return if crm_module_account&.crm_kanban?

    render_not_found_error(I18n.t('crm.module_disabled'))
  end

  # `Current.account` is set by `EnsureCurrentAccountHelper` on every authenticated account-scoped
  # request. Controllers outside that stack override this.
  def crm_module_account
    Current.account
  end
end
