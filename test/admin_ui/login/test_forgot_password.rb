require_relative "../../test_helper"

class Test::AdminUi::Login::TestForgotPassword < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::DelayedJob

  def setup
    setup_server
    Admin.delete_all
    response = Typhoeus.delete("http://127.0.0.1:#{$config["mailhog"]["api_port"]}/api/v1/messages")
    assert_response_code(200, response)
  end

  def test_non_existent_email
    visit "/admins/password/new"

    fill_in "Email", :with => "foobar@example.com"
    click_button "Send me reset password instructions"
    assert_content("If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes.")

    assert_equal(0, delayed_job_sent_messages.length)
  end

  def test_reset_process
    admin = FactoryGirl.create(:admin, :username => "admin@example.com")
    assert_nil(admin.reset_password_token)
    assert_nil(admin.reset_password_sent_at)
    original_encrypted_password = admin.encrypted_password
    assert(original_encrypted_password)

    visit "/admins/password/new"

    # Reset password
    fill_in "Email", :with => "admin@example.com"
    click_button "Send me reset password instructions"
    assert_content("If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes.")

    # Check for reset token on database record.
    admin.reload
    assert(admin.reset_password_token)
    assert(admin.reset_password_sent_at)
    assert_equal(original_encrypted_password, admin.encrypted_password)

    # Find sent email
    messages = delayed_job_sent_messages
    assert_equal(1, messages.length)
    message = messages.first

    # To
    assert_equal(["admin@example.com"], message["Content"]["Headers"]["To"])

    # Subject
    assert_equal(["Reset password instructions"], message["Content"]["Headers"]["Subject"])

    # Use description in body
    assert_match(%r{http://localhost/admins/password/edit\?reset_password_token=[^"]+}, message["_mime_parts"]["text/html; charset=UTF-8"]["Body"])
    assert_match(%r{http://localhost/admins/password/edit\?reset_password_token=[^"]+}, message["_mime_parts"]["text/plain; charset=UTF-8"]["Body"])

    # Follow link to reset URL
    reset_url = message["_mime_parts"]["text/html; charset=UTF-8"]["Body"].match(%r{/admins/password/edit\?reset_password_token=[^"]+})[0]
    visit reset_url

    fill_in "New password", :with => "password"
    fill_in "Confirm new password", :with => "password"
    click_button "Change my password"

    # Ensure the user gets logged in.
    assert_logged_in(admin)

    # Check for database record updates.
    admin.reload
    assert_nil(admin.reset_password_token)
    assert_nil(admin.reset_password_sent_at)
    assert(admin.encrypted_password)
    refute_equal(original_encrypted_password, admin.encrypted_password)
  end
end
