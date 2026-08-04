class CreateCrmActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_activities do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, index: true, foreign_key: { to_table: :crm_deals, on_delete: :cascade }
      t.references :user, null: true, index: true, foreign_key: { on_delete: :nullify }
      t.integer :kind, null: false, default: 0
      t.text :content
      t.datetime :due_at
      t.datetime :completed_at

      t.timestamps

      t.index [:deal_id, :created_at], name: 'index_crm_activities_on_deal_id_and_created_at'
      t.index [:account_id, :due_at], name: 'index_crm_activities_on_account_id_and_due_at'
    end
  end
end
