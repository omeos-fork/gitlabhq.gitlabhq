# frozen_string_literal: true

class AddProtectedBranchNamespaceIdToRequiredCodeOwnersSections < Gitlab::Database::Migration[2.2]
  milestone '17.9'

  def change
    add_column :required_code_owners_sections, :protected_branch_namespace_id, :bigint
  end
end
