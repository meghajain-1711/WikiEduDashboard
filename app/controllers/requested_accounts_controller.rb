# frozen_string_literal: true

#= Controller for requesting new wiki accounts and processing those requests
class RequestedAccountsController < ApplicationController
  respond_to :html
  before_action :set_course
  before_action :check_creation_permissions, only: %i[index create_accounts enable_account_requests]

  # This creates (or updates) a RequestedAccount, which is a username and email
  # for a user who wants to create a wiki account (but may not be able to do so
  # because of a shared IP that has hit the new account limit).
  def request_account
    redirect_if_passcode_invalid { return }
    # If there is already a request for a certain username for this course, then
    # it's probably the same user who put in the wrong email the first time.
    # Just overwrite the email with the new one in this case.
    existing_request = RequestedAccount.find_by(course: @course, username: params[:username])
    if existing_request
      existing_request.update_attribute(:email, params[:email])
      return # TODO: sensible error message rendered
    end

    requested = RequestedAccount.create(course: @course, username: params[:username], email: params[:email])
    return requested unless params[:create_account_now] == 'true' # TODO: render relevant json to be handled on the frontend
    result = create_account(requested)
    render json: { message: result.values.first }, status: 500 # TODO: handle both success and failure
  end

  # Sets the flag on a course so that clicking 'Sign Up' opens the Request Account
  # modal instead of redirecting to the mediawiki account creation flow.
  def enable_account_requests
    @course.flags[:register_accounts] = true
    @course.save
  end

  # List of requested accounts for a course.
  def index; end

  def destroy
    # TODO: let privileged user destroy bad account requests before processing
    # the acceptable ones.
  end

  # Try to create each of the requested accounts for a course, and show the
  # result for each.
  def create_accounts
    @results = []
    @course.requested_accounts.each do |requested_account|
      @results << create_account(requested_account)
    end
  end

  private

  def create_account(requested_account)
    creation_attempt = CreateRequestedAccount.new(requested_account, current_user)
    result = creation_attempt.result
    return result unless result[:success]
    # If it was successful, enroll the user in the course
    user = creation_attempt.user
    JoinCourse.new(course: @course, user: user, role: CoursesUsers::Roles::STUDENT_ROLE)
    result
  end

  def check_creation_permissions
    return if user_signed_in? && current_user.can_edit?(@course)
    exception = ActionController::InvalidAuthenticityToken.new('Unauthorized')
    raise exception
  end

  def set_course
    @course = Course.find_by_slug(params[:course_slug])
  end

  def redirect_if_passcode_invalid
    return if passcode_valid?
    redirect_to '/errors/incorrect_passcode'
    yield
  end

  def passcode_valid?
    return true if @course.passcode.nil?
    params[:passcode] == @course.passcode
  end
end
