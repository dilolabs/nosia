require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class LocalizationSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  test "French composer feedback uses the server dictionary and resets failed sources" do
    visit root_url
    select "Français", from: "language_preference_locale"
    click_button "Apply"
    assert_button "Se connecter"
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Se connecter"
    assert_selector "select[name='chat[account_id]']"

    visit new_chat_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"
    assert_selector ".n-chat-composer[data-composer-sources-messages-value]"

    page.execute_script <<~JS
      const root = document.querySelector('[data-controller~="composer-sources"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "composer-sources")
      controller.operations.set("localization-failure", {
        payload: { url: "https://example.invalid/" }, failed: true, pending: false,
        message: controller.messagesValue.registration_retry
      })
      controller.renderErrors()
      controller.publishState()
    JS

    assert_button "Réessayer la source"
    assert_button "Réinitialiser le brouillon"
    assert_selector "[data-composer-sources-target=errors]", text: "Échec de l’enregistrement de la source. Réessayez ou réinitialisez le brouillon."
    assert_selector "button[aria-label=Envoyer][disabled]"

    accept_confirm "Réinitialiser ce brouillon non envoyé ? Les sources enregistrées resteront dans leur compte." do
      click_button "Réinitialiser le brouillon"
    end

    assert_no_button "Réessayer la source"
    assert_selector "button[aria-label=Envoyer]:not([disabled])"
  end
end
