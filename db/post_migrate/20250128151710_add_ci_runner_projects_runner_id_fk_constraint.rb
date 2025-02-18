# frozen_string_literal: true

class AddCiRunnerProjectsRunnerIdFkConstraint < Gitlab::Database::Migration[2.2]
  milestone '17.9'
  disable_ddl_transaction!

  SOURCE_TABLE_NAME = :ci_runner_projects
  TARGET_TABLE_NAME = :project_type_ci_runners_e59bb2812d
  COLUMN_NAME = :runner_id
  FK_CONSTRAINT_NAME = 'fk_98f08fcaf7'

  def up
    add_concurrent_foreign_key SOURCE_TABLE_NAME, TARGET_TABLE_NAME,
      name: FK_CONSTRAINT_NAME, column: COLUMN_NAME, on_delete: :cascade
  end

  def down
    with_lock_retries do
      remove_foreign_key_if_exists SOURCE_TABLE_NAME, TARGET_TABLE_NAME, name: FK_CONSTRAINT_NAME
    end
  end
end
