require 'json'

# Only the version-localized What's New field is written. Store screenshots,
# review contact, privacy details, descriptions, and pricing remain untouched.
module MellowReleaseNotes
  class Error < StandardError; end

  def self.prepare(app:, version:, directory:)
    raise Error, 'Release version must be X.Y.Z' unless version.match?(/\A\d+\.\d+\.\d+\z/)
    editable = app.get_edit_app_store_version(platform: 'IOS')
    if editable && editable.version_string != version
      raise Error, 'A different editable App Store version already exists; do not overwrite it'
    end
    live = app.get_live_app_store_version(platform: 'IOS')
    return nil unless live # Apple does not require What's New for the first release.
    raise Error, 'Use a new version number after a version has been released' if live.version_string == version

    path = File.join(directory, "#{version}.json")
    raise Error, "Missing release notes: fastlane/release_notes/#{version}.json" unless File.file?(path)
    begin
      notes = JSON.parse(File.read(path))
    rescue JSON::ParserError
      raise Error, 'Release notes must be a JSON object mapping App Store locale to text'
    end
    unless notes.is_a?(Hash) && !notes.empty? && notes.all? { |locale, text| locale.is_a?(String) && text.is_a?(String) && !text.strip.empty? && text.strip.length <= 4000 }
      raise Error, 'Every release note must be nonblank text of at most 4000 characters'
    end
    notes = notes.transform_values(&:strip)
    locales = (editable || live).get_app_store_version_localizations.map(&:locale)
    validate_locales!(notes, locales)
    Plan.new(version, notes)
  end

  def self.validate_locales!(notes, locales)
    unless !locales.empty? && notes.keys.sort == locales.sort
      raise Error, "Release note locales must exactly match the App Store version: #{locales.sort.join(', ')}"
    end
  end

  class Plan
    def initialize(version, notes)
      @version = version
      @notes = notes.freeze
    end

    def apply!(store_version)
      raise Error, 'Release notes target does not match the uploaded version' unless store_version.version_string == @version
      localizations = store_version.get_app_store_version_localizations
      MellowReleaseNotes.validate_locales!(@notes, localizations.map(&:locale))
      localizations.each do |localization|
        localization.update(attributes: { 'whats_new' => @notes.fetch(localization.locale) })
      end
    end
  end
end
