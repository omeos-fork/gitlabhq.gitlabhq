# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineSchedulePolicy, :models, :clean_gitlab_redis_cache, feature_category: :continuous_integration do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :repository, create_tag: tag_ref_name) }
  let_it_be_with_reload(:pipeline_schedule) { create(:ci_pipeline_schedule, :nightly, project: project) }
  let_it_be(:tag_ref_name) { "v1.0.0" }

  let(:policy) do
    described_class.new(user, pipeline_schedule)
  end

  describe 'rules' do
    describe 'rules for protected ref' do
      context 'for branch' do
        %w[refs/heads/master master].each do |branch_ref|
          context "with #{branch_ref}" do
            let_it_be(:branch_ref_name) { "master" }
            let_it_be(:branch_pipeline_schedule) do
              create(:ci_pipeline_schedule, :nightly, project: project, ref: branch_ref)
            end

            where(:push_access_level, :merge_access_level, :project_role, :accessible) do
              :no_one_can_push | :no_one_can_merge | :owner      | :be_disallowed
              :no_one_can_push | :no_one_can_merge | :maintainer | :be_disallowed
              :no_one_can_push | :no_one_can_merge | :developer  | :be_disallowed
              :no_one_can_push | :no_one_can_merge | :reporter   | :be_disallowed
              :no_one_can_push | :no_one_can_merge | :guest      | :be_disallowed

              :maintainers_can_push | :no_one_can_merge | :owner      | :be_allowed
              :maintainers_can_push | :no_one_can_merge | :maintainer | :be_allowed
              :maintainers_can_push | :no_one_can_merge | :developer  | :be_disallowed
              :maintainers_can_push | :no_one_can_merge | :reporter   | :be_disallowed
              :maintainers_can_push | :no_one_can_merge | :guest      | :be_disallowed

              :developers_can_push | :no_one_can_merge |  :owner      | :be_allowed
              :developers_can_push | :no_one_can_merge |  :maintainer | :be_allowed
              :developers_can_push | :no_one_can_merge |  :developer  | :be_allowed
              :developers_can_push | :no_one_can_merge |  :reporter   | :be_disallowed
              :developers_can_push | :no_one_can_merge |  :guest      | :be_disallowed

              :no_one_can_push | :maintainers_can_merge | :owner      | :be_allowed
              :no_one_can_push | :maintainers_can_merge | :maintainer | :be_allowed
              :no_one_can_push | :maintainers_can_merge | :developer  | :be_disallowed
              :no_one_can_push | :maintainers_can_merge | :reporter   | :be_disallowed
              :no_one_can_push | :maintainers_can_merge | :guest      | :be_disallowed

              :maintainers_can_push | :maintainers_can_merge | :owner      | :be_allowed
              :maintainers_can_push | :maintainers_can_merge | :maintainer | :be_allowed
              :maintainers_can_push | :maintainers_can_merge | :developer  | :be_disallowed
              :maintainers_can_push | :maintainers_can_merge | :reporter   | :be_disallowed
              :maintainers_can_push | :maintainers_can_merge | :guest      | :be_disallowed

              :developers_can_push | :maintainers_can_merge |  :owner      | :be_allowed
              :developers_can_push | :maintainers_can_merge |  :maintainer | :be_allowed
              :developers_can_push | :maintainers_can_merge |  :developer  | :be_allowed
              :developers_can_push | :maintainers_can_merge |  :reporter   | :be_disallowed
              :developers_can_push | :maintainers_can_merge |  :guest      | :be_disallowed

              :no_one_can_push | :developers_can_merge | :owner      | :be_allowed
              :no_one_can_push | :developers_can_merge | :maintainer | :be_allowed
              :no_one_can_push | :developers_can_merge | :developer  | :be_allowed
              :no_one_can_push | :developers_can_merge | :reporter   | :be_disallowed
              :no_one_can_push | :developers_can_merge | :guest      | :be_disallowed

              :maintainers_can_push | :developers_can_merge | :owner      | :be_allowed
              :maintainers_can_push | :developers_can_merge | :maintainer | :be_allowed
              :maintainers_can_push | :developers_can_merge | :developer  | :be_allowed
              :maintainers_can_push | :developers_can_merge | :reporter   | :be_disallowed
              :maintainers_can_push | :developers_can_merge | :guest      | :be_disallowed

              :developers_can_push | :developers_can_merge |  :owner      | :be_allowed
              :developers_can_push | :developers_can_merge |  :maintainer | :be_allowed
              :developers_can_push | :developers_can_merge |  :developer  | :be_allowed
              :developers_can_push | :developers_can_merge |  :reporter   | :be_disallowed
              :developers_can_push | :developers_can_merge |  :guest      | :be_disallowed
            end

            with_them do
              before do
                create(:protected_branch, push_access_level, merge_access_level, name: branch_ref_name,
                  project: project)
                project.add_role(user, project_role)
              end

              context 'for create_pipeline_schedule' do
                subject(:policy) { described_class.new(user, new_branch_pipeline_schedule) }

                let(:new_branch_pipeline_schedule) { project.pipeline_schedules.new(ref: branch_ref) }

                it { expect(policy).to try(accessible, :create_pipeline_schedule) }
              end

              context 'for play_pipeline_schedule' do
                subject(:policy) { described_class.new(user, branch_pipeline_schedule) }

                it { expect(policy).to try(accessible, :play_pipeline_schedule) }
              end
            end
          end
        end
      end

      context 'for tag' do
        %w[refs/tags/v1.0.0 v1.0.0].each do |tag_ref|
          context "with #{tag_ref}" do
            let_it_be(:tag_pipeline_schedule) do
              create(:ci_pipeline_schedule, :nightly, project: project, ref: tag_ref)
            end

            where(:access_level, :project_role, :accessible) do
              :no_one_can_create | :owner      | :be_disallowed
              :no_one_can_create | :maintainer | :be_disallowed
              :no_one_can_create | :developer  | :be_disallowed
              :no_one_can_create | :reporter   | :be_disallowed
              :no_one_can_create | :guest      | :be_disallowed

              :maintainers_can_create | :owner      | :be_allowed
              :maintainers_can_create | :maintainer | :be_allowed
              :maintainers_can_create | :developer  | :be_disallowed
              :maintainers_can_create | :reporter   | :be_disallowed
              :maintainers_can_create | :guest      | :be_disallowed

              :developers_can_create | :owner      | :be_allowed
              :developers_can_create | :maintainer | :be_allowed
              :developers_can_create | :developer  | :be_allowed
              :developers_can_create | :reporter   | :be_disallowed
              :developers_can_create | :guest      | :be_disallowed
            end

            with_them do
              before do
                create(:protected_tag, access_level, name: tag_ref_name, project: project)
                project.add_role(user, project_role)
              end

              context 'for create_pipeline_schedule' do
                subject(:policy) { described_class.new(user, new_tag_pipeline_schedule) }

                let(:new_tag_pipeline_schedule) { project.pipeline_schedules.new(ref: tag_ref) }

                it { expect(policy).to try(accessible, :create_pipeline_schedule) }
              end

              context 'for play_pipeline_schedule' do
                subject(:policy) { described_class.new(user, tag_pipeline_schedule) }

                it { expect(policy).to try(accessible, :play_pipeline_schedule) }
              end
            end
          end
        end
      end
    end

    describe 'rules for owner of schedule' do
      before do
        project.add_developer(user)
        pipeline_schedule.update!(owner: user)
      end

      it 'includes abilities to do all operations on pipeline schedule' do
        expect(policy).to be_allowed :play_pipeline_schedule
        expect(policy).to be_allowed :update_pipeline_schedule
        expect(policy).to be_allowed :admin_pipeline_schedule
      end
    end

    describe 'rules for a maintainer' do
      before do
        project.add_maintainer(user)
      end

      it 'allows for playing and destroying a pipeline schedule' do
        expect(policy).to be_allowed :play_pipeline_schedule
        expect(policy).to be_allowed :admin_pipeline_schedule
      end

      it 'does not allow for updating of an existing schedule' do
        expect(policy).not_to be_allowed :update_pipeline_schedule
      end
    end

    describe 'rules for non-owner of schedule' do
      let(:owner) { create(:user) }

      before do
        project.add_maintainer(owner)
        project.add_maintainer(user)
        pipeline_schedule.update!(owner: owner)
      end

      it 'includes abilities to take ownership' do
        expect(policy).to be_allowed :admin_pipeline_schedule
      end
    end
  end
end
