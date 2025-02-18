# frozen_string_literal: true

class AddEnvironmentFkToClustersManagedResources < Gitlab::Database::Migration[2.2]
  disable_ddl_transaction!
  milestone '17.9'

  def up
    add_concurrent_foreign_key :clusters_managed_resources, :environments, column: :environment_id, on_delete: :cascade
  end

  def down
    with_lock_retries do
      remove_foreign_key :clusters_managed_resources, column: :environment_id
    end
  end
end
