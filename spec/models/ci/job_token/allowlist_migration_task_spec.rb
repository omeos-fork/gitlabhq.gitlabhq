# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::JobToken::AllowlistMigrationTask, :silence_stdout, feature_category: :secrets_management do
  let(:only_ids) { nil }
  let(:exclude_ids) { nil }
  let(:preview) { nil }
  let(:output_stream) { StringIO.new }
  let(:path) { Rails.root.join('tmp/tests/doc/ci/jobs') }
  let(:user) { ::Users::Internal.admin_bot }

  let(:task) do
    described_class.new(only_ids: only_ids, exclude_ids: exclude_ids, preview: preview, user: user,
      output_stream: output_stream)
  end

  let_it_be(:origin_project) { create(:project) }
  let_it_be(:accessed_project1) { create(:project) }
  let_it_be(:accessed_project2) { create(:project) }
  let_it_be(:accessed_project3) { create(:project) }
  let(:accessed_projects) do
    [
      accessed_project1.reload,
      accessed_project2.reload,
      accessed_project3.reload
    ]
  end

  before do
    accessed_projects.each do |accessed_project|
      create(:ci_job_token_authorization, origin_project: origin_project, accessed_project: accessed_project,
        last_authorized_at: 1.day.ago)

      accessed_projects.map { |p| p.ci_cd_settings.update!(inbound_job_token_scope_enabled: false) }
    end
  end

  describe '#execute' do
    context "when preview mode is enabled" do
      let(:preview) { "1" }

      it 'does not call unsafe_execute!' do
        expect_any_instance_of(::Ci::JobToken::AutopopulateAllowlistService).not_to receive(:unsafe_execute!) # rubocop:disable RSpec/AnyInstanceOf -- not the next instance

        task.execute
      end

      it 'logs the expected messages' do
        messages = []
        messages << task.send(:preview_banner)
        messages << "\n\nMigrating project(s) in preview mode...\n"
        accessed_projects.each do |accessed_project|
          messages << "\nWould have migrated project id: #{accessed_project.id}."
        end
        messages << "\n\nMigration complete in preview mode.\n\n"

        task.execute

        expect(output_stream.string).to eq(messages.join)
      end
    end

    context "when preview mode is disabled" do
      it 'calls unsafe_execute!' do
        service = instance_double(::Ci::JobToken::AutopopulateAllowlistService)
        allow(::Ci::JobToken::AutopopulateAllowlistService).to receive(:new).and_return(service)
        expect(service).to receive(:unsafe_execute!).exactly(3).times

        task.execute
      end

      it 'logs the expected messages' do
        messages = []
        messages << "\nMigrating project(s)...\n"
        accessed_projects.each do |accessed_project|
          messages << "\nMigrated project id: #{accessed_project.id}."
        end
        messages << "\n\nMigration complete.\n\n"

        task.execute

        expect(output_stream.string).to eq(messages.join)
      end

      context "when an exception is raised" do
        let(:project) { create(:project) }
        let(:only_ids) { project.id.to_s }

        it 'logs the error' do
          exception = Gitlab::Utils::TraversalIdCompactor::CompactionLimitCannotBeAchievedError
          message = "Error migrating project id: #{project.id}, error: #{exception}\n"

          expect_next_instance_of(::Ci::JobToken::AutopopulateAllowlistService) do |instance|
            expect(instance).to receive(:unsafe_execute!).and_raise(exception)
          end

          task.execute

          expect(output_stream.string).to include(message)
        end
      end
    end

    context "when exclude_ids is supplied" do
      let(:exclude_ids) { "#{accessed_project1.id}, #{accessed_project2.id}" }

      it 'migrates all projects expect those excluded by exclude_ids' do
        expect(task).not_to receive(:migrate_project).with(accessed_project1)
        expect(task).not_to receive(:migrate_project).with(accessed_project2)
        expect(task).to receive(:migrate_project).with(accessed_project3)

        task.execute
      end

      context 'when too many exclude_ids are supplied' do
        let(:exclude_ids) { (1..1001).to_a.join(",") }

        it 'displays an error' do
          task.execute

          expect(output_stream.string).to include(
            "ONLY_PROJECT_IDS and EXCLUDE_PROJECT_IDS must contain less than 1000 items, try again"
          )
        end
      end
    end

    context "when only_ids is supplied" do
      let(:only_ids) { "#{accessed_project1.id}, #{accessed_project2.id}" }

      it 'only migrates projects listed in only_ids' do
        Project.find([accessed_project1.id, accessed_project2.id]).each do |project|
          expect(task).to receive(:migrate_project).with(project)
        end

        task.execute
      end

      context 'when too many only_ids are supplied' do
        let(:only_ids) { (1..1001).to_a.join(",") }

        it 'displays an error' do
          task.execute

          expect(output_stream.string).to include(
            "ONLY_PROJECT_IDS and EXCLUDE_PROJECT_IDS must contain less than 1000 items, try again"
          )
        end
      end
    end

    context "when both only_ids and exclude_ids are supplied" do
      let(:exclude_ids) { accessed_project1.id.to_s }
      let(:only_ids) { accessed_project2.id.to_s }

      it 'displays an error' do
        task.execute

        expect(output_stream.string).to include(
          "ONLY_PROJECT_IDS and EXCLUDE_PROJECT_IDS cannot both be set, try again."
        )
      end
    end
  end
end
