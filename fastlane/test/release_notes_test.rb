require 'minitest/autorun'
require 'tmpdir'
require_relative '../release_notes'

class ReleaseNotesTest < Minitest::Test
  Localization = Struct.new(:locale, :updates) do
    def update(attributes:); updates << attributes; end
  end
  Version = Struct.new(:version_string, :localizations) do
    def get_app_store_version_localizations; localizations; end
  end
  App = Struct.new(:live, :editable) do
    def get_live_app_store_version(platform:); live; end
    def get_edit_app_store_version(platform:); editable; end
  end

  def setup
    @directory = Dir.mktmpdir('mellow-release-notes-test')
    @live = Version.new('1.0.0', [Localization.new('ko', [])])
    @app = App.new(@live, nil)
  end
  def teardown; FileUtils.remove_entry(@directory); end
  def prepare(app = @app, version = '1.0.1')
    MellowReleaseNotes.prepare(app: app, version: version, directory: @directory)
  end
  def notes(value)
    File.write(File.join(@directory, '1.0.1.json'), JSON.generate(value))
  end

  def test_first_release_skips_notes_without_writing_anything
    first = Version.new('1.0.0', [Localization.new('ko', [])])
    assert_nil prepare(App.new(nil, first), '1.0.0')
    assert_empty first.localizations.first.updates
  end
  def test_future_release_fails_early_when_notes_missing_or_blank
    assert_raises(MellowReleaseNotes::Error) { prepare }
    notes('ko' => '   ')
    assert_raises(MellowReleaseNotes::Error) { prepare }
    assert_empty @live.localizations.first.updates
  end
  def test_notes_update_only_whats_new_on_matching_target_locale
    notes('ko' => "  보정 결과 저장 문제를 수정했습니다.\n")
    plan = prepare
    target = Version.new('1.0.1', [Localization.new('ko', [])])
    plan.apply!(target)
    assert_equal [{ 'whats_new' => '보정 결과 저장 문제를 수정했습니다.' }], target.localizations.first.updates
    assert_empty @live.localizations.first.updates
  end
  def test_locale_mismatch_fails_before_any_write
    notes('ko' => '보정 결과 저장 문제를 수정했습니다.')
    plan = prepare
    target = Version.new('1.0.1', [Localization.new('ko', []), Localization.new('en-US', [])])
    assert_raises(MellowReleaseNotes::Error) { plan.apply!(target) }
    assert target.localizations.all? { |locale| locale.updates.empty? }
    notes('en-US' => 'Fixed photo export.')
    assert_raises(MellowReleaseNotes::Error) { prepare }
  end
  def test_never_overwrites_other_editable_version_or_live_version
    notes('ko' => '보정 결과 저장 문제를 수정했습니다.')
    assert_raises(MellowReleaseNotes::Error) { prepare(App.new(@live, Version.new('1.0.2', []))) }
    assert_raises(MellowReleaseNotes::Error) { prepare(@app, '1.0.0') }
    assert_raises(MellowReleaseNotes::Error) { prepare.apply!(@live) }
  end
  def test_malformed_and_oversized_notes_rejected
    File.write(File.join(@directory, '1.0.1.json'), '{')
    assert_raises(MellowReleaseNotes::Error) { prepare }
    notes('ko' => '가' * 4001)
    assert_raises(MellowReleaseNotes::Error) { prepare }
  end
end
