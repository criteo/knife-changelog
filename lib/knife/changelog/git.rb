class KnifeChangelog
  class Git
    attr_accessor :tmp_prefix, :uri

    def initialize(tmp_prefix, uri)
      @tmp_prefix = tmp_prefix
      @uri = uri
    end

    def shallow_clone
      Chef::Log.debug "Cloning #{uri} in #{tmp_prefix}"
      dir = Dir.mktmpdir(tmp_prefix)
      clone = Mixlib::ShellOut.new("git clone --bare #{uri} bare-clone", cwd: dir)
      clone.run_command
      clone.error!
      @clone_dir = ::File.join(dir, 'bare-clone')
      @clone_dir
    end

    def files(rev_parse)
      ls_tree = Mixlib::ShellOut.new("git ls-tree -r #{rev_parse}", cwd: @clone_dir)
      ls_tree.run_command
      ls_tree.error!
      ls_tree.stdout.lines.map(&:strip)
    end

    def diff(filename, current_rev, rev_parse)
      diff = Mixlib::ShellOut.new("git diff #{current_rev}..#{rev_parse} --word-diff -- #{filename}", cwd: @clone_dir)
      diff.run_command
      diff.stdout.lines
    end

    def log(current_rev, rev_parse)
      log = Mixlib::ShellOut.new("git log --no-merges --abbrev-commit --pretty=oneline #{current_rev}..#{rev_parse}", cwd: @clone_dir)
      log.run_command
      log.stdout.lines
    end

    def revision_exists?(revision)
      Chef::Log.debug "Testing existence of #{revision}"
      revlist = Mixlib::ShellOut.new("git rev-list --quiet #{revision}", cwd: @clone_dir)
      revlist.run_command
      !revlist.error?
    end
  end
end
