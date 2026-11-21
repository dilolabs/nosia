require "test_helper"

class NotesIndexStatusesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users, :note_folders, :notes

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @account = accounts(:picker_first)
    @user = users(:picker_owner)
    @note = notes(:field_notes)
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    post login_path, params: { email: @user.email, password: "picker-password-123" }
    assert_response :redirect
  end

  test "status is uncached and does not render note content in plain or frame HTML" do
    [ {}, frame_headers ].each do |headers|
      get index_status_path, headers: headers
      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      assert_select "turbo-frame#note-index-status [role='status'][data-note-index-status='failed']", text: "Indexing failed"
      assert_select "form[action='#{index_retry_path}'] button", text: "Retry indexing"
      assert_select "lexxy-editor", count: 0
      refute_includes response.body, @note.title
      refute_includes response.body, @note.body_text
    end
    assert_equal index_status_path, account_note_index_status_path(@account, @note)
    assert_equal index_retry_path, account_note_index_retry_path(@account, @note)
  end

  test "empty pending ready and failed have different localized announcements" do
    {
      empty: "Aucun texte à indexer", pending: "Indexation en cours",
      ready: "Note indexée", failed: "Échec de l’indexation"
    }.each do |state, label|
      @note.update!(embedding_status: state)
      get index_status_path, headers: frame_headers.merge("Accept-Language" => "fr")
      assert_response :success
      assert_select "[role='status'][data-note-index-status='#{state}']", text: label
      assert_select "form[action='#{index_retry_path}']", count: state == :failed ? 1 : 0
    end
  end

  test "plain retry schedules one job and redirects to the note without saving text" do
    original = @note.values_at(:title, :body_html, :content_revision, :content_updated_at, :embedding_generation)
    assert_enqueued_with(job: Note::IndexJob, args: [ @note.id, 2 ]) do
      post index_retry_path, params: { note: { title: "Not an edit", body_html: "<p>Not saved</p>" } }
      assert_response :see_other
    end
    assert_redirected_to account_note_path(@account, @note)
    assert @note.reload.embedding_pending?
    assert_equal original, @note.values_at(:title, :body_html, :content_revision, :content_updated_at, :embedding_generation)

    [ :pending, :ready, :empty ].each do |state|
      @note.update!(embedding_status: state)
      assert_no_enqueued_jobs(only: Note::IndexJob) do
        post index_retry_path
        assert_response :see_other
      end
      assert_equal state.to_s, @note.reload.embedding_status
    end
  end

  test "Turbo retry redirects to only its status frame" do
    post index_retry_path, headers: frame_headers.merge("Accept" => "text/vnd.turbo-stream.html, text/html")
    assert_response :see_other
    assert_redirected_to index_status_path
    follow_redirect!(headers: frame_headers)
    assert_response :success
    assert_select "turbo-frame#note-index-status [data-note-index-status='pending']"
    assert_select "lexxy-editor, .n-notes-form", count: 0
  end

  test "a failed post-commit enqueue reports a localized outcome only to the retry frame" do
    adapter = queue_adapter
    adapter.define_singleton_method(:enqueue_at) do |_job, _timestamp|
      raise SolidQueue::Job::EnqueueError, "Synthetic queue outage"
    end
    original = @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    headers = frame_headers.merge("Accept-Language" => "fr")

    assert_no_enqueued_jobs(only: Note::IndexJob) do
      post index_retry_path, headers: headers
      assert_response :see_other
    end
    retry_status_location = response.location
    assert @note.reload.embedding_failed?
    assert_equal original, @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    follow_redirect!(headers: headers)
    assert_response :success
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "[role='status'][data-note-index-status='failed']", text: "Échec de l’indexation"
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez."
    assert_select "button", text: "Relancer l’indexation"
    assert_select "lexxy-editor, .n-notes-form", count: 0

    get index_status_path, headers: headers
    assert_response :success
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez.", count: 0

    @note.update!(embedding_generation: 3)
    get retry_status_location, headers: headers
    assert_response :success
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez.", count: 0
  ensure
    adapter.singleton_class.remove_method(:enqueue_at)
  end

  test "cross-account notes and missing membership do not reveal status or retry" do
    assert_inaccessible account: accounts(:picker_second)
    assert_inaccessible account: accounts(:picker_foreign)
    @user.account_users.find_by!(account: @account).destroy!
    assert_inaccessible
    assert @note.reload.embedding_failed?
  end

  test "a directly trashed or ancestor-hidden note does not reveal status or retry" do
    @note.trash
    assert_inaccessible

    @note.restore
    note_folders(:sessions).trash
    assert_inaccessible
  end

  private
    def index_status_path(account = @account)
      "#{account_note_path(account, @note)}/index_status"
    end

    def index_retry_path(account = @account)
      "#{account_note_path(account, @note)}/index_retry"
    end

    def frame_headers
      { "Turbo-Frame" => "note-index-status" }
    end

    def assert_inaccessible(account: @account)
      get index_status_path(account), headers: frame_headers
      assert_response :not_found
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      assert_empty response.body

      assert_no_enqueued_jobs(only: Note::IndexJob) do
        post index_retry_path(account), headers: frame_headers
        assert_response :not_found
        assert_empty response.body
      end
    end
end
