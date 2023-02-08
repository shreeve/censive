#!/usr/bin/env ruby

require "./censive"
require "digest/md5"

if ARGV.empty?
  path = "KEN_ALL.CSV"
  mode = "r:cp932"
else
  path = ARGV.shift || "5.csv"
  mode = "r"
end

data = File.open(path, mode).read
rows = Censive.parse(data)

puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
