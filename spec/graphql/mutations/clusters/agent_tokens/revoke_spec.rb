# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Clusters::AgentTokens::Revoke do
  let_it_be(:token) { create(:cluster_agent_token) }
  let_it_be(:user) { create(:user) }

  let(:mutation) do
    described_class.new(
      object: double,
      context: { current_user: user },
      field: double
    )
  end

  it { expect(described_class.graphql_name).to eq('ClusterAgentTokenRevoke') }
  it { expect(described_class).to require_graphql_authorizations(:admin_cluster) }

  describe '#resolve' do
    let(:global_id) { token.to_global_id }

    subject { mutation.resolve(id: global_id) }

    context 'user does not have permission' do
      it 'does not revoke the token' do
        expect { subject }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)

        expect(token.reload).not_to be_revoked
      end
    end

    context 'user has permission' do
      before do
        token.agent.project.add_maintainer(user)
      end

      it 'revokes the token' do
        subject

        expect(token.reload).to be_revoked
      end

      context 'supplied ID is invalid' do
        let(:global_id) { token.id }

        it 'raises a coercion error' do
          expect { subject }.to raise_error(::GraphQL::CoercionError)

          expect(token.reload).not_to be_revoked
        end
      end
    end
  end
end
