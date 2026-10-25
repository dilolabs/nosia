require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceUploadTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    select "EN", from: "language_preference_locale"
    visit account_sources_path(@second)
    assert_selector "[data-source-upload]"
  end

  test "the add source menu and every destination stay inside a 375px viewport" do
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: false)
    assert_equal [ 375, 812 ], page.evaluate_script("[window.innerWidth, window.innerHeight]")
    @second.update!(name: "Research team with a deliberately long account name")
    visit account_sources_path(@second)

    find(".n-source-add-menu summary").click
    assert_selector ".n-source-add-menu[open] .n-source-add-options a", count: 4
    bounds = page.evaluate_script(<<~JS)
      (() => {
        const menu = document.querySelector('.n-source-add-options');
        return [menu, ...menu.querySelectorAll('a')].map(element => {
          const rect = element.getBoundingClientRect();
          return { element: element.tagName, left: rect.left, right: rect.right };
        });
      })()
    JS
    puts "Sources add-menu bounds at 375x812: #{bounds.to_json}"
    assert_equal 5, bounds.length
    bounds.each do |rect|
      assert_operator rect.fetch("left"), :>=, 0, "Add source destination clips the viewport: #{rect}"
      assert_operator rect.fetch("right"), :<=, page.evaluate_script("window.innerWidth"), "Add source destination clips the viewport: #{rect}"
    end
  ensure
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "browse activates the existing input and real uploads stay in the URL account" do
    page.execute_script(<<~JS)
      const input = document.getElementById('source-upload-files');
      window.sourceBrowseCalls = 0;
      window.sourceOriginalClick = input.click;
      input.click = () => { window.sourceBrowseCalls += 1; };
    JS
    click_on "Choose files"
    assert_equal 1, page.evaluate_script("window.sourceBrowseCalls")
    page.execute_script("const input = document.getElementById('source-upload-files'); input.click = window.sourceOriginalClick;")

    previous = @second.documents.count
    clear_enqueued_jobs
    find("#source-upload-files", visible: :all).set(file_fixture("account_source.txt"))

    assert_selector "[data-upload-status='success'] [data-source-upload-label]", text: "Uploaded. Check source status for indexing."
    assert_equal previous + 1, @second.documents.count
    assert_not @first.documents.exists?(title: "account_source.txt")
    assert_enqueued_jobs 1, only: AddDocumentJob
  end

  test "retry after a committed response is lost reuses the intent and job" do
    path = account_sources_documents_path(@second)
    page.execute_script(<<~JS, path)
      const target = arguments[0], open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      window.sourceUploadedIds = [];
      XMLHttpRequest.prototype.open = function(method, url, ...args) {
        this.sourcePath = new URL(url, location.href).pathname;
        return open.call(this, method, url, ...args);
      };
      XMLHttpRequest.prototype.send = function(body) {
        if (this.sourcePath === target) {
          const loaded = this.onload;
          this.onload = event => {
            if (this.status >= 200 && this.status < 300) {
              window.sourceUploadedIds.push(JSON.parse(this.responseText).id);
              if (window.sourceUploadedIds.length === 1) return this.onerror(new ProgressEvent('error'));
            }
            loaded.call(this, event);
          };
        }
        return send.call(this, body);
      };
    JS

    previous = @second.documents.count
    clear_enqueued_jobs
    find("#source-upload-files", visible: :all).set(file_fixture("account_source.txt"))
    assert_selector "[data-upload-status='error']"
    within("[data-dropzone-target='list']") { click_on "Retry" }

    assert_selector "[data-upload-status='success'] [data-source-upload-label]", text: "Uploaded. Check source status for indexing."
    ids = page.evaluate_script("window.sourceUploadedIds")
    assert_equal 2, ids.length
    assert_equal 1, ids.uniq.length
    assert_equal previous + 1, @second.documents.count
    assert_enqueued_jobs 1, only: AddDocumentJob
  end
end
