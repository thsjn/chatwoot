class CreateCrmSources < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_sources do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.references :inbox, null: true, index: true, foreign_key: { on_delete: :nullify }
      t.string :identifier
      t.string :token_digest
      t.boolean :active, null: false, default: true

      t.timestamps

      t.index [:account_id, :kind]
      t.index [:account_id, :identifier]
    end
  end
end
