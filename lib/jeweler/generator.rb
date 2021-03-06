require 'git'
require 'erb'

require 'net/http'
require 'uri'

class Jeweler
  class NoGitUserName < StandardError
  end
  class NoGitUserEmail < StandardError
  end
  class FileInTheWay < StandardError
  end
  class NoGitHubRepoNameGiven < StandardError
  end
  class NoGitHubUser < StandardError
  end
  class NoGitHubToken < StandardError
  end
  class GitInitFailed < StandardError
  end    

  class Generator    
    attr_accessor :target_dir, :user_name, :user_email, :summary,
                  :github_repo_name, :github_remote, :github_url, 
                  :github_username, :github_token,
                  :lib_dir, :constant_name, :file_name_prefix, :config, :test_style,
                  :repo, :should_create_repo

    def initialize(github_repo_name, options = {})
      check_user_git_config()
      
      if github_repo_name.nil?
        raise NoGitHubRepoNameGiven
      end
      self.github_repo_name = github_repo_name

      self.github_remote = "git@github.com:#{github_username}/#{github_repo_name}.git"
      self.github_url = "http://github.com/#{github_username}/#{github_repo_name}"

      self.test_style = options[:test_style] || :shoulda
      self.target_dir = options[:directory] || self.github_repo_name
      self.lib_dir = File.join(target_dir, 'lib')
      self.constant_name = self.github_repo_name.split(/[-_]/).collect{|each| each.capitalize }.join
      self.file_name_prefix = self.github_repo_name.gsub('-', '_')
      self.should_create_repo = options[:create_repo]
      self.summary = options[:summary] || 'TODO'
    end

    def run
      create_files
      gitify
      puts "Jeweler has prepared your gem in #{github_repo_name}"
      if should_create_repo
        create_and_push_repo
        puts "Jeweler has pushed your repo to #{github_url}"
        enable_gem_for_repo
        puts "Jeweler has enabled gem building for your repo"
      end
    end

    def testspec
      case test_style
      when :shoulda
        'test'
      when :bacon
        'spec'
      end
    end

    def test_dir
      File.join(target_dir, testspec)
    end


  private
    def create_files
      unless File.exists?(target_dir) || File.directory?(target_dir)
        FileUtils.mkdir target_dir
      else
        raise FileInTheWay, "The directory #{target_dir} already exists, aborting. Maybe move it out of the way before continuing?"
      end

      FileUtils.mkdir lib_dir
      FileUtils.mkdir test_dir

      output_template_in_target('.gitignore')
      output_template_in_target('Rakefile')
      output_template_in_target('LICENSE')
      output_template_in_target('README')
      output_template_in_target("#{test_style}/#{testspec}_helper.rb", "#{testspec}/#{testspec}_helper.rb")
      output_template_in_target("#{test_style}/flunking_#{testspec}.rb", "#{testspec}/#{file_name_prefix}_#{testspec}.rb")

      FileUtils.touch File.join(lib_dir, "#{file_name_prefix}.rb")
    end

    def check_user_git_config
      self.config = read_git_config
      
      unless config.has_key? 'user.name'
        raise NoGitUserName
      end
      
      unless config.has_key? 'user.email'
        raise NoGitUserEmail
      end
      
      unless config.has_key? 'github.user'
        raise NoGitHubUser
      end
      
      unless config.has_key? 'github.token'
        raise NoGitHubToken
      end

      self.user_name = config['user.name']
      self.user_email = config['user.email']
      self.github_username = config['github.user']
      self.github_token = config['github.token']
    end

    def output_template_in_target(source, destination = source)
      template = ERB.new(File.read(File.join(File.dirname(__FILE__), 'templates', source)))

      File.open(File.join(target_dir, destination), 'w') {|file| file.write(template.result(binding))}
    end

    def gitify
      saved_pwd = Dir.pwd
      Dir.chdir(target_dir)
      begin
        begin
          @repo = Git.init()
        rescue Git::GitExecuteError => e
          raise GitInitFailed, "Encountered an error during gitification. Maybe the repo already exists, or has already been pushed to?"
        end

        begin
          @repo.add('.')
        rescue Git::GitExecuteError => e
          #raise GitAddFailed, "There was some problem adding this directory to the git changeset"
          raise
        end

        begin
          @repo.commit "Initial commit to #{github_repo_name}."
        rescue Git::GitExecuteError => e
          raise
        end

        begin
          @repo.add_remote('origin', github_remote)
        rescue Git::GitExecuteError => e
          puts "Encountered an error while adding origin remote. Maybe you have some weird settings in ~/.gitconfig?"
          raise
        end
      ensure
        Dir.chdir(saved_pwd)
      end
    end
    
    def create_and_push_repo
      Net::HTTP.post_form URI.parse('http://github.com/repositories'),
                                'login' => github_username,
                                'token' => github_token,
                                'repository[description]' => summary,
                                'repository[name]' => github_repo_name
      sleep 2
      @repo.push('origin')
    end

    def enable_gem_for_repo
      url = "https://github.com/#{github_username}/#{github_repo_name}/update"
      `curl -F 'login=#{github_username}' -F 'token=#{github_token}' -F 'field=repository_rubygem' -F 'value=1' #{url} 2>/dev/null`
      # FIXME use NET::HTTP instead of curl
      #Net::HTTP.post_form URI.parse(url),
                                #'login' => github_username,
                                #'token' => github_token,
                                #'field' => 'repository_rubygem',
                                #'value' => '1'
    end

    def read_git_config
      # we could just use Git::Base's .config, but that relies on a repo being around already
      # ... which we don't have yet, since this is part of a sanity check
      lib = Git::Lib.new(nil, nil)
      config = lib.parse_config '~/.gitconfig'
    end
  end
end
