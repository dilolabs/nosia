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
      assert_select "turbo-frame##{frame_id} [role='status'][data-note-index-status='failed']", text: "Indexing failed"
      assert_select "form[action='#{index_retry_path}'] button", text: "Retry indexing"
      assert_select "lexxy-editor", count: 0
      refute_includes response.body, @note.title
      refute_includes response.body, @note.body_text
    end
    assert_equal index_status_path, account_note_index_status_path(@account, @note)
    assert_equal index_retry_path, account_note_index_retry_path(@account, @note)
  end

  test "each authorized note status renders and targets its own Turbo frame" do
    [ [ @account, @note ], [ accounts(:picker_second), notes(:second_team_note) ] ].each do |account, note|
      note.update!(embedding_status: :failed, embedding_generation: 2)
      frame = ActionView::RecordIdentifier.dom_id(note, :index_status)
      status_path = account_note_index_status_path(account, note)
      retry_path = account_note_index_retry_path(account, note)

      get status_path, headers: { "Turbo-Frame" => frame }
      assert_response :success
      assert_select "turbo-frame##{frame} form[action='#{retry_path}'][data-turbo='false'] input[name='expected_generation'][value='2']"
      post retry_path, params: { expected_generation: 2 }, headers: { "Turbo-Frame" => frame }
      assert_response :success
      assert_select "turbo-frame##{frame} [data-note-index-status='pending']"
    end
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
      post index_retry_path, params: { expected_generation: 2, note: { title: "Not an edit", body_html: "<p>Not saved</p>" } }
      assert_response :see_other
    end
    assert_redirected_to account_note_path(@account, @note)
    assert @note.reload.embedding_pending?
    assert_equal original, @note.values_at(:title, :body_html, :content_revision, :content_updated_at, :embedding_generation)

    [ :pending, :ready, :empty ].each do |state|
      @note.update!(embedding_status: state)
      assert_no_enqueued_jobs(only: Note::IndexJob) do
        post index_retry_path, params: { expected_generation: 2 }
        assert_response :see_other
      end
      assert_equal state.to_s, @note.reload.embedding_status
    end
  end

  test "frame retry returns only its updated status" do
    post index_retry_path, params: { expected_generation: 2 }, headers: frame_headers
    assert_response :success
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "turbo-frame##{frame_id} [data-note-index-status='pending']"
    assert_select "lexxy-editor, .n-notes-form", count: 0
  end

  test "a stale retry cannot enqueue the newer failed generation saved by another member" do
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    editor = open_session
    editor.post login_path, params: { email: member.email, password: "picker-password-123" }
    editor.patch account_note_path(@account, @note), params: {
      note: { title: "Saved by another member", body_html: "<p>New saved text</p>", expected_revision: 1 }
    }
    assert_equal 303, editor.response.status
    @note.reload.mark_index_failed(3)
    original = @note.reload.values_at(:title, :body_html, :content_revision, :embedding_generation)
    headers = frame_headers.merge("Accept-Language" => "fr")

    assert_no_enqueued_jobs(only: Note::IndexJob) do
      post index_retry_path, params: { expected_generation: "2" }, headers: headers
      assert_response :conflict
    end
    assert_equal original, @note.reload.values_at(:title, :body_html, :content_revision, :embedding_generation)
    assert @note.embedding_failed?
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "[role='status']", text: "L’état de l’indexation a changé. Vérifiez-le avant de réessayer."
    assert_select "form[action='#{index_retry_path}'] input[name='expected_generation'][value='3']"
    refute_includes response.body, "New saved text"

    assert_no_enqueued_jobs(only: Note::IndexJob) do
      post index_retry_path, params: { expected_generation: "2" }
      assert_redirected_to account_note_path(@account, @note)
    end
    follow_redirect!
    assert_select "[role='alert']", text: /Indexing state changed\. Check the current status before retrying\./
    assert_select "form[action='#{index_retry_path}'] input[name='expected_generation'][value='3']"

    assert_enqueued_with(job: Note::IndexJob, args: [ @note.id, 3 ]) do
      post index_retry_path, params: { expected_generation: "3" }, headers: headers
      assert_response :success
    end
    assert @note.reload.embedding_pending?
  end

  test "missing or malformed expected generations cannot enqueue a failed note" do
    [ {}, { expected_generation: "2x" }, { expected_generation: [ "2" ] } ].each do |payload|
      assert_no_enqueued_jobs(only: Note::IndexJob) do
        post index_retry_path, params: payload, headers: frame_headers
        assert_response :conflict
      end
      assert @note.reload.embedding_failed?
    end
  end

  test "a failed post-commit enqueue reports a localized outcome only to the retry frame" do
    adapter = queue_adapter
    adapter.define_singleton_method(:enqueue_at) do |_job, _timestamp|
      raise SolidQueue::Job::EnqueueError, "Synthetic queue outage"
    end
    original = @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    headers = frame_headers.merge("Accept-Language" => "fr")

    assert_no_enqueued_jobs(only: Note::IndexJob) do
      post index_retry_path, params: { expected_generation: 2 }, headers: headers
      assert_response :success
    end
    assert @note.reload.embedding_failed?
    assert_equal original, @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_select "[role='status'][data-note-index-status='failed']", text: "Échec de l’indexation"
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez."
    assert_select "button", text: "Relancer l’indexation"
    assert_select "lexxy-editor, .n-notes-form", count: 0

    get index_status_path, headers: headers
    assert_response :success
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez.", count: 0

    get "#{index_status_path}?retry_failed=2", headers: headers
    assert_response :success
    assert_select "[role='status']", text: "La relance de l’indexation n’a pas démarré. Réessayez.", count: 0

    post index_retry_path, params: { expected_generation: 2 }
    assert_redirected_to account_note_path(@account, @note)
    follow_redirect!
    assert_select "[role='alert']", text: /Indexing retry failed to start\. Try again\./
    assert_select "form[action='#{index_retry_path}'] input[name='expected_generation'][value='2']"
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
      { "Turbo-Frame" => frame_id }
    end

    def frame_id
      ActionView::RecordIdentifier.dom_id(@note, :index_status)
    end

    def assert_inaccessible(account: @account)
      get index_status_path(account), headers: frame_headers
      assert_response :not_found
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      assert_empty response.body

      assert_no_enqueued_jobs(only: Note::IndexJob) do
        post index_retry_path(account), params: { expected_generation: 2 }, headers: frame_headers
        assert_response :not_found
        assert_empty response.body
      end
    end
end
