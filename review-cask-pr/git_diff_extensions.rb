require "git_diff"

module GitDiffExtension
  refine GitDiff::Diff do
    def cask_name
      File.basename(files.first.b_path, '.rb') if single_cask?
    end

    def cask_path
      files.first.b_path if single_cask?
    end

    def simple?
      single_cask? && only_version_or_checksum?
    end

    def single_cask?
      return false unless files.count == 1
      file = files.first
      return false unless file.a_path == file.b_path
      file.b_path.match?(%r{\ACasks/[^/]+\.rb\Z})
    end

    def only_version_or_checksum?
      return false if additions.count != deletions.count
      return false unless (additions + deletions).all? { |line| line.version? || line.sha256? }

      additions.count { |line| line.version? } <= 1
    end

    def version_changed?
      old_version != new_version
    end

    def version_decreased?
      return false unless version_changed?

      new_parts = new_version.split(/[,:]/)
      old_parts = old_version.split(/[,:]/)

      # Most of the time, the first (`before_comma`) part is the actual version, so
      # return early if this increased and ignore other parts used to build the URL.
      return false if Version.new(new_parts.first) > Version.new(old_parts.first)

      new_parts.zip(old_parts)
        .any? { |v_new, v_old|
          if Version.new(v_new) < Version.new(v_old)
            # Don't treat hex IDs as versions. This will not match normal versions since
            # they usually contain dots and we only remove hyphens and underscores here.
            new_id = v_new.gsub(/[-_]/, '')
            old_id = v_old.gsub(/-_/, '')
            r = /\A[\da-f]+\Z/
            next false if new_id.match?(r) && old_id.match?(r) && v_new.length == v_old.length

            true
          else
            false
          end
        }
    end

    def old_version
      @old_version ||= deletions.find { |line| line.version? }&.version
    end

    def new_version
      @new_version ||= additions.find { |line| line.version? }&.version
    end

    def lines
      @lines ||= files.flat_map(&:hunks).flat_map(&:lines)
    end

    def additions
      @additions ||= lines.select(&:addition?)
    end

    def deletions
      @deletions ||= lines.select(&:deletion?)
    end
  end

  refine GitDiff::Line::Context do
    def version?
      !version.nil?
    end

    def version
      to_s[/\A[+-]\s*version "([^"]+)"\Z/, 1]
    end

    def sha256?
      to_s.match?(/\A[+-]\s*sha256 "[0-9a-f]{64}"\Z/)
    end
  end
end
