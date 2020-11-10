#!/usr/bin/env ruby

# ^-- I prefer rbenv to rvm for managing different local versions of
# ruby, personally

# Especially if this is going to be shipped as a single binary for
# developers/etc to use, I also like inline bundler as opposed to a
# separate Gemfile. If this is a system-wide suite of utilities, then
# an external Gemfile makes more sense and is easier to manage.
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'slop', '~> 4.8.2'     # My favorite argument parser
  gem 'colorize', '~> 0.8.1' # Prettified text
end

# What am I going to do here? Just this:
# https://www.howtoforge.com/creating_a_local_yum_repository_centos

# That's right... this is all just a fancy front-end to rsync. But the
# nice thing about using rsync is that we can use hard links to save
# space across directories; to the filesystem, everything will look
# like a file, but will only take up the space it takes to store
# entries, unless a package actually differs. This is also a nice way
# to do incremental backups!

# Like me, my programs tend to blather. Log levels are a good way to
# manage this.
require 'logger'
# For the datestamped directories
require 'date'

# Use my colorizer to colorize the various levels
class ColorLogger < Logger
  def warn(msg)
    msg = msg.yellow
    super
  end

  def error(msg)
    msg = msg.red
    super
  end

  def debug(msg)
    msg = msg.cyan
    super
  end
end

logger = ColorLogger.new(STDOUT)
logger.level = Logger::WARN

# Parsing args... and checking them somewhat.
# I'm a little lax on checking the arguments, since for this case, I somewhat trust the user
opts = Slop.parse do |o|
  o.banner = 'Usage: update-repo.rb [options] <source repo path> <dest repo path>\n\tpath is up to, but not including, the updates dir'
  o.on '-v', '--verbose', 'Blather on considerably.' do
    logger.level = Logger::INFO
  end
  o.on '-d', '--debug',   'TMI' do
    logger.level = Logger::DEBUG
  end
  o.on '-h', '--help', 'Print this help text.' do
    puts o
    exit
  end
  o.bool '-c', '--create', 'Create a new repo if this doesn\'t already exist.'
  o.bool '-n', '--dry-run', 'Dry run. Show what you would do, but don\'t actually do it.'
end

if opts.arguments.length < 2
  logger.error('I need two arguments.')
  puts opts
  exit
end

logger.debug("Our arguments are: #{opts.arguments}")
source = opts.arguments[0]
dest = opts.arguments[1]

# Construct the REAL directories we'll use from the arguments given.
# Replace any protocol with rsync://; replace the destination with a datestamped name.
# Using DateTime just in case we later need to split it up for per-hour, per-minute, what have you.
actual_source = source.gsub(/^(http(s)?:\/\/)?/, 'rsync://')
datestamp = DateTime.now.strftime('%Y%m%d')
actual_dest = dest.gsub(/\/?$/, "/#{datestamp}")
link_dest   = dest.gsub(/\/?$/, '/latest')

logger.info("\n\tSource: #{actual_source}\n\tDest: #{actual_dest}")

# Behave differently if this is the first sync or a subsequent sync.
# Explanation of rsync arguments:
# a: archive. v: verbose. z: use compression. t: preserve times. r: recursive.
# --link-dest=DIR hardlink to file when unchanged
# Only use link-dest if there's a "latest" symlink in there already
rsync_opts = "-avzrt"
unless File.exist?(link_dest)
  unless opts.create?
    logger.error('"latest" symlink doesn\'t exist, and you didn\'t specify to create a new one with -c')
    exit
  end
else
  rsync_opts="-avzrt --link-dest=#{link_dest}"
end

if opts.dry_run?
  rsync_opts += " -n"
end

rsync_cmd="rsync #{rsync_opts} #{actual_source} #{actual_dest}"
logger.info("Executing rsync as:\n\t#{rsync_cmd}")
exit
system(rsync_cmd)

# Now we just have to clean up our "latest" symlink and we're done.
File.delete(link_dest) if File.exist?(link_dest)
File.symlink(actual_dest, link_dest)
