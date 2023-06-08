# frozen_string_literal: true

class ReplacePCiRunnerMachineBuildsForeignKey < Gitlab::Database::Migration[2.1]
  include Gitlab::Database::PartitioningMigrationHelpers

  disable_ddl_transaction!

  def up
    add_concurrent_partitioned_foreign_key :p_ci_runner_machine_builds, :p_ci_builds,
      name: 'temp_fk_bb490f12fe_p',
      column: [:partition_id, :build_id],
      target_column: [:partition_id, :id],
      on_update: :cascade,
      on_delete: :cascade,
      validate: false,
      reverse_lock_order: true

    prepare_partitioned_async_foreign_key_validation :p_ci_runner_machine_builds,
      name: 'temp_fk_bb490f12fe_p'
  end

  def down
    unprepare_partitioned_async_foreign_key_validation :p_ci_runner_machine_builds, name: 'temp_fk_bb490f12fe_p'

    Gitlab::Database::PostgresPartitionedTable.each_partition(:p_ci_runner_machine_builds) do |partition|
      execute "ALTER TABLE #{partition.identifier} DROP CONSTRAINT IF EXISTS temp_fk_bb490f12fe_p"
    end
  end
end
