# frozen_string_literal: true

module PersonalAccessTokens
  class RotateService
    EXPIRATION_PERIOD = 1.week

    def initialize(current_user, token, resource = nil, params = {})
      @current_user = current_user
      @token = token
      @resource = resource
      @params = params.dup
      @target_user = token.user
    end

    def execute
      return error_response(_('token already revoked')) if token.revoked?

      response = ServiceResponse.success

      PersonalAccessToken.transaction do
        unless token.revoke!
          response = error_response(_('failed to revoke token'))
          raise ActiveRecord::Rollback
        end

        response = create_access_token

        raise ActiveRecord::Rollback unless response.success?
      end

      response
    end

    private

    attr_reader :current_user, :token, :resource, :params, :target_user

    def create_access_token
      unless valid_access_level?
        return error_response(_('Not eligible to rotate token with access level higher than the user'))
      end

      new_token = target_user.personal_access_tokens.create(create_token_params)

      if new_token.persisted?
        update_bot_membership(target_user, new_token.expires_at)

        return success_response(new_token)
      end

      error_response(new_token.errors.full_messages.to_sentence)
    end

    def valid_access_level?
      true
    end

    def update_bot_membership(target_user, expires_at)
      return if target_user.human?

      target_user.members.update(expires_at: expires_at)
    end

    def expires_at
      return params[:expires_at] if params[:expires_at].present?

      return default_expiration_date if Gitlab::CurrentSettings.require_personal_access_token_expiry?

      nil
    end

    def success_response(new_token)
      ServiceResponse.success(payload: { personal_access_token: new_token })
    end

    def error_response(message)
      ServiceResponse.error(message: message)
    end

    def create_token_params
      { name: token.name,
        previous_personal_access_token_id: token.id,
        impersonation: token.impersonation,
        scopes: token.scopes,
        expires_at: expires_at }
    end

    def default_expiration_date
      EXPIRATION_PERIOD.from_now.to_date
    end
  end
end

PersonalAccessTokens::RotateService.prepend_mod
