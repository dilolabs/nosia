require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
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

  private
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
