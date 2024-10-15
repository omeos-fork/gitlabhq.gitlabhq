# frozen_string_literal: true

class AddPackagesPypiMetadataProjectIdFk < Gitlab::Database::Migration[2.2]
  milestone '17.5'
  disable_ddl_transaction!

  def up
    add_concurrent_foreign_key :packages_pypi_metadata, :projects, column: :project_id, on_delete: :cascade
  end

  def down
    with_lock_retries do
      remove_foreign_key :packages_pypi_metadata, column: :project_id
    end
  end
end
