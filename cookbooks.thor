require 'thor'
require 'fog'
require 'zlib'
require 'archive/tar/minitar'

class Cookbooks < Thor
  include Archive::Tar
  include Thor::Actions

  desc 'install', 'Install cookbooks from Cheffile'
  option :package, type: :boolean, default: false
  def install
    run 'bundle exec librarian-chef install'

    if options[:package]
      if !package
        raise Thor::Error, "Cookbook packaging failed; aborting upload."
      end

      puts
    end
  end

  desc 'update', 'Update cookbook versions from Cheffile'
  def update
    run 'bundle exec librarian-chef update'
  end

  desc 'package', 'Package cookbooks into a tgz file'
  def package
    puts "Packaging cookbooks"

    FileUtils.mkdir_p('tmp')
    tgz = Zlib::GzipWriter.new(File.open(cookbook_tarball_name, 'wb'))

    package = Dir['cookbooks/*']

    Minitar.pack(package, tgz)
  end

  desc 'upload ACCESS_KEY SECRET_KEY BUCKET [REGION]', 'Upload cookbooks to S3 (default region us-east-1)'
  option :install, type: :boolean, default: false
  option :package, type: :boolean, default: true
  def upload(access_key, secret_access_key, bucket, region='us-east-1')
    save_credentials(access_key, secret_access_key, bucket, region)

    if options[:install]
      if !install
        raise Thor::Error, "Cookbook installation failed; aborting upload."
      end

      puts
    end

    if options[:package]
      if !package
        raise Thor::Error, "Cookbook packaging failed; aborting upload."
      end

      puts
    end

    remote_file = directory.files.head(cookbook_tarball_name)
    remote_file.destroy if remote_file

    puts "Uploading to S3"

    directory.files.create(
      key: "cookbooks.tgz",
      body: File.open(cookbook_tarball_name)
    )
  end

  desc 'sync', 'Install all cookbooks and synchronize them to GitHub'
  option :install, type: :boolean, default: true
  def sync
    if options[:install]
      if !install
        raise Thor::Error, "Cookbook installation failed; aborting upload."
      end

      puts
    end

    Dir.chdir('cookbooks') do
      system %Q(echo "gitdir: ../.git/modules/cookbooks" > .git)
      system "git add ."
      system "git add -u"
      message = "Cookbooks generated via librarian-chef at #{Time.now.utc}"
      system "git commit -m \"#{message}\""
      system "git pull"
      system "git push origin cookbooks"
    end
  end

  no_tasks do
    def save_credentials(access_key, secret_access_key, bucket, region)
      @access_key = access_key
      @secret_access_key = secret_access_key
      @bucket = bucket
      @region = region
    end

    def connection
      Fog::Storage.new({
        provider: 'AWS',
        aws_access_key_id: @access_key,
        aws_secret_access_key: @secret_access_key,
        region: @region
      })
    end

    def directory
      connection.directories.get(@bucket)
    end

    def cookbook_tarball_name
      File.join('tmp', 'cookbooks.tgz')
    end
  end
end
