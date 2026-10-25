require "application_system_test_case"
require "turbo/broadcastable/test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceTest < ApplicationSystemTestCase
  include AccountExperienceFixtures
  include Turbo::Broadcastable::TestHelper

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/sources-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    puts "Sources workspace evidence: #{@evidence_dir}"
    sign_in_workspace_browser
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    Capybara.reset_sessions!
  end

  test "invalid source editor borders use the error color in both themes" do
    visit new_account_sources_text_path(@second)
    assert_selector "lexxy-editor.n-source-editor[connected]"

    # Test-only presentation probe: Text has no required-data validation.
    # No form is submitted, and the original theme and attribute are restored.
    measurements = source_editor_border_probe
    puts "Source editor border style probe: #{measurements.to_json}"
    assert_kind_of Array, measurements
    assert_equal %w[light dark], measurements.map { |measurement| measurement.fetch("theme") }
    measurements.each do |measurement|
      theme = measurement.fetch("theme")
      refute_equal measurement.fetch("neutral").fetch("rgba"), measurement.fetch("error").fetch("rgba"), "#{theme} theme tokens must differ"
      assert_equal measurement.fetch("neutral").fetch("rgba"), measurement.fetch("valid").fetch("rgba"), "#{theme} valid editor border: #{measurement}"
      assert_equal measurement.fetch("error").fetch("rgba"), measurement.fetch("invalid").fetch("rgba"), "#{theme} invalid editor border: #{measurement}"
    end
    assert_no_enqueued_jobs
  end

  test "GET filters retain account scope through history and reset without changing the default" do
    visit account_sources_path(@second)
    fill_in "source-q", with: "Research"
    click_on "Filter"
    assert_current_path %r{#{Regexp.escape(account_sources_path(@second))}\?[^#]*\bq=Research(?:&|$)}
    find("[data-source-filter-type='text']").click
    assert_selector "[data-source-filter-type='text'][aria-current='true']"
    select "Failed", from: "status"
    assert_selector "#status option[value='failed'][selected]"
    select "Title", from: "sort"

    assert_current_path account_sources_path(@second), ignore_query: true
    assert_selector "[data-source-filter-type='text'][aria-current='true']"
    assert_field "source-q", with: "Research"
    assert_selector "#status option[value='failed'][selected]"
    assert_selector "#sort option[value='title'][selected]"
    assert_selector ".n-source-row", count: 1

    page.go_back
    assert_selector "#sort option[value='recent'][selected]"
    assert_selector "#status option[value='failed'][selected]"
    click_on "Reset"
    assert_current_path account_sources_path(@second)
    assert_field "source-q", with: ""
    assert_selector "#status option[value='all'][selected]"

    visit sources_path
    assert_selector "[data-workspace-scope]", text: "Default account: #{@first.name}"
    assert_equal @first, @user.reload.first_account
  end

  test "all four source types create and edit in their URL account through existing jobs" do
    SourceRow::TYPES.each do |type|
      visit public_send("new_account_sources_#{type}_path", @second)
      case type
      when "document"
        fill_in "document_title", with: "Browser document"
        attach_file "document_file", file_fixture("account_source.txt")
      when "text"
        fill_source_editor "Browser text"
      when "qna"
        fill_in "qna_question", with: "Browser question?"
        fill_source_editor "Browser answer"
      when "website"
        fill_in "website_url", with: "https://browser-source.example/reference"
        fill_source_editor "Browser website"
      end

      clear_enqueued_jobs
      click_on "Save"
      assert_selector "[data-source-detail]"
      record = @second.public_send(type.pluralize).order(:id).last
      detail_path = public_send("account_sources_#{type}_path", @second, record)
      assert_current_path detail_path
      assert_enqueued_with job: ingestion_job(type), args: [ record.id ]
      assert_equal @second.id, record.account_id

      find("[data-source-edit]").click
      assert_selector "[data-source-fixed-account]", text: @second.name
      case type
      when "document" then fill_in "document_title", with: "Edited browser document"
      when "qna" then fill_in "qna_question", with: "Edited browser question?"
      else fill_source_editor "Edited browser #{type}"
      end
      clear_enqueued_jobs
      click_on "Save"
      assert_selector "[data-source-detail]"
      assert_current_path detail_path
      assert_enqueued_with job: ingestion_job(type), args: [ record.id ]
      find("[data-workspace-back]").click
      assert_current_path account_sources_path(@second, type: type)
    end
    assert_equal @first, @user.reload.first_account
  end

  test "row Retry and confirmed Delete affect only the displayed account source" do
    source = experience(:texts, :overview_second_text)
    other = experience(:texts, :overview_first_text)
    other_before = other.attributes
    row = "[data-source-id='#{source.id}']"
    visit account_sources_path(@second)
    clear_enqueued_jobs
    assert_enqueued_with job: AddTextJob, args: [ source.id ] do
      within(row) { click_on "Retry" }
      assert_current_path account_sources_path(@second, type: "text")
      assert_selector "#{row} [data-source-index-status='pending']"
    end
    assert_enqueued_jobs 1, only: AddTextJob
    assert source.reload.pending?
    assert_no_selector "#{row} form"

    disconnect_source_streams
    observe_source_delete_requests(account_sources_text_path(@second, source))
    before_delete = source.attributes
    confirmation = /#{Regexp.escape(source.title)}.*#{Regexp.escape(@second.name)}/
    clear_enqueued_jobs
    dismiss_confirm(confirmation) { within(row) { click_on "Delete" } }
    assert_equal before_delete, source.reload.attributes
    assert_empty page.evaluate_script("window.sourceDeleteRequests")
    assert_no_enqueued_jobs
    assert_no_enqueued_jobs do
      accept_confirm(confirmation) { within(row) { click_on "Delete" } }
      assert_current_path account_sources_path(@second, type: "text")
      assert_no_selector row
      assert_selector "[data-source-results][data-total='0']"
    end
    assert_equal 1, page.evaluate_script("window.sourceDeleteRequests.length")
    assert_not @second.texts.exists?(source.id)
    assert_equal other_before, other.reload.attributes
    assert_equal @first, @user.reload.first_account
  end

  test "detail Delete confirms its source and navigates to the actual typed result without live streams" do
    source = experience(:texts, :overview_second_text)
    other = experience(:texts, :overview_first_text)
    before_delete = source.attributes
    other_before = other.attributes
    visit account_sources_text_path(@second, source)
    assert_no_selector "turbo-cable-stream-source", visible: :all
    observe_source_delete_requests(account_sources_text_path(@second, source))
    confirmation = /#{Regexp.escape(source.title)}.*#{Regexp.escape(@second.name)}/

    dismiss_confirm(confirmation) { within(".n-workspace-actions") { click_on "Delete text" } }
    assert_equal before_delete, source.reload.attributes
    assert_empty page.evaluate_script("window.sourceDeleteRequests")
    assert_no_enqueued_jobs
    assert_no_enqueued_jobs do
      accept_confirm(confirmation) { within(".n-workspace-actions") { click_on "Delete text" } }
      assert_current_path account_sources_path(@second, type: "text")
      assert_no_selector "[data-source-detail], [data-source-id='#{source.id}']"
      assert_selector "[data-source-results][data-total='0']"
    end
    assert_equal 1, page.evaluate_script("window.sourceDeleteRequests.length")
    assert_not @second.texts.exists?(source.id)
    assert_equal other_before, other.reload.attributes
    assert_equal @first, @user.reload.first_account
  end

  test "source navigation changes only current generated Delete forms and preserves load more streams" do
    visit account_sources_path(@second)
    assert_selector "[data-source-workspace][data-controller~='source-navigation']"
    assert page.evaluate_async_script(<<~JS)
      const done=arguments[arguments.length-1],deadline=performance.now()+2000;
      const connected=()=>{
        if(window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector('[data-source-workspace]'),'source-navigation'))done(true);
        else if(performance.now()>deadline)done(false);
        else requestAnimationFrame(connected);
      };
      connected();
    JS
    samples = page.evaluate_script(<<~JS)
      (()=>{
        const link=document.querySelector('[data-source-workspace] a[data-turbo-method="delete"]');
        const originalAccept='text/vnd.turbo-stream.html, text/html, application/xhtml+xml';
        window.sampleSourceNavigation=({method='DELETE',hidden=true,action=link.href,tag='form'}={})=>{
          const target=document.createElement(tag);target.setAttribute('action',action);
          if(hidden)target.setAttribute('hidden','');
          document.body.append(target);
          const fetchOptions={method,headers:{Accept:originalAccept,'X-Source-Probe':'unchanged'}};
          target.dispatchEvent(new CustomEvent('turbo:before-fetch-request',{bubbles:true,detail:{fetchOptions,url:new URL(action)}}));
          target.remove();
          return {method,hidden,action,tag,headers:fetchOptions.headers};
        };
        const samples=[sampleSourceNavigation(),...['GET','POST','PATCH'].map(method=>sampleSourceNavigation({method})),
          sampleSourceNavigation({hidden:false}),sampleSourceNavigation({action:new URL('/unmatched-delete',location.href).href}),
          sampleSourceNavigation({tag:'div'})];
        const parent=link.parentNode,next=link.nextSibling;link.remove();
        samples.push(sampleSourceNavigation());parent.insertBefore(link,next);
        return samples;
      })()
    JS
    assert_equal "text/html, application/xhtml+xml", samples.first.fetch("headers").fetch("Accept")
    samples.drop(1).each do |sample|
      assert_equal "text/vnd.turbo-stream.html, text/html, application/xhtml+xml", sample.fetch("headers").fetch("Accept"), sample.to_json
    end
    assert samples.all? { |sample| sample.fetch("headers").fetch("X-Source-Probe") == "unchanged" }

    assert_selector "[data-source-workspace] form[data-source-retry]"
    retry_samples = page.evaluate_script(<<~JS)
      (()=>{
        const workspace=document.querySelector('[data-source-workspace]');
        const retry=workspace.querySelector('form[data-source-retry]');
        const originalAccept='text/vnd.turbo-stream.html, text/html, application/xhtml+xml';
        window.sampleSourceRetry=({method='POST',marked=true,inside=true}={})=>{
          const form=retry.cloneNode(true);
          if(!marked)form.removeAttribute('data-source-retry');
          (inside&&workspace.isConnected?workspace:document.body).append(form);
          const fetchOptions={method,headers:{Accept:originalAccept,'X-Source-Probe':'unchanged'}};
          form.dispatchEvent(new CustomEvent('turbo:before-fetch-request',{bubbles:true,detail:{fetchOptions,url:new URL(form.action)}}));
          form.remove();
          return {method,marked,inside,headers:fetchOptions.headers};
        };
        return [sampleSourceRetry(),sampleSourceRetry({marked:false}),sampleSourceRetry({inside:false}),
          ...['GET','DELETE','PATCH'].map(method=>sampleSourceRetry({method}))];
      })()
    JS
    assert_equal "text/html, application/xhtml+xml", retry_samples.first.fetch("headers").fetch("Accept")
    retry_samples.drop(1).each do |sample|
      assert_equal "text/vnd.turbo-stream.html, text/html, application/xhtml+xml", sample.fetch("headers").fetch("Accept"), sample.to_json
    end
    assert retry_samples.all? { |sample| sample.fetch("headers").fetch("X-Source-Probe") == "unchanged" }

    page.execute_script(<<~JS, account_sources_path(@second, format: :turbo_stream, page: 2))
      window.sourceLoadMoreControl={};
      document.addEventListener('turbo:before-fetch-request',event=>{
        sourceLoadMoreControl.accept=new Headers(event.detail.fetchOptions.headers).get('Accept');
      },{once:true});
      document.addEventListener('turbo:before-fetch-response',event=>{
        sourceLoadMoreControl.contentType=event.detail.fetchResponse.response.headers.get('Content-Type');
        document.documentElement.setAttribute('data-source-load-more-response','true');
      },{once:true});
      Turbo.visit(arguments[0],{acceptsStreamResponse:true});
    JS
    assert_selector "html[data-source-load-more-response='true']", visible: :all
    control = page.evaluate_script("window.sourceLoadMoreControl")
    assert_equal "text/vnd.turbo-stream.html, text/html, application/xhtml+xml", control.fetch("accept")
    assert_match(/\Atext\/vnd\.turbo-stream\.html/, control.fetch("contentType"))
    assert_current_path account_sources_path(@second)
    assert_selector ".n-source-row", count: 4
    assert_no_enqueued_jobs

    find("a[href='#{accounts_path}']", match: :first).click
    assert_current_path accounts_path
    assert_selector ".n-account-cards"
    assert_equal "text/vnd.turbo-stream.html, text/html, application/xhtml+xml", page.evaluate_script("sampleSourceNavigation().headers.Accept")
    assert_equal "text/vnd.turbo-stream.html, text/html, application/xhtml+xml", page.evaluate_script("sampleSourceRetry().headers.Accept")
    File.write("#{@evidence_dir}/navigation-guards.json", { samples: samples, retry_samples: retry_samples, load_more: control, disconnected_action_unchanged: true, disconnected_retry_unchanged: true }.to_json)
  end

  test "detail Retry navigates to its typed account list and queues the existing job once" do
    source = experience(:texts, :overview_second_text)
    other = experience(:texts, :overview_first_text)
    other_before = other.attributes
    visit account_sources_text_path(@second, source)
    assert_selector "[data-source-detail] [data-source-index-status='failed']"
    clear_enqueued_jobs

    assert_enqueued_with job: AddTextJob, args: [ source.id ] do
      within(".n-workspace-actions") { click_on "Retry" }
      assert_current_path account_sources_path(@second, type: "text")
      assert_selector "[data-source-id='#{source.id}'] [data-source-index-status='pending']"
    end
    assert_enqueued_jobs 1, only: AddTextJob
    assert source.reload.pending?
    assert_equal @second.id, source.account_id
    assert_equal other_before, other.reload.attributes
    assert_equal @first, @user.reload.first_account
  end

  test "a live failed row Retry preserves CSRF protection and navigates within its account" do
    protection_classes = [ ActionController::Base, ApplicationController, Sources::Texts::RetriesController ]
    previous_protection = protection_classes.to_h { |controller| [ controller, controller.allow_forgery_protection ] }
    ActionController::Base.allow_forgery_protection = true
    Capybara.reset_sessions!
    sign_in_workspace_browser

    source = experience(:texts, :overview_second_text)
    other = experience(:texts, :overview_first_text)
    other_before = other.attributes
    source.update_columns(index_status: :pending)
    row = "[data-source-id='#{source.id}']"
    visit account_sources_path(@second)
    assert_selector "meta[name='csrf-token'][content]:not([content=''])", visible: :all
    assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
    assert_selector "#{row} [data-source-index-status='pending']"
    assert_no_selector "#{row} form"

    Current.reset
    source.mark_indexing_failed!
    assert_selector "#{row} [data-source-index-status='failed']"
    assert_selector "#{row} form button", text: "Retry"
    assert_no_selector "#{row} form input[name='authenticity_token']", visible: :all
    assert Sources::Texts::RetriesController.allow_forgery_protection
    before_retry = source.reload.attributes
    clear_enqueued_jobs
    page.execute_script(<<~JS)
      window.sourceRetryRequests=[];
      document.addEventListener('turbo:before-fetch-request',event=>{
        if(event.target instanceof HTMLFormElement&&event.target.querySelector('button')){
          const headers=new Headers(event.detail.fetchOptions.headers);
          sourceRetryRequests.push({method:event.detail.fetchOptions.method,accept:headers.get('Accept'),csrf:headers.has('X-CSRF-Token')});
        }
      });
    JS

    within(row) { click_on "Retry" }
    assert_current_path account_sources_path(@second, type: "text")
    assert_selector "#{row} [data-source-index-status='pending']"
    assert source.reload.pending?
    assert_equal @second.id, source.account_id
    assert_equal other_before, other.reload.attributes
    assert_equal @first, @user.reload.first_account
    assert_enqueued_with job: AddTextJob, args: [ source.id ]
    assert_enqueued_jobs 1, only: AddTextJob
    requests = page.evaluate_script("window.sourceRetryRequests")
    assert_equal 1, requests.size
    assert_equal "POST", requests.first.fetch("method").upcase
    assert_equal "text/html, application/xhtml+xml", requests.first.fetch("accept")
    assert requests.first.fetch("csrf"), "Turbo must supply the session CSRF token for the tokenless broadcast form"
    assert Sources::Texts::RetriesController.allow_forgery_protection
    save_source_screenshot("live-retry-csrf")
  ensure
    begin
      if source
        evidence = {
          protection_during_request: Sources::Texts::RetriesController.allow_forgery_protection,
          navigation_status: page.evaluate_script("performance.getEntriesByType('navigation').at(-1)?.responseStatus"),
          csrf_error: page.has_text?("InvalidAuthenticityToken", wait: 0),
          source_status: source.reload.index_status,
          unchanged: source.attributes == before_retry,
          retry_jobs: enqueued_jobs.count { |job| job[:job] == AddTextJob }
        }
        puts "Live Retry CSRF evidence: #{evidence.to_json}"
        File.write("#{@evidence_dir}/live-retry-csrf.json", evidence.to_json)
      end
    ensure
      ActionController::Base.allow_forgery_protection = previous_protection.fetch(ActionController::Base)
      assert_equal previous_protection, protection_classes.to_h { |controller| [ controller, controller.allow_forgery_protection ] }, "Forgery protection settings must not leak to other tests"
    end
  end

  test "a duplicate website 422 focuses linked errors and retains the editor draft" do
    visit new_account_sources_website_path(@second)
    fill_in "website_url", with: experience(:websites, :overview_second_website).url
    fill_source_editor "Keep my draft after validation"
    find(".lexxy-editor__content").send_keys([ :control, "a" ], [ :control, "b" ])
    assert_selector ".lexxy-editor__content strong", text: "Keep my draft after validation"
    assert_no_enqueued_jobs do
      click_on "Save"
      assert_selector ".n-source-errors:focus"
    end
    assert_selector "#website_url[aria-invalid='true'][aria-describedby~='website_url_error']"
    assert_selector "#website_url_error", text: "has already been taken"
    assert_selector ".lexxy-editor__content", text: "Keep my draft after validation"
    assert_selector ".lexxy-editor__content strong", text: "Keep my draft after validation"
    before_link = page.current_url
    observe_source_error_navigation
    find(".n-source-errors a[href='#website_url']").click
    assert_selector "#website_url:focus"
    assert_focused_source_visible
    assert_field "website_url", with: experience(:websites, :overview_second_website).url
    assert_selector ".n-source-errors"
    assert_selector ".lexxy-editor__content", text: "Keep my draft after validation"
    assert_selector ".lexxy-editor__content strong", text: "Keep my draft after validation"
    assert_equal before_link, page.current_url
    assert_empty page.evaluate_script("window.sourceErrorNavigation")
    save_source_screenshot("422-website")
  end

  test "a missing document file 422 retains legacy filing and explains reselection" do
    visit new_sources_document_path
    fill_in "document_title", with: "Retained title"
    select @second.name, from: "document_account_id"
    assert_no_enqueued_jobs do
      click_on "Save"
      assert_selector ".n-source-errors:focus"
    end
    assert_field "document_title", with: "Retained title"
    assert_select "document_account_id", selected: @second.name
    assert_equal "", find("#document_file").value
    assert_text "Browsers do not retain file selections after a failed save. Select the file again"
    before_link = page.current_url
    observe_source_error_navigation
    find(".n-source-errors a[href='#document_file']").send_keys(:enter)
    assert_selector "#document_file:focus"
    assert_focused_source_visible
    assert_field "document_title", with: "Retained title"
    assert_select "document_account_id", selected: @second.name
    assert_selector ".n-source-errors"
    assert_equal before_link, page.current_url
    assert_empty page.evaluate_script("window.sourceErrorNavigation")
    assert_equal @first, @user.reload.first_account
  end

  test "source error links focus only local fields for unmodified clicks" do
    visit new_sources_document_path
    fill_in "document_title", with: "Guarded draft"
    click_on "Save"
    assert_selector ".n-source-errors:focus"
    samples = page.evaluate_script(<<~JS)
      (()=>{
        const form=document.querySelector('.n-source-form'),link=form.querySelector('.n-source-error-link');
        const originalHref=link.getAttribute('href'),seed=form.querySelector('#document_title');
        const sample=(name,options={},target=link)=>{
          seed.focus();let result;
          document.addEventListener('click',event=>{
            result={name,prevented:event.defaultPrevented,active:document.activeElement.id};
            event.preventDefault();
          },{once:true});
          target.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,button:0,...options}));
          return result;
        };
        const samples=[sample('ordinary'),sample('Enter click',{detail:0}),
          ...['metaKey','ctrlKey','shiftKey','altKey'].map(key=>sample(key,{[key]:true})),sample('non-primary',{button:1})];
        for(const href of ['#missing-source-field','#language_preference_locale','/unmatched-error-link']){
          link.setAttribute('href',href);samples.push(sample(href));
        }
        link.setAttribute('href',originalHref);
        const outsideSummary=link.cloneNode(true);form.append(outsideSummary);
        samples.push(sample('outside summary',{},outsideSummary));outsideSummary.remove();
        const otherForm=document.createElement('form'),otherLink=link.cloneNode(true);
        otherForm.append(otherLink);document.body.append(otherForm);
        samples.push(sample('other form',{},otherLink));otherForm.remove();
        return samples;
      })()
    JS
    samples.first(2).each do |sample|
      assert sample.fetch("prevented"), sample.fetch("name")
      assert_equal "document_file", sample.fetch("active")
    end
    samples.drop(2).each do |sample|
      assert_not sample.fetch("prevented"), sample.fetch("name")
      assert_equal "document_title", sample.fetch("active")
    end
    assert_field "document_title", with: "Guarded draft"
    assert_no_enqueued_jobs
    File.write("#{@evidence_dir}/error-link-guards.json", samples.to_json)
  end

  test "Save stays disabled while a real request is pending and submits only once" do
    visit new_account_sources_text_path(@second)
    fill_source_editor "Delayed real source submission"
    page.execute_script(<<~JS, account_sources_texts_path(@second))
      const target = arguments[0], original = window.fetch;
      window.fetch = function(...args) {
        const request = args[0], url = request instanceof Request ? request.url : request;
        const method = (args[1]?.method || (request instanceof Request ? request.method : 'GET')).toUpperCase();
        if (new URL(url, location.href).pathname === target && method === 'POST') {
          window.fetch = original;
          return new Promise((resolve, reject) => {
            window.releaseSourceSave = () => original.apply(window, args).then(resolve, reject);
          });
        }
        return original.apply(this, args);
      };
    JS
    clear_enqueued_jobs
    click_on "Save"
    assert_selector ".n-source-form input[type='submit'][disabled][value='Saving…']"
    page.execute_script("window.releaseSourceSave()")
    assert_selector "[data-source-detail-content]", text: "Delayed real source submission"
    assert_enqueued_jobs 1, only: AddTextJob
  end

  test "live English and French status updates preserve scoped row actions and unique counts" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(index_status: :pending)
    %w[en fr].each do |locale|
      Capybara.using_session("sources-#{locale}") do
        sign_in_workspace_browser(locale: locale)
        visit account_sources_path(@second)
        assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
        assert_selector "[data-source-id='#{source.id}'] [data-source-index-status='pending']"
      end
    end

    source.mark_indexed!
    { "en" => "Indexed", "fr" => "Indexé" }.each do |locale, label|
      Capybara.using_session("sources-#{locale}") do
        row = "[data-source-id='#{source.id}']"
        assert_selector "#{row} [data-source-index-status='indexed']", text: label
        assert_no_selector "#{row} form"
        assert_selector "#{row} [data-source-edit]"
        assert_selector "[id^='source_count_']", count: 7
        assert_equal 7, all("[id^='source_count_']").map { |node| node[:id] }.uniq.length
        assert_current_path account_sources_path(@second)
      end
    end
  end

  test "long source and account names fit the locale viewport theme matrix with accessible row actions" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: "SourceSansEspaces" * 20)
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']"
      visit account_sources_path(@second)
      [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
        resize_sources(width, height)
        %w[light dark].each do |theme|
          set_sources_theme(theme)
          assert_source_layout
          within("[data-source-id='#{source.id}']") do
            assert_selector ".n-source-title", text: source.title
            assert_selector "[data-source-type-label]"
            assert_selector "[data-source-index-status='failed']"
          end
          verify_row_keyboard(source)
          measure_source_contrast([
            [ ".n-workspace-title", "color", 4.5 ], [ ".n-workspace-help", "color", 4.5 ],
            [ "[data-workspace-scope]", "color", 4.5 ], [ ".n-source-subtitle", "color", 4.5 ],
            [ "[data-source-index-status='failed']", "color", 4.5 ],
            [ "[data-source-index-status='indexed']", "color", 4.5 ],
            [ "[data-source-index-status='pending']", "color", 4.5 ],
            [ ".n-workspace-primary", "color", 4.5 ], [ ".n-workspace-danger", "color", 4.5 ],
            [ "#source-q", "borderColor", 3 ], [ ".n-source-row-actions :focus", "outlineColor", 3 ]
          ])
          save_source_screenshot("focused-row-#{locale}-#{width}-#{height}-#{theme}") if width == 375
          page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
          save_source_screenshot("list-#{locale}-#{width}-#{height}-#{theme}")
        end
      end
    end
  end

  test "all typed new edit and detail pages fit mobile and desktop with native editors" do
    [ [ "en", "light" ], [ "fr", "dark" ] ].each do |locale, theme|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']"
      [ [ 375, 812 ], [ 1440, 1000 ] ].each do |width, height|
        resize_sources(width, height)
        SourceRow::TYPES.each do |type|
          record = experience(type.pluralize, "overview_second_#{type}")
          paths = {
            new: public_send("new_account_sources_#{type}_path", @second),
            edit: public_send("edit_account_sources_#{type}_path", @second, record),
            show: public_send("account_sources_#{type}_path", @second, record)
          }
          paths.each do |action, path|
            visit path
            set_sources_theme(theme)
            assert_source_layout
            if action != :show
              if type != "document"
                assert_selector "lexxy-editor[connected][attachments='false'] lexxy-toolbar"
                assert_operator find(".lexxy-editor__content").rect.height, :>=, 200
              end
              columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-source-form-layout')).gridTemplateColumns").split.length
              assert_equal width >= 1280 ? 2 : 1, columns
              find(".n-source-form input[type='submit']").send_keys(:null)
              page.execute_script("document.querySelector('.n-source-form input[type=submit]').focus()")
              assert_focused_source_visible
              measure_source_contrast([
                [ ".n-workspace-help", "color", 4.5 ], [ ".n-workspace-primary", "color", 4.5 ],
                [ ".n-source-form :focus", "outlineColor", 3 ]
              ])
            end
            page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
            save_source_screenshot("#{type}-#{action}-#{locale}-#{width}-#{theme}")
          end
        end
      end
    end
  end

  test "reduced motion removes source field transitions and no-account guidance stays accessible" do
    visit new_account_sources_text_path(@second)
    assert_selector "lexxy-editor[connected]"
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    transitions = page.evaluate_script("Array.from(document.querySelectorAll('.n-source-workspace .n-field,.n-source-workspace .n-select,.n-source-workspace .n-source-editor')).map(e => ({tag:e.tagName,duration:getComputedStyle(e).transitionDuration}))")
    assert transitions.all? { |row| row.fetch("duration") == "0s" }, "Reduced-motion source transitions: #{transitions}"

    page.driver.browser.manage.delete_all_cookies
    sign_in_workspace_browser(user: experience(:users, :overview_no_account))
    resize_sources(375, 812)
    %w[light dark].each do |theme|
      visit sources_path
      set_sources_theme(theme)
      assert_selector "[data-source-setup]"
      assert_no_selector ".n-source-form, [data-source-upload]"
      assert_source_layout
      find("[data-source-setup] section a").send_keys(:null)
      page.execute_script("document.querySelector('[data-source-setup] section a').focus()")
      assert_focused_source_visible
      measure_source_contrast([
        [ "[data-source-setup] section .n-workspace-help", "color", 4.5 ],
        [ ".n-workspace-primary", "color", 4.5 ], [ "[data-source-setup] section a:focus", "outlineColor", 3 ]
      ])
      save_source_screenshot("no-account-#{theme}")
    end
  end

  private
    def observe_source_error_navigation
      page.execute_script(<<~JS)
        window.sourceErrorNavigation=[];
        for(const name of ['turbo:before-fetch-request','turbo:before-cache'])
          document.addEventListener(name,()=>sourceErrorNavigation.push(name));
      JS
    end

    def disconnect_source_streams
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
      page.execute_script("document.querySelectorAll('turbo-cable-stream-source').forEach(element => element.remove())")
      assert_no_selector "turbo-cable-stream-source", visible: :all
    end

    def observe_source_delete_requests(path)
      page.execute_script(<<~JS, path)
        const action=new URL(arguments[0],location.href).href;
        window.sourceDeleteRequests=[];
        document.addEventListener('turbo:before-fetch-request',event=>{
          if(event.target instanceof HTMLFormElement&&event.target.action===action)
            sourceDeleteRequests.push({method:event.detail.fetchOptions.method});
        });
      JS
    end

    def screenshots_dir
      @evidence_dir
    end

    def sign_in_workspace_browser(user: @user, locale: "en")
      visit root_url
      fill_in "email", with: user.email
      fill_in "password", with: AccountExperienceFixtures::PASSWORD
      click_on "Sign in"
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']"
    end

    def fill_source_editor(content)
      assert_selector "lexxy-editor[connected]"
      editor = find(".lexxy-editor__content")
      editor.click
      editor.send_keys([ :control, "a" ], content)
    end

    def ingestion_job(type)
      { "document" => AddDocumentJob, "text" => AddTextJob, "qna" => AddQnaJob, "website" => CrawlWebsiteUrlJob }.fetch(type)
    end

    def resize_sources(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_sources_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
        (async () => {
          await frame();
          const finite = document.getAnimations().filter(animation =>
            animation.effect && Number.isFinite(animation.effect.getComputedTiming().endTime));
          await Promise.allSettled(finite.map(animation => animation.finished));
          await frame();
        })().then(done);
      JS
    end

    def assert_source_layout
      assert_selector "[data-source-workspace] .n-workspace-header h1", count: 1
      assert_no_text(/translation missing|missing translation/i)
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"), "Source workspace overflows horizontally"
    end

    def verify_row_keyboard(source)
      row = "[data-source-id='#{source.id}']"
      find("#{row} .n-source-title").send_keys(:null)
      page.execute_script("document.querySelector(arguments[0]).focus()", "#{row} .n-source-title")
      [ "[data-source-edit]", "form button", "a[data-turbo-method='delete']" ].each do |selector|
        page.send_keys(:tab)
        focused = find("#{row} #{selector}:focus")
        assert_focused_source_visible
        assert_operator focused.rect.width, :>=, 44
        assert_operator focused.rect.height, :>=, 44
      end
      page.send_keys([ :shift, :tab ])
      assert_selector "#{row} form button:focus"
      assert_focused_source_visible
    end

    def assert_focused_source_visible
      state = page.evaluate_script(<<~JS)
        (() => {
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,main.top)&&r.bottom<=Math.min(innerHeight,main.bottom)&&points.every(([x,y])=>{
            const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));
          })};
        })()
      JS
      assert_operator state.fetch("outline"), :>=, 2
      assert state.fetch("visible"), "Focused source control is obscured: #{state}"
    end

    def measure_source_contrast(samples)
      rows = page.evaluate_script(<<~JS, samples)
        (() => {
          const samples=arguments[0],canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){if(!CSS.supports('color',color))throw new Error(`Unsupported color: ${color}`);ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          return samples.map(([selector,property,minimum])=>{
            const e=Array.from(document.querySelectorAll(selector)).find(candidate=>candidate.getClientRects().length>0&&getComputedStyle(candidate).visibility==='visible');
            if(!e)throw new Error(`No rendered visible contrast sample for ${selector}`);
            const bg=background(property==='color'?e:e.parentElement),fg=blend(rgba(getComputedStyle(e)[property]),bg),a=luminance(fg),b=luminance(bg);
            return {selector,property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
          });
        })()
      JS
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ path: page.current_path, viewport: page.evaluate_script("[innerWidth,innerHeight]"), dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), "#{row.fetch('selector')} #{row.fetch('property')}" }
    end

    def save_source_screenshot(name)
      page.evaluate_async_script(<<~JS)
        const done=arguments[arguments.length-1];
        requestAnimationFrame(()=>requestAnimationFrame(done));
      JS
      page.save_screenshot("#{@evidence_dir}/#{name}.png")
    end

    def source_editor_border_probe
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        const root = document.documentElement;
        const editor = document.querySelector('lexxy-editor.n-source-editor');
        const originalTheme = root.getAttribute('class');
        const originalInvalid = editor.getAttribute('aria-invalid');
        const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
        const settle = async () => {
          await frame();
          const finite = document.getAnimations().filter(animation =>
            animation.effect && Number.isFinite(animation.effect.getComputedTiming().endTime));
          await Promise.allSettled(finite.map(animation => animation.finished));
          await frame();
        };
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 1;
        const context = canvas.getContext('2d', { willReadFrequently: true });
        const sample = color => {
          if (!CSS.supports('color', color)) throw new Error(`Unsupported theme color: ${color}`);
          context.clearRect(0, 0, 1, 1);
          context.fillStyle = color;
          context.fillRect(0, 0, 1, 1);
          return { css: color, rgba: Array.from(context.getImageData(0, 0, 1, 1).data) };
        };
        (async () => {
          try {
            const measurements = [];
            for (const theme of ['light', 'dark']) {
              root.classList.toggle('dark', theme === 'dark');
              editor.setAttribute('aria-invalid', 'false');
              await settle();
              const style = getComputedStyle(editor);
              const neutral = sample(style.getPropertyValue('--color-neutral-500').trim());
              const error = sample(style.getPropertyValue(theme === 'dark' ? '--color-red-300' : '--color-red-700').trim());
              const valid = sample(style.borderTopColor);
              editor.setAttribute('aria-invalid', 'true');
              await settle();
              measurements.push({ theme, neutral, error, valid, invalid: sample(getComputedStyle(editor).borderTopColor) });
            }
            return measurements;
          } finally {
            if (originalTheme === null) root.removeAttribute('class');
            else root.setAttribute('class', originalTheme);
            if (originalInvalid === null) editor.removeAttribute('aria-invalid');
            else editor.setAttribute('aria-invalid', originalInvalid);
            await settle();
          }
        })().then(done, error => done({ error: error.message }));
      JS
    end
end
