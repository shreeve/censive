#!/usr/bin/env ruby

STDOUT.sync = true

require 'fileutils'
require_relative 'censive'

# ARGV << "9.csv"

abort "usage: #{File.basename($0)} <files>" if ARGV.empty?

rand = `LC_ALL=C tr -dc a-zA-Z0-9 < /dev/random | head -c12`

rows = []
cols = []
coun = 0
full = 0

ARGV.each do |path|
  File.file?(path) or next

  print "Processing #{path.inspect}"

  rows.clear
  cols.clear
  seen = 0
  coun += 1

  dest = "#{path}-#{rand}"

  begin
    Censive.writer(dest) do |file|
      Censive.reader(path, excel: true, relax: true).each do |cols|
        file << cols
        seen += 1
        print "." if (seen % 1e5) == 0
      end
    end
    FileUtils.mv(dest, path)
    full += (seen - 1)
    puts " (#{seen - 1} rows of data)" #!# FIXME: no headers? then, don't subtract 1
  rescue
    puts " - unable to process (#{$!})"
    FileUtils.rm_f(dest)
  end
end

puts "Processed #{coun} files with a total of #{full} rows of data" if coun > 1
