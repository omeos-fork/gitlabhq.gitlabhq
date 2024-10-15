# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe QueueBackfillMilestoneReleasesProjectId, feature_category: :release_orchestration do
  let!(:batched_migration) { described_class::MIGRATION }

  it 'schedules a new batched migration' do
    reversible_migration do |migration|
      migration.before -> {
        expect(batched_migration).not_to have_scheduled_batched_migration
      }

      migration.after -> {
        expect(batched_migration).to have_scheduled_batched_migration(
          table_name: :milestone_releases,
          column_name: :milestone_id,
          interval: described_class::DELAY_INTERVAL,
          batch_size: described_class::BATCH_SIZE,
          batch_class_name: 'LooseIndexScanBatchingStrategy',
          sub_batch_size: described_class::SUB_BATCH_SIZE,
          gitlab_schema: :gitlab_main_cell,
          job_arguments: [
            :project_id,
            :releases,
            :project_id,
            :release_id
          ]
        )
      }
    end
  end
end
